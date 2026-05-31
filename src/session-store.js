"use strict";

const crypto = require("node:crypto");

const SESSION_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const PIN_RATE_LIMIT_WINDOW_MS = 60 * 1000;
const PIN_RATE_LIMIT_MAX_FAILURES = 5;
const PIN_RATE_LIMIT_LOCKOUT_MS = 90 * 1000;

function randomToken(bytes = 24) {
  return crypto.randomBytes(bytes).toString("base64url");
}

function trustedDeviceKey({ deviceName = "", userAgent = "", remoteAddress = "" } = {}) {
  return crypto
    .createHash("sha256")
    .update(`${deviceName}\n${userAgent}\n${remoteAddress}`)
    .digest("base64url");
}

function trustedDeviceId(key) {
  return crypto.createHash("sha256").update(key).digest("base64url").slice(0, 18);
}

function createSessionStore({ log, trustedDeviceKeys = [], trustedDevices: trustedDeviceRecords = [], onTrustedDevicesChanged = () => {} }) {
  const sessions = new Map();
  const pinFailures = new Map();
  const trustedDevices = new Map();
  for (const record of trustedDeviceRecords) {
    if (record?.key) trustedDevices.set(record.key, { ...record });
  }
  for (const key of trustedDeviceKeys) {
    if (!trustedDevices.has(key)) {
      trustedDevices.set(key, {
        key,
        deviceName: "Trusted phone",
        remoteAddress: "",
        trustedAt: Date.now(),
        lastSeenAt: Date.now()
      });
    }
  }
  let pin = makePin();
  let pinExpiresAt = Date.now() + 2 * 60 * 1000;

  function makePin() {
    return String(crypto.randomInt(100000, 999999));
  }

  function refreshPin() {
    pin = makePin();
    pinExpiresAt = Date.now() + 2 * 60 * 1000;
    log("auth.pin.refreshed", { pinExpiresAt });
    return getPairingState();
  }

  function ensurePinFresh() {
    if (Date.now() >= pinExpiresAt) refreshPin();
  }

  function getPairingState() {
    ensurePinFresh();
    return {
      pin,
      pinExpiresAt,
      secondsRemaining: Math.max(0, Math.ceil((pinExpiresAt - Date.now()) / 1000)),
      rateLimit: getRateLimitSummary()
    };
  }

  function rateLimitKey(remoteAddress) {
    return remoteAddress || "unknown";
  }

  function getRateLimitRecord(remoteAddress) {
    const key = rateLimitKey(remoteAddress);
    const now = Date.now();
    const existing = pinFailures.get(key);
    if (!existing || now - existing.windowStartedAt > PIN_RATE_LIMIT_WINDOW_MS) {
      const fresh = { failures: 0, windowStartedAt: now, lockedUntil: 0 };
      pinFailures.set(key, fresh);
      return fresh;
    }
    return existing;
  }

  function getRateLimitSummary() {
    const now = Date.now();
    let lockedRemotes = 0;
    let recentFailures = 0;
    for (const [key, record] of pinFailures.entries()) {
      if (record.lockedUntil <= now && now - record.windowStartedAt > PIN_RATE_LIMIT_WINDOW_MS) {
        pinFailures.delete(key);
        continue;
      }
      if (record.lockedUntil > now) lockedRemotes += 1;
      recentFailures += record.failures;
    }
    return {
      maxFailures: PIN_RATE_LIMIT_MAX_FAILURES,
      windowSeconds: Math.round(PIN_RATE_LIMIT_WINDOW_MS / 1000),
      lockoutSeconds: Math.round(PIN_RATE_LIMIT_LOCKOUT_MS / 1000),
      recentFailures,
      lockedRemotes
    };
  }

  function recordPinFailure(remoteAddress) {
    const record = getRateLimitRecord(remoteAddress);
    record.failures += 1;
    if (record.failures >= PIN_RATE_LIMIT_MAX_FAILURES) {
      record.lockedUntil = Date.now() + PIN_RATE_LIMIT_LOCKOUT_MS;
    }
    return record;
  }

  function createPendingSession({ providedPin, deviceName, userAgent, remoteAddress, origin, autoApproveTrusted = false, keepSignedIn = false }) {
    ensurePinFresh();
    const record = getRateLimitRecord(remoteAddress);
    if (record.lockedUntil > Date.now()) {
      const retryAfterSeconds = Math.ceil((record.lockedUntil - Date.now()) / 1000);
      log("auth.pin.rateLimited", { remoteAddress, deviceName, retryAfterSeconds });
      return {
        ok: false,
        code: "PIN_RATE_LIMITED",
        message: `Too many wrong PIN attempts. Try again in ${retryAfterSeconds}s.`,
        retryAfterSeconds
      };
    }
    if (providedPin !== pin) {
      const failed = recordPinFailure(remoteAddress);
      log("auth.pin.failed", { remoteAddress, deviceName });
      return {
        ok: false,
        code: "BAD_PIN",
        message: "The pairing PIN is wrong or expired.",
        attemptsRemaining: Math.max(0, PIN_RATE_LIMIT_MAX_FAILURES - failed.failures)
      };
    }
    pinFailures.delete(rateLimitKey(remoteAddress));
    const key = trustedDeviceKey({ deviceName, userAgent, remoteAddress });
    const trusted = trustedDevices.has(key);
    const approved = Boolean(autoApproveTrusted && trusted);
    if (trusted) {
      const record = trustedDevices.get(key);
      record.lastSeenAt = Date.now();
      record.deviceName = deviceName || record.deviceName || "Trusted phone";
      record.remoteAddress = remoteAddress || record.remoteAddress || "";
      onTrustedDevicesChanged([...trustedDevices.values()]);
    }
    const session = {
      id: randomToken(12),
      token: randomToken(32),
      deviceName: deviceName || "Phone",
      userAgent: userAgent || "unknown",
      remoteAddress,
      allowedOrigin: origin || null,
      trusted,
      keepSignedIn: Boolean(keepSignedIn),
      trustKey: key,
      approved,
      connected: false,
      createdAt: Date.now(),
      approvedAt: approved ? Date.now() : null,
      lastSeenAt: Date.now(),
      expiresAt: Date.now() + SESSION_TTL_MS,
      permissions: {
        view: true,
        pointer: true,
        keyboard: true,
        text: true
      }
    };
    sessions.set(session.token, session);
    refreshPin();
    log(approved ? "auth.session.autoApprovedTrusted" : "auth.session.pending", {
      sessionId: session.id,
      deviceName: session.deviceName,
      remoteAddress
    });
    return { ok: true, session };
  }

  function approveSession(sessionId) {
    for (const session of sessions.values()) {
      if (session.id !== sessionId) continue;
      session.approved = true;
      session.approvedAt = Date.now();
      log("auth.session.approved", { sessionId, deviceName: session.deviceName });
      return session;
    }
    return null;
  }

  function trustSession(sessionId) {
    for (const session of sessions.values()) {
      if (session.id !== sessionId) continue;
      trustedDevices.set(session.trustKey, {
        key: session.trustKey,
        deviceName: session.deviceName,
        remoteAddress: session.remoteAddress || "",
        trustedAt: Date.now(),
        lastSeenAt: Date.now()
      });
      session.trusted = true;
      onTrustedDevicesChanged([...trustedDevices.values()]);
      log("auth.device.trusted", { sessionId, deviceName: session.deviceName });
      return true;
    }
    return false;
  }

  function listTrustedDevices() {
    return [...trustedDevices.values()].map((record) => ({
      id: trustedDeviceId(record.key),
      deviceName: record.deviceName || "Trusted phone",
      remoteAddress: record.remoteAddress || "",
      trustedAt: record.trustedAt,
      lastSeenAt: record.lastSeenAt
    }));
  }

  function revokeTrustedDevice(deviceId) {
    for (const [key, record] of trustedDevices.entries()) {
      if (trustedDeviceId(key) !== deviceId) continue;
      trustedDevices.delete(key);
      let revokedSessions = 0;
      const revokedSessionIds = [];
      for (const [token, session] of sessions.entries()) {
        if (session.trustKey === key) {
          sessions.delete(token);
          revokedSessions += 1;
          revokedSessionIds.push(session.id);
        }
      }
      onTrustedDevicesChanged([...trustedDevices.values()]);
      log("auth.device.revoked", { deviceId, deviceName: record.deviceName, revokedSessions });
      return { ok: true, revokedSessions, revokedSessionIds };
    }
    return { ok: false, revokedSessions: 0, revokedSessionIds: [] };
  }

  function clearTrustedDevices() {
    const removed = trustedDevices.size;
    let revokedSessions = 0;
    const revokedSessionIds = [];
    trustedDevices.clear();
    for (const [token, session] of sessions.entries()) {
      if (session.trusted) {
        sessions.delete(token);
        revokedSessions += 1;
        revokedSessionIds.push(session.id);
      }
    }
    onTrustedDevicesChanged([]);
    log("auth.devices.cleared", { removed, revokedSessions });
    return { removed, revokedSessions, revokedSessionIds };
  }

  function revokeSession(sessionId) {
    for (const [token, session] of sessions.entries()) {
      if (session.id !== sessionId) continue;
      sessions.delete(token);
      log("auth.session.revoked", { sessionId, deviceName: session.deviceName });
      return true;
    }
    return false;
  }

  function revokeAll(reason = "manual") {
    const revoked = sessions.size;
    sessions.clear();
    log("auth.sessions.revokedAll", { revoked, reason });
    return revoked;
  }

  function getSessionByToken(token) {
    const session = sessions.get(token);
    if (session && session.expiresAt <= Date.now()) {
      sessions.delete(token);
      log("auth.session.expired", { sessionId: session.id, deviceName: session.deviceName });
      return null;
    }
    if (session) session.lastSeenAt = Date.now();
    return session || null;
  }

  function listSessions() {
    return [...sessions.values()].map((session) => ({
      id: session.id,
      deviceName: session.deviceName,
      remoteAddress: session.remoteAddress,
      allowedOrigin: session.allowedOrigin,
      trusted: session.trusted,
      approved: session.approved,
      connected: session.connected,
      createdAt: session.createdAt,
      approvedAt: session.approvedAt,
      lastSeenAt: session.lastSeenAt,
      expiresAt: session.expiresAt,
      permissions: session.permissions
    }));
  }

  return {
    approveSession,
    createPendingSession,
    getPairingState,
    getSessionByToken,
    listTrustedDevices,
    revokeTrustedDevice,
    clearTrustedDevices,
    trustSession,
    listSessions,
    refreshPin,
    revokeAll,
    revokeSession
  };
}

module.exports = {
  PIN_RATE_LIMIT_LOCKOUT_MS,
  PIN_RATE_LIMIT_MAX_FAILURES,
  PIN_RATE_LIMIT_WINDOW_MS,
  SESSION_TTL_MS,
  createSessionStore,
  randomToken,
  trustedDeviceId,
  trustedDeviceKey
};

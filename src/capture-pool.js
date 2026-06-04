"use strict";

function cleanString(value, fallback = "", maxLength = 120) {
  return typeof value === "string" && value.trim()
    ? value.replace(/\s+/g, " ").trim().slice(0, maxLength)
    : fallback;
}

function cleanNumber(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function createEmptySlot(monitorId, now) {
  return {
    monitorId,
    sourceName: "",
    status: "idle",
    usable: false,
    peerId: "",
    captureUrl: "",
    lastLaunchAt: 0,
    lastSeenAt: 0,
    verification: null,
    error: "",
    updatedAt: now()
  };
}

function verificationMatches(monitorId, capture = {}) {
  const verification = capture.verification || {};
  return Boolean(
    capture.sharing
    && capture.requestedMonitor === monitorId
    && verification.status === "matched"
    && verification.actualMonitorId === monitorId
  );
}

function statusFromCapture(monitorId, capture = {}) {
  const verification = capture.verification || {};
  if (!capture.sharing) return "failed";
  if (verification.status === "matched" && verification.actualMonitorId === monitorId && capture.requestedMonitor === monitorId) {
    return "verified";
  }
  if (verification.status === "mismatch") return "mismatch";
  if (verification.status === "ambiguous") return "ambiguous";
  if (verification.status === "failed") return "failed";
  return "alive";
}

function createCapturePool({ now = () => Date.now(), staleAfterMs = 12000 } = {}) {
  const slots = new Map();

  function ensureSlot(monitorId) {
    const cleanMonitorId = cleanString(monitorId, "", 80);
    if (!cleanMonitorId) return null;
    if (!slots.has(cleanMonitorId)) slots.set(cleanMonitorId, createEmptySlot(cleanMonitorId, now));
    return slots.get(cleanMonitorId);
  }

  function withFreshness(slot) {
    const ageMs = slot.lastSeenAt ? Math.max(0, now() - slot.lastSeenAt) : 0;
    const stale = Boolean(slot.usable && ageMs > staleAfterMs);
    return {
      ...slot,
      status: stale ? "stale" : slot.status,
      usable: stale ? false : slot.usable,
      stale,
      ageMs
    };
  }

  function syncMonitors(monitors = []) {
    const seen = new Set();
    for (const monitor of Array.isArray(monitors) ? monitors : []) {
      const monitorId = cleanString(monitor?.id, "", 80);
      if (!monitorId) continue;
      seen.add(monitorId);
      ensureSlot(monitorId);
    }
    for (const [monitorId, slot] of slots.entries()) {
      if (!seen.has(monitorId)) {
        slot.status = "stale";
        slot.usable = false;
        slot.error = "Monitor is no longer connected.";
        slot.updatedAt = now();
      }
    }
    return publicState();
  }

  function markStarting(monitorId, details = {}) {
    const slot = ensureSlot(monitorId);
    if (!slot) return null;
    slot.sourceName = cleanString(details.sourceName, slot.sourceName, 120);
    slot.captureUrl = cleanString(details.captureUrl, slot.captureUrl, 500);
    slot.status = "starting";
    slot.usable = false;
    slot.error = "";
    slot.lastLaunchAt = now();
    slot.updatedAt = slot.lastLaunchAt;
    return withFreshness(slot);
  }

  function markAlive({ peerId = "", monitorId = "", capture = {}, captureUrl = "" } = {}) {
    const slot = ensureSlot(monitorId || capture.requestedMonitor);
    if (!slot) return null;
    slot.peerId = cleanString(peerId, "", 120);
    slot.captureUrl = cleanString(captureUrl, slot.captureUrl, 500);
    slot.sourceName = cleanString(capture.requestedSource, slot.sourceName, 120);
    slot.verification = capture.verification || null;
    slot.status = statusFromCapture(slot.monitorId, capture);
    slot.usable = verificationMatches(slot.monitorId, capture);
    slot.error = cleanString(capture.fallbackReason || capture.verification?.error, "", 180);
    slot.lastSeenAt = now();
    slot.updatedAt = slot.lastSeenAt;
    return withFreshness(slot);
  }

  function markPeerGone(peerId, reason = "peer-disconnected") {
    const cleanPeerId = cleanString(peerId, "", 120);
    for (const slot of slots.values()) {
      if (slot.peerId !== cleanPeerId) continue;
      slot.status = "stale";
      slot.usable = false;
      slot.error = cleanString(reason, "peer-disconnected", 180);
      slot.updatedAt = now();
      return withFreshness(slot);
    }
    return null;
  }

  function getSlot(monitorId) {
    const slot = slots.get(cleanString(monitorId, "", 80));
    return slot ? withFreshness(slot) : null;
  }

  function getUsableSlot(monitorId) {
    const slot = getSlot(monitorId);
    return slot?.usable ? slot : null;
  }

  function publicState() {
    return {
      slots: [...slots.values()].map(withFreshness)
    };
  }

  return {
    syncMonitors,
    markStarting,
    markAlive,
    markPeerGone,
    getSlot,
    getUsableSlot,
    publicState
  };
}

module.exports = {
  createCapturePool,
  verificationMatches
};

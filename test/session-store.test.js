"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { PIN_RATE_LIMIT_MAX_FAILURES, SESSION_TTL_MS, createSessionStore } = require("../src/session-store");

test("pairing creates pending session and approval unlocks it", () => {
  const events = [];
  const store = createSessionStore({ log: (event, detail) => events.push({ event, detail }) });
  const pairing = store.getPairingState();
  const failed = store.createPendingSession({ providedPin: "000000", deviceName: "Phone" });
  assert.equal(failed.ok, false);
  const created = store.createPendingSession({ providedPin: pairing.pin, deviceName: "Phone" });
  assert.equal(created.ok, true);
  assert.equal(created.session.approved, false);
  const approved = store.approveSession(created.session.id);
  assert.equal(approved.approved, true);
  assert.equal(store.getSessionByToken(created.session.token).approved, true);
  assert.equal(created.session.expiresAt > created.session.createdAt, true);
  assert.equal(created.session.expiresAt - created.session.createdAt <= SESSION_TTL_MS + 10, true);
  assert.equal(events.some((entry) => entry.event === "auth.session.approved"), true);
});

test("expired sessions fail closed and are removed", () => {
  const events = [];
  const store = createSessionStore({ log: (event, detail) => events.push({ event, detail }) });
  const pairing = store.getPairingState();
  const created = store.createPendingSession({ providedPin: pairing.pin, deviceName: "Old Phone" });
  created.session.expiresAt = Date.now() - 1;

  assert.equal(store.getSessionByToken(created.session.token), null);
  assert.equal(store.listSessions().length, 0);
  assert.equal(events.some((entry) => entry.event === "auth.session.expired"), true);
});

test("wrong pairing pins are rate limited per remote", () => {
  const events = [];
  const store = createSessionStore({ log: (event, detail) => events.push({ event, detail }) });
  const remoteAddress = "192.168.1.44";
  let result = null;

  for (let index = 0; index < PIN_RATE_LIMIT_MAX_FAILURES; index += 1) {
    result = store.createPendingSession({ providedPin: "111111", deviceName: "Phone", remoteAddress });
    assert.equal(result.ok, false);
  }

  const limited = store.createPendingSession({ providedPin: "111111", deviceName: "Phone", remoteAddress });
  assert.equal(limited.ok, false);
  assert.equal(limited.code, "PIN_RATE_LIMITED");
  assert.equal(limited.retryAfterSeconds > 0, true);
  assert.equal(store.getPairingState().rateLimit.lockedRemotes, 1);
  assert.equal(events.some((entry) => entry.event === "auth.pin.rateLimited"), true);
});

test("trusted devices still require a correct pin but can skip repeat approval", () => {
  const events = [];
  const store = createSessionStore({ log: (event, detail) => events.push({ event, detail }) });
  const device = {
    deviceName: "My Phone",
    userAgent: "Mobile Browser",
    remoteAddress: "192.168.1.55",
    origin: "http://192.168.1.2:4317"
  };

  const firstPairing = store.getPairingState();
  const first = store.createPendingSession({ providedPin: firstPairing.pin, ...device, autoApproveTrusted: true });
  assert.equal(first.ok, true);
  assert.equal(first.session.approved, false);
  assert.equal(store.trustSession(first.session.id), true);

  const secondPairing = store.getPairingState();
  const second = store.createPendingSession({ providedPin: secondPairing.pin, ...device, autoApproveTrusted: true });
  assert.equal(second.ok, true);
  assert.equal(second.session.approved, true);
  assert.equal(second.session.trusted, true);
  assert.equal(second.session.allowedOrigin, device.origin);
  assert.equal(events.some((entry) => entry.event === "auth.session.autoApprovedTrusted"), true);
});

test("pairing can request keeping a device signed in", () => {
  const events = [];
  const trustedChanges = [];
  const store = createSessionStore({
    log: (event, detail) => events.push({ event, detail }),
    onTrustedDevicesChanged: (devices) => trustedChanges.push(devices)
  });
  const device = {
    deviceName: "iPhone",
    userAgent: "Mobile Safari",
    remoteAddress: "192.168.0.21",
    origin: "http://192.168.0.7:4317"
  };
  const first = store.createPendingSession({
    providedPin: store.getPairingState().pin,
    ...device,
    keepSignedIn: true,
    autoApproveTrusted: true
  });
  assert.equal(first.session.keepSignedIn, true);
  assert.equal(first.session.approved, false);
  store.approveSession(first.session.id);
  assert.equal(store.trustSession(first.session.id), true);
  assert.equal(trustedChanges.at(-1).length, 1);

  const second = store.createPendingSession({
    providedPin: store.refreshPin().pin,
    ...device,
    keepSignedIn: true,
    autoApproveTrusted: true
  });
  assert.equal(second.session.approved, true);
  assert.equal(second.session.trusted, true);
  assert.equal(events.some((entry) => entry.event === "auth.device.trusted"), true);
});

test("trusted devices can be listed, revoked, and cleared without exposing raw keys", () => {
  const events = [];
  const changes = [];
  const store = createSessionStore({
    log: (event, detail) => events.push({ event, detail }),
    onTrustedDevicesChanged: (devices) => changes.push(devices)
  });
  const device = {
    deviceName: "Lost Phone",
    userAgent: "Mobile Browser",
    remoteAddress: "192.168.1.77"
  };

  const first = store.createPendingSession({ providedPin: store.getPairingState().pin, ...device });
  assert.equal(first.ok, true);
  assert.equal(store.trustSession(first.session.id), true);

  const listed = store.listTrustedDevices();
  assert.equal(listed.length, 1);
  assert.equal(listed[0].deviceName, "Lost Phone");
  assert.equal(listed[0].remoteAddress, "192.168.1.77");
  assert.equal(Object.hasOwn(listed[0], "key"), false);
  assert.equal(changes.at(-1)[0].key.length > 16, true);

  const revoked = store.revokeTrustedDevice(listed[0].id);
  assert.equal(revoked.ok, true);
  assert.equal(revoked.revokedSessions, 1);
  assert.deepEqual(revoked.revokedSessionIds, [first.session.id]);
  assert.equal(store.getSessionByToken(first.session.token), null);
  assert.equal(store.listTrustedDevices().length, 0);
  assert.equal(events.some((entry) => entry.event === "auth.device.revoked"), true);

  const second = store.createPendingSession({ providedPin: store.getPairingState().pin, ...device });
  store.trustSession(second.session.id);
  const cleared = store.clearTrustedDevices();
  assert.equal(cleared.removed, 1);
  assert.equal(cleared.revokedSessions, 1);
  assert.equal(store.listTrustedDevices().length, 0);
});

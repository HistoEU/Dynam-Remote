"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { makeError, makeMessage, PROTOCOL_VERSION, nextActionForCode, validateClientMessage } = require("../src/protocol");
const {
  formatAddressUrl,
  isPrivateIPv4,
  isTailscaleIPv4,
  isTailscaleIPv6,
  classifyAddress,
  getNetworkRisk,
  getNetworkValidation,
  isAllowedRemoteAddress,
  normalizeRemoteAddress
} = require("../src/network");
const { encodeFrame, decodeFrames } = require("../src/ws");

test("protocol messages are versioned and validated", () => {
  const now = Date.now();
  const msg = makeMessage("pointer.move", { dx: 1, dy: 2 }, { sequence: 1, timestamp: now });
  assert.equal(msg.protocolVersion, PROTOCOL_VERSION);
  assert.equal(validateClientMessage(msg, { now }).ok, true);
  assert.equal(validateClientMessage(makeMessage("pointer.doubleClick", { button: "left" }, { sequence: 2, timestamp: now }), { now, lastSequence: 1 }).ok, true);
  assert.equal(validateClientMessage(makeMessage("pointer.cancelDrag", {}, { sequence: 3, timestamp: now }), { now }).ok, true);
  assert.equal(validateClientMessage(makeMessage("chord", { modifiers: ["Ctrl"], key: "C" }, { sequence: 4, timestamp: now }), { now }).ok, true);
  assert.equal(validateClientMessage(makeMessage("pasteText", { text: "hello" }, { sequence: 5, timestamp: now }), { now }).ok, true);
  assert.equal(validateClientMessage(makeMessage("stream.visibility", { visible: false }, { sequence: 6, timestamp: now }), { now }).ok, true);
  assert.equal(validateClientMessage(makeMessage("acceptance.mark", { marker: "manual-phone-proof" }, { sequence: 7, timestamp: now }), { now }).ok, true);
  assert.equal(validateClientMessage({ ...msg, protocolVersion: 99 }).code, "BAD_PROTOCOL_VERSION");
  assert.equal(validateClientMessage({ ...msg, type: "bad" }).code, "BAD_TYPE");
  assert.equal(validateClientMessage(makeMessage("hello", {}, { sequence: 8, timestamp: now }), { now }).code, "BAD_CLIENT_TYPE");
  assert.equal(validateClientMessage(makeMessage("pointer.move", {}, { timestamp: now }), { now }).code, "BAD_SEQUENCE");
  assert.equal(validateClientMessage(makeMessage("pointer.move", {}, { sequence: 1, timestamp: now }), { now, lastSequence: 1 }).code, "STALE_SEQUENCE");
  assert.equal(validateClientMessage(makeMessage("pointer.move", {}, { sequence: 9, timestamp: now - 61000 }), { now }).code, "STALE_TIMESTAMP");
  assert.equal(validateClientMessage(makeMessage("pointer.move", {}, { sequence: 10, timestamp: now + 11000 }), { now }).code, "FUTURE_TIMESTAMP");
  assert.equal(validateClientMessage(makeMessage("pointer.move", [], { sequence: 11, timestamp: now }), { now }).code, "BAD_PAYLOAD");
});

test("protocol error envelopes include recoverability and next action guidance", () => {
  const badMonitor = makeError("BAD_MONITOR", "That monitor is not available.");
  assert.equal(badMonitor.type, "error");
  assert.equal(badMonitor.payload.code, "BAD_MONITOR");
  assert.equal(badMonitor.payload.recoverable, true);
  assert.match(badMonitor.payload.nextAction, /Monitors/);

  const custom = makeError("CUSTOM", "Custom failure.", { detail: true }, false, "Do the custom recovery.");
  assert.equal(custom.payload.recoverable, false);
  assert.deepEqual(custom.payload.detail, { detail: true });
  assert.equal(custom.payload.nextAction, "Do the custom recovery.");
  assert.equal(nextActionForCode("UNKNOWN_CODE"), "Check the host console, then retry the action.");
});

test("private and tailscale addresses are classified", () => {
  assert.equal(isPrivateIPv4("192.168.0.7"), true);
  assert.equal(isPrivateIPv4("100.80.1.2"), true);
  assert.equal(isTailscaleIPv4("100.80.1.2"), true);
  assert.equal(isTailscaleIPv6("fd7a:115c:a1e0:ab12:4843:cd96:627e:9975"), true);
  assert.equal(isPrivateIPv4("8.8.8.8"), false);
  assert.equal(classifyAddress("100.80.1.2"), "tailscale");
  assert.equal(classifyAddress("fd7a:115c:a1e0:ab12:4843:cd96:627e:9975"), "tailscale");
  assert.equal(classifyAddress("10.0.0.2"), "lan");
  assert.equal(formatAddressUrl("fd7a:115c:a1e0:ab12:4843:cd96:627e:9975", 4317), "http://[fd7a:115c:a1e0:ab12:4843:cd96:627e:9975]:4317");
  assert.equal(getNetworkRisk([{ kind: "lan" }]).level, "lan");
  assert.equal(getNetworkRisk([{ kind: "tailscale" }]).level, "tailscale");
  assert.equal(getNetworkRisk([{ kind: "tunnel" }]).level, "public-tunnel");
});

test("remote network guard allows loopback and private networks by default", () => {
  assert.equal(normalizeRemoteAddress("::ffff:192.168.0.7"), "192.168.0.7");
  assert.equal(normalizeRemoteAddress("::1"), "127.0.0.1");
  assert.equal(isAllowedRemoteAddress("127.0.0.1"), true);
  assert.equal(isAllowedRemoteAddress("::ffff:127.0.0.1"), true);
  assert.equal(isAllowedRemoteAddress("192.168.0.7"), true);
  assert.equal(isAllowedRemoteAddress("100.80.1.2"), true);
  assert.equal(isAllowedRemoteAddress("fd7a:115c:a1e0:ab12:4843:cd96:627e:9975"), true);
  assert.equal(isAllowedRemoteAddress("2001:4860:4860::8888"), false);
  assert.equal(isAllowedRemoteAddress("8.8.8.8"), false);
  assert.equal(isAllowedRemoteAddress("8.8.8.8", { allowPublic: true }), true);
});

test("network validation explains LAN, Tailscale, and tunnel readiness", () => {
  const validation = getNetworkValidation([
    { kind: "lan", name: "Wi-Fi", url: "http://192.168.0.7:4317" },
    { kind: "tailscale", name: "Tailscale", url: "http://[fd7a:115c:a1e0:ab12:4843:cd96:627e:9975]:4317" },
    { kind: "tunnel", name: "Public tunnel", url: "https://example.trycloudflare.com" }
  ]);
  assert.equal(validation.sameWifi.status, "ready");
  assert.equal(validation.sameWifi.url, "http://192.168.0.7:4317");
  assert.equal(validation.tailscale.status, "ready");
  assert.equal(validation.tailscale.url, "http://[fd7a:115c:a1e0:ab12:4843:cd96:627e:9975]:4317");
  assert.equal(validation.tunnel.status, "testing-only");

  const missing = getNetworkValidation([]);
  assert.equal(missing.sameWifi.status, "missing");
  assert.equal(missing.tailscale.status, "missing");
  assert.equal(missing.tunnel.status, "off");
});

test("websocket text frames round trip", () => {
  const encoded = encodeFrame(JSON.stringify({ hello: true }));
  const decoded = decodeFrames(encoded);
  assert.equal(decoded.remaining.length, 0);
  assert.equal(decoded.messages.length, 1);
  assert.deepEqual(JSON.parse(decoded.messages[0].data), { hello: true });
});

test("websocket binary frames round trip", () => {
  const payload = Buffer.from([0x52, 0x44, 0x43, 0x46, 0, 0, 0, 2, 0x7b, 0x7d]);
  const encoded = encodeFrame(payload, { opcode: 0x2 });
  const decoded = decodeFrames(encoded);
  assert.equal(decoded.remaining.length, 0);
  assert.equal(decoded.messages.length, 1);
  assert.equal(decoded.messages[0].type, "binary");
  assert.deepEqual(decoded.messages[0].data, payload);
});

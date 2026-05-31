"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { createRtcRoom, validateSignalMessage } = require("../src/rtc-room");

function createHarness() {
  let clock = 1000;
  let id = 0;
  const sent = [];
  const events = [];
  const room = createRtcRoom({
    now: () => {
      clock += 1;
      return clock;
    },
    idFactory: () => `peer-${++id}`,
    send: (peer, message) => sent.push({ to: peer.role, peerId: peer.id, message }),
    log: (event, detail) => events.push({ event, detail })
  });
  return { room, sent, events };
}

test("rtc room connects one host and one phone with public state", () => {
  const { room, sent, events } = createHarness();
  const host = room.connectPeer({ role: "host", label: "Capture page" });
  assert.equal(host.ok, true);
  assert.equal(room.getState().hostConnected, true);
  assert.equal(room.getState().phoneConnected, false);
  assert.equal(room.getState().state, "waiting");

  const phone = room.connectPeer({ role: "phone", sessionId: "session-1", label: "iPhone" });
  assert.equal(phone.ok, true);
  assert.equal(room.getState().state, "ready");
  assert.equal(room.getState().hostConnected, true);
  assert.equal(room.getState().phoneConnected, true);
  assert.equal(sent.some((item) => item.message.type === "rtc.peerJoined" && item.to === "host"), true);
  assert.equal(events.some((item) => item.event === "rtc.peer.connected" && item.detail.role === "phone"), true);
});

test("rtc room routes host offer, phone answer, and ice candidates", () => {
  const { room, sent } = createHarness();
  const host = room.connectPeer({ role: "host" }).peer;
  const phone = room.connectPeer({ role: "phone", sessionId: "session-1" }).peer;
  sent.length = 0;

  const offer = { type: "offer", sdp: "v=0\r\no=- host-offer" };
  const offered = room.handleMessage(host.id, { type: "rtc.offer", payload: offer });
  assert.equal(offered.ok, true);
  assert.equal(room.getState().state, "negotiating");
  assert.equal(room.getState().negotiationId, 1);
  assert.equal(sent.at(-1).to, "phone");
  assert.equal(sent.at(-1).message.type, "rtc.offer");
  assert.deepEqual(sent.at(-1).message.payload, offer);

  const answer = { type: "answer", sdp: "v=0\r\no=- phone-answer" };
  const answered = room.handleMessage(phone.id, { type: "rtc.answer", payload: answer });
  assert.equal(answered.ok, true);
  assert.equal(room.getState().state, "connected");
  assert.equal(sent.at(-1).to, "host");
  assert.equal(sent.at(-1).message.type, "rtc.answer");

  const candidate = { candidate: { candidate: "candidate:1 udp 2122260223 192.168.0.7 5000 typ host" } };
  const iced = room.handleMessage(host.id, { type: "rtc.ice", payload: candidate });
  assert.equal(iced.ok, true);
  assert.equal(sent.at(-1).to, "phone");
  assert.equal(sent.at(-1).message.type, "rtc.ice");
});

test("rtc room rejects invalid role messages and reports errors to sender", () => {
  const { room, sent } = createHarness();
  const host = room.connectPeer({ role: "host" }).peer;
  sent.length = 0;

  const result = room.handleMessage(host.id, { type: "rtc.answer", payload: { type: "answer", sdp: "v=0" } });
  assert.equal(result.ok, false);
  assert.equal(result.code, "BAD_RTC_TYPE");
  assert.equal(room.getState().state, "failed");
  assert.equal(sent.at(-1).to, "host");
  assert.equal(sent.at(-1).message.type, "rtc.error");
});

test("rtc room replaces stale peers and notifies the remaining side", () => {
  const { room, sent } = createHarness();
  const oldHost = room.connectPeer({ role: "host" }).peer;
  room.connectPeer({ role: "phone", sessionId: "session-1" });
  sent.length = 0;

  const freshHost = room.connectPeer({ role: "host", label: "Refreshed capture page" });
  assert.equal(freshHost.ok, true);
  assert.equal(freshHost.replacedPeerId, oldHost.id);
  assert.equal(room.getState().host.id, freshHost.peer.id);
  assert.equal(room.getState().state, "ready");
  assert.equal(sent.some((item) => item.to === "phone" && item.message.type === "rtc.peerLeft"), true);
  assert.equal(sent.some((item) => item.to === "phone" && item.message.type === "rtc.peerJoined"), true);
});

test("rtc room clears state when peers disconnect", () => {
  const { room, sent } = createHarness();
  const host = room.connectPeer({ role: "host" }).peer;
  room.connectPeer({ role: "phone", sessionId: "session-1" });
  sent.length = 0;

  const disconnected = room.disconnectPeer(host.id, "test-close");
  assert.equal(disconnected.ok, true);
  assert.equal(room.getState().hostConnected, false);
  assert.equal(room.getState().phoneConnected, true);
  assert.equal(room.getState().state, "waiting");
  assert.equal(sent.at(-1).to, "phone");
  assert.equal(sent.at(-1).message.type, "rtc.peerLeft");
});

test("rtc signal validation accepts null end-of-candidates markers", () => {
  const result = validateSignalMessage("host", {
    protocol: "remote-controller-rtc",
    version: 1,
    type: "rtc.ice",
    payload: { candidate: null }
  });
  assert.equal(result.ok, true);
});

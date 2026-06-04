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

test("rtc room keeps separate monitor hosts and routes only the selected host", () => {
  const { room, sent } = createHarness();
  const hostOne = room.connectPeer({
    role: "host",
    label: "Capture display 1",
    metadata: {
      monitorId: "display-1",
      captureUrl: "http://127.0.0.1:4334/rtc?monitor=display-1&slot=display-1"
    }
  }).peer;
  const hostTwo = room.connectPeer({
    role: "host",
    label: "Capture display 2",
    metadata: {
      monitorId: "display-2",
      captureUrl: "http://127.0.0.1:4334/rtc?monitor=display-2&slot=display-2"
    }
  }).peer;
  const phone = room.connectPeer({ role: "phone", sessionId: "session-1" }).peer;

  const state = room.getState();
  assert.equal(state.hostConnected, true);
  assert.equal(state.hosts.length, 2);
  assert.equal(state.hosts.find((host) => host.monitorId === "display-1").id, hostOne.id);
  assert.equal(state.hosts.find((host) => host.monitorId === "display-2").id, hostTwo.id);
  assert.match(state.hosts.find((host) => host.monitorId === "display-1").captureUrl, /slot=display-1/);
  assert.match(state.hosts.find((host) => host.monitorId === "display-2").captureUrl, /slot=display-2/);
  assert.equal(state.host.monitorId, "display-1");

  room.setSelectedMonitor("display-2");
  assert.equal(room.getState().host.monitorId, "display-2");
  sent.length = 0;

  const ignoredOffer = room.handleMessage(hostOne.id, {
    type: "rtc.offer",
    payload: { type: "offer", sdp: "v=0\r\no=- wrong-monitor" }
  });
  assert.equal(ignoredOffer.ok, true);
  assert.equal(ignoredOffer.routed, false);
  assert.equal(sent.length, 0);

  const selectedOffer = { type: "offer", sdp: "v=0\r\no=- display-2-offer" };
  const offered = room.handleMessage(hostTwo.id, { type: "rtc.offer", payload: selectedOffer });
  assert.equal(offered.ok, true);
  assert.equal(offered.routed, true);
  assert.equal(sent.at(-1).to, "phone");
  assert.equal(sent.at(-1).message.type, "rtc.offer");
  assert.equal(sent.at(-1).message.fromMonitorId, "display-2");
  assert.deepEqual(sent.at(-1).message.payload, selectedOffer);

  sent.length = 0;
  const answer = { type: "answer", sdp: "v=0\r\no=- phone-answer" };
  const answered = room.handleMessage(phone.id, { type: "rtc.answer", payload: answer });
  assert.equal(answered.ok, true);
  assert.equal(sent.at(-1).to, "host");
  assert.equal(sent.at(-1).peerId, hostTwo.id);
  assert.equal(sent.at(-1).message.type, "rtc.answer");
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

test("rtc room sanitizes capture source and performance diagnostics", () => {
  const { room } = createHarness();
  const host = room.connectPeer({ role: "host", label: "Capture page" }).peer;

  const result = room.handleMessage(host.id, {
    type: "rtc.status",
    payload: {
      sharing: true,
      width: "2560",
      height: "1440",
      frameRate: "59.94",
      displaySurface: "monitor",
      reportedSource: "monitor selected by browser",
      audioTracks: 0,
      audioSource: "system-output-only",
      microphone: true,
      requestedMonitor: "display-2",
      requestedSource: "Screen 2",
      connectionState: "connected",
      iceConnectionState: "completed",
      firstFrameTimeMs: "421",
      staleCaptureAgeMs: "13001",
      fallbackReason: "manual source confirmation required",
      verification: {
        status: "mismatch",
        requestedMonitor: "display-2",
        requestedSource: "Screen 2",
        actualMonitorId: "display-1",
        score: "0.913",
        requestedScore: "0.541",
        runnerUpMonitorId: "display-2",
        runnerUpScore: "0.541",
        scores: [
          { monitorId: "display-1", score: "0.913", name: "Display 1" },
          { monitorId: "display-2", score: "0.541", name: "Display 2" },
          { monitorId: "display-3", score: "0.212", name: "Display 3", error: "too dark" }
        ],
        comparedAt: "1234567",
        reason: "video fingerprint matched display-1",
        probeUsed: true
      }
    }
  });

  assert.equal(result.ok, true);
  const capture = room.getState().host.capture;
  assert.equal(capture.sharing, true);
  assert.equal(capture.width, 2560);
  assert.equal(capture.height, 1440);
  assert.equal(capture.frameRate, 59.94);
  assert.equal(capture.reportedSource, "monitor selected by browser");
  assert.equal(capture.connectionState, "connected");
  assert.equal(capture.iceConnectionState, "completed");
  assert.equal(capture.firstFrameTimeMs, 421);
  assert.equal(capture.staleCaptureAgeMs, 13001);
  assert.equal(capture.fallbackReason, "manual source confirmation required");
  assert.equal(capture.requestedMonitor, "display-2");
  assert.equal(capture.requestedSource, "Screen 2");
  assert.equal(capture.verification.status, "mismatch");
  assert.equal(capture.verification.actualMonitorId, "display-1");
  assert.equal(capture.verification.score, 0.913);
  assert.equal(capture.verification.requestedScore, 0.541);
  assert.equal(capture.verification.runnerUpMonitorId, "display-2");
  assert.equal(capture.verification.runnerUpScore, 0.541);
  assert.deepEqual(capture.verification.scores, [
    { monitorId: "display-1", score: 0.913, name: "Display 1", error: "" },
    { monitorId: "display-2", score: 0.541, name: "Display 2", error: "" },
    { monitorId: "display-3", score: 0.212, name: "Display 3", error: "too dark" }
  ]);
  assert.equal(capture.verification.probeUsed, true);
  assert.equal(capture.verification.reason, "video fingerprint matched display-1");
});

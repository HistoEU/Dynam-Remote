"use strict";

const crypto = require("node:crypto");

const RTC_PROTOCOL = "remote-controller-rtc";
const RTC_VERSION = 1;
const VALID_ROLES = new Set(["host", "phone"]);
const HOST_MESSAGE_TYPES = new Set(["rtc.ready", "rtc.offer", "rtc.ice", "rtc.stop", "rtc.status", "rtc.ping"]);
const PHONE_MESSAGE_TYPES = new Set(["rtc.ready", "rtc.answer", "rtc.ice", "rtc.stop", "rtc.status", "rtc.ping"]);

function isObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function cleanPeer(peer) {
  return {
    id: peer.id,
    role: peer.role,
    monitorId: peer.monitorId || "",
    label: peer.label || peer.role,
    sessionId: peer.sessionId || null,
    wantsAllMonitors: Boolean(peer.metadata?.wantsAllMonitors),
    captureUrl: peer.metadata?.captureUrl || "",
    capture: peer.metadata?.capture || null,
    connectedAt: peer.connectedAt,
    lastSeenAt: peer.lastSeenAt
  };
}

function cleanString(value, maxLength = 120) {
  return typeof value === "string" ? value.replace(/\s+/g, " ").trim().slice(0, maxLength) : "";
}

function cleanNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
}

function cleanCaptureVerificationScore(payload = {}) {
  if (!isObject(payload)) return null;
  return {
    monitorId: cleanString(payload.monitorId, 80),
    score: cleanNumber(payload.score),
    name: cleanString(payload.name, 80),
    error: cleanString(payload.error, 160)
  };
}

function cleanCaptureVerification(payload = {}) {
  if (!isObject(payload)) return null;
  const scores = Array.isArray(payload.scores)
    ? payload.scores.map(cleanCaptureVerificationScore).filter(Boolean).slice(0, 8)
    : [];
  return {
    status: cleanString(payload.status, 40),
    requestedMonitor: cleanString(payload.requestedMonitor, 80),
    requestedSource: cleanString(payload.requestedSource, 120),
    actualMonitorId: cleanString(payload.actualMonitorId, 80),
    score: cleanNumber(payload.score),
    requestedScore: cleanNumber(payload.requestedScore),
    runnerUpMonitorId: cleanString(payload.runnerUpMonitorId, 80),
    runnerUpScore: cleanNumber(payload.runnerUpScore),
    scores,
    probeUsed: Boolean(payload.probeUsed),
    comparedAt: cleanNumber(payload.comparedAt),
    reason: cleanString(payload.reason, 180),
    error: cleanString(payload.error, 160)
  };
}

function cleanCaptureMetadata(payload = {}) {
  return {
    sharing: Boolean(payload.sharing),
    width: cleanNumber(payload.width),
    height: cleanNumber(payload.height),
    frameRate: cleanNumber(payload.frameRate),
    displaySurface: cleanString(payload.displaySurface, 80),
    reportedSource: cleanString(payload.reportedSource || payload.displaySurface, 120),
    audioTracks: cleanNumber(payload.audioTracks),
    audioSource: cleanString(payload.audioSource, 80),
    microphone: Boolean(payload.microphone),
    requestedMonitor: cleanString(payload.requestedMonitor, 80),
    requestedSource: cleanString(payload.requestedSource, 120),
    connectionState: cleanString(payload.connectionState, 40),
    iceConnectionState: cleanString(payload.iceConnectionState, 40),
    firstFrameTimeMs: cleanNumber(payload.firstFrameTimeMs),
    staleCaptureAgeMs: cleanNumber(payload.staleCaptureAgeMs),
    fallbackReason: cleanString(payload.fallbackReason, 160),
    verification: cleanCaptureVerification(payload.verification),
    updatedAt: Date.now()
  };
}

function monitorIdFromMetadata(metadata = {}) {
  const captureMonitor = metadata?.capture?.requestedMonitor;
  const monitorId = metadata?.monitorId || metadata?.slotMonitorId || captureMonitor;
  return cleanString(monitorId, 80) || "default";
}

function phoneWantsAllMonitorsPayload(payload = {}) {
  const wants = cleanString(payload.wants || payload.mode || payload.viewMode, 80).toLowerCase();
  return wants === "all-screen-video"
    || wants === "all-monitors"
    || wants === "virtual-desktop"
    || wants === "virtual-ultrawide"
    || Boolean(payload.allMonitors || payload.virtualDesktop);
}

function cleanMonitorIdList(value = []) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map((item) => cleanString(item, 80)).filter(Boolean))].slice(0, 16);
}

function validateSignalMessage(role, message) {
  if (!isObject(message)) return { ok: false, code: "BAD_RTC_JSON", message: "RTC signaling message must be a JSON object." };
  if (message.protocol && message.protocol !== RTC_PROTOCOL) {
    return { ok: false, code: "BAD_RTC_PROTOCOL", message: "RTC signaling protocol does not match this server." };
  }
  if (message.version && message.version !== RTC_VERSION) {
    return { ok: false, code: "BAD_RTC_VERSION", message: "RTC signaling version is not supported." };
  }
  const type = String(message.type || "");
  const allowed = role === "host" ? HOST_MESSAGE_TYPES : PHONE_MESSAGE_TYPES;
  if (!allowed.has(type)) return { ok: false, code: "BAD_RTC_TYPE", message: `RTC message type ${type || "(missing)"} is not allowed for ${role}.` };
  const payload = isObject(message.payload) ? message.payload : {};
  if (type === "rtc.offer" || type === "rtc.answer") {
    if (payload.type !== "offer" && payload.type !== "answer") {
      return { ok: false, code: "BAD_RTC_DESCRIPTION", message: "RTC session description type is invalid." };
    }
    if (typeof payload.sdp !== "string" || payload.sdp.length < 8) {
      return { ok: false, code: "BAD_RTC_DESCRIPTION", message: "RTC session description SDP is missing." };
    }
  }
  if (type === "rtc.ice" && payload.candidate !== null && payload.candidate !== undefined && !isObject(payload.candidate)) {
    return { ok: false, code: "BAD_RTC_ICE", message: "RTC ICE payload must contain a candidate object or null." };
  }
  return { ok: true, type, payload };
}

function createRtcRoom({ send, log = () => {}, now = () => Date.now(), idFactory = () => crypto.randomUUID() } = {}) {
  if (typeof send !== "function") throw new TypeError("createRtcRoom requires a send(peer, message) function.");
  const peers = new Map();
  const hostPeers = new Map();
  let phonePeer = null;
  let selectedMonitorId = "";
  let negotiationId = 0;
  let state = "idle";
  let lastError = null;
  let updatedAt = now();

  function activeHost() {
    if (selectedMonitorId && hostPeers.has(selectedMonitorId)) return hostPeers.get(selectedMonitorId);
    return hostPeers.values().next().value || null;
  }

  function syncState(preferred = "") {
    const hasHost = Boolean(activeHost());
    if (preferred) {
      state = preferred;
    } else if (hasHost && phonePeer) {
      state = "ready";
    } else if (hasHost || phonePeer) {
      state = "waiting";
    } else {
      state = "idle";
    }
    updatedAt = now();
  }

  function touch(nextState = state) {
    state = nextState;
    updatedAt = now();
  }

  function publicState() {
    const host = activeHost();
    const hosts = [...hostPeers.values()].map(cleanPeer);
    return {
      available: true,
      state,
      negotiationId,
      updatedAt,
      lastError,
      hostConnected: hosts.length > 0,
      phoneConnected: Boolean(phonePeer),
      selectedMonitorId,
      host: host ? cleanPeer(host) : null,
      hosts,
      phone: phonePeer ? cleanPeer(phonePeer) : null
    };
  }

  function sendTo(peer, message) {
    if (!peer) return false;
    send(peer, {
      protocol: RTC_PROTOCOL,
      version: RTC_VERSION,
      at: now(),
      negotiationId,
      ...message
    });
    return true;
  }

  function sendToRole(role, message) {
    if (role === "host") return sendTo(activeHost(), message);
    if (role === "phone") return sendTo(phonePeer, message);
    return false;
  }

  function phoneWantsAllMonitors() {
    return Boolean(phonePeer?.metadata?.wantsAllMonitors);
  }

  function hostForMonitor(monitorId = "") {
    const cleanMonitorId = cleanString(monitorId, 80);
    if (cleanMonitorId && hostPeers.has(cleanMonitorId)) return hostPeers.get(cleanMonitorId);
    return activeHost();
  }

  function monitorTargetFromMessage(message = {}, payload = {}) {
    return cleanString(
      message.toMonitorId
      || message.targetMonitorId
      || payload.toMonitorId
      || payload.targetMonitorId
      || payload.monitorId,
      80
    );
  }

  function sendError(peer, code, message) {
    lastError = { code, message, at: now(), peerRole: peer?.role || null };
    touch("failed");
    sendTo(peer, { type: "rtc.error", payload: { code, message } });
    log("rtc.error", { code, message, role: peer?.role || null, peerId: peer?.id || null });
  }

  function disconnectPeer(peerId, reason = "socket-closed") {
    const peer = peers.get(peerId);
    if (!peer) return { ok: false, state: publicState() };
    peers.delete(peerId);
    if (peer.role === "host") {
      if (hostPeers.get(peer.monitorId)?.id === peer.id) hostPeers.delete(peer.monitorId);
      if (phonePeer) {
        sendTo(phonePeer, {
          type: "rtc.peerLeft",
          from: peer.role,
          fromMonitorId: peer.monitorId,
          payload: { role: peer.role, monitorId: peer.monitorId, reason }
        });
      }
      syncState(phonePeer ? "waiting" : "");
    } else {
      if (phonePeer?.id === peer.id) phonePeer = null;
      for (const host of hostPeers.values()) {
        sendTo(host, { type: "rtc.peerLeft", from: peer.role, payload: { role: peer.role, reason } });
      }
      syncState(hostPeers.size ? "waiting" : "");
    }
    log("rtc.peer.disconnected", { role: peer.role, peerId: peer.id, monitorId: peer.monitorId || "", reason });
    return { ok: true, peer, state: publicState() };
  }

  function connectPeer({ role, socket = null, label = "", sessionId = null, metadata = {} } = {}) {
    if (!VALID_ROLES.has(role)) return { ok: false, code: "BAD_RTC_ROLE", message: "RTC role must be host or phone." };
    const monitorId = role === "host" ? monitorIdFromMetadata(metadata) : "";
    const replaced = role === "host" ? hostPeers.get(monitorId) : phonePeer;
    if (replaced) disconnectPeer(replaced.id, "replaced");
    const peer = {
      id: idFactory(),
      role,
      monitorId,
      socket,
      label,
      sessionId,
      metadata,
      connectedAt: now(),
      lastSeenAt: now()
    };
    peers.set(peer.id, peer);
    if (role === "host") {
      hostPeers.set(monitorId, peer);
      if (!selectedMonitorId || selectedMonitorId === "default") selectedMonitorId = monitorId;
    } else {
      phonePeer = peer;
    }
    lastError = null;
    syncState();
    log("rtc.peer.connected", { role, peerId: peer.id, sessionId, monitorId });
    sendTo(peer, { type: "rtc.hello", payload: { peer: cleanPeer(peer), room: publicState() } });
    if (role === "host") {
      if (phonePeer) {
        sendTo(phonePeer, {
          type: "rtc.peerJoined",
          from: role,
          fromMonitorId: monitorId,
          payload: { peer: cleanPeer(peer), room: publicState() }
        });
        sendTo(peer, { type: "rtc.peerJoined", from: phonePeer.role, payload: { peer: cleanPeer(phonePeer), room: publicState() } });
      }
    } else {
      for (const host of hostPeers.values()) {
        sendTo(host, { type: "rtc.peerJoined", from: role, payload: { peer: cleanPeer(peer), room: publicState() } });
        sendTo(peer, {
          type: "rtc.peerJoined",
          from: host.role,
          fromMonitorId: host.monitorId,
          payload: { peer: cleanPeer(host), room: publicState() }
        });
      }
    }
    return { ok: true, peer, replacedPeerId: replaced?.id || null, state: publicState() };
  }

  function rekeyHostPeer(peer, nextMonitorId) {
    if (!peer || peer.role !== "host") return;
    const cleanMonitorId = cleanString(nextMonitorId, 80) || peer.monitorId || "default";
    if (cleanMonitorId === peer.monitorId) return;
    if (hostPeers.get(peer.monitorId)?.id === peer.id) hostPeers.delete(peer.monitorId);
    peer.monitorId = cleanMonitorId;
    hostPeers.set(cleanMonitorId, peer);
    if (!selectedMonitorId || selectedMonitorId === "default") selectedMonitorId = cleanMonitorId;
  }

  function setSelectedMonitor(monitorId) {
    selectedMonitorId = cleanString(monitorId, 80);
    syncState();
    log("rtc.monitor.selected", { monitorId: selectedMonitorId, activeHostPeerId: activeHost()?.id || null });
    return publicState();
  }

  function handleMessage(peerId, rawMessage) {
    const peer = peers.get(peerId);
    if (!peer) return { ok: false, code: "RTC_PEER_NOT_FOUND", message: "RTC peer is no longer connected." };
    let message = rawMessage;
    if (typeof rawMessage === "string") {
      try {
        message = JSON.parse(rawMessage);
      } catch {
        sendError(peer, "BAD_RTC_JSON", "RTC signaling message was not valid JSON.");
        return { ok: false, code: "BAD_RTC_JSON" };
      }
    }
    const validation = validateSignalMessage(peer.role, message);
    if (!validation.ok) {
      sendError(peer, validation.code, validation.message);
      return validation;
    }
    peer.lastSeenAt = now();
    if (peer.role === "host" && ["rtc.ready", "rtc.ping", "rtc.status"].includes(validation.type)) {
      peer.metadata.capture = cleanCaptureMetadata(validation.payload);
      rekeyHostPeer(peer, peer.metadata.capture.requestedMonitor);
    }
    if (peer.role === "phone" && validation.type === "rtc.ready") {
      peer.metadata.wantsAllMonitors = phoneWantsAllMonitorsPayload(validation.payload);
    }
    const selectedHost = activeHost();
    const routedTypes = new Set(["rtc.offer", "rtc.answer", "rtc.ice", "rtc.stop", "rtc.status"]);
    const targetMonitorId = monitorTargetFromMessage(message, validation.payload);
    const other = peer.role === "host"
      ? ((phoneWantsAllMonitors() || selectedHost?.id === peer.id) ? phonePeer : null)
      : (targetMonitorId ? hostForMonitor(targetMonitorId) : selectedHost);
    if (validation.type === "rtc.ping") {
      sendTo(peer, { type: "rtc.pong", payload: { room: publicState() } });
      return { ok: true, routed: false, state: publicState() };
    }
    if (validation.type === "rtc.status" && !other) {
      return { ok: true, routed: false, state: publicState() };
    }
    if (validation.type === "rtc.ready") {
      sendTo(peer, { type: "rtc.readyAck", payload: { room: publicState() } });
      if (peer.role === "phone" && peer.metadata.wantsAllMonitors) {
        const requestedMonitorIds = cleanMonitorIdList(validation.payload.missingMonitorIds || validation.payload.monitorIds);
        const targetHosts = requestedMonitorIds.length
          ? requestedMonitorIds.map((monitorId) => hostPeers.get(monitorId)).filter(Boolean)
          : [...hostPeers.values()];
        for (const host of targetHosts) {
          sendTo(host, {
            type: "rtc.peerReady",
            from: peer.role,
            payload: { room: publicState() }
          });
        }
        return { ok: true, routed: targetHosts.length > 0, state: publicState() };
      }
      if (other) {
        sendTo(other, {
          type: "rtc.peerReady",
          from: peer.role,
          fromMonitorId: peer.monitorId || "",
          payload: { room: publicState() }
        });
      }
      return { ok: true, routed: Boolean(other), state: publicState() };
    }
    if (peer.role === "host" && routedTypes.has(validation.type) && !phoneWantsAllMonitors() && selectedHost?.id !== peer.id) {
      log("rtc.host.messageIgnored", {
        type: validation.type,
        peerId: peer.id,
        monitorId: peer.monitorId,
        selectedMonitorId
      });
      return { ok: true, routed: false, state: publicState() };
    }
    if (!other) {
      sendError(peer, "RTC_PEER_WAITING", "The other RTC peer is not connected yet.");
      touch("waiting");
      return { ok: false, code: "RTC_PEER_WAITING", state: publicState() };
    }
    if (validation.type === "rtc.offer") {
      negotiationId += 1;
      touch("negotiating");
    } else if (validation.type === "rtc.answer") {
      touch("connected");
    } else if (validation.type === "rtc.stop") {
      touch("stopped");
    }
    if (routedTypes.has(validation.type)) {
      sendTo(other, {
        type: validation.type,
        from: peer.role,
        fromMonitorId: peer.monitorId || "",
        toMonitorId: peer.role === "phone" ? (other.monitorId || "") : "",
        payload: validation.payload
      });
      return { ok: true, routed: true, state: publicState() };
    }
    return { ok: true, routed: false, state: publicState() };
  }

  function reset(reason = "manual") {
    for (const peer of [...peers.values()]) {
      sendTo(peer, { type: "rtc.stop", payload: { reason } });
    }
    peers.clear();
    hostPeers.clear();
    phonePeer = null;
    selectedMonitorId = "";
    negotiationId += 1;
    lastError = null;
    touch("idle");
    log("rtc.room.reset", { reason });
    return publicState();
  }

  return {
    connectPeer,
    disconnectPeer,
    getState: publicState,
    handleMessage,
    setSelectedMonitor,
    sendToRole,
    reset
  };
}

module.exports = {
  RTC_PROTOCOL,
  RTC_VERSION,
  createRtcRoom,
  validateSignalMessage
};

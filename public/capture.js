"use strict";

const params = new URLSearchParams(location.search);
const hostKey = params.get("key") || "";
const autoStart = params.get("autostart") === "1";
const requestedSource = params.get("source") || "this screen";
const requestedMonitor = params.get("monitor") || "";
const RTC_HEARTBEAT_MS = 2000;
const DISPLAY_OUTPUT_AUDIO = {
  systemAudio: "include",
  suppressLocalAudioPlayback: false,
  echoCancellation: false,
  noiseSuppression: false,
  autoGainControl: false
};
const el = {
  status: document.getElementById("captureStatus"),
  start: document.getElementById("startCaptureBtn"),
  stop: document.getElementById("stopCaptureBtn"),
  preview: document.getElementById("capturePreview"),
  signal: document.getElementById("signalState"),
  phone: document.getElementById("phoneState"),
  video: document.getElementById("videoState"),
  ice: document.getElementById("iceState"),
  source: document.getElementById("sourceState"),
  firstFrame: document.getElementById("firstFrameState"),
  hostConsole: document.getElementById("hostConsoleLink")
};

const capture = {
  ws: null,
  pc: null,
  stream: null,
  phoneReady: false,
  makingOffer: false,
  queuedIce: [],
  startedAt: 0,
  firstFrameAt: 0,
  fallbackReason: "",
  statsTimer: null
};

setInterval(() => {
  sendRtc("rtc.ping", currentCaptureMeta());
}, RTC_HEARTBEAT_MS);

if (hostKey) {
  el.hostConsole.href = `/host?key=${encodeURIComponent(hostKey)}`;
}

function setStatus(message, parts = {}) {
  el.status.textContent = message;
  if (parts.signal) el.signal.textContent = parts.signal;
  if (parts.phone) el.phone.textContent = parts.phone;
  if (parts.video) el.video.textContent = parts.video;
  if (parts.ice && el.ice) el.ice.textContent = parts.ice;
  if (parts.source && el.source) el.source.textContent = parts.source;
  if (parts.firstFrame && el.firstFrame) el.firstFrame.textContent = parts.firstFrame;
  updateCaptureDiagnosticsUi();
}

function sendRtc(type, payload = {}) {
  if (!capture.ws || capture.ws.readyState !== WebSocket.OPEN) return false;
  capture.ws.send(JSON.stringify({
    protocol: "remote-controller-rtc",
    version: 1,
    type,
    at: Date.now(),
    payload
  }));
  return true;
}

function hideCaptureWindowSoon(reason = "capture-sharing") {
  for (const delayMs of [80, 450, 1200]) {
    setTimeout(() => {
      fetch(`/api/hide-capture-window?reason=${encodeURIComponent(`${reason}-${delayMs}ms`)}`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-host-key": hostKey
        },
        body: "{}"
      }).catch(() => {});
    }, delayMs);
  }
}

function connectSignal() {
  if (!hostKey) {
    setStatus("Missing host key. Open this from the Host Console.", { signal: "blocked" });
    return;
  }
  if (capture.ws && [WebSocket.CONNECTING, WebSocket.OPEN].includes(capture.ws.readyState)) return;
  const scheme = location.protocol === "https:" ? "wss" : "ws";
  capture.ws = new WebSocket(`${scheme}://${location.host}/rtc?role=host&key=${encodeURIComponent(hostKey)}`);
  setStatus("Connecting the low-latency signal channel...", { signal: "connecting" });
  capture.ws.addEventListener("open", () => {
    setStatus("Signal ready. Waiting for the phone if it is not already connected.", { signal: "ready" });
    sendRtc("rtc.ready", currentCaptureMeta());
    if (autoStart && !capture.stream) {
      setTimeout(() => {
        void startCapture();
      }, 120);
    }
    if (capture.phoneReady && capture.stream) void makeOffer();
  });
  capture.ws.addEventListener("message", (event) => {
    void handleSignal(event.data);
  });
  capture.ws.addEventListener("close", () => {
    setStatus("Signal disconnected. Reconnecting...", { signal: "reconnecting" });
    closePeer();
    setTimeout(connectSignal, 1000);
  });
  capture.ws.addEventListener("error", () => {
    setStatus("Signal failed. Refresh this page if it does not reconnect.", { signal: "error" });
  });
}

function currentCaptureMeta() {
  const track = capture.stream?.getVideoTracks()[0];
  const settings = track?.getSettings?.() || {};
  const width = Number(settings.width || 0);
  const height = Number(settings.height || 0);
  const reportedSource = String(settings.displaySurface || (track ? "unknown" : "")).slice(0, 80);
  return {
    sharing: Boolean(track),
    width,
    height,
    frameRate: settings.frameRate || 0,
    displaySurface: settings.displaySurface || "",
    reportedSource,
    audioTracks: capture.stream?.getAudioTracks?.().length || 0,
    audioSource: "system-output-only",
    microphone: false,
    requestedMonitor,
    requestedSource,
    connectionState: capture.pc?.connectionState || "",
    iceConnectionState: capture.pc?.iceConnectionState || "",
    firstFrameTimeMs: capture.startedAt && capture.firstFrameAt ? capture.firstFrameAt - capture.startedAt : 0,
    staleCaptureAgeMs: 0,
    fallbackReason: capture.fallbackReason || ""
  };
}

function updateCaptureDiagnosticsUi() {
  const meta = currentCaptureMeta();
  if (el.source) {
    const size = meta.width && meta.height ? ` ${meta.width}x${meta.height}` : "";
    el.source.textContent = `${meta.reportedSource || "unknown"}${size}`;
  }
  if (el.ice) el.ice.textContent = meta.iceConnectionState || "idle";
  if (el.firstFrame) {
    el.firstFrame.textContent = meta.firstFrameTimeMs ? `${meta.firstFrameTimeMs}ms` : "waiting";
  }
}

function markFirstFrame() {
  if (!capture.startedAt || capture.firstFrameAt) return;
  capture.firstFrameAt = Date.now();
  updateCaptureDiagnosticsUi();
  sendRtc("rtc.status", currentCaptureMeta());
}

function startStatsTimer() {
  clearInterval(capture.statsTimer);
  capture.statsTimer = setInterval(() => {
    updateCaptureDiagnosticsUi();
    sendRtc("rtc.status", currentCaptureMeta());
  }, 2000);
}

function stopStatsTimer() {
  clearInterval(capture.statsTimer);
  capture.statsTimer = null;
}

async function startCapture() {
  try {
    if (!navigator.mediaDevices?.getDisplayMedia) {
      setStatus("This browser cannot share the screen. Open this page in Chrome or Edge from the Host Console.", { video: "unsupported" });
      return;
    }
    setStatus(`Starting ${requestedSource}. Choose it if Chrome asks.`, { video: "asking permission" });
    capture.startedAt = Date.now();
    capture.firstFrameAt = 0;
    capture.fallbackReason = "";
    const stream = await navigator.mediaDevices.getDisplayMedia({
      video: {
        displaySurface: "monitor",
        frameRate: { ideal: 45, max: 60 },
        cursor: "always"
      },
      audio: DISPLAY_OUTPUT_AUDIO
    });
    capture.stream = stream;
    for (const track of stream.getVideoTracks()) {
      try {
        track.contentHint = "motion";
      } catch {}
    }
    el.preview.srcObject = stream;
    el.preview.addEventListener("loadeddata", markFirstFrame, { once: true });
    el.preview.addEventListener("playing", markFirstFrame, { once: true });
    el.start.disabled = true;
    el.stop.disabled = false;
    stream.getVideoTracks()[0].addEventListener("unmute", markFirstFrame, { once: true });
    stream.getVideoTracks()[0].addEventListener("ended", () => stopCapture("screen-share-ended"));
    const audioCount = stream.getAudioTracks().length;
    setStatus(`Sharing ${requestedSource}${audioCount ? " with audio" : ""}. Keep this page open while using the phone.`, { video: "sharing" });
    startStatsTimer();
    hideCaptureWindowSoon("capture-sharing");
    connectSignal();
    sendRtc("rtc.ready", currentCaptureMeta());
    if (capture.phoneReady) await makeOffer();
  } catch (error) {
    const denied = /denied|permission|not allowed/i.test(error.message || "");
    const message = denied
      ? "Screen sharing was blocked. Use the default Chrome or Edge window opened from Host Console, then click Start again."
      : `Screen sharing did not start: ${error.message}`;
    capture.fallbackReason = denied ? "permission-denied" : String(error.message || "capture-start-failed").slice(0, 160);
    setStatus(message, { video: "not sharing" });
    el.start.disabled = false;
    el.stop.disabled = true;
    sendRtc("rtc.status", currentCaptureMeta());
  }
}

function closePeer() {
  if (!capture.pc) return;
  capture.pc.onicecandidate = null;
  capture.pc.onconnectionstatechange = null;
  capture.pc.oniceconnectionstatechange = null;
  capture.pc.close();
  capture.pc = null;
  capture.queuedIce = [];
}

function stopCapture(reason = "manual") {
  capture.fallbackReason = reason;
  sendRtc("rtc.stop", { reason });
  closePeer();
  stopStatsTimer();
  for (const track of capture.stream?.getTracks?.() || []) track.stop();
  capture.stream = null;
  capture.startedAt = 0;
  capture.firstFrameAt = 0;
  el.preview.srcObject = null;
  el.start.disabled = false;
  el.stop.disabled = true;
  setStatus("Stopped. Start again when you want live video.", { video: "not sharing" });
}

function ensurePeer() {
  closePeer();
  const pc = new RTCPeerConnection({ iceServers: [] });
  for (const track of capture.stream.getTracks()) {
    if (track.kind === "video") {
      try {
        track.contentHint = "motion";
      } catch {}
    }
    const sender = pc.addTrack(track, capture.stream);
    if (track.kind !== "video") continue;
    try {
      const params = sender.getParameters();
      params.degradationPreference = "maintain-framerate";
      params.encodings = Array.isArray(params.encodings) && params.encodings.length ? params.encodings : [{}];
      params.encodings[0].maxFramerate = 60;
      params.encodings[0].scaleResolutionDownBy = 1;
      sender.setParameters(params).catch(() => {});
    } catch {}
  }
  pc.onicecandidate = (event) => {
    sendRtc("rtc.ice", { candidate: event.candidate ? event.candidate.toJSON() : null });
  };
  pc.onconnectionstatechange = () => {
    const state = pc.connectionState;
    setStatus(
      state === "connected" ? "Live video is connected to the phone." : `Video connection: ${state}`,
      { signal: state, phone: capture.phoneReady ? "connected" : "waiting", ice: pc.iceConnectionState }
    );
    sendRtc("rtc.status", currentCaptureMeta());
  };
  pc.oniceconnectionstatechange = () => {
    setStatus(`ICE connection: ${pc.iceConnectionState}`, { ice: pc.iceConnectionState });
    sendRtc("rtc.status", currentCaptureMeta());
  };
  capture.pc = pc;
  return pc;
}

async function makeOffer() {
  if (!capture.stream || capture.makingOffer) return;
  capture.makingOffer = true;
  try {
    const pc = ensurePeer();
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    sendRtc("rtc.offer", pc.localDescription.toJSON());
    setStatus("Offer sent. Waiting for the phone answer.", { signal: "negotiating", phone: "answering" });
  } finally {
    capture.makingOffer = false;
  }
}

async function flushQueuedIce() {
  if (!capture.pc?.remoteDescription) return;
  const queued = capture.queuedIce.splice(0);
  for (const candidate of queued) {
    await capture.pc.addIceCandidate(candidate ? new RTCIceCandidate(candidate) : null);
  }
}

async function handleSignal(raw) {
  let message;
  try {
    message = JSON.parse(raw);
  } catch {
    return;
  }
  if (message.type === "rtc.hello") {
    setStatus("Signal ready. Start sharing, then open the phone controller.", { signal: "ready" });
    return;
  }
  if (message.type === "rtc.startCapture") {
    if (!capture.stream) {
      setStatus("Phone requested video. Starting screen capture...", { video: "auto-start" });
      await startCapture();
    } else if (capture.phoneReady) {
      await makeOffer();
    }
    return;
  }
  if (message.type === "rtc.peerJoined" || message.type === "rtc.peerReady") {
    if (message.from === "phone" || message.payload?.peer?.role === "phone") {
      capture.phoneReady = true;
      setStatus(capture.stream ? "Phone ready. Starting video negotiation." : "Phone ready. Start sharing this screen.", { phone: "ready" });
      if (autoStart && !capture.stream) {
        setTimeout(() => {
          void startCapture();
        }, 120);
      }
      if (capture.stream) await makeOffer();
    }
    return;
  }
  if (message.type === "rtc.answer") {
    if (!capture.pc) return;
    await capture.pc.setRemoteDescription(new RTCSessionDescription(message.payload));
    await flushQueuedIce();
    setStatus("Live video connected.", { signal: "connected", phone: "connected", video: "live" });
    return;
  }
  if (message.type === "rtc.ice") {
    const candidate = message.payload?.candidate ?? null;
    if (!capture.pc?.remoteDescription) {
      capture.queuedIce.push(candidate);
      return;
    }
    await capture.pc.addIceCandidate(candidate ? new RTCIceCandidate(candidate) : null);
    return;
  }
  if (message.type === "rtc.peerLeft") {
    capture.phoneReady = false;
    closePeer();
    setStatus("Phone disconnected. Keep sharing open, then reconnect the phone.", { phone: "waiting" });
    return;
  }
  if (message.type === "rtc.error") {
    setStatus(message.payload?.message || "RTC signaling error.", { signal: "error" });
  }
}

el.start.addEventListener("click", startCapture);
el.stop.addEventListener("click", () => stopCapture("manual"));
connectSignal();
if (autoStart) {
  setStatus(`Auto-start is armed for ${requestedSource}.`, { video: "auto-start" });
}

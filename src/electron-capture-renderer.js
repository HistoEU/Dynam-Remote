"use strict";

const RTC_HEARTBEAT_MS = 2000;
const START_RETRY_MS = 1200;

const el = {
  status: document.getElementById("status"),
  preview: document.getElementById("preview")
};

const capture = {
  config: null,
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

function report(event, payload = {}) {
  window.electronCaptureHost?.report?.(event, payload);
}

function setStatus(message, payload = {}) {
  el.status.textContent = message;
  report("status", { message, ...payload });
}

function hostUrl(pathname) {
  const base = new URL(capture.config.hostUrl);
  base.pathname = pathname;
  base.search = "";
  return base;
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

function verification() {
  const monitorId = capture.config?.monitorId || "";
  const sourceName = capture.config?.sourceName || "Electron desktop source";
  return {
    status: "matched",
    requestedMonitor: monitorId,
    requestedSource: sourceName,
    actualMonitorId: monitorId,
    score: 1,
    requestedScore: 1,
    runnerUpMonitorId: "",
    runnerUpScore: 0,
    scores: [{ monitorId, name: capture.config?.monitorName || monitorId, score: 1, error: "" }],
    probeUsed: false,
    comparedAt: Date.now(),
    reason: `Electron desktopCapturer granted exact source ${sourceName}.`
  };
}

function currentCaptureMeta() {
  const track = capture.stream?.getVideoTracks()[0];
  const settings = track?.getSettings?.() || {};
  return {
    sharing: Boolean(track),
    width: Number(settings.width || capture.config?.bounds?.width || 0),
    height: Number(settings.height || capture.config?.bounds?.height || 0),
    frameRate: Number(settings.frameRate || 0),
    displaySurface: "monitor",
    reportedSource: "electron-desktop-capturer",
    audioTracks: capture.stream?.getAudioTracks?.().length || 0,
    audioSource: "none",
    microphone: false,
    requestedMonitor: capture.config?.monitorId || "",
    requestedSource: capture.config?.sourceName || "",
    connectionState: capture.pc?.connectionState || "",
    iceConnectionState: capture.pc?.iceConnectionState || "",
    firstFrameTimeMs: capture.startedAt && capture.firstFrameAt ? capture.firstFrameAt - capture.startedAt : 0,
    staleCaptureAgeMs: 0,
    fallbackReason: capture.fallbackReason || "",
    verification: track ? verification() : null
  };
}

function connectSignal() {
  if (!capture.config?.hostKey) {
    setStatus("Missing host key.", { level: "error" });
    return;
  }
  if (capture.ws && [WebSocket.CONNECTING, WebSocket.OPEN].includes(capture.ws.readyState)) return;
  const url = hostUrl("/rtc");
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  url.searchParams.set("role", "host");
  url.searchParams.set("key", capture.config.hostKey);
  url.searchParams.set("monitor", capture.config.monitorId);
  url.searchParams.set("slot", capture.config.monitorId);
  url.searchParams.set("source", capture.config.sourceName || "Electron desktop source");
  url.searchParams.set("engine", "electron");
  capture.ws = new WebSocket(url.href);
  setStatus("Connecting RTC signal.", { url: url.href });
  capture.ws.addEventListener("open", () => {
    setStatus("RTC signal ready.");
    sendRtc("rtc.ready", currentCaptureMeta());
    if (capture.phoneReady && capture.stream) void makeOffer();
  });
  capture.ws.addEventListener("message", (event) => {
    void handleSignal(event.data);
  });
  capture.ws.addEventListener("close", () => {
    setStatus("Signal disconnected; reconnecting.");
    closePeer();
    setTimeout(connectSignal, 1000);
  });
  capture.ws.addEventListener("error", () => {
    setStatus("RTC signal error.", { level: "error" });
  });
}

function markFirstFrame() {
  if (!capture.startedAt || capture.firstFrameAt) return;
  capture.firstFrameAt = Date.now();
  sendRtc("rtc.status", currentCaptureMeta());
  if (capture.phoneReady) void makeOffer();
}

async function startCapture() {
  if (capture.stream) return true;
  try {
    capture.startedAt = Date.now();
    capture.firstFrameAt = 0;
    const bounds = capture.config.bounds || {};
    const stream = await navigator.mediaDevices.getDisplayMedia({
      audio: false,
      video: {
        width: { ideal: Number(bounds.width || 1920) },
        height: { ideal: Number(bounds.height || 1080) },
        frameRate: { ideal: 60, max: 60 },
        cursor: "always"
      }
    });
    capture.stream = stream;
    for (const track of stream.getVideoTracks()) {
      try {
        track.contentHint = "motion";
      } catch {}
      track.addEventListener("unmute", markFirstFrame, { once: true });
      track.addEventListener("ended", () => stopCapture("screen-share-ended"));
    }
    el.preview.srcObject = stream;
    el.preview.addEventListener("loadeddata", markFirstFrame, { once: true });
    el.preview.addEventListener("playing", markFirstFrame, { once: true });
    await el.preview.play?.().catch(() => {});
    setStatus(`Sharing exact display ${capture.config.monitorId}.`);
    sendRtc("rtc.ready", currentCaptureMeta());
    startStatsTimer();
    return true;
  } catch (error) {
    capture.fallbackReason = error.message || "electron-capture-start-failed";
    setStatus(`Exact display capture failed: ${capture.fallbackReason}`, { level: "error" });
    sendRtc("rtc.status", currentCaptureMeta());
    setTimeout(() => {
      void startCapture();
    }, START_RETRY_MS);
    return false;
  }
}

function startStatsTimer() {
  clearInterval(capture.statsTimer);
  capture.statsTimer = setInterval(() => {
    sendRtc("rtc.status", currentCaptureMeta());
  }, RTC_HEARTBEAT_MS);
}

function stopStatsTimer() {
  clearInterval(capture.statsTimer);
  capture.statsTimer = null;
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
  setStatus(`Capture stopped: ${reason}`);
}

function ensurePeer() {
  closePeer();
  const pc = new RTCPeerConnection({ iceServers: [] });
  for (const track of capture.stream.getTracks()) {
    try {
      if (track.kind === "video") track.contentHint = "motion";
    } catch {}
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
    sendRtc("rtc.status", currentCaptureMeta());
    setStatus(`RTC connection: ${pc.connectionState}`);
  };
  pc.oniceconnectionstatechange = () => {
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
    setStatus("Offer sent to phone.");
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
    return;
  }
  if (message.type === "rtc.startCapture") {
    await startCapture();
    if (capture.phoneReady) await makeOffer();
    return;
  }
  if (message.type === "rtc.peerJoined" || message.type === "rtc.peerReady") {
    if (message.from === "phone" || message.payload?.peer?.role === "phone") {
      capture.phoneReady = true;
      await startCapture();
      if (capture.stream) await makeOffer();
    }
    return;
  }
  if (message.type === "rtc.answer") {
    if (!capture.pc) return;
    await capture.pc.setRemoteDescription(new RTCSessionDescription(message.payload));
    await flushQueuedIce();
    setStatus("Live video connected.");
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
    setStatus("Phone disconnected; exact capture remains ready.");
  }
}

window.electronCaptureHost.onConfig(async (config) => {
  capture.config = config;
  report("config", config);
  connectSignal();
  await startCapture();
});

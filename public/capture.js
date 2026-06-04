"use strict";

const params = new URLSearchParams(location.search);
const hostKey = params.get("key") || "";
const autoStart = params.get("autostart") === "1";
const requestedSource = params.get("source") || "this screen";
const requestedMonitor = params.get("monitor") || "";
const requestedSlot = params.get("slot") || requestedMonitor;
const debugProbe = params.get("debugProbe") === "1";
const RTC_HEARTBEAT_MS = 2000;
const CAPTURE_VERIFY_SAMPLE_W = 64;
const CAPTURE_VERIFY_SAMPLE_H = 36;
const CAPTURE_VERIFY_DELAY_MS = 420;
const CAPTURE_VERIFY_RETRY_MS = 1800;
const CAPTURE_VERIFY_REFRESH_MS = 9000;
const CAPTURE_VERIFY_MATCH_SCORE = 0.74;
const CAPTURE_VERIFY_AMBIGUOUS_GAP = 0.018;
const CAPTURE_VERIFY_MISMATCH_GAP = 0.018;
const CAPTURE_VERIFY_PROBE_DELAY_MS = 220;
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
  verification: null,
  verifying: false,
  verifyTimer: null,
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
      const hideUrl = new URL("/api/hide-capture-window", location.origin);
      hideUrl.searchParams.set("reason", `${reason}-${delayMs}ms`);
      if (requestedSlot) hideUrl.searchParams.set("monitor", requestedSlot);
      fetch(hideUrl.href, {
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
  const rtcUrl = new URL(`${scheme}://${location.host}/rtc`);
  rtcUrl.searchParams.set("role", "host");
  rtcUrl.searchParams.set("key", hostKey);
  if (requestedMonitor) rtcUrl.searchParams.set("monitor", requestedMonitor);
  if (requestedSlot) rtcUrl.searchParams.set("slot", requestedSlot);
  if (requestedSource) rtcUrl.searchParams.set("source", requestedSource);
  capture.ws = new WebSocket(rtcUrl.href);
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
    fallbackReason: capture.fallbackReason || "",
    verification: capture.verification || null
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

function captureVerifiedForOffer() {
  if (!requestedMonitor) return true;
  return Boolean(
    capture.verification?.status === "matched"
    && capture.verification?.actualMonitorId === requestedMonitor
  );
}

function markFirstFrame() {
  if (!capture.startedAt || capture.firstFrameAt) return;
  capture.firstFrameAt = Date.now();
  updateCaptureDiagnosticsUi();
  sendRtc("rtc.status", currentCaptureMeta());
  scheduleCaptureVerification("first-frame", CAPTURE_VERIFY_DELAY_MS);
}

function scheduleCaptureVerification(reason = "scheduled", delayMs = CAPTURE_VERIFY_REFRESH_MS) {
  clearTimeout(capture.verifyTimer);
  capture.verifyTimer = setTimeout(() => {
    capture.verifyTimer = null;
    void verifyCaptureSource(reason);
  }, Math.max(0, Number(delayMs) || 0));
}

function sourceSize(source) {
  return {
    width: Number(source.videoWidth || source.naturalWidth || source.width || 0),
    height: Number(source.videoHeight || source.naturalHeight || source.height || 0)
  };
}

function probeRegion(source) {
  const size = sourceSize(source);
  if (!size.width || !size.height) return null;
  return {
    x: 0,
    y: 0,
    width: Math.max(1, Math.round(size.width * 0.34)),
    height: Math.max(1, Math.round(size.height * 0.28))
  };
}

function sampleDrawable(source, options = {}) {
  const canvas = document.createElement("canvas");
  canvas.width = CAPTURE_VERIFY_SAMPLE_W;
  canvas.height = CAPTURE_VERIFY_SAMPLE_H;
  const context = canvas.getContext("2d", { willReadFrequently: true });
  if (!context) return null;
  const region = options.region === "probe" ? probeRegion(source) : null;
  if (region) {
    context.drawImage(source, region.x, region.y, region.width, region.height, 0, 0, canvas.width, canvas.height);
  } else {
    context.drawImage(source, 0, 0, canvas.width, canvas.height);
  }
  const pixels = context.getImageData(0, 0, canvas.width, canvas.height).data;
  const values = [];
  for (let index = 0; index < pixels.length; index += 4) {
    values.push(pixels[index], pixels[index + 1], pixels[index + 2]);
  }
  return values;
}

async function drawableFromBlob(blob) {
  if (typeof createImageBitmap === "function") {
    return createImageBitmap(blob);
  }
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.addEventListener("load", () => resolve(image), { once: true });
    image.addEventListener("error", () => reject(new Error("Reference image failed to load.")), { once: true });
    image.src = URL.createObjectURL(blob);
  });
}

async function fingerprintReference(monitorId, options = {}) {
  const response = await fetch(`/api/capture-reference?monitor=${encodeURIComponent(monitorId)}&_=${Date.now()}`, {
    headers: { "x-host-key": hostKey }
  });
  if (!response.ok) throw new Error(`Reference ${monitorId} failed with ${response.status}.`);
  const blob = await response.blob();
  const drawable = await drawableFromBlob(blob);
  try {
    return sampleDrawable(drawable, options);
  } finally {
    if (typeof drawable.close === "function") drawable.close();
    if (drawable instanceof HTMLImageElement && drawable.src?.startsWith("blob:")) URL.revokeObjectURL(drawable.src);
  }
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, Math.max(0, Number(ms) || 0)));
}

async function requestCaptureProbe(reason = "verify") {
  if (!requestedMonitor) return null;
  try {
    const probeUrl = new URL("/api/capture-probe", location.origin);
    probeUrl.searchParams.set("reason", reason);
    const response = await fetch(probeUrl.href, {
      headers: { "x-host-key": hostKey }
    });
    if (!response.ok) return null;
    return response.json();
  } catch {
    return null;
  }
}

function compareFingerprints(a = [], b = []) {
  const length = Math.min(a.length, b.length);
  if (!length) return 0;
  let squaredDiff = 0;
  for (let index = 0; index < length; index += 1) {
    const diff = Number(a[index] || 0) - Number(b[index] || 0);
    squaredDiff += diff * diff;
  }
  const rms = Math.sqrt(squaredDiff / length);
  const score = 1 - rms / 255;
  return Math.max(0, Math.min(1, Math.round(score * 10000) / 10000));
}

async function verifyCaptureSource(reason = "manual") {
  if (!capture.stream || capture.verifying) return false;
  const track = capture.stream.getVideoTracks()[0];
  if (!track || track.readyState === "ended") return false;
  if (!el.preview.videoWidth || !el.preview.videoHeight || el.preview.readyState < 2) {
    scheduleCaptureVerification(`${reason}-waiting-video`, CAPTURE_VERIFY_RETRY_MS);
    return false;
  }
  capture.verifying = true;
  try {
    const hostState = await fetch(`/api/host?key=${encodeURIComponent(hostKey)}&_=${Date.now()}`).then((response) => response.json());
    const monitors = Array.isArray(hostState.monitors) ? hostState.monitors.filter((monitor) => monitor?.id) : [];
    const probe = debugProbe && monitors.length > 1 ? await requestCaptureProbe(reason) : null;
    const probeActive = Boolean(probe?.ok || probe?.reused);
    if (probeActive) await wait(CAPTURE_VERIFY_PROBE_DELAY_MS);
    const sampleOptions = probeActive ? { region: "probe" } : {};
    const liveFingerprint = sampleDrawable(el.preview, sampleOptions);
    if (!liveFingerprint) throw new Error("Live video fingerprint could not be sampled.");
    const results = await Promise.all(monitors.map(async (monitor) => {
      try {
        const reference = await fingerprintReference(monitor.id, sampleOptions);
        return {
          monitorId: monitor.id,
          sourceId: monitor.sourceId || "",
          name: monitor.name || monitor.id,
          score: compareFingerprints(liveFingerprint, reference)
        };
      } catch (error) {
        return {
          monitorId: monitor.id,
          sourceId: monitor.sourceId || "",
          name: monitor.name || monitor.id,
          score: 0,
          error: error.message
        };
      }
    }));
    results.sort((a, b) => b.score - a.score);
    const best = results[0] || null;
    const runnerUp = results[1] || null;
    const requestedResult = results.find((result) => result.monitorId === requestedMonitor) || null;
    const gap = best && runnerUp ? best.score - runnerUp.score : best ? best.score : 0;
    const requestedGap = best && requestedResult ? best.score - requestedResult.score : 0;
    let status = "failed";
    let actualMonitorId = best?.monitorId || "";
    let verifyReason = "No monitor reference could be compared.";
    if (best && best.score >= CAPTURE_VERIFY_MATCH_SCORE && gap >= CAPTURE_VERIFY_AMBIGUOUS_GAP) {
      status = best.monitorId === requestedMonitor ? "matched" : "mismatch";
      verifyReason = status === "matched"
        ? `Video fingerprint matches ${requestedMonitor}.`
        : `Video fingerprint matched ${best.monitorId} while ${requestedMonitor} was requested.`;
    } else if (best && best.score >= CAPTURE_VERIFY_MATCH_SCORE && best.monitorId !== requestedMonitor && requestedGap >= CAPTURE_VERIFY_MISMATCH_GAP) {
      status = "mismatch";
      verifyReason = `Video fingerprint matched ${best.monitorId} while ${requestedMonitor} was requested.`;
    } else if (best) {
      status = "ambiguous";
      verifyReason = `Best visual match was ${best.monitorId}, but the score gap was too small.`;
    }
    capture.verification = {
      status,
      requestedMonitor,
      requestedSource,
      actualMonitorId,
      score: best?.score || 0,
      requestedScore: requestedResult?.score || 0,
      runnerUpMonitorId: runnerUp?.monitorId || "",
      runnerUpScore: runnerUp?.score || 0,
      scores: results.map((result) => ({
        monitorId: result.monitorId,
        name: result.name,
        score: result.score,
        error: result.error || ""
      })),
      probeUsed: probeActive,
      comparedAt: Date.now(),
      reason: verifyReason
    };
    sendRtc("rtc.status", currentCaptureMeta());
    if (status === "matched" && capture.phoneReady) await makeOffer();
    if (status === "mismatch" || status === "ambiguous" || status === "failed") {
      scheduleCaptureVerification(status, status === "mismatch" ? CAPTURE_VERIFY_REFRESH_MS : CAPTURE_VERIFY_RETRY_MS);
    }
    return status === "matched";
  } catch (error) {
    capture.verification = {
      status: "failed",
      requestedMonitor,
      requestedSource,
      actualMonitorId: "",
      score: 0,
      runnerUpMonitorId: "",
      runnerUpScore: 0,
      comparedAt: Date.now(),
      reason,
      error: error.message
    };
    sendRtc("rtc.status", currentCaptureMeta());
    scheduleCaptureVerification("failed", CAPTURE_VERIFY_RETRY_MS);
    return false;
  } finally {
    capture.verifying = false;
  }
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
      audio: DISPLAY_OUTPUT_AUDIO,
      monitorTypeSurfaces: "include",
      preferCurrentTab: false,
      selfBrowserSurface: "exclude",
      surfaceSwitching: "exclude"
    });
    capture.stream = stream;
    capture.verification = null;
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
    scheduleCaptureVerification("capture-started", CAPTURE_VERIFY_DELAY_MS);
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
  clearTimeout(capture.verifyTimer);
  capture.verifyTimer = null;
  capture.verification = null;
  capture.verifying = false;
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
  if (!captureVerifiedForOffer()) {
    setStatus(`Verifying ${requestedSource} before sending video.`, { signal: "verifying", video: "verifying" });
    scheduleCaptureVerification("offer-gated", CAPTURE_VERIFY_RETRY_MS);
    return;
  }
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

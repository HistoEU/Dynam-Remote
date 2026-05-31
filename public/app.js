"use strict";

const PROTOCOL_VERSION = 1;
const DEFAULT_POINTER_SPEED = 1.55;
const BINARY_STREAM_MAGIC = "RDCF";
const STREAM_WATCHDOG_MS = 1050;
const STREAM_STALL_MS = 4200;
const STREAM_RECONNECT_MS = 9500;
const STREAM_WAKE_POKE_MS = 900;
const STREAM_INITIAL_FRAME_RECONNECT_MS = 3800;
const STREAM_DECODE_RECONNECT_MS = 4600;
const STREAM_WAKE_BURST_INTERVAL_MS = 420;
const STREAM_WAKE_BURST_COUNT = 8;
const STREAM_RESUME_PROBE_MS = 850;
const FRAME_DECODE_STALL_MS = 1200;
const VISIBLE_STREAM_ASSERT_MS = 900;
const CANVAS_KEEPALIVE_PAINT_MS = 220;
const RTC_HEARTBEAT_MS = 2500;
const TOUCHPAD_VIRTUAL_GAIN = 1.34;
const TOUCHPAD_HINT_GAIN = 0.18;
const TOUCHPAD_EDGE_GAIN = 1.18;
const TOUCHPAD_EDGE_FRAME_MS = 16;
const TOUCHPAD_EDGE_SPEED_MIN = 330;
const TOUCHPAD_EDGE_SPEED_MAX = 920;
const TOUCHPAD_SMOOTHING_MIN = 0.42;
const TOUCHPAD_SMOOTHING_MAX = 0.78;
const TOUCHPAD_EDGE_SMOOTHING = 0.34;
const TOUCHPAD_SCROLL_EDGE_SPEED_MIN = 28;
const TOUCHPAD_SCROLL_EDGE_SPEED_MAX = 76;
const TOUCHPAD_SCROLL_EDGE_SMOOTHING = 0.28;
const ACK_CURSOR_HOLD_MS = 1400;
const CURSOR_LENS_MIN_W = 220;
const CURSOR_LENS_MAX_W = 460;
const CURSOR_LENS_VIEWPORT_W = 0.72;
const CURSOR_LENS_VIEWPORT_H = 0.78;
const CURSOR_LENS_MARGIN = 6;
const CURSOR_LENS_HOLD_MS = 520;
const CALIBRATION_STORAGE_KEY = "remote-monitor-calibrations";
const CALIBRATION_TARGETS = [
  { id: "top-left", label: "Top left", x: 0.04, y: 0.06 },
  { id: "top-right", label: "Top right", x: 0.96, y: 0.06 },
  { id: "bottom-left", label: "Bottom left", x: 0.04, y: 0.94 },
  { id: "bottom-right", label: "Bottom right", x: 0.96, y: 0.94 }
];

function normalizeAcceptanceGate(value = "") {
  const gate = String(value || "").trim().toLowerCase();
  return gate === "same-wifi" || gate === "tailscale" ? gate : "";
}

function cleanAcceptanceStep(value = "") {
  return String(value || "").replace(/\s+/g, " ").trim().slice(0, 80);
}

function formatAcceptanceGate(value = "") {
  const gate = normalizeAcceptanceGate(value);
  if (gate === "same-wifi") return "Same-Wi-Fi";
  if (gate === "tailscale") return "Tailscale";
  return "Manual";
}

function readAcceptanceContext() {
  const params = new URLSearchParams(location.search);
  const gate = normalizeAcceptanceGate(params.get("gate") || params.get("acceptanceGate"));
  const step = cleanAcceptanceStep(params.get("step") || "physical-phone-proof");
  return {
    enabled: gate !== "" || params.get("acceptance") === "1",
    gate,
    step
  };
}

const acceptanceContext = readAcceptanceContext();
const ACCEPTANCE_CHECKLISTS = {
  "same-wifi": [
    "Start from the LAN URL shown by the host console.",
    "Open the LAN URL from the phone on the same Wi-Fi.",
    "Pair with the current PIN and approve on the laptop.",
    "Confirm the phone sees the live selected monitor.",
    "Move with the touchpad, single-tap left click, double-tap right click, press-and-hold right click, double-tap drag a tab/window, scroll, use the keyboard sheet, compose text, switch monitor, reconnect, and press Stop.",
    "Confirm diagnostics enter responsive mode during input and settle after idle.",
    "Lock the phone or switch away from the PWA, then confirm hidden-stream mode and resume.",
    "Adjust scroll speed, touch halo, haptics, zoom, pinch pan, edge pan, and precision mode.",
    "Tap Mark Proof from the controller proof banner or phone Settings so the host logs the phone viewport, PWA mode, and diagnostics marker.",
    "Add the PWA to the home screen and confirm it reopens the remembered host session.",
    "Enable real input only after dry-run behavior is correct, then test one low-risk click/move/text action.",
    "Enable trusted devices, approve once manually, verify repeat correct-PIN pairing can auto-approve, then revoke trust.",
    "Confirm Stop All Control disables real input, releases held buttons, disconnects the phone, and revokes the session."
  ],
  tailscale: [
    "Install and start Tailscale on the laptop and phone.",
    "Sign both devices into the same Tailscale tailnet.",
    "Confirm the host console shows Different Wi-Fi as ready with a Tailscale IPv4 URL or bracketed IPv6 URL.",
    "Move the phone away from the laptop Wi-Fi path, for example cellular data with Tailscale still connected.",
    "Open the Tailscale URL from the phone.",
    "Pair with the current PIN and approve on the laptop.",
    "Tap Mark Proof from the controller proof banner or phone Settings so the exported host logs include the different-Wi-Fi phone marker.",
    "Confirm live selected-monitor viewing, dry-run input, real-input safety gating, reconnect, and Stop.",
    "Confirm Stop All Control disables real input, releases held buttons, disconnects the phone, and revokes the session."
  ]
};

const state = {
  token: localStorage.getItem("remote-token") || "",
  sessionId: localStorage.getItem("remote-session-id") || "",
  ws: null,
  rtcWs: null,
  rtcPc: null,
  rtcConnected: false,
  rtcActive: false,
  rtcStatus: "idle",
  rtcReconnectTimer: null,
  rtcRemoteStream: null,
  rtcVideoWidth: 0,
  rtcVideoHeight: 0,
  rtcIceQueue: [],
  connected: false,
  approved: false,
  selectedMonitorId: "display-1",
  monitors: [],
  captureLaunch: null,
  frame: null,
  inputMode: "touchpad",
  dragLock: false,
  precisionMode: false,
  viewportZoom: 1,
  viewportPanX: 0,
  viewportPanY: 0,
  autoFollowCursor: localStorage.getItem("remote-auto-follow-cursor") !== "0",
  cursorLensEnabled: localStorage.getItem("remote-cursor-lens") !== "0",
  cursorLensHold: localStorage.getItem("remote-cursor-lens-hold") === "1",
  cursorLensZoom: Number(localStorage.getItem("remote-cursor-lens-zoom") || 1.7),
  cursorLensSize: Number(localStorage.getItem("remote-cursor-lens-size") || 1),
  cursorLensActiveUntil: 0,
  cursorLensHoldTimer: null,
  followPausedUntil: 0,
  lastCursorMap: null,
  lastCursorLensBox: null,
  lastAckCursor: null,
  lastAckCursorAt: 0,
  calibrationMode: false,
  calibrationSamples: [],
  calibrationMessage: "",
  monitorCalibrations: loadMonitorCalibrations(),
  edgePanStats: {
    localMoves: 0
  },
  scrollSpeed: Number(localStorage.getItem("remote-scroll-speed") || 1),
  showHalo: localStorage.getItem("remote-show-halo") !== "0",
  hapticsEnabled: localStorage.getItem("remote-haptics") !== "0",
  hostClockOffsetMs: 0,
  hostClockSynced: false,
  lastHostClockSyncAt: 0,
  seq: 0,
  sensitivity: Number(localStorage.getItem("remote-sensitivity") || DEFAULT_POINTER_SPEED),
  lastPointer: null,
  lastFrameAt: 0,
  lastDecodedFrameAt: 0,
  connectedAt: 0,
  lastStreamWatchdogAt: 0,
  lastStreamWakePokeAt: 0,
  lastBlankCanvasWakeAt: 0,
  lastVisibleStreamAssertAt: 0,
  streamWakeBurstTimer: null,
  streamWakeBurstCount: 0,
  streamWatchdogReconnects: 0,
  streamWakePokes: 0,
  frameDecodeRecoveries: 0,
  frameDecodeErrors: 0,
  frameBlobFallbacks: 0,
  skippedBlackFrames: 0,
  canvasKeepalivePaints: 0,
  lastCanvasPaintAt: 0,
  latency: 0,
  frameImage: null,
  frameImageReady: false,
  frameImageSource: "",
  frameImageObjectUrl: "",
  pendingFrameImage: null,
  pendingFrameImageSource: "",
  pendingFrameImageObjectUrl: "",
  pendingFrameImageStartedAt: 0,
  pendingFrameImageAttempts: 0,
  queuedFrameImage: null,
  queuedFrameImageSource: "",
  queuedFrameImageObjectUrl: "",
  manualDisconnect: false,
  reconnectAttempts: 0,
  reconnectTimer: null,
  activePointers: new Map(),
  touchpadPointerId: null,
  touchpadPointers: new Map(),
  touchpadLastPoint: null,
  touchpadCursorX: 0.5,
  touchpadCursorY: 0.5,
  touchpadSent: 0,
  touchpadAcked: 0,
  touchpadLastError: "",
  touchpadEdgeHoldTimer: null,
  touchpadEdgeHoldVector: { x: 0, y: 0 },
  touchpadEdgeHoldLastAt: 0,
  touchpadSmoothDx: 0,
  touchpadSmoothDy: 0,
  touchpadGesture: null,
  touchpadLongPressTimer: null,
  touchpadLastTapAt: 0,
  touchpadLastTapPoint: null,
  touchpadDragActive: false,
  touchpadScrollGesture: null,
  touchpadScrollEdgeTimer: null,
  touchpadScrollEdgeVector: 0,
  touchpadScrollEdgeLastAt: 0,
  touchpadSuppressUntilAllLift: false,
  directPointerDown: false,
  longPressTimer: null,
  pendingTapTimer: null,
  lastTapAt: 0,
  gesture: null,
  latchedModifiers: new Set(),
  controlHoldActive: false,
  activeSheetId: "",
  streamStats: {},
  streamVisible: typeof document === "undefined" ? true : !document.hidden,
  lastError: null,
  frameTimes: [],
  pendingCommands: new Map(),
  lastAck: null,
  inputRttMs: 0,
  nativeKeyboardOpen: false,
  nativeKeyboardBlurredAt: 0,
  nativeKeyboardPointerToggleAt: 0,
  pendingPointerMove: null,
  pointerMoveTimer: null,
  pointerMoveStats: {
    queued: 0,
    sent: 0,
    coalesced: 0
  },
  pinchGesture: null,
  acceptanceMode: acceptanceContext.enabled,
  acceptanceGate: acceptanceContext.gate,
  acceptanceStep: acceptanceContext.step,
  acceptanceProofSaved: false,
  acceptanceChecklistPassed: new Set()
};

const el = {
  pairing: document.getElementById("pairing"),
  controller: document.getElementById("controller"),
  pairForm: document.getElementById("pairForm"),
  pairStatus: document.getElementById("pairStatus"),
  connectionHelp: document.getElementById("connectionHelp"),
  connectionHelpTitle: document.getElementById("connectionHelpTitle"),
  connectionHelpMessage: document.getElementById("connectionHelpMessage"),
  connectionHelpSteps: document.getElementById("connectionHelpSteps"),
  forgetSession: document.getElementById("forgetSession"),
  pin: document.getElementById("pin"),
  keepDeviceSignedIn: document.getElementById("keepDeviceSignedIn"),
  deviceName: document.getElementById("deviceName"),
  canvas: document.getElementById("streamCanvas"),
  displayStage: document.getElementById("displayStage"),
  rtcVideo: document.getElementById("rtcVideo"),
  touchpadArea: document.getElementById("touchpadArea"),
  touchpadSurface: document.getElementById("touchpadSurface"),
  touchpadCursorHint: document.getElementById("touchpadCursorHint"),
  touchpadStatus: document.getElementById("touchpadStatus"),
  leftClickPadBtn: document.getElementById("leftClickPadBtn"),
  rightClickPadBtn: document.getElementById("rightClickPadBtn"),
  monitorName: document.getElementById("monitorName"),
  connectionState: document.getElementById("connectionState"),
  qualityChip: document.getElementById("qualityChip"),
  latencyChip: document.getElementById("latencyChip"),
  disconnectBtn: document.getElementById("disconnectBtn"),
  precisionBtn: document.getElementById("precisionBtn"),
  pointerHalo: document.getElementById("pointerHalo"),
  monitorSheet: document.getElementById("monitorSheet"),
  keyboardSheet: document.getElementById("keyboardSheet"),
  settingsSheet: document.getElementById("settingsSheet"),
  monitorGrid: document.getElementById("monitorGrid"),
  captureSourceGrid: document.getElementById("captureSourceGrid"),
  keyGrid: document.getElementById("keyGrid"),
  textForm: document.getElementById("textForm"),
  textInput: document.getElementById("textInput"),
  keyboardToggleBtn: document.getElementById("keyboardToggleBtn"),
  followCursorBtn: document.getElementById("followCursorBtn"),
  controlHoldBtn: document.getElementById("controlHoldBtn"),
  windowsShortcutBtn: document.getElementById("windowsShortcutBtn"),
  codexShortcutBtn: document.getElementById("codexShortcutBtn"),
  claudeShortcutBtn: document.getElementById("claudeShortcutBtn"),
  nativeKeyboardInput: document.getElementById("nativeKeyboardInput"),
  qualitySelect: document.getElementById("qualitySelect"),
  sensitivity: document.getElementById("sensitivity"),
  scrollSpeed: document.getElementById("scrollSpeed"),
  scrollSpeedValue: document.getElementById("scrollSpeedValue"),
  zoomRange: document.getElementById("zoomRange"),
  zoomValue: document.getElementById("zoomValue"),
  lensZoomRange: document.getElementById("lensZoomRange"),
  lensZoomValue: document.getElementById("lensZoomValue"),
  lensSizeRange: document.getElementById("lensSizeRange"),
  lensSizeValue: document.getElementById("lensSizeValue"),
  resetZoomBtn: document.getElementById("resetZoomBtn"),
  autoFollowCursor: document.getElementById("autoFollowCursor"),
  cursorLensEnabled: document.getElementById("cursorLensEnabled"),
  cursorLensHold: document.getElementById("cursorLensHold"),
  showHalo: document.getElementById("showHalo"),
  hapticsEnabled: document.getElementById("hapticsEnabled"),
  calibrationToggleBtn: document.getElementById("calibrationToggleBtn"),
  calibrationCaptureBtn: document.getElementById("calibrationCaptureBtn"),
  calibrationResetBtn: document.getElementById("calibrationResetBtn"),
  calibrationStatus: document.getElementById("calibrationStatus"),
  acceptanceProofBanner: document.getElementById("acceptanceProofBanner"),
  acceptanceBannerTitle: document.getElementById("acceptanceBannerTitle"),
  acceptanceBannerMeta: document.getElementById("acceptanceBannerMeta"),
  acceptanceBannerStatus: document.getElementById("acceptanceBannerStatus"),
  acceptanceBannerMarkBtn: document.getElementById("acceptanceBannerMarkBtn"),
  acceptanceProofPanel: document.getElementById("acceptanceProofPanel"),
  acceptanceGateLabel: document.getElementById("acceptanceGateLabel"),
  acceptanceStepLabel: document.getElementById("acceptanceStepLabel"),
  acceptanceChecklist: document.getElementById("acceptanceChecklist"),
  acceptanceChecklistItems: document.getElementById("acceptanceChecklistItems"),
  acceptanceChecklistStatus: document.getElementById("acceptanceChecklistStatus"),
  acceptanceMarkBtn: document.getElementById("acceptanceMarkBtn"),
  acceptanceMarkStatus: document.getElementById("acceptanceMarkStatus"),
  diagnostics: document.getElementById("diagnostics")
};

const ctx = el.canvas.getContext("2d");

function setStatus(text) {
  el.connectionState.textContent = text;
}

function showController(show) {
  el.pairing.classList.toggle("hidden", show);
  el.controller.classList.toggle("hidden", !show);
}

async function api(path, options = {}) {
  let response;
  try {
    response = await fetch(path, {
      headers: { "Content-Type": "application/json", ...(options.headers || {}) },
      ...options
    });
  } catch (error) {
    error.code = "NETWORK_UNREACHABLE";
    error.status = 0;
    throw error;
  }
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw enrichApiError(new Error(data.message || data.error || "Request failed"), response, data);
  return data;
}

function enrichApiError(error, response, data) {
  error.code = data.code || data.error || `HTTP_${response.status}`;
  error.status = response.status;
  error.friendly = data.friendly || data.message || data.error;
  error.detail = data.detail;
  error.recoverable = data.recoverable;
  error.nextAction = data.nextAction;
  error.retryAfterSeconds = data.retryAfterSeconds;
  error.attemptsRemaining = data.attemptsRemaining;
  return error;
}

async function checkedApi(path, options = {}) {
  let response;
  try {
    response = await fetch(path, {
      headers: { "Content-Type": "application/json", ...(options.headers || {}) },
      ...options
    });
  } catch (error) {
    error.code = "NETWORK_UNREACHABLE";
    error.status = 0;
    throw error;
  }
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw enrichApiError(new Error(data.message || data.error || "Request failed"), response, data);
  return data;
}

function explainConnectionIssue(error, context = "pair") {
  const code = error?.code || "";
  const status = error?.status || 0;
  if (code === "NETWORK_UNREACHABLE" || status === 0) {
    return {
      title: "Host not reachable",
      message: "The phone cannot reach the laptop host at this address.",
      steps: [
        "Confirm the laptop host is running and the host console is open.",
        "For same Wi-Fi, scan the LAN QR shown in the host console.",
        "For different Wi-Fi, connect both devices to Tailscale and use the Tailscale URL.",
        "If the URL is correct, check that Windows Firewall is not blocking port 4317."
      ],
      canForget: Boolean(state.token)
    };
  }
  if (code === "BAD_PIN") {
    const remaining = Number.isFinite(error.attemptsRemaining) ? `${error.attemptsRemaining} attempt(s) remain. ` : "";
    return {
      title: "PIN did not match",
      message: `${remaining}The PIN may be mistyped or expired.`,
      steps: [
        "Read the current PIN from the laptop host console.",
        "Tap New PIN on the host if the timer is low.",
        "Enter the six digits again from this phone."
      ],
      canForget: false
    };
  }
  if (code === "PIN_RATE_LIMITED") {
    return {
      title: "Too many wrong PIN attempts",
      message: `Pairing is locked for this phone for about ${error.retryAfterSeconds || 90}s.`,
      steps: [
        "Wait for the lockout to end.",
        "Confirm you are reading the current host PIN.",
        "Use the host console to generate a fresh PIN before trying again."
      ],
      canForget: false
    };
  }
  if (code === "SESSION_NOT_FOUND" || status === 404) {
    return {
      title: "Saved session expired",
      message: "The saved phone session was revoked, expired, or belongs to a previous host run.",
      steps: [
        "The old saved session was cleared on this phone.",
        "Pair again with the current PIN.",
        "Approve the new session on the laptop."
      ],
      canForget: Boolean(state.token)
    };
  }
  if (context === "websocket") {
    return {
      title: "Realtime channel closed",
      message: "The control socket disconnected before the phone could control the laptop.",
      steps: [
        "Keep this page open while the laptop host is running.",
        "If you changed networks, reopen the LAN or Tailscale URL from the host console.",
        "If the host used Stop All Control, pair and approve again."
      ],
      canForget: Boolean(state.token)
    };
  }
  return {
    title: "Connection needs attention",
    message: error?.message || "The phone could not complete the current connection step.",
    steps: [
      error?.nextAction,
      "Check that the host console is running.",
      "Confirm the URL matches the LAN or Tailscale address shown on the laptop.",
      "Pair again with the current PIN."
    ].filter(Boolean),
    canForget: Boolean(state.token)
  };
}

function showConnectionHelp(error, context) {
  const help = explainConnectionIssue(error, context);
  el.connectionHelpTitle.textContent = help.title;
  el.connectionHelpMessage.textContent = help.message;
  el.connectionHelpSteps.textContent = "";
  for (const step of help.steps) {
    const li = document.createElement("li");
    li.textContent = step;
    el.connectionHelpSteps.appendChild(li);
  }
  el.forgetSession.classList.toggle("hidden", !help.canForget);
  el.connectionHelp.classList.remove("hidden");
}

function hideConnectionHelp() {
  el.connectionHelp.classList.add("hidden");
}

function forgetSavedSession() {
  state.token = "";
  state.sessionId = "";
  state.approved = false;
  state.connected = false;
  state.manualDisconnect = true;
  clearTimeout(state.reconnectTimer);
  state.ws?.close();
  localStorage.removeItem("remote-token");
  localStorage.removeItem("remote-session-id");
  showController(false);
  el.pairStatus.textContent = "Pair with the laptop host.";
  hideConnectionHelp();
}

function clearExpiredSavedSession(error) {
  state.token = "";
  state.sessionId = "";
  state.approved = false;
  state.connected = false;
  state.manualDisconnect = true;
  state.reconnectAttempts = 0;
  clearTimeout(state.reconnectTimer);
  state.ws?.close();
  localStorage.removeItem("remote-token");
  localStorage.removeItem("remote-session-id");
  showController(false);
  el.pairStatus.textContent = "Saved session expired. Pair with the current PIN.";
  showConnectionHelp(error, "approval");
  el.forgetSession.classList.add("hidden");
}

function message(type, payload = {}) {
  const sequence = ++state.seq;
  state.pendingCommands.set(sequence, performance.now());
  return {
    protocolVersion: PROTOCOL_VERSION,
    type,
    sequence,
    timestamp: commandTimestamp(),
    payload
  };
}

function syncHostClock(packet = {}) {
  const hostTimestamp = Number(packet.timestamp);
  if (!Number.isFinite(hostTimestamp) || hostTimestamp <= 0) return;
  const observedOffset = hostTimestamp - Date.now();
  state.hostClockOffsetMs = state.hostClockSynced
    ? Math.round((state.hostClockOffsetMs * 0.75) + (observedOffset * 0.25))
    : Math.round(observedOffset);
  state.hostClockSynced = true;
  state.lastHostClockSyncAt = performance.now();
}

function commandTimestamp() {
  return Math.round(Date.now() + (Number(state.hostClockOffsetMs) || 0));
}

function isTimestampError(payload = {}) {
  return /TIMESTAMP|CLOCK/i.test(`${payload.code || ""} ${payload.friendly || ""} ${payload.nextAction || ""}`);
}

function socketOpen() {
  return state.ws && state.ws.readyState === WebSocket.OPEN;
}

function sendNow(type, payload = {}) {
  if (!socketOpen()) return false;
  state.ws.send(JSON.stringify(message(type, payload)));
  if (type === "pointer.move") state.pointerMoveStats.sent += 1;
  return true;
}

function schedulePointerMoveFlush() {
  if (state.pointerMoveTimer) return;
  const flush = () => {
    state.pointerMoveTimer = null;
    flushPointerMove();
  };
  if (typeof requestAnimationFrame === "function") {
    state.pointerMoveTimer = requestAnimationFrame(flush);
  } else {
    state.pointerMoveTimer = setTimeout(flush, 16);
  }
}

function clearPointerMoveTimer() {
  if (!state.pointerMoveTimer) return;
  if (typeof cancelAnimationFrame === "function") {
    cancelAnimationFrame(state.pointerMoveTimer);
  } else {
    clearTimeout(state.pointerMoveTimer);
  }
  state.pointerMoveTimer = null;
}

function queuePointerMove(payload = {}) {
  if (!socketOpen()) return;
  state.pointerMoveStats.queued += 1;
  if (!state.pendingPointerMove) {
    state.pendingPointerMove = { ...payload, coalescedCount: 1 };
    schedulePointerMoveFlush();
    return;
  }
  state.pendingPointerMove = {
    ...state.pendingPointerMove,
    ...payload,
    dx: Number(state.pendingPointerMove.dx || 0) + Number(payload.dx || 0),
    dy: Number(state.pendingPointerMove.dy || 0) + Number(payload.dy || 0),
    dragging: Boolean(state.pendingPointerMove.dragging || payload.dragging),
    coalescedCount: Number(state.pendingPointerMove.coalescedCount || 1) + 1
  };
  state.pointerMoveStats.coalesced += 1;
}

function flushPointerMove() {
  if (!state.pendingPointerMove) return false;
  clearPointerMoveTimer();
  const payload = state.pendingPointerMove;
  state.pendingPointerMove = null;
  return sendNow("pointer.move", payload);
}

function send(type, payload = {}) {
  if (!state.ws || state.ws.readyState !== WebSocket.OPEN) return;
  if (type === "pointer.move") {
    queuePointerMove(payload);
    return;
  }
  flushPointerMove();
  sendNow(type, payload);
}

function approximateFps() {
  return state.frameTimes.length > 1
    ? Math.round(((state.frameTimes.length - 1) / ((state.frameTimes.at(-1) - state.frameTimes[0]) / 1000)) * 10) / 10
    : 0;
}

function getAcceptanceChecklistItems(gate = state.acceptanceGate) {
  const selectedGate = normalizeAcceptanceGate(gate);
  return ACCEPTANCE_CHECKLISTS[selectedGate] || [];
}

function acceptanceChecklistState(gate = state.acceptanceGate) {
  const selectedGate = normalizeAcceptanceGate(gate);
  const items = getAcceptanceChecklistItems(selectedGate).map((label, index) => {
    const id = `${selectedGate || "manual"}-${index + 1}`;
    return {
      id,
      label,
      checked: state.acceptanceChecklistPassed.has(id)
    };
  });
  const passedCount = items.filter((item) => item.checked).length;
  return {
    source: "phone-ui",
    gate: selectedGate,
    requiredCount: items.length,
    passedCount,
    complete: items.length > 0 && passedCount === items.length,
    items
  };
}

function isAcceptanceChecklistComplete() {
  if (!state.acceptanceMode) return true;
  return acceptanceChecklistState().complete;
}

function acceptanceProofPayload(overrides = {}) {
  const standalone = window.matchMedia?.("(display-mode: standalone)")?.matches || navigator.standalone === true;
  const gate = normalizeAcceptanceGate(overrides.gate || state.acceptanceGate);
  const step = cleanAcceptanceStep(overrides.step || state.acceptanceStep || "manual-phone-proof");
  const checklist = acceptanceChecklistState(gate);
  return {
    marker: "manual-phone-proof",
    gate,
    step,
    urlOrigin: location.origin,
    urlPath: `${location.pathname}${location.search ? "?query" : ""}`,
    userAgent: navigator.userAgent,
    viewport: {
      width: Math.round(window.innerWidth || 0),
      height: Math.round(window.innerHeight || 0),
      devicePixelRatio: Number(window.devicePixelRatio || 1),
      orientation: screen.orientation?.type || ""
    },
    screen: {
      width: Number(screen.width || 0),
      height: Number(screen.height || 0)
    },
    features: {
      touch: navigator.maxTouchPoints > 0,
      standalone,
      serviceWorker: "serviceWorker" in navigator,
      vibration: "vibrate" in navigator
    },
    diagnostics: {
      frameId: state.frame?.frameId || 0,
      monitor: state.selectedMonitorId,
      quality: state.streamStats.quality || el.qualitySelect.value,
      inputMode: state.inputMode,
      precisionMode: state.precisionMode,
      viewportZoom: state.viewportZoom,
      fpsApprox: approximateFps(),
      inputRttMs: state.inputRttMs
    },
    checklist
  };
}

function markAcceptanceProof(overrides = {}) {
  if (!isAcceptanceChecklistComplete()) {
    const checklist = acceptanceChecklistState();
    const text = `Finish checklist first (${checklist.passedCount}/${checklist.requiredCount}).`;
    if (el.acceptanceMarkStatus) el.acceptanceMarkStatus.textContent = text;
    setAcceptanceProofStatus(text, false);
    touchFeedback([8, 40, 8]);
    updateDiagnostics();
    return false;
  }
  const ok = sendNow("acceptance.mark", acceptanceProofPayload(overrides));
  if (el.acceptanceMarkStatus) {
    const gateLabel = normalizeAcceptanceGate(overrides.gate || state.acceptanceGate);
    el.acceptanceMarkStatus.textContent = ok
      ? `Proof marker sent${gateLabel ? ` for ${gateLabel}.` : "."}`
      : "Connect before marking proof.";
  }
  setAcceptanceProofStatus(ok ? "Sent to host. Waiting for saved confirmation." : "Connect before marking proof.", false);
  touchFeedback(ok ? 10 : [8, 40, 8]);
  updateDiagnostics();
  return ok;
}

function updateAcceptanceChecklistUi() {
  if (!el.acceptanceChecklist || !el.acceptanceChecklistItems) return;
  const checklist = acceptanceChecklistState();
  el.acceptanceChecklist.classList.toggle("hidden", !state.acceptanceMode || checklist.requiredCount === 0);
  el.acceptanceChecklistItems.textContent = "";
  for (const item of checklist.items) {
    const label = document.createElement("label");
    label.className = "checkbox-row acceptance-check";
    const input = document.createElement("input");
    input.type = "checkbox";
    input.checked = item.checked;
    input.dataset.acceptanceCheckId = item.id;
    input.addEventListener("change", () => {
      if (input.checked) {
        state.acceptanceChecklistPassed.add(item.id);
      } else {
        state.acceptanceChecklistPassed.delete(item.id);
      }
      state.acceptanceProofSaved = false;
      updateAcceptanceChecklistUi();
      updateAcceptanceUi();
      updateDiagnostics();
    });
    const text = document.createElement("span");
    text.textContent = item.label;
    label.append(input, text);
    el.acceptanceChecklistItems.append(label);
  }
  if (el.acceptanceChecklistStatus) {
    el.acceptanceChecklistStatus.textContent = `${checklist.passedCount} / ${checklist.requiredCount}`;
  }
  if (el.acceptanceMarkBtn) {
    el.acceptanceMarkBtn.disabled = state.acceptanceMode && !checklist.complete;
  }
  if (el.acceptanceBannerMarkBtn) {
    el.acceptanceBannerMarkBtn.disabled = state.acceptanceMode && !checklist.complete;
    el.acceptanceBannerMarkBtn.title = checklist.complete ? "Save physical proof marker" : "Finish the proof checklist in Settings first";
  }
}

function setAcceptanceProofStatus(text, saved = false) {
  state.acceptanceProofSaved = saved;
  if (el.acceptanceBannerStatus) {
    el.acceptanceBannerStatus.textContent = text;
  }
  if (el.acceptanceProofBanner) {
    el.acceptanceProofBanner.classList.toggle("saved", saved);
    el.acceptanceProofBanner.classList.toggle("pending", !saved && state.acceptanceMode);
  }
  if (el.acceptanceMarkStatus && saved) {
    el.acceptanceMarkStatus.textContent = text;
  }
}

function updateAcceptanceUi() {
  if (!el.acceptanceProofPanel) return;
  el.acceptanceProofPanel.classList.toggle("hidden", !state.acceptanceMode);
  if (el.acceptanceProofBanner) {
    el.acceptanceProofBanner.classList.add("hidden");
  }
  const gateText = state.acceptanceGate ? state.acceptanceGate : "manual";
  const gateLabel = formatAcceptanceGate(state.acceptanceGate);
  el.acceptanceGateLabel.textContent = `${gateLabel} proof`;
  el.acceptanceStepLabel.textContent = state.acceptanceStep || "physical-phone-proof";
  if (el.acceptanceBannerTitle) {
    el.acceptanceBannerTitle.textContent = `${gateLabel} proof required`;
  }
  if (el.acceptanceBannerMeta) {
    el.acceptanceBannerMeta.textContent = `${gateText} / ${state.acceptanceStep || "physical-phone-proof"}`;
  }
  if (state.acceptanceMode && el.acceptanceMarkBtn) {
    el.acceptanceMarkBtn.textContent = `Mark ${gateLabel} Proof`;
  }
  if (state.acceptanceMode && el.acceptanceBannerMarkBtn) {
    el.acceptanceBannerMarkBtn.textContent = `Mark ${gateLabel} Proof`;
  }
  if (state.acceptanceMode && el.acceptanceBannerStatus && !state.acceptanceProofSaved) {
    const checklist = acceptanceChecklistState();
    el.acceptanceBannerStatus.textContent = checklist.complete
      ? "Ready to mark proof"
      : `Checklist ${checklist.passedCount}/${checklist.requiredCount}`;
  }
  updateAcceptanceChecklistUi();
}

function reportStreamVisibility() {
  if (state.rtcActive) return false;
  state.streamVisible = true;
  state.lastVisibleStreamAssertAt = performance.now();
  send("stream.visibility", { visible: true, hidden: false });
  if (state.streamVisible && !state.frameImageReady) startStreamWakeBurst("visibility-report-burst");
  updateDiagnostics();
  return true;
}

function setScreenshotFallbackVisible(visible, reason = "rtc-video") {
  if (!state.token || !state.approved || !state.connected) return false;
  state.streamVisible = Boolean(visible);
  state.lastVisibleStreamAssertAt = performance.now();
  stopStreamWakeBurst();
  send("stream.visibility", {
    visible: Boolean(visible),
    hidden: !visible,
    reason
  });
  updateDiagnostics();
  return true;
}

function assertLiveStreamVisible(reason = "active-controller", options = {}) {
  if (state.rtcActive) return false;
  if (!state.token || !state.approved || !state.connected || document.hidden) return false;
  const now = performance.now();
  if (!options.force && state.lastVisibleStreamAssertAt && now - state.lastVisibleStreamAssertAt < VISIBLE_STREAM_ASSERT_MS) return true;
  state.lastVisibleStreamAssertAt = now;
  state.streamVisible = true;
  send("stream.visibility", { visible: true, hidden: false, reason });
  if (!state.frameImageReady) startStreamWakeBurst(`${reason}-burst`);
  updateDiagnostics();
  return true;
}

function stopStreamWakeBurst() {
  if (state.streamWakeBurstTimer) {
    clearTimeout(state.streamWakeBurstTimer);
    state.streamWakeBurstTimer = null;
  }
  state.streamWakeBurstCount = 0;
}

function startStreamWakeBurst(reason = "stream-wake") {
  if (state.rtcActive) return false;
  if (!state.token || !state.approved || !state.connected) return false;
  if (state.streamWakeBurstTimer) return true;
  state.streamWakeBurstCount = 0;
  const tick = () => {
    state.streamWakeBurstTimer = null;
    if (!state.token || !state.approved || !state.connected) {
      stopStreamWakeBurst();
      return;
    }
    if (state.frameImageReady && state.lastDecodedFrameAt) {
      stopStreamWakeBurst();
      return;
    }
    state.streamWakeBurstCount += 1;
    state.streamVisible = true;
    send("stream.visibility", {
      visible: true,
      hidden: false,
      reason,
      burst: state.streamWakeBurstCount
    });
    if (state.streamWakeBurstCount < STREAM_WAKE_BURST_COUNT) {
      state.streamWakeBurstTimer = setTimeout(tick, STREAM_WAKE_BURST_INTERVAL_MS);
    }
  };
  tick();
  return true;
}

function pokeLiveStream(reason = "watchdog") {
  if (state.rtcActive) return false;
  const now = performance.now();
  if (state.lastStreamWakePokeAt && now - state.lastStreamWakePokeAt < STREAM_WAKE_POKE_MS) return false;
  state.lastStreamWakePokeAt = now;
  state.streamWakePokes += 1;
  state.streamVisible = true;
  send("stream.visibility", { visible: true, hidden: false, reason });
  if (!state.frameImageReady) startStreamWakeBurst(`${reason}-burst`);
  return true;
}

function kickBlankCanvasStream(reason = "blank-canvas") {
  if (state.rtcActive) return false;
  if (!state.token || !state.approved || !state.connected || document.hidden) return false;
  const now = performance.now();
  if (state.lastBlankCanvasWakeAt && now - state.lastBlankCanvasWakeAt < 650) return false;
  state.lastBlankCanvasWakeAt = now;
  state.streamVisible = true;
  send("stream.visibility", { visible: true, hidden: false, reason });
  startStreamWakeBurst(`${reason}-burst`);
  return true;
}

function resumeLiveSession(reason = "resume") {
  if (!state.token || document.hidden) return false;
  if (!state.approved) {
    pollApproval();
    return false;
  }
  if (!state.connected) {
    connectWebSocket();
    return true;
  }
  if (state.rtcActive) return true;
  assertLiveStreamVisible(reason, { force: true });
  setTimeout(() => {
    if (!state.connected || document.hidden || state.frameImageReady) return;
    pokeLiveStream(`${reason}-probe`);
    setStatus("Starting screen stream");
  }, STREAM_RESUME_PROBE_MS);
  return true;
}

function handleStreamWatchdogTick() {
  if (!state.token || !state.approved || !state.connected || document.hidden) return;
  const now = performance.now();
  const pendingDecodeAge = state.pendingFrameImageSource
    ? now - Number(state.pendingFrameImageStartedAt || now)
    : 0;
  if (pendingDecodeAge > FRAME_DECODE_STALL_MS) {
    clearPendingFrameDecode("watchdog-decode-stall");
    if (!prepareQueuedFrameImage() && state.frame && (state.frame.imageObjectUrl || state.frame.imageDataUrl)) {
      prepareFrameImage(state.frame);
    }
  }
  if (state.frame && !state.frameImageReady && !state.pendingFrameImageSource && (state.frame.imageObjectUrl || state.frame.imageDataUrl)) {
    prepareFrameImage(state.frame);
  }
  const lastVisibleFrameAt = state.frame && !state.frameImageReady
    ? (state.lastDecodedFrameAt || state.connectedAt || now)
    : (state.lastDecodedFrameAt || state.lastFrameAt || state.connectedAt || now);
  const stalledFor = now - lastVisibleFrameAt;
  const neverReceivedFrame = !state.lastFrameAt && !state.frame && !state.frameImageReady;
  const waitingOnFirstDecode = state.frame && !state.frameImageReady && !state.lastDecodedFrameAt;
  if ((neverReceivedFrame || waitingOnFirstDecode) && stalledFor >= STREAM_WATCHDOG_MS) {
    if (pokeLiveStream(neverReceivedFrame ? "initial-frame-watchdog" : "decode-watchdog")) {
      setStatus(neverReceivedFrame ? "Starting screen stream" : "Waking screen stream");
      startStreamWakeBurst(neverReceivedFrame ? "initial-frame-burst" : "decode-burst");
    }
  }
  if (stalledFor < STREAM_STALL_MS) return;
  state.lastStreamWatchdogAt = now;
  pokeLiveStream("watchdog");
  if (!state.frame || !state.frameImageReady) {
    setStatus("Waking screen stream");
  }
  const reconnectAfter = neverReceivedFrame
    ? STREAM_INITIAL_FRAME_RECONNECT_MS
    : waitingOnFirstDecode
      ? STREAM_DECODE_RECONNECT_MS
      : STREAM_RECONNECT_MS;
  if (stalledFor < reconnectAfter || !state.ws || state.ws.readyState !== WebSocket.OPEN) {
    updateDiagnostics();
    return;
  }
  state.streamWatchdogReconnects += 1;
  state.lastError = {
    code: neverReceivedFrame ? "STREAM_INITIAL_FRAME_MISSING" : "STREAM_STALLED",
    friendly: neverReceivedFrame
      ? "Screen stream did not start; requesting a fresh live frame."
      : "Screen stream stalled; requesting a fresh live frame.",
    recoverable: true
  };
  send("stream.visibility", { visible: true, hidden: false, reason: "watchdog-stall", prime: true });
  updateDiagnostics();
}

function scheduleReconnect() {
  if (state.manualDisconnect || !state.token) return;
  clearTimeout(state.reconnectTimer);
  const delay = Math.min(8000, 700 * Math.max(1, state.reconnectAttempts));
  state.reconnectAttempts += 1;
  setStatus(`Reconnecting in ${Math.round(delay / 1000)}s`);
  state.reconnectTimer = setTimeout(() => {
    setStatus("Reconnecting");
    connectWebSocket();
  }, delay);
}

async function verifySavedSessionBeforeReconnect() {
  if (!state.token) return false;
  try {
    const session = await checkedApi(`/api/session?token=${encodeURIComponent(state.token)}`);
    state.approved = session.approved;
    if (!session.approved) {
      state.manualDisconnect = true;
      clearTimeout(state.reconnectTimer);
      showController(false);
      el.pairStatus.textContent = "Waiting for laptop approval.";
      hideConnectionHelp();
      setTimeout(pollApproval, 1200);
      return false;
    }
    return true;
  } catch (error) {
    if (error.code === "SESSION_NOT_FOUND" || error.status === 404) {
      clearExpiredSavedSession(error);
      return false;
    }
    if (error.code !== "NETWORK_UNREACHABLE" && error.status !== 0) {
      state.lastError = {
        code: error.code,
        friendly: error.friendly || error.message,
        detail: error.detail || null,
        recoverable: error.recoverable !== false,
        nextAction: error.nextAction || "Check the host console, then retry the action."
      };
      updateDiagnostics();
    }
    return true;
  }
}

function connectWebSocket() {
  if (!state.token) return;
  if (state.ws && [WebSocket.CONNECTING, WebSocket.OPEN].includes(state.ws.readyState)) return;
  const scheme = location.protocol === "https:" ? "wss" : "ws";
  state.ws = new WebSocket(`${scheme}://${location.host}/ws?token=${encodeURIComponent(state.token)}`);
  state.ws.binaryType = "arraybuffer";
  state.ws.addEventListener("open", () => {
    state.connected = true;
    state.connectedAt = performance.now();
    state.manualDisconnect = false;
    state.reconnectAttempts = 0;
    state.streamWatchdogReconnects = 0;
    state.lastStreamWakePokeAt = 0;
    clearTimeout(state.reconnectTimer);
    showController(true);
    hideConnectionHelp();
    setStatus("Connected");
    reportStreamVisibility(document.hidden);
    connectRtcReceiver();
    resumeLiveSession("socket-open-resume");
    setTimeout(() => assertLiveStreamVisible("socket-open"), 120);
    setTimeout(() => startStreamWakeBurst("socket-open-burst"), 160);
  });
  state.ws.addEventListener("message", (event) => {
    void handleSocketMessage(event);
  });
  state.ws.addEventListener("close", async () => {
    state.connected = false;
    closeRtcReceiver("control-socket-closed", { reconnect: false });
    state.pendingPointerMove = null;
    stopStreamWakeBurst();
    clearPointerMoveTimer();
    setStatus("Disconnected");
    if (!state.manualDisconnect) {
      const canReconnect = await verifySavedSessionBeforeReconnect();
      if (!canReconnect) return;
    }
    if (!state.manualDisconnect && state.reconnectAttempts >= 1) {
      showConnectionHelp(new Error("Realtime connection closed."), "websocket");
    }
    scheduleReconnect();
  });
}

function sendRtc(type, payload = {}) {
  if (!state.rtcWs || state.rtcWs.readyState !== WebSocket.OPEN) return false;
  state.rtcWs.send(JSON.stringify({
    protocol: "remote-controller-rtc",
    version: 1,
    type,
    at: Date.now(),
    payload
  }));
  return true;
}

function connectRtcReceiver() {
  if (!state.token || !state.connected) return;
  if (state.rtcWs && [WebSocket.CONNECTING, WebSocket.OPEN].includes(state.rtcWs.readyState)) return;
  const scheme = location.protocol === "https:" ? "wss" : "ws";
  state.rtcStatus = "connecting";
  state.rtcWs = new WebSocket(`${scheme}://${location.host}/rtc?role=phone&token=${encodeURIComponent(state.token)}`);
  state.rtcWs.addEventListener("open", () => {
    state.rtcConnected = true;
    state.rtcStatus = "waiting";
    sendRtc("rtc.ready", { wants: "screen-video" });
    updateDiagnostics();
  });
  state.rtcWs.addEventListener("message", (event) => {
    void handleRtcSignal(event.data);
  });
  state.rtcWs.addEventListener("close", () => {
    state.rtcConnected = false;
    setRtcVideoActive(false, "rtc-socket-closed");
    closeRtcPeer();
    if (!state.manualDisconnect && state.connected) {
      clearTimeout(state.rtcReconnectTimer);
      state.rtcReconnectTimer = setTimeout(connectRtcReceiver, 1200);
    }
  });
  state.rtcWs.addEventListener("error", () => {
    state.rtcStatus = "error";
    updateDiagnostics();
  });
}

function closeRtcPeer() {
  if (state.rtcPc) {
    state.rtcPc.ontrack = null;
    state.rtcPc.onicecandidate = null;
    state.rtcPc.onconnectionstatechange = null;
    state.rtcPc.close();
  }
  state.rtcPc = null;
  state.rtcIceQueue = [];
}

function closeRtcReceiver(reason = "manual", options = {}) {
  clearTimeout(state.rtcReconnectTimer);
  closeRtcPeer();
  if (state.rtcWs) {
    try {
      if (state.rtcWs.readyState === WebSocket.OPEN) sendRtc("rtc.stop", { reason });
      state.rtcWs.close();
    } catch {}
  }
  state.rtcWs = null;
  state.rtcConnected = false;
  setRtcVideoActive(false, reason);
  if (options.reconnect) connectRtcReceiver();
}

function ensureRtcPeer() {
  if (state.rtcPc) return state.rtcPc;
  const pc = new RTCPeerConnection({ iceServers: [] });
  pc.addTransceiver("video", { direction: "recvonly" });
  pc.addTransceiver("audio", { direction: "recvonly" });
  pc.ontrack = (event) => {
    const stream = event.streams[0] || new MediaStream([event.track]);
    state.rtcRemoteStream = stream;
    el.rtcVideo.srcObject = stream;
    el.rtcVideo.play?.().catch(() => {});
    setRtcVideoActive(true, "track");
  };
  pc.onicecandidate = (event) => {
    sendRtc("rtc.ice", { candidate: event.candidate ? event.candidate.toJSON() : null });
  };
  pc.onconnectionstatechange = () => {
    state.rtcStatus = pc.connectionState;
    if (pc.connectionState === "connected") setRtcVideoActive(true, "connected");
    if (["failed", "closed", "disconnected"].includes(pc.connectionState)) {
      setRtcVideoActive(false, pc.connectionState);
    }
    updateDiagnostics();
  };
  state.rtcPc = pc;
  return pc;
}

async function flushRtcIceQueue() {
  if (!state.rtcPc?.remoteDescription) return;
  const queued = state.rtcIceQueue.splice(0);
  for (const candidate of queued) {
    await state.rtcPc.addIceCandidate(candidate ? new RTCIceCandidate(candidate) : null);
  }
}

async function handleRtcSignal(raw) {
  let message;
  try {
    message = JSON.parse(raw);
  } catch {
    return;
  }
  if (message.type === "rtc.hello" || message.type === "rtc.peerJoined" || message.type === "rtc.peerReady") {
    state.rtcStatus = message.payload?.room?.state || "waiting";
    sendRtc("rtc.ready", { wants: "screen-video" });
    updateDiagnostics();
    return;
  }
  if (message.type === "rtc.offer") {
    const pc = ensureRtcPeer();
    state.rtcStatus = "negotiating";
    await pc.setRemoteDescription(new RTCSessionDescription(message.payload));
    await flushRtcIceQueue();
    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    sendRtc("rtc.answer", pc.localDescription.toJSON());
    updateDiagnostics();
    return;
  }
  if (message.type === "rtc.ice") {
    const candidate = message.payload?.candidate ?? null;
    if (!state.rtcPc?.remoteDescription) {
      state.rtcIceQueue.push(candidate);
      return;
    }
    await state.rtcPc.addIceCandidate(candidate ? new RTCIceCandidate(candidate) : null);
    return;
  }
  if (message.type === "rtc.stop" || message.type === "rtc.peerLeft") {
    state.rtcStatus = message.type === "rtc.peerLeft" ? "waiting" : "stopped";
    setRtcVideoActive(false, message.type);
    closeRtcPeer();
    updateDiagnostics();
  }
  if (message.type === "rtc.error") {
    state.rtcStatus = message.payload?.code || "error";
    state.lastError = { code: "RTC_SIGNAL", friendly: message.payload?.message || "RTC signaling failed." };
    setRtcVideoActive(false, "rtc-error");
    updateDiagnostics();
  }
}

function setRtcVideoActive(active, reason = "") {
  const videoReady = Boolean(el.rtcVideo?.srcObject);
  const next = Boolean(active && videoReady);
  if (state.rtcActive === next && reason !== "metadata") return;
  state.rtcActive = next;
  el.controller?.classList.toggle("rtc-active", next);
  el.controller?.classList.toggle("rtc-fallback", !next);
  if (!next && el.rtcVideo) {
    el.rtcVideo.pause?.();
    setScreenshotFallbackVisible(true, `rtc-${reason || "inactive"}`);
  } else {
    setScreenshotFallbackVisible(false, `rtc-${reason || "active"}`);
    updateRtcVideoViewport();
    el.rtcVideo?.play?.().catch(() => {});
  }
  drawFrame();
}

el.rtcVideo?.addEventListener("loadedmetadata", () => {
  state.rtcVideoWidth = el.rtcVideo.videoWidth || 0;
  state.rtcVideoHeight = el.rtcVideo.videoHeight || 0;
  setRtcVideoActive(true, "metadata");
  updateDiagnostics();
});

setInterval(() => {
  if (!state.rtcWs || state.rtcWs.readyState !== WebSocket.OPEN) return;
  sendRtc("rtc.ping", {
    active: state.rtcActive,
    videoWidth: state.rtcVideoWidth,
    videoHeight: state.rtcVideoHeight
  });
}, RTC_HEARTBEAT_MS);

async function handleSocketMessage(event) {
  try {
    const packet = typeof event.data === "string"
      ? JSON.parse(event.data)
      : await decodeBinaryStreamPacket(event.data);
    handleServerPacket(packet);
  } catch (error) {
    state.lastError = { code: "BAD_STREAM_PACKET", friendly: error.message };
    updateDiagnostics();
  }
}

async function decodeBinaryStreamPacket(data) {
  const buffer = data instanceof ArrayBuffer ? data : await data.arrayBuffer();
  const bytes = new Uint8Array(buffer);
  if (bytes.length < 8) throw new Error("Binary stream packet was too short.");
  const magic = String.fromCharCode(bytes[0], bytes[1], bytes[2], bytes[3]);
  if (magic !== BINARY_STREAM_MAGIC) throw new Error("Unknown binary stream packet.");
  const view = new DataView(buffer);
  const headerLength = view.getUint32(4);
  const imageOffset = 8 + headerLength;
  if (headerLength <= 0 || imageOffset > bytes.length) throw new Error("Binary stream packet header was invalid.");
  const headerText = new TextDecoder().decode(bytes.subarray(8, imageOffset));
  const packet = JSON.parse(headerText);
  const mimeType = packet.payload?.mimeType || packet.payload?.binaryImage?.mimeType || "image/jpeg";
  const imageBytes = bytes.subarray(imageOffset);
  const imageBlob = new Blob([imageBytes], { type: mimeType });
  packet.payload = {
    ...packet.payload,
    imageBlob,
    imageObjectUrl: URL.createObjectURL(imageBlob),
    imageByteLength: imageBytes.byteLength,
    binaryTransport: true
  };
  return packet;
}

function handleServerPacket(packet) {
  syncHostClock(packet);
  if (packet.type === "hello" || packet.type === "state") {
    applyState(packet.payload.state || packet.payload);
  }
  if (packet.type === "stream.frame") {
    state.frame = normalizeIncomingFrame(packet.payload);
    followViewportTowardCursor({ force: false, strength: 1, skipDraw: true });
    state.lastFrameAt = performance.now();
    state.frameTimes.push(state.lastFrameAt);
    state.frameTimes = state.frameTimes.filter((time) => state.lastFrameAt - time <= 5000);
    state.latency = Math.max(0, commandTimestamp() - packet.payload.capturedAt);
    prepareFrameImage(state.frame);
    updateDiagnostics();
  }
  if (packet.type === "ack") {
      const startedAt = state.pendingCommands.get(packet.payload.sequence);
      if (startedAt) {
        state.inputRttMs = Math.round(performance.now() - startedAt);
        state.pendingCommands.delete(packet.payload.sequence);
      }
      state.lastAck = packet.payload;
      if (packet.payload.ackType === "pointer.move") {
        state.touchpadAcked += 1;
        updateRemoteCursorFromAck(packet.payload);
        updateTouchpadStatus();
      }
      if (packet.payload.ackType === "acceptance.mark" && el.acceptanceMarkStatus) {
        setAcceptanceProofStatus("Proof marker saved in host logs.", true);
      }
      updateDiagnostics(packet.payload);
  }
  if (packet.type === "error") {
    state.lastError = packet.payload;
    state.touchpadLastError = isTimestampError(packet.payload)
      ? "clock synced, try again"
      : packet.payload.code || packet.payload.friendly || "error";
    updateTouchpadStatus();
    setStatus(packet.payload.nextAction || packet.payload.friendly || "Error");
    updateDiagnostics();
  }
}

function applyState(next) {
  state.monitors = next.monitors || [];
  const nextMonitorId = next.selectedMonitorId || state.selectedMonitorId;
  if (nextMonitorId !== state.selectedMonitorId) {
    resetMonitorViewState({ clearFrame: true });
  }
  state.selectedMonitorId = nextMonitorId;
  state.streamStats = next.streamStats || state.streamStats;
  state.captureLaunch = next.captureLaunch || state.captureLaunch;
  if (next.rtcStatus) state.rtcStatus = next.rtcStatus.state || state.rtcStatus;
  if (next.settings && !state.defaultSettingsApplied) {
    if (!localStorage.getItem("remote-sensitivity")) {
      state.sensitivity = Math.max(DEFAULT_POINTER_SPEED, Number(next.settings.inputSensitivityDefault || state.sensitivity));
    }
    el.sensitivity.value = String(state.sensitivity);
    el.qualitySelect.value = next.settings.qualityDefault || el.qualitySelect.value;
    state.defaultSettingsApplied = true;
  }
  el.qualityChip.textContent = next.streamStats?.quality || "balanced";
  const monitor = state.monitors.find((item) => item.id === state.selectedMonitorId);
  el.monitorName.textContent = monitor ? monitor.name : "Display";
  renderMonitors();
  updateCalibrationUi();
  updateDiagnostics();
}

function releaseFrameImages() {
  if (state.frameImageObjectUrl) {
    URL.revokeObjectURL(state.frameImageObjectUrl);
    state.frameImageObjectUrl = "";
  }
  if (state.pendingFrameImageObjectUrl) {
    URL.revokeObjectURL(state.pendingFrameImageObjectUrl);
    state.pendingFrameImageObjectUrl = "";
  }
  if (state.queuedFrameImageObjectUrl) {
    URL.revokeObjectURL(state.queuedFrameImageObjectUrl);
    state.queuedFrameImageObjectUrl = "";
  }
  state.frameImage = null;
  state.pendingFrameImage = null;
  state.queuedFrameImage = null;
  state.frameImageSource = "";
  state.pendingFrameImageSource = "";
  state.queuedFrameImageSource = "";
  state.pendingFrameImageStartedAt = 0;
  state.frameImageReady = false;
  state.lastDecodedFrameAt = 0;
  state.lastStreamWakePokeAt = 0;
  stopStreamWakeBurst();
}

function resetMonitorViewState({ clearFrame = false } = {}) {
  state.viewportZoom = 1;
  state.viewportPanX = 0;
  state.viewportPanY = 0;
  state.followPausedUntil = 0;
  state.lastCursorMap = null;
  state.lastCursorLensBox = null;
  state.lastAckCursor = null;
  state.lastAckCursorAt = 0;
  state.calibrationMode = false;
  state.calibrationSamples = [];
  state.calibrationMessage = "";
  state.edgePanStats.localMoves = 0;
  setTouchpadCursorHint(0.5, 0.5);
  stopTouchpadEdgeHold();
  stopTouchpadScrollEdgeHold();
  clearTouchpadLongPress();
  if (clearFrame) {
    state.frame = null;
    releaseFrameImages();
  }
  updateZoomUi();
  updateCalibrationUi();
}

function selectMonitor(monitorId) {
  if (!monitorId || monitorId === state.selectedMonitorId) return false;
  state.selectedMonitorId = monitorId;
  if (state.rtcActive || el.rtcVideo?.srcObject) {
    closeRtcPeer();
    state.rtcRemoteStream = null;
    state.rtcVideoWidth = 0;
    state.rtcVideoHeight = 0;
    if (el.rtcVideo) {
      el.rtcVideo.pause?.();
      el.rtcVideo.srcObject = null;
    }
    setRtcVideoActive(false, "monitor-switch");
  }
  resetMonitorViewState({ clearFrame: true });
  const monitor = state.monitors.find((item) => item.id === state.selectedMonitorId);
  el.monitorName.textContent = monitor ? monitor.name : "Display";
  send("monitor.select", { monitorId, monitor });
  startStreamWakeBurst("monitor-select-burst");
  renderMonitors();
  drawFrame();
  updateDiagnostics();
  return true;
}

function renderMonitors() {
  el.monitorGrid.textContent = "";
  if (state.monitors.length) {
    const layout = document.createElement("div");
    layout.className = "monitor-layout";
    const bounds = state.monitors.reduce((acc, monitor) => ({
      left: Math.min(acc.left, monitor.bounds.left),
      top: Math.min(acc.top, monitor.bounds.top),
      right: Math.max(acc.right, monitor.bounds.left + monitor.bounds.width),
      bottom: Math.max(acc.bottom, monitor.bounds.top + monitor.bounds.height)
    }), { left: Infinity, top: Infinity, right: -Infinity, bottom: -Infinity });
    const totalW = Math.max(1, bounds.right - bounds.left);
    const totalH = Math.max(1, bounds.bottom - bounds.top);
    for (const monitor of state.monitors) {
      const mini = document.createElement("button");
      mini.className = `monitor-mini ${monitor.id === state.selectedMonitorId ? "active" : ""}`;
      mini.style.left = `${((monitor.bounds.left - bounds.left) / totalW) * 100}%`;
      mini.style.top = `${((monitor.bounds.top - bounds.top) / totalH) * 100}%`;
      mini.style.width = `${Math.max(16, (monitor.bounds.width / totalW) * 100)}%`;
      mini.style.height = `${Math.max(16, (monitor.bounds.height / totalH) * 100)}%`;
      mini.textContent = monitor.name.replace("Display ", "");
      mini.title = `${monitor.name} ${monitor.bounds.width} x ${monitor.bounds.height}`;
      mini.addEventListener("click", () => {
        selectMonitor(monitor.id);
      });
      layout.appendChild(mini);
    }
    el.monitorGrid.appendChild(layout);
  }
  for (const monitor of state.monitors) {
    const button = document.createElement("button");
    button.className = `monitor-tile ${monitor.id === state.selectedMonitorId ? "active" : ""}`;
    button.innerHTML = `
      <div class="monitor-preview"><span>${monitor.status || "ready"}</span></div>
      <strong>${monitor.name}</strong><br>
      <span>${monitor.bounds.width} x ${monitor.bounds.height} - ${monitor.orientation}${monitor.primary ? " - primary" : ""}</span><br>
      <small>${monitor.scaleFactor || 1}x scale</small>
    `;
    button.addEventListener("click", () => {
      selectMonitor(monitor.id);
    });
    el.monitorGrid.appendChild(button);
  }
  renderCaptureSources();
}

function captureSourceOptions() {
  const count = Math.max(3, state.monitors.length || 1);
  return ["Auto", ...Array.from({ length: Math.min(6, count + 1) }, (_, index) => `Screen ${index + 1}`), "Entire screen"];
}

function selectCaptureSource(sourceName) {
  if (!sourceName) return false;
  send("capture.source", {
    monitorId: state.selectedMonitorId,
    sourceName
  });
  state.captureLaunch = {
    ...(state.captureLaunch || {}),
    monitorId: state.selectedMonitorId,
    captureSourceName: sourceName === "Auto" ? "" : sourceName,
    autoDetect: {
      status: sourceName === "Auto" ? "auto" : "locked",
      reason: sourceName === "Auto" ? "Automatic source matching enabled." : `Locked to ${sourceName}.`,
      checkedAt: Date.now()
    }
  };
  renderCaptureSources();
  return true;
}

function renderCaptureSources() {
  if (!el.captureSourceGrid) return;
  el.captureSourceGrid.textContent = "";
  const active = state.captureLaunch?.monitorId === state.selectedMonitorId
    ? state.captureLaunch?.captureSourceName || "Auto"
    : "Auto";
  for (const sourceName of captureSourceOptions()) {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = sourceName === "Entire screen" ? "All" : sourceName.replace("Screen ", "S");
    button.title = sourceName;
    button.className = sourceName === active ? "active" : "";
    button.addEventListener("click", () => selectCaptureSource(sourceName));
    el.captureSourceGrid.appendChild(button);
  }
}

function prepareFrameImage(frame) {
  const source = frame.imageObjectUrl || frame.imageDataUrl;
  if (!source) {
    if (state.frameImageObjectUrl) {
      URL.revokeObjectURL(state.frameImageObjectUrl);
      state.frameImageObjectUrl = "";
    }
    if (state.pendingFrameImageObjectUrl) {
      URL.revokeObjectURL(state.pendingFrameImageObjectUrl);
      state.pendingFrameImageObjectUrl = "";
    }
    if (state.queuedFrameImageObjectUrl) {
      URL.revokeObjectURL(state.queuedFrameImageObjectUrl);
      state.queuedFrameImageObjectUrl = "";
    }
    state.frameImage = null;
    state.pendingFrameImage = null;
    state.queuedFrameImage = null;
    state.pendingFrameImageSource = "";
    state.queuedFrameImageSource = "";
    state.pendingFrameImageStartedAt = 0;
    state.pendingFrameImageAttempts = 0;
    state.frameImageSource = "";
    state.frameImageReady = false;
    drawFrame();
    return;
  }

  if (source === state.frameImageSource && state.frameImageReady) {
    drawFrame();
    return;
  }
  if (source === state.pendingFrameImageSource) return;

  if (state.pendingFrameImageSource) {
    const pendingAge = performance.now() - Number(state.pendingFrameImageStartedAt || 0);
    if (pendingAge > FRAME_DECODE_STALL_MS) {
      clearPendingFrameDecode("decode-stall");
    }
  }

  if (state.pendingFrameImageSource) {
    if (
      state.queuedFrameImageObjectUrl &&
      state.queuedFrameImageObjectUrl !== state.frameImageObjectUrl &&
      state.queuedFrameImageObjectUrl !== state.pendingFrameImageObjectUrl &&
      state.queuedFrameImageObjectUrl !== frame.imageObjectUrl
    ) {
      URL.revokeObjectURL(state.queuedFrameImageObjectUrl);
    }
    state.queuedFrameImage = frame;
    state.queuedFrameImageSource = source;
    state.queuedFrameImageObjectUrl = frame.imageObjectUrl || "";
    return;
  }

  if (state.pendingFrameImageObjectUrl && state.pendingFrameImageObjectUrl !== state.frameImageObjectUrl) {
    URL.revokeObjectURL(state.pendingFrameImageObjectUrl);
  }
  state.pendingFrameImageObjectUrl = frame.imageObjectUrl || "";
  state.pendingFrameImageSource = source;
  state.pendingFrameImageStartedAt = performance.now();
  state.pendingFrameImageAttempts += 1;
  const image = new Image();
  state.pendingFrameImage = image;
  image.decoding = "async";
  image.loading = "eager";
  let settled = false;
  let decodeFallbackTimer = null;
  const clearDecodeFallback = () => {
    if (!decodeFallbackTimer) return;
    clearTimeout(decodeFallbackTimer);
    decodeFallbackTimer = null;
  };
  const commitDecodedFrame = () => {
    if (settled) return;
    settled = true;
    clearDecodeFallback();
    if (state.pendingFrameImageSource !== source) return;
    if (state.frameImageObjectUrl && state.frameImageObjectUrl !== source) {
      URL.revokeObjectURL(state.frameImageObjectUrl);
    }
    state.frameImage = image;
    state.frameImageReady = true;
    state.frameImageSource = source;
    state.frameImageObjectUrl = frame.imageObjectUrl || "";
    state.pendingFrameImage = null;
    state.pendingFrameImageSource = "";
    state.pendingFrameImageObjectUrl = "";
    state.pendingFrameImageStartedAt = 0;
    state.pendingFrameImageAttempts = 0;
    state.lastDecodedFrameAt = performance.now();
    stopStreamWakeBurst();
    if (state.frame === frame && state.frame?.cursor?.raw) {
      const remapped = mapHostCursorToFrame(state.frame.cursor, selectedMonitor(), state.frame);
      if (remapped) state.frame.cursor = remapped;
    }
    followViewportTowardCursor({ force: true, strength: 1, skipDraw: true });
    drawFrame();
    prepareQueuedFrameImage();
  };
  const failDecodeFrame = () => {
    if (settled) return;
    settled = true;
    clearDecodeFallback();
    if (state.pendingFrameImageSource !== source) return;
    if (frame.imageObjectUrl && frame.imageObjectUrl !== state.frameImageObjectUrl) {
      URL.revokeObjectURL(frame.imageObjectUrl);
    }
    state.pendingFrameImage = null;
    state.pendingFrameImageSource = "";
    state.pendingFrameImageObjectUrl = "";
    state.pendingFrameImageStartedAt = 0;
    state.pendingFrameImageAttempts = 0;
    state.frameImageReady = Boolean(state.frameImage);
    state.frameDecodeErrors += 1;
    const fallbackStarted = fallbackFrameImageToDataUrl(frame);
    state.lastError = {
      code: "FRAME_DECODE_FAILED",
      friendly: fallbackStarted
        ? "Screen frame decoder fell back to a mobile-safe image path."
        : "Screen frame decode failed; keeping the last visible frame.",
      recoverable: true
    };
    drawFrame();
    if (!fallbackStarted) prepareQueuedFrameImage();
  };
  image.addEventListener("load", commitDecodedFrame, { once: true });
  image.addEventListener("error", failDecodeFrame, { once: true });
  image.src = source;
  decodeFallbackTimer = setTimeout(() => {
    if (settled || state.pendingFrameImageSource !== source) return;
    if (image.complete && image.naturalWidth > 0) {
      commitDecodedFrame();
      return;
    }
    failDecodeFrame();
  }, FRAME_DECODE_STALL_MS);
  if (typeof image.decode === "function") {
    image.decode().then(commitDecodedFrame).catch(() => {
      if (image.complete && image.naturalWidth > 0) {
        commitDecodedFrame();
      }
    });
  } else if (image.complete && image.naturalWidth > 0) {
    queueMicrotask(commitDecodedFrame);
  }
}

function fallbackFrameImageToDataUrl(frame) {
  if (!frame?.imageBlob || frame.imageDataFallbackTried || typeof FileReader === "undefined") return false;
  frame.imageDataFallbackTried = true;
  const reader = new FileReader();
  reader.addEventListener("load", () => {
    const dataUrl = String(reader.result || "");
    if (!dataUrl.startsWith("data:image/")) {
      prepareQueuedFrameImage();
      return;
    }
    if (frame.imageObjectUrl && frame.imageObjectUrl !== state.frameImageObjectUrl) {
      URL.revokeObjectURL(frame.imageObjectUrl);
    }
    frame.imageObjectUrl = "";
    frame.imageDataUrl = dataUrl;
    frame.imageBlob = null;
    state.frameBlobFallbacks += 1;
    if (state.frame === frame) {
      prepareFrameImage(frame);
    } else {
      prepareQueuedFrameImage();
    }
  }, { once: true });
  reader.addEventListener("error", () => {
    prepareQueuedFrameImage();
  }, { once: true });
  reader.readAsDataURL(frame.imageBlob);
  return true;
}

function clearPendingFrameDecode(reason = "decode-reset") {
  const currentFrameObjectUrl = state.frame?.imageObjectUrl || "";
  const queuedFrameObjectUrl = state.queuedFrameImageObjectUrl || "";
  if (
    state.pendingFrameImageObjectUrl &&
    state.pendingFrameImageObjectUrl !== state.frameImageObjectUrl &&
    state.pendingFrameImageObjectUrl !== currentFrameObjectUrl &&
    state.pendingFrameImageObjectUrl !== queuedFrameObjectUrl
  ) {
    URL.revokeObjectURL(state.pendingFrameImageObjectUrl);
  }
  state.pendingFrameImage = null;
  state.pendingFrameImageSource = "";
  state.pendingFrameImageObjectUrl = "";
  state.pendingFrameImageStartedAt = 0;
  state.pendingFrameImageAttempts = 0;
  state.frameImageReady = Boolean(state.frameImage);
  state.frameDecodeRecoveries += 1;
  state.lastError = {
    code: "FRAME_DECODE_RESET",
    friendly: "Refreshing the screen frame decoder.",
    detail: reason,
    recoverable: true
  };
}

function prepareQueuedFrameImage() {
  const queued = state.queuedFrameImage;
  const queuedSource = state.queuedFrameImageSource;
  state.queuedFrameImage = null;
  state.queuedFrameImageSource = "";
  state.queuedFrameImageObjectUrl = "";
  if (!queued || !queuedSource || queuedSource === state.frameImageSource) return false;
  prepareFrameImage(queued);
  return true;
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function loadMonitorCalibrations() {
  try {
    const parsed = JSON.parse(localStorage.getItem(CALIBRATION_STORAGE_KEY) || "{}");
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

function saveMonitorCalibrations() {
  localStorage.setItem(CALIBRATION_STORAGE_KEY, JSON.stringify(state.monitorCalibrations));
}

function monitorCalibrationSignature(monitor = selectedMonitor(), frame = state.frame) {
  const bounds = monitor?.bounds || {};
  const capture = frame?.monitorGeometry?.captureSize || {};
  return [
    monitor?.id || "display",
    monitor?.sourceId || "source",
    Number(bounds.width || capture.width || frame?.width || 0),
    Number(bounds.height || capture.height || frame?.height || 0),
    Number(monitor?.scaleFactor || 1)
  ].join("|");
}

function activeMonitorCalibration(monitor = selectedMonitor(), frame = state.frame) {
  return state.monitorCalibrations[monitorCalibrationSignature(monitor, frame)] || null;
}

function applyMonitorCalibrationToNormalized(normalizedX, normalizedY, monitor = selectedMonitor(), frame = state.frame, options = {}) {
  const calibration = activeMonitorCalibration(monitor, frame);
  if (!calibration?.enabled || options.applyCalibration === false || state.calibrationMode) {
    return {
      x: clamp(normalizedX, 0, 1),
      y: clamp(normalizedY, 0, 1),
      applied: false,
      id: calibration?.id || null
    };
  }
  const transform = calibration.transform || {};
  return {
    x: clamp(normalizedX * Number(transform.scaleX || 1) + Number(transform.offsetX || 0), 0, 1),
    y: clamp(normalizedY * Number(transform.scaleY || 1) + Number(transform.offsetY || 0), 0, 1),
    applied: true,
    id: calibration.id
  };
}

function calibrationStatusText(calibration = activeMonitorCalibration()) {
  if (state.calibrationMode) {
    const next = CALIBRATION_TARGETS[state.calibrationSamples.length];
    return next ? `Aim ${next.label}` : "Ready to save";
  }
  if (state.calibrationMessage) return state.calibrationMessage;
  if (!calibration?.enabled) return "Not calibrated";
  return `Calibrated ${Math.round(Number(calibration.maxError || 0) * 1000) / 10}%`;
}

function frameMetrics(frame = state.frame, rect = el.canvas.getBoundingClientRect()) {
  const { width: sourceW, height: sourceH } = frameSourceSize(frame);
  return sourceMetrics(sourceW, sourceH, rect);
}

function sourceMetrics(sourceW, sourceH, rect = el.canvas.getBoundingClientRect()) {
  const scale = Math.min(rect.width / sourceW, rect.height / sourceH);
  const drawW = sourceW * scale;
  const drawH = sourceH * scale;
  const portrait = (window.innerHeight || rect.height) > (window.innerWidth || rect.width);
  return {
    sourceW,
    sourceH,
    drawW,
    drawH,
    dx: (rect.width - drawW) / 2,
    dy: portrait ? 0 : (rect.height - drawH) / 2
  };
}

function selectedMonitor() {
  return state.monitors.find((item) => item.id === state.selectedMonitorId) || null;
}

function monitorScale(monitor = selectedMonitor()) {
  const scale = Number(monitor?.scaleFactor || 1);
  return Number.isFinite(scale) && scale > 0 ? scale : 1;
}

function frameSourceSize(frame = state.frame) {
  const naturalW = Number(state.frameImage?.naturalWidth || state.frameImage?.width || 0);
  const naturalH = Number(state.frameImage?.naturalHeight || state.frameImage?.height || 0);
  const frameW = Number(frame?.width || frame?.monitorGeometry?.captureSize?.width || 0);
  const frameH = Number(frame?.height || frame?.monitorGeometry?.captureSize?.height || 0);
  const monitor = selectedMonitor();
  return {
    width: Math.max(1, naturalW || frameW || Number(monitor?.bounds?.width || 0) || 1),
    height: Math.max(1, naturalH || frameH || Number(monitor?.bounds?.height || 0) || 1)
  };
}

function frameCoordinateSize(frame = state.frame, monitor = selectedMonitor()) {
  const capture = frame?.monitorGeometry?.captureSize || {};
  return {
    width: Math.max(1, Number(capture.width || monitor?.bounds?.width || frame?.width || state.frameImage?.naturalWidth || 1)),
    height: Math.max(1, Number(capture.height || monitor?.bounds?.height || frame?.height || state.frameImage?.naturalHeight || 1))
  };
}

function monitorLogicalBounds(monitor = selectedMonitor()) {
  if (!monitor?.bounds) return { left: 0, top: 0, width: 1, height: 1 };
  const scale = monitorScale(monitor);
  const bounds = monitor.bounds;
  const logical = monitor.logicalBounds || {};
  return {
    left: Number.isFinite(Number(logical.left)) ? Number(logical.left) : Number(bounds.left || 0) / scale,
    top: Number.isFinite(Number(logical.top)) ? Number(logical.top) : Number(bounds.top || 0) / scale,
    width: Math.max(1, Number.isFinite(Number(logical.width)) ? Number(logical.width) : Number(bounds.width || 1) / scale),
    height: Math.max(1, Number.isFinite(Number(logical.height)) ? Number(logical.height) : Number(bounds.height || 1) / scale)
  };
}

function mapHostCursorToFrame(cursor = {}, monitor = selectedMonitor(), frame = state.frame, options = {}) {
  const sourceCursor = cursor.raw && cursor.coordinateSpace === "physical-frame"
    ? { ...cursor.raw, visible: cursor.visible, source: cursor.source || "frame" }
    : cursor;
  const visual = frameSourceSize(frame);
  const coordinate = frameCoordinateSize(frame, monitor);
  const scale = monitorScale(monitor);
  const space = sourceCursor.coordinateSpace || sourceCursor.rawPoint?.coordinateSpace || "physical-frame";
  let x = Number(sourceCursor.x);
  let y = Number(sourceCursor.y);
  if (Number.isFinite(Number(sourceCursor.physicalX)) && Number.isFinite(Number(sourceCursor.physicalY))) {
    x = Number(sourceCursor.physicalX);
    y = Number(sourceCursor.physicalY);
  } else if (space === "logical-monitor") {
    x *= scale;
    y *= scale;
  } else if (space === "logical-desktop") {
    const logical = monitorLogicalBounds(monitor);
    x = (Number(sourceCursor.x) - logical.left) * scale;
    y = (Number(sourceCursor.y) - logical.top) * scale;
  } else if (space === "physical-desktop") {
    const bounds = monitor?.bounds || {};
    x = Number(sourceCursor.x) - Number(bounds.left || 0);
    y = Number(sourceCursor.y) - Number(bounds.top || 0);
  }

  if (!Number.isFinite(x) || !Number.isFinite(y)) return null;
  const rawNormalizedX = coordinate.width ? clamp(x / coordinate.width, 0, 1) : 0;
  const rawNormalizedY = coordinate.height ? clamp(y / coordinate.height, 0, 1) : 0;
  const calibrated = applyMonitorCalibrationToNormalized(rawNormalizedX, rawNormalizedY, monitor, frame, options);
  const visualX = calibrated.x * visual.width;
  const visualY = calibrated.y * visual.height;
  const mapped = {
    x: Math.round(clamp(visualX, 0, visual.width)),
    y: Math.round(clamp(visualY, 0, visual.height)),
    visible: cursor.visible !== false,
    source: cursor.source || "frame",
    coordinateSpace: "physical-frame",
    raw: {
      x: sourceCursor.x,
      y: sourceCursor.y,
      coordinateSpace: space,
      physicalX: sourceCursor.physicalX,
      physicalY: sourceCursor.physicalY,
      rawPoint: sourceCursor.rawPoint || null
    },
    normalizedX: calibrated.x,
    normalizedY: calibrated.y
  };
  state.lastCursorMap = {
    monitorId: monitor?.id || null,
    scale,
    frameSize: { width: visual.width, height: visual.height },
    coordinateFrameSize: { width: coordinate.width, height: coordinate.height },
    monitorBounds: monitor?.bounds || null,
    logicalBounds: monitorLogicalBounds(monitor),
    input: mapped.raw,
    calibration: {
      applied: calibrated.applied,
      id: calibrated.id,
      rawNormalizedX,
      rawNormalizedY
    },
    output: {
      x: mapped.x,
      y: mapped.y,
      physicalX: Math.round(clamp(x, 0, coordinate.width)),
      physicalY: Math.round(clamp(y, 0, coordinate.height)),
      normalizedX: mapped.normalizedX,
      normalizedY: mapped.normalizedY
    }
  };
  return mapped;
}

function normalizeIncomingFrame(frame = {}) {
  const next = { ...frame };
  if (next.cursor && next.cursor.visible !== false) {
    const monitor = state.monitors.find((item) => item.id === (next.monitorId || state.selectedMonitorId)) || selectedMonitor();
    const mapped = mapHostCursorToFrame(next.cursor, monitor, next);
    if (mapped) next.cursor = mapped;
  }
  return next;
}

function recentAckCursor(frame = state.frame) {
  if (!state.lastAckCursor || !state.lastAckCursorAt || !frame) return null;
  if (performance.now() - state.lastAckCursorAt > ACK_CURSOR_HOLD_MS) return null;
  const { width, height } = frameSourceSize(frame);
  const ackWidth = Number(state.lastAckCursor.frameWidth || width);
  const ackHeight = Number(state.lastAckCursor.frameHeight || height);
  if (Math.abs(ackWidth - width) > 2 || Math.abs(ackHeight - height) > 2) return null;
  return state.lastAckCursor;
}

function activeDisplayCursor(frame = state.frame) {
  return recentAckCursor(frame) || frame?.cursor || null;
}

function clampViewportPan() {
  const visible = 1 / state.viewportZoom;
  const maxPan = Math.max(0, 1 - visible);
  state.viewportPanX = clamp(state.viewportPanX, 0, maxPan);
  state.viewportPanY = clamp(state.viewportPanY, 0, maxPan);
}

function updateZoomUi() {
  state.cursorLensZoom = clamp(Number(state.cursorLensZoom) || 1.7, 1.15, 3);
  state.cursorLensSize = clamp(Number(state.cursorLensSize) || 1, 0.65, 1.35);
  if (el.zoomRange) el.zoomRange.value = String(state.viewportZoom);
  if (el.zoomValue) el.zoomValue.textContent = `${Math.round(state.viewportZoom * 100)}%`;
  if (el.lensZoomRange) el.lensZoomRange.value = String(state.cursorLensZoom);
  if (el.lensZoomValue) el.lensZoomValue.textContent = `${Math.round(state.cursorLensZoom * 100)}%`;
  if (el.lensSizeRange) el.lensSizeRange.value = String(state.cursorLensSize);
  if (el.lensSizeValue) el.lensSizeValue.textContent = `${Math.round(state.cursorLensSize * 100)}%`;
  if (el.cursorLensHold) el.cursorLensHold.checked = state.cursorLensHold;
}

function setViewportZoom(value, options = {}) {
  const focal = options.focalCanvasPoint || null;
  const beforeFocus = focal ? normalizeCanvasPoint(focal) : null;
  const metrics = focal ? frameMetrics() : null;
  state.viewportZoom = clamp(Number(value) || 1, 1, 3);
  if (state.viewportZoom <= 1.01) {
    state.viewportZoom = 1;
    state.viewportPanX = 0;
    state.viewportPanY = 0;
  } else if (beforeFocus && metrics) {
    const visible = 1 / state.viewportZoom;
    const localX = clamp((focal.x - metrics.dx) / Math.max(1, metrics.drawW), 0, 1);
    const localY = clamp((focal.y - metrics.dy) / Math.max(1, metrics.drawH), 0, 1);
    state.viewportPanX = beforeFocus.normalizedX - localX * visible;
    state.viewportPanY = beforeFocus.normalizedY - localY * visible;
    if (options.pauseFollow !== false) {
      state.followPausedUntil = performance.now() + 650;
    }
  } else if (options.follow !== false) {
    followViewportTowardCursor({ force: true, strength: 0.8, skipDraw: true });
  } else {
    state.followPausedUntil = performance.now() + 650;
  }
  clampViewportPan();
  updateZoomUi();
  updateRtcVideoViewport();
  drawFrame();
  updateDiagnostics();
}

function setViewportPan(panX, panY) {
  state.viewportPanX = Number(panX) || 0;
  state.viewportPanY = Number(panY) || 0;
  clampViewportPan();
  updateRtcVideoViewport();
  drawFrame();
  updateDiagnostics();
}

function panViewportByCanvasDelta(deltaX, deltaY) {
  if (state.viewportZoom <= 1) return;
  state.followPausedUntil = performance.now() + 650;
  const metrics = frameMetrics();
  state.viewportPanX -= deltaX / Math.max(1, metrics.drawW * state.viewportZoom);
  state.viewportPanY -= deltaY / Math.max(1, metrics.drawH * state.viewportZoom);
  clampViewportPan();
  drawFrame();
}

function isEdgePanPoint(point) {
  if (state.viewportZoom <= 1 || state.inputMode !== "touchpad" || state.dragLock || state.gesture?.dragging) return false;
  const rect = el.canvas.getBoundingClientRect();
  const edge = Math.min(72, Math.max(34, Math.round(Math.min(rect.width, rect.height) * 0.12)));
  return point.x <= edge || point.y <= edge || point.x >= rect.width - edge || point.y >= rect.height - edge;
}

function handleEdgePan(point, lastPoint) {
  if (!isEdgePanPoint(point) || !lastPoint) return false;
  panViewportByCanvasDelta(point.x - lastPoint.x, point.y - lastPoint.y);
  state.edgePanStats.localMoves += 1;
  if (state.gesture) state.gesture.moved = true;
  updateDiagnostics();
  return true;
}

function resetViewport() {
  state.viewportZoom = 1;
  state.viewportPanX = 0;
  state.viewportPanY = 0;
  updateZoomUi();
  updateRtcVideoViewport();
  drawFrame();
  updateDiagnostics();
}

function isCursorLensCurrentlyAllowed() {
  return !state.cursorLensHold || performance.now() <= state.cursorLensActiveUntil;
}

function markCursorLensMoving() {
  if (!state.cursorLensHold || !state.cursorLensEnabled) return;
  const wasInactive = performance.now() > state.cursorLensActiveUntil;
  state.cursorLensActiveUntil = performance.now() + CURSOR_LENS_HOLD_MS;
  if (state.cursorLensHoldTimer) clearTimeout(state.cursorLensHoldTimer);
  state.cursorLensHoldTimer = setTimeout(() => {
    state.cursorLensHoldTimer = null;
    if (performance.now() <= state.cursorLensActiveUntil) return;
    drawFrame();
  }, CURSOR_LENS_HOLD_MS + 35);
  if (wasInactive) drawFrame();
}

function setCursorLensHold(enabled) {
  state.cursorLensHold = Boolean(enabled);
  localStorage.setItem("remote-cursor-lens-hold", state.cursorLensHold ? "1" : "0");
  if (!state.cursorLensHold) {
    state.cursorLensActiveUntil = 0;
    if (state.cursorLensHoldTimer) {
      clearTimeout(state.cursorLensHoldTimer);
      state.cursorLensHoldTimer = null;
    }
  }
  updateZoomUi();
  drawFrame();
  updateDiagnostics();
}

function setCursorLensZoom(value) {
  state.cursorLensZoom = clamp(Number(value) || 1.7, 1.15, 3);
  localStorage.setItem("remote-cursor-lens-zoom", String(state.cursorLensZoom));
  updateZoomUi();
  drawFrame();
  updateDiagnostics();
}

function setCursorLensSize(value) {
  state.cursorLensSize = clamp(Number(value) || 1, 0.65, 1.35);
  localStorage.setItem("remote-cursor-lens-size", String(state.cursorLensSize));
  updateZoomUi();
  drawFrame();
  updateDiagnostics();
}

function viewportCrop(sourceW, sourceH) {
  const visible = 1 / state.viewportZoom;
  return {
    sx: state.viewportPanX * sourceW,
    sy: state.viewportPanY * sourceH,
    sw: sourceW * visible,
    sh: sourceH * visible
  };
}

function rtcVideoFrame() {
  return state.frame || {
    width: state.rtcVideoWidth || selectedMonitor()?.bounds?.width || 1280,
    height: state.rtcVideoHeight || selectedMonitor()?.bounds?.height || 720
  };
}

function updateRtcVideoViewport() {
  if (!el.rtcVideo) return;
  const rect = el.canvas?.getBoundingClientRect?.();
  if (!rect?.width || !rect?.height) return;
  const frame = rtcVideoFrame();
  const sourceW = Math.max(1, Number(state.rtcVideoWidth || frame?.width || selectedMonitor()?.bounds?.width || 1280));
  const sourceH = Math.max(1, Number(state.rtcVideoHeight || frame?.height || selectedMonitor()?.bounds?.height || 720));
  const metrics = sourceMetrics(sourceW, sourceH, rect);
  const zoom = Math.max(1, Number(state.viewportZoom) || 1);
  el.rtcVideo.style.inset = "auto";
  el.rtcVideo.style.left = `${metrics.dx - state.viewportPanX * metrics.drawW * zoom}px`;
  el.rtcVideo.style.top = `${metrics.dy - state.viewportPanY * metrics.drawH * zoom}px`;
  el.rtcVideo.style.width = `${metrics.drawW * zoom}px`;
  el.rtcVideo.style.height = `${metrics.drawH * zoom}px`;
}

function normalizeCanvasPoint(point) {
  const metrics = frameMetrics();
  const visible = 1 / state.viewportZoom;
  const localX = clamp((point.x - metrics.dx) / Math.max(1, metrics.drawW), 0, 1);
  const localY = clamp((point.y - metrics.dy) / Math.max(1, metrics.drawH), 0, 1);
  return {
    normalizedX: clamp(state.viewportPanX + localX * visible, 0, 1),
    normalizedY: clamp(state.viewportPanY + localY * visible, 0, 1)
  };
}

function remoteCursorNormalized() {
  const cursor = activeDisplayCursor(state.frame);
  if (!state.frame || !cursor || cursor.visible === false) return null;
  const { width: sourceW, height: sourceH } = frameSourceSize(state.frame);
  const x = Number(cursor.x);
  const y = Number(cursor.y);
  if (!Number.isFinite(x) || !Number.isFinite(y)) return null;
  return {
    x: clamp(x / sourceW, 0, 1),
    y: clamp(y / sourceH, 0, 1)
  };
}

function followViewportTowardCursor({ force = false, strength = 0.55, skipDraw = false } = {}) {
  if (!state.autoFollowCursor) return false;
  if (state.viewportZoom <= 1.01) return false;
  if (!force && performance.now() < state.followPausedUntil) return false;
  const cursor = remoteCursorNormalized();
  if (!cursor) return false;
  const visible = 1 / state.viewportZoom;
  const maxPan = Math.max(0, 1 - visible);
  let nextX = state.viewportPanX;
  let nextY = state.viewportPanY;
  const targetX = clamp(cursor.x - visible / 2, 0, maxPan);
  const targetY = clamp(cursor.y - visible / 2, 0, maxPan);
  const followStrength = force ? 1 : clamp(Number(strength) || 1, 0, 1);
  nextX = state.viewportPanX + (targetX - state.viewportPanX) * followStrength;
  nextY = state.viewportPanY + (targetY - state.viewportPanY) * followStrength;
  if (Math.abs(nextX - state.viewportPanX) < 0.0005 && Math.abs(nextY - state.viewportPanY) < 0.0005) return false;
  state.viewportPanX = nextX;
  state.viewportPanY = nextY;
  clampViewportPan();
  if (!skipDraw) drawFrame();
  return true;
}

function forceViewportCenterOnCursor({ skipDraw = false } = {}) {
  if (state.viewportZoom <= 1.01) return false;
  if (!remoteCursorNormalized()) return false;
  const previousPause = state.followPausedUntil;
  state.followPausedUntil = 0;
  const moved = followViewportTowardCursor({ force: true, strength: 1, skipDraw });
  state.followPausedUntil = previousPause;
  return moved;
}

function localCursorFromAbsolute(point, monitor = selectedMonitor()) {
  const mapped = mapHostCursorToFrame({
    x: point?.x,
    y: point?.y,
    visible: true,
    coordinateSpace: point?.coordinateSpace || "logical-desktop",
    source: point?.source || "ack"
  }, monitor, state.frame);
  return mapped || { x: Math.round(Number(point?.x || 0)), y: Math.round(Number(point?.y || 0)) };
}

function updateRemoteCursorFromAck(ack = {}) {
  const point = ack.point;
  if (!state.frame || !point || !Number.isFinite(Number(point.x)) || !Number.isFinite(Number(point.y))) return;
  const local = localCursorFromAbsolute({ ...point, coordinateSpace: ack.coordinateSpace || "logical-desktop", source: "ack" });
  const { width, height } = frameSourceSize(state.frame);
  state.lastAckCursor = {
    x: local.x,
    y: local.y,
    visible: true,
    source: "ack",
    coordinateSpace: "physical-frame",
    frameWidth: width,
    frameHeight: height,
    raw: local.raw || null
  };
  state.lastAckCursorAt = performance.now();
  state.frame.cursor = state.lastAckCursor;
  followViewportTowardCursor({ force: false, strength: 1, skipDraw: true });
  drawFrame();
}

function cursorCanvasPoint(frame, metrics, sourceW, sourceH) {
  const cursor = activeDisplayCursor(frame);
  if (!cursor || cursor.visible === false) return null;
  const crop = viewportCrop(sourceW, sourceH);
  const cursorX = Number(cursor.x);
  const cursorY = Number(cursor.y);
  if (!Number.isFinite(cursorX) || !Number.isFinite(cursorY)) return null;
  if (cursorX < crop.sx || cursorY < crop.sy || cursorX > crop.sx + crop.sw || cursorY > crop.sy + crop.sh) return null;
  return {
    x: metrics.dx + ((cursorX - crop.sx) / Math.max(1, crop.sw)) * metrics.drawW,
    y: metrics.dy + ((cursorY - crop.sy) / Math.max(1, crop.sh)) * metrics.drawH,
    sourceX: cursorX,
    sourceY: cursorY,
    crop
  };
}

function cursorSourcePoint(frame, sourceW, sourceH) {
  const cursor = activeDisplayCursor(frame);
  if (!cursor || cursor.visible === false) return null;
  const x = Number(cursor.x);
  const y = Number(cursor.y);
  if (!Number.isFinite(x) || !Number.isFinite(y)) return null;
  return {
    sourceX: clamp(x, 0, sourceW),
    sourceY: clamp(y, 0, sourceH)
  };
}

function cursorFullCanvasPoint(sourcePoint, metrics, sourceW, sourceH) {
  if (!sourcePoint) return null;
  return {
    x: metrics.dx + (sourcePoint.sourceX / Math.max(1, sourceW)) * metrics.drawW,
    y: metrics.dy + (sourcePoint.sourceY / Math.max(1, sourceH)) * metrics.drawH,
    sourceX: sourcePoint.sourceX,
    sourceY: sourcePoint.sourceY,
    crop: viewportCrop(sourceW, sourceH)
  };
}

function roundedRectPath(x, y, width, height, radius) {
  const r = Math.min(radius, width / 2, height / 2);
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.lineTo(x + width - r, y);
  ctx.quadraticCurveTo(x + width, y, x + width, y + r);
  ctx.lineTo(x + width, y + height - r);
  ctx.quadraticCurveTo(x + width, y + height, x + width - r, y + height);
  ctx.lineTo(x + r, y + height);
  ctx.quadraticCurveTo(x, y + height, x, y + height - r);
  ctx.lineTo(x, y + r);
  ctx.quadraticCurveTo(x, y, x + r, y);
  ctx.closePath();
}

function drawCursorLens(frame, metrics, sourceW, sourceH, sourceElement = state.frameImage) {
  state.lastCursorLensBox = null;
  const elementReady = Boolean(sourceElement && (
    sourceElement === state.frameImage
      ? (state.frameImageReady || sourceElement.complete || sourceElement.naturalWidth > 0 || sourceElement.width > 0)
      : (sourceElement.readyState >= 2 || sourceElement.videoWidth > 0 || sourceElement.width > 0)
  ));
  if (!state.cursorLensEnabled || !elementReady) return false;
  if (!isCursorLensCurrentlyAllowed()) return false;
  const sourcePoint = cursorSourcePoint(frame, sourceW, sourceH);
  if (!sourcePoint) return false;
  let point = cursorCanvasPoint(frame, metrics, sourceW, sourceH);
  if (!point) {
    forceViewportCenterOnCursor({ skipDraw: true });
    point = cursorCanvasPoint(frame, metrics, sourceW, sourceH);
  }
  if (!point) {
    point = cursorFullCanvasPoint(sourcePoint, metrics, sourceW, sourceH);
  }
  if (!point) {
    point = {
      x: metrics.dx + metrics.drawW / 2,
      y: metrics.dy + metrics.drawH / 2,
      sourceX: sourcePoint.sourceX,
      sourceY: sourcePoint.sourceY,
      crop: viewportCrop(sourceW, sourceH)
    };
  }
  const imageW = sourceElement.videoWidth || sourceElement.naturalWidth || sourceElement.width || sourceW;
  const imageH = sourceElement.videoHeight || sourceElement.naturalHeight || sourceElement.height || sourceH;
  const maxLensW = Math.max(1, metrics.drawW - CURSOR_LENS_MARGIN * 2);
  const maxLensH = Math.max(1, metrics.drawH * CURSOR_LENS_VIEWPORT_H);
  const lensSize = clamp(Number(state.cursorLensSize) || 1, 0.65, 1.35);
  const lensZoom = clamp(Number(state.cursorLensZoom) || 1.7, 1.15, 3);
  let lensW = Math.min(
    maxLensW,
    CURSOR_LENS_MAX_W * lensSize,
    Math.max(CURSOR_LENS_MIN_W * lensSize, metrics.drawW * CURSOR_LENS_VIEWPORT_W * lensSize)
  );
  let lensH = lensW * 0.68;
  if (lensH > maxLensH) {
    lensH = maxLensH;
    lensW = Math.min(maxLensW, lensH / 0.68);
  }
  const lensAspect = lensH / Math.max(1, lensW);
  const sourceLensW = Math.min(sourceW, Math.max(120, sourceW * 0.22 / lensZoom));
  const sourceLensH = Math.min(sourceH, Math.max(132, sourceLensW * lensAspect));
  const dx = clamp(
    point.x - lensW / 2,
    metrics.dx + CURSOR_LENS_MARGIN,
    metrics.dx + metrics.drawW - lensW - CURSOR_LENS_MARGIN
  );
  const dy = clamp(
    point.y - lensH / 2,
    metrics.dy + CURSOR_LENS_MARGIN,
    metrics.dy + metrics.drawH - lensH - CURSOR_LENS_MARGIN
  );

  const dotX = dx + lensW / 2;
  const dotY = dy + lensH / 2;
  const drawScaleX = lensW / Math.max(1, sourceLensW);
  const drawScaleY = lensH / Math.max(1, sourceLensH);
  const imageCursorX = sourcePoint.sourceX * (imageW / Math.max(1, sourceW));
  const imageCursorY = sourcePoint.sourceY * (imageH / Math.max(1, sourceH));
  const imageDrawScaleX = drawScaleX * (sourceW / Math.max(1, imageW));
  const imageDrawScaleY = drawScaleY * (sourceH / Math.max(1, imageH));
  ctx.save();
  roundedRectPath(dx, dy, lensW, lensH, 8);
  ctx.clip();
  try {
    ctx.drawImage(
      sourceElement,
      0,
      0,
      imageW,
      imageH,
      dotX - imageCursorX * imageDrawScaleX,
      dotY - imageCursorY * imageDrawScaleY,
      imageW * imageDrawScaleX,
      imageH * imageDrawScaleY
    );
  } catch (error) {
    ctx.restore();
    state.lastError = {
      code: "CURSOR_LENS_DRAW_FAILED",
      friendly: "Zoom lens skipped a bad frame and kept the main screen alive.",
      detail: error.message,
      recoverable: true
    };
    updateDiagnostics();
    return false;
  }
  ctx.fillStyle = "rgba(5, 4, 3, 0.08)";
  ctx.fillRect(dx, dy, lensW, lensH);
  ctx.restore();

  ctx.save();
  state.lastCursorLensBox = {
    x: dx,
    y: dy,
    width: lensW,
    height: lensH,
    dotX,
    dotY,
    imageCursorX,
    imageCursorY,
    sourceLensW,
    sourceLensH,
    cursorCentered: true,
    cursorX: dotX,
    cursorY: dotY,
    screenCursorX: point.x,
    screenCursorY: point.y,
    sourceCursorX: sourcePoint.sourceX,
    sourceCursorY: sourcePoint.sourceY
  };
  ctx.beginPath();
  ctx.arc(dotX, dotY, 2.25, 0, Math.PI * 2);
  ctx.fillStyle = "rgba(214, 168, 74, 0.98)";
  ctx.shadowColor = "rgba(214, 168, 74, 0.5)";
  ctx.shadowBlur = 3;
  ctx.fill();
  ctx.shadowBlur = 0;
  ctx.strokeStyle = "rgba(255, 243, 207, 0.82)";
  ctx.lineWidth = 0.9;
  ctx.stroke();
  roundedRectPath(dx + 0.5, dy + 0.5, lensW - 1, lensH - 1, 8);
  ctx.strokeStyle = "rgba(241, 211, 107, 0.86)";
  ctx.lineWidth = 1.4;
  ctx.stroke();
  roundedRectPath(dx + 3.5, dy + 3.5, lensW - 7, lensH - 7, 6);
  ctx.strokeStyle = "rgba(255, 243, 207, 0.16)";
  ctx.lineWidth = 1;
  ctx.stroke();
  ctx.restore();
  return true;
}

function drawRemoteCursor(frame, metrics, sourceW, sourceH) {
  const point = cursorCanvasPoint(frame, metrics, sourceW, sourceH);
  if (!point) return;
  const { x, y } = point;
  ctx.save();
  ctx.beginPath();
  ctx.arc(x, y, 4.5, 0, Math.PI * 2);
  ctx.fillStyle = "rgba(214, 168, 74, 0.96)";
  ctx.shadowColor = "rgba(214, 168, 74, 0.34)";
  ctx.shadowBlur = 7;
  ctx.fill();
  ctx.shadowBlur = 0;
  ctx.lineWidth = 1.5;
  ctx.strokeStyle = "#fff3cf";
  ctx.stroke();
  ctx.beginPath();
  ctx.moveTo(x + 7, y);
  ctx.lineTo(x + 15, y);
  ctx.moveTo(x, y + 7);
  ctx.lineTo(x, y + 15);
  ctx.strokeStyle = "rgba(255, 243, 207, 0.58)";
  ctx.lineWidth = 1.2;
  ctx.stroke();
  ctx.restore();
}

function drawCalibrationOverlay(metrics) {
  if (!state.calibrationMode) return false;
  const nextIndex = state.calibrationSamples.length;
  ctx.save();
  ctx.beginPath();
  ctx.rect(metrics.dx, metrics.dy, metrics.drawW, metrics.drawH);
  ctx.clip();
  for (let index = 0; index < CALIBRATION_TARGETS.length; index += 1) {
    const target = CALIBRATION_TARGETS[index];
    const x = metrics.dx + target.x * metrics.drawW;
    const y = metrics.dy + target.y * metrics.drawH;
    const active = index === nextIndex;
    const captured = index < nextIndex;
    ctx.save();
    ctx.globalAlpha = active ? 1 : 0.48;
    ctx.strokeStyle = captured ? "rgba(136, 220, 155, 0.9)" : "rgba(241, 211, 107, 0.92)";
    ctx.fillStyle = active ? "rgba(214, 168, 74, 0.16)" : "rgba(5, 4, 3, 0.38)";
    ctx.lineWidth = active ? 2.2 : 1.2;
    ctx.beginPath();
    ctx.arc(x, y, active ? 20 : 14, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(x - 28, y);
    ctx.lineTo(x + 28, y);
    ctx.moveTo(x, y - 28);
    ctx.lineTo(x, y + 28);
    ctx.stroke();
    if (active) {
      ctx.fillStyle = "rgba(255, 243, 207, 0.95)";
      ctx.font = "12px Segoe UI";
      ctx.fillText(target.label, clamp(x - 38, metrics.dx + 8, metrics.dx + metrics.drawW - 88), clamp(y - 34, metrics.dy + 18, metrics.dy + metrics.drawH - 8));
    }
    ctx.restore();
  }
  ctx.restore();
  return true;
}

function drawFrameShell(rect, dpr) {
  const width = Math.max(1, Math.round(rect.width * dpr));
  const height = Math.max(1, Math.round(rect.height * dpr));
  if (el.canvas.width !== width || el.canvas.height !== height) {
    el.canvas.width = width;
    el.canvas.height = height;
  }
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
}

function drawScreenFrame(frame, w, h) {
  const drawableImage = state.frameImage
    && (
      state.frameImageReady
      || state.frameImage.complete
      || state.frameImage.naturalWidth > 0
      || state.frameImage.width > 0
    );

  if (drawableImage) {
    const { width: sourceW, height: sourceH } = frameSourceSize(frame);
    if (state.autoFollowCursor && state.viewportZoom > 1.01) {
      forceViewportCenterOnCursor({ skipDraw: true });
    }
    const metrics = frameMetrics(frame, { width: w, height: h });
    const crop = viewportCrop(sourceW, sourceH);
    try {
      ctx.fillStyle = "#030706";
      if (metrics.dx > 0) {
        ctx.fillRect(0, 0, metrics.dx, h);
        ctx.fillRect(metrics.dx + metrics.drawW, 0, Math.max(0, w - metrics.dx - metrics.drawW), h);
      }
      if (metrics.dy > 0) {
        ctx.fillRect(0, 0, w, metrics.dy);
        ctx.fillRect(0, metrics.dy + metrics.drawH, w, Math.max(0, h - metrics.dy - metrics.drawH));
      }
      ctx.drawImage(state.frameImage, crop.sx, crop.sy, crop.sw, crop.sh, metrics.dx, metrics.dy, metrics.drawW, metrics.drawH);
    } catch (error) {
      state.frameImageReady = Boolean(state.frameImage && (state.frameImage.naturalWidth || state.frameImage.width));
      state.frameDecodeRecoveries += 1;
      state.lastError = {
        code: "FRAME_DRAW_FAILED",
        friendly: "Screen frame draw failed; waiting for the next live frame.",
        detail: error.message,
        recoverable: true
      };
      updateDiagnostics();
      return;
    }
    const lensDrawn = drawCursorLens(frame, metrics, sourceW, sourceH);
    if (!lensDrawn) drawRemoteCursor(frame, metrics, sourceW, sourceH);
    drawCalibrationOverlay(metrics);
    ctx.strokeStyle = "rgba(255,255,255,0.22)";
    ctx.lineWidth = 1;
    ctx.strokeRect(metrics.dx, metrics.dy, metrics.drawW, metrics.drawH);
  } else {
    if (state.lastDecodedFrameAt || state.frameImage) {
      kickBlankCanvasStream("canvas-awaiting-next-decode");
      return;
    }
    ctx.fillStyle = "#0f1c1d";
    ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = "#d7eded";
    ctx.font = "16px Segoe UI";
    ctx.fillText("Loading screen frame...", 18, 34);
    kickBlankCanvasStream("canvas-loading");
  }

  el.latencyChip.textContent = `${Math.max(0, state.latency)} ms`;
}

function drawRtcOverlay(frame, w, h) {
  ctx.clearRect(0, 0, w, h);
  const overlayFrame = frame || rtcVideoFrame();
  updateRtcVideoViewport();
  const sourceW = Math.max(1, Number(state.rtcVideoWidth || overlayFrame?.width || selectedMonitor()?.bounds?.width || 1280));
  const sourceH = Math.max(1, Number(state.rtcVideoHeight || overlayFrame?.height || selectedMonitor()?.bounds?.height || 720));
  if (state.autoFollowCursor && state.viewportZoom > 1.01) {
    forceViewportCenterOnCursor({ skipDraw: true });
    updateRtcVideoViewport();
  }
  const metrics = sourceMetrics(sourceW, sourceH, { width: w, height: h });
  if (frame) {
    const lensDrawn = drawCursorLens(frame, metrics, sourceW, sourceH, el.rtcVideo);
    if (!lensDrawn) drawRemoteCursor(frame, metrics, sourceW, sourceH);
  }
  drawCalibrationOverlay(metrics);
  if (state.calibrationMode) {
    ctx.strokeStyle = "rgba(241, 211, 107, 0.64)";
    ctx.lineWidth = 1;
    ctx.strokeRect(metrics.dx, metrics.dy, metrics.drawW, metrics.drawH);
  }
  el.latencyChip.textContent = state.rtcStatus === "connected" || state.rtcActive ? "RTC" : "wait";
}

function drawFrame() {
  const frame = state.frame;
  const dpr = window.devicePixelRatio || 1;
  const rect = el.canvas.getBoundingClientRect();
  drawFrameShell(rect, dpr);
  const w = rect.width;
  const h = rect.height;
  if (state.rtcActive) {
    drawRtcOverlay(frame, w, h);
    state.lastCanvasPaintAt = performance.now();
    return;
  }
  if (!frame) {
    ctx.fillStyle = "#030706";
    ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = "#f1d36b";
    ctx.font = "15px Segoe UI";
    ctx.fillText("Switching display...", 18, 34);
    return;
  }

  if (frame.imageObjectUrl || frame.imageDataUrl) {
    drawScreenFrame(frame, w, h);
    state.lastCanvasPaintAt = performance.now();
    return;
  }

  const gradient = ctx.createLinearGradient(0, 0, w, h);
  gradient.addColorStop(0, "#071527");
  gradient.addColorStop(1, "#122b2d");
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, w, h);
  ctx.strokeStyle = "#28494d";
  ctx.lineWidth = 1;
  const metrics = frameMetrics(frame, { width: w, height: h });
  const crop = viewportCrop(frame.width, frame.height);
  const sx = metrics.drawW / crop.sw;
  const sy = metrics.drawH / crop.sh;
  const mapX = (value) => metrics.dx + (value - crop.sx) * sx;
  const mapY = (value) => metrics.dy + (value - crop.sy) * sy;
  ctx.save();
  ctx.beginPath();
  ctx.rect(metrics.dx, metrics.dy, metrics.drawW, metrics.drawH);
  ctx.clip();
  ctx.fillStyle = "#090704";
  ctx.fillRect(metrics.dx, metrics.dy, metrics.drawW, metrics.drawH);
  for (let x = Math.floor(crop.sx / 48) * 48; x < crop.sx + crop.sw; x += 48) {
    ctx.beginPath();
    ctx.moveTo(mapX(x), metrics.dy);
    ctx.lineTo(mapX(x), metrics.dy + metrics.drawH);
    ctx.stroke();
  }
  for (let y = Math.floor(crop.sy / 48) * 48; y < crop.sy + crop.sh; y += 48) {
    ctx.beginPath();
    ctx.moveTo(metrics.dx, mapY(y));
    ctx.lineTo(metrics.dx + metrics.drawW, mapY(y));
    ctx.stroke();
  }
  for (const win of frame.windows) {
    ctx.fillStyle = win.active ? "rgba(214, 168, 74, 0.22)" : "rgba(255,255,255,0.08)";
    ctx.strokeStyle = win.active ? "#d6a84a" : "#66583e";
    ctx.lineWidth = 2;
    ctx.fillRect(mapX(win.x), mapY(win.y), win.width * sx, win.height * sy);
    ctx.strokeRect(mapX(win.x), mapY(win.y), win.width * sx, win.height * sy);
    ctx.fillStyle = "#f7f0df";
    ctx.font = "14px Segoe UI";
    ctx.fillText(win.title, mapX(win.x) + 12, mapY(win.y) + 26);
  }
  ctx.fillStyle = "#f7f0df";
  ctx.font = "18px Segoe UI";
  ctx.fillText(frame.desktopLabel, metrics.dx + 18, metrics.dy + 96);
  const cursor = activeDisplayCursor(frame);
  if (cursor && cursor.visible !== false) {
    ctx.fillStyle = "#d6a84a";
    ctx.beginPath();
    ctx.arc(mapX(cursor.x), mapY(cursor.y), 13, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = "#ffffff";
    ctx.lineWidth = 2;
    ctx.stroke();
  }
  ctx.restore();
  ctx.strokeStyle = "rgba(255,255,255,0.22)";
  ctx.strokeRect(metrics.dx, metrics.dy, metrics.drawW, metrics.drawH);
  drawCalibrationOverlay(metrics);
  if (state.viewportZoom > 1) {
    ctx.fillStyle = "rgba(3, 7, 6, 0.76)";
    ctx.fillRect(metrics.dx + 10, metrics.dy + 10, 88, 28);
    ctx.fillStyle = "#f1d36b";
    ctx.font = "13px Segoe UI";
    ctx.fillText(`${Math.round(state.viewportZoom * 100)}% view`, metrics.dx + 20, metrics.dy + 29);
  }
  el.latencyChip.textContent = `${Math.max(0, state.latency)} ms`;
}

function canvasPoint(event) {
  const rect = el.canvas.getBoundingClientRect();
  const point = {
    x: event.clientX - rect.left,
    y: event.clientY - rect.top
  };
  const normalized = normalizeCanvasPoint(point);
  return {
    ...point,
    ...normalized
  };
}

function movementSensitivity() {
  return state.sensitivity * (state.precisionMode ? 0.35 : 1);
}

function isZoomModeActive() {
  return Boolean(state.autoFollowCursor && (state.viewportZoom > 1.01 || state.cursorLensEnabled));
}

function allSheets() {
  return [el.monitorSheet, el.keyboardSheet, el.settingsSheet].filter(Boolean);
}

function setRailSheetState() {
  document.querySelectorAll("[data-sheet]").forEach((button) => {
    button.classList.toggle("active", button.dataset.sheet === state.activeSheetId);
    button.setAttribute("aria-pressed", button.dataset.sheet === state.activeSheetId ? "true" : "false");
  });
}

function closeSheets() {
  allSheets().forEach((sheet) => sheet.classList.remove("open"));
  state.activeSheetId = "";
  setRailSheetState();
}

function openSheet(sheetId) {
  const sheet = document.getElementById(sheetId);
  if (!sheet) return;
  allSheets().forEach((item) => item.classList.toggle("open", item === sheet));
  state.activeSheetId = sheetId;
  setRailSheetState();
}

function updatePreferenceUi() {
  state.sensitivity = clamp(Number(state.sensitivity) || DEFAULT_POINTER_SPEED, 0.35, 3.5);
  state.scrollSpeed = clamp(Number(state.scrollSpeed) || 1, 0.35, 2.5);
  if (el.sensitivity) el.sensitivity.value = String(state.sensitivity);
  if (el.scrollSpeed) el.scrollSpeed.value = String(state.scrollSpeed);
  if (el.scrollSpeedValue) el.scrollSpeedValue.textContent = `${Math.round(state.scrollSpeed * 100)}%`;
  if (el.autoFollowCursor) el.autoFollowCursor.checked = state.autoFollowCursor;
  if (el.cursorLensEnabled) el.cursorLensEnabled.checked = state.cursorLensEnabled;
  if (el.followCursorBtn) {
    const zoomActive = isZoomModeActive();
    el.followCursorBtn.classList.toggle("follow-active", zoomActive);
    el.followCursorBtn.setAttribute("aria-pressed", zoomActive ? "true" : "false");
    el.followCursorBtn.textContent = "Zoom";
  }
  setRailSheetState();
  if (el.showHalo) el.showHalo.checked = state.showHalo;
  if (el.hapticsEnabled) el.hapticsEnabled.checked = state.hapticsEnabled;
}

function setPointerSensitivity(value) {
  state.sensitivity = clamp(Number(value) || DEFAULT_POINTER_SPEED, 0.35, 3.5);
  localStorage.setItem("remote-sensitivity", String(state.sensitivity));
  updatePreferenceUi();
  updateDiagnostics();
}

function setAutoFollowCursor(enabled, options = {}) {
  state.autoFollowCursor = Boolean(enabled);
  localStorage.setItem("remote-auto-follow-cursor", state.autoFollowCursor ? "1" : "0");
  if (state.autoFollowCursor && options.autoZoom) {
    state.cursorLensEnabled = true;
    localStorage.setItem("remote-cursor-lens", "1");
  }
  updatePreferenceUi();
  if (state.autoFollowCursor) {
    state.followPausedUntil = 0;
    if (options.autoZoom && state.viewportZoom <= 1.01) {
      state.viewportZoom = state.cursorLensZoom;
      updateZoomUi();
    }
    state.cursorLensEnabled = true;
    localStorage.setItem("remote-cursor-lens", "1");
    followViewportTowardCursor({ force: true, strength: 1 });
  } else if (options.resetZoom) {
    state.viewportZoom = 1;
    state.viewportPanX = 0;
    state.viewportPanY = 0;
    state.cursorLensEnabled = false;
    state.lastCursorLensBox = null;
    localStorage.setItem("remote-cursor-lens", "0");
    updateZoomUi();
    updatePreferenceUi();
  }
  drawFrame();
  updateDiagnostics();
}

function setZoomModeActive(enabled) {
  closeSheets();
  if (enabled) {
    state.autoFollowCursor = true;
    state.cursorLensEnabled = true;
    state.followPausedUntil = 0;
    localStorage.setItem("remote-auto-follow-cursor", "1");
    localStorage.setItem("remote-cursor-lens", "1");
    if (state.viewportZoom <= 1.01) {
      state.viewportZoom = state.cursorLensZoom;
      updateZoomUi();
    }
    followViewportTowardCursor({ force: true, strength: 1 });
  } else {
    state.autoFollowCursor = false;
    state.cursorLensEnabled = false;
    state.viewportZoom = 1;
    state.viewportPanX = 0;
    state.viewportPanY = 0;
    state.lastCursorLensBox = null;
    localStorage.setItem("remote-auto-follow-cursor", "0");
    localStorage.setItem("remote-cursor-lens", "0");
    updateZoomUi();
  }
  updatePreferenceUi();
  drawFrame();
  updateDiagnostics();
}

function setCursorLensEnabled(enabled, options = {}) {
  state.cursorLensEnabled = Boolean(enabled);
  localStorage.setItem("remote-cursor-lens", state.cursorLensEnabled ? "1" : "0");
  updatePreferenceUi();
  if (!options.skipDraw) {
    drawFrame();
    updateDiagnostics();
  }
  state.lastCanvasPaintAt = performance.now();
}

function setScrollSpeed(value) {
  state.scrollSpeed = clamp(Number(value) || 1, 0.35, 2.5);
  localStorage.setItem("remote-scroll-speed", String(state.scrollSpeed));
  updatePreferenceUi();
  updateDiagnostics();
}

function setHaloEnabled(enabled) {
  state.showHalo = Boolean(enabled);
  localStorage.setItem("remote-show-halo", state.showHalo ? "1" : "0");
  if (!state.showHalo) hidePointerHalo();
  updatePreferenceUi();
  updateDiagnostics();
}

function setHapticsEnabled(enabled) {
  state.hapticsEnabled = Boolean(enabled);
  localStorage.setItem("remote-haptics", state.hapticsEnabled ? "1" : "0");
  updatePreferenceUi();
  updateDiagnostics();
}

function setControlHold(enabled, source = "rail-control") {
  const active = Boolean(enabled);
  if (state.controlHoldActive === active) return;
  state.controlHoldActive = active;
  el.controlHoldBtn?.classList.toggle("active", active);
  el.controlHoldBtn?.setAttribute("aria-pressed", active ? "true" : "false");
  touchFeedback(active ? [8, 28, 8] : 6);
  send(active ? "keyDown" : "keyUp", { key: "Ctrl", source });
  updateDiagnostics();
}

function updateCalibrationUi() {
  if (!el.calibrationStatus) return;
  const calibration = activeMonitorCalibration();
  el.calibrationStatus.textContent = calibrationStatusText(calibration);
  el.calibrationToggleBtn?.classList.toggle("active", state.calibrationMode);
  if (el.calibrationToggleBtn) {
    el.calibrationToggleBtn.textContent = state.calibrationMode ? "Hide Targets" : "Show Targets";
  }
  if (el.calibrationCaptureBtn) {
    const next = CALIBRATION_TARGETS[state.calibrationSamples.length];
    el.calibrationCaptureBtn.textContent = next ? `Capture ${state.calibrationSamples.length + 1}/4` : "Save Calibration";
    el.calibrationCaptureBtn.disabled = !state.calibrationMode;
  }
}

function setCalibrationMode(enabled) {
  state.calibrationMode = Boolean(enabled);
  state.calibrationSamples = [];
  state.calibrationMessage = state.calibrationMode ? "Move cursor to the highlighted target." : "";
  if (state.frame?.cursor?.raw) {
    const remapped = mapHostCursorToFrame(state.frame.cursor, selectedMonitor(), state.frame, {
      applyCalibration: !state.calibrationMode
    });
    if (remapped) state.frame.cursor = remapped;
  }
  updateCalibrationUi();
  drawFrame();
  updateDiagnostics();
}

function resetMonitorCalibration() {
  delete state.monitorCalibrations[monitorCalibrationSignature()];
  saveMonitorCalibrations();
  state.calibrationSamples = [];
  state.calibrationMessage = "Calibration reset";
  updateCalibrationUi();
  if (state.frame?.cursor?.raw) {
    const remapped = mapHostCursorToFrame(state.frame.cursor, selectedMonitor(), state.frame);
    if (remapped) state.frame.cursor = remapped;
  }
  drawFrame();
  updateDiagnostics();
}

function buildCalibrationFromSamples(samples = state.calibrationSamples) {
  if (samples.length < CALIBRATION_TARGETS.length) return null;
  const byId = Object.fromEntries(samples.map((sample) => [sample.id, sample]));
  const required = CALIBRATION_TARGETS.every((target) => byId[target.id]);
  if (!required) return null;
  const leftObserved = (byId["top-left"].observedX + byId["bottom-left"].observedX) / 2;
  const rightObserved = (byId["top-right"].observedX + byId["bottom-right"].observedX) / 2;
  const topObserved = (byId["top-left"].observedY + byId["top-right"].observedY) / 2;
  const bottomObserved = (byId["bottom-left"].observedY + byId["bottom-right"].observedY) / 2;
  const targetLeft = (byId["top-left"].targetX + byId["bottom-left"].targetX) / 2;
  const targetRight = (byId["top-right"].targetX + byId["bottom-right"].targetX) / 2;
  const targetTop = (byId["top-left"].targetY + byId["top-right"].targetY) / 2;
  const targetBottom = (byId["bottom-left"].targetY + byId["bottom-right"].targetY) / 2;
  const observedSpanX = Math.max(0.05, rightObserved - leftObserved);
  const observedSpanY = Math.max(0.05, bottomObserved - topObserved);
  const scaleX = (targetRight - targetLeft) / observedSpanX;
  const scaleY = (targetBottom - targetTop) / observedSpanY;
  const offsetX = targetLeft - leftObserved * scaleX;
  const offsetY = targetTop - topObserved * scaleY;
  const maxError = Math.max(...samples.map((sample) => Math.hypot(sample.targetX - sample.observedX, sample.targetY - sample.observedY)));
  return {
    id: `cal-${Date.now()}`,
    enabled: true,
    monitorId: selectedMonitor()?.id || state.selectedMonitorId,
    signature: monitorCalibrationSignature(),
    createdAt: new Date().toISOString(),
    maxError,
    transform: {
      scaleX: Math.round(scaleX * 1000000) / 1000000,
      scaleY: Math.round(scaleY * 1000000) / 1000000,
      offsetX: Math.round(offsetX * 1000000) / 1000000,
      offsetY: Math.round(offsetY * 1000000) / 1000000
    },
    samples
  };
}

function captureCalibrationPoint() {
  if (!state.calibrationMode) return false;
  const target = CALIBRATION_TARGETS[state.calibrationSamples.length];
  if (!target) {
    const calibration = buildCalibrationFromSamples();
    if (!calibration) return false;
    state.monitorCalibrations[calibration.signature] = calibration;
    saveMonitorCalibrations();
    state.calibrationMode = false;
    state.calibrationSamples = [];
    state.calibrationMessage = "Calibration saved";
    if (state.frame?.cursor?.raw) {
      const remapped = mapHostCursorToFrame(state.frame.cursor, selectedMonitor(), state.frame);
      if (remapped) state.frame.cursor = remapped;
    }
    updateCalibrationUi();
    drawFrame();
    updateDiagnostics();
    return true;
  }
  const cursor = remoteCursorNormalized();
  if (!cursor) {
    state.calibrationMessage = "Cursor not visible";
    updateCalibrationUi();
    return false;
  }
  state.calibrationSamples.push({
    id: target.id,
    label: target.label,
    targetX: target.x,
    targetY: target.y,
    observedX: cursor.x,
    observedY: cursor.y,
    cursor: { ...(state.frame?.cursor || {}) },
    cursorMap: state.lastCursorMap,
    capturedAt: new Date().toISOString()
  });
  state.calibrationMessage = state.calibrationSamples.length === CALIBRATION_TARGETS.length
    ? "Tap Save Calibration"
    : `Captured ${target.label}`;
  updateCalibrationUi();
  drawFrame();
  updateDiagnostics();
  return true;
}

function touchFeedback(pattern = 8) {
  if (!state.hapticsEnabled || !navigator.vibrate) return false;
  return navigator.vibrate(pattern);
}

function setTouchpadCursorHint(x = state.touchpadCursorX, y = state.touchpadCursorY) {
  state.touchpadCursorX = clamp(Number(x) || 0.5, 0.01, 0.99);
  state.touchpadCursorY = clamp(Number(y) || 0.5, 0.01, 0.99);
  if (!el.touchpadCursorHint) return;
  el.touchpadSurface?.style.setProperty("--touch-vfx-x", `${state.touchpadCursorX * 100}%`);
  el.touchpadSurface?.style.setProperty("--touch-vfx-y", `${state.touchpadCursorY * 100}%`);
  el.touchpadCursorHint.style.left = `${state.touchpadCursorX * 100}%`;
  el.touchpadCursorHint.style.top = `${state.touchpadCursorY * 100}%`;
}

function touchpadPoint(event) {
  const rect = el.touchpadSurface.getBoundingClientRect();
  return {
    x: event.clientX - rect.left,
    y: event.clientY - rect.top,
    width: rect.width,
    height: rect.height,
    at: performance.now()
  };
}

function averageTouchpadPointers() {
  const points = [...state.touchpadPointers.values()];
  if (!points.length) return null;
  const reference = points[points.length - 1] || {};
  return {
    x: points.reduce((sum, point) => sum + point.x, 0) / points.length,
    y: points.reduce((sum, point) => sum + point.y, 0) / points.length,
    width: reference.width || 0,
    height: reference.height || 0,
    at: Math.max(...points.map((point) => Number(point.at || performance.now())))
  };
}

function startTouchpadScrollGesture() {
  clearTouchpadLongPress();
  stopTouchpadEdgeHold();
  if (state.touchpadGesture) state.touchpadGesture.moved = true;
  finishTouchpadDrag();
  state.touchpadScrollGesture = {
    startedAt: performance.now(),
    lastAverage: averageTouchpadPointers()
  };
  state.touchpadSuppressUntilAllLift = true;
  scheduleTouchpadScrollEdgeHold(state.touchpadScrollGesture.lastAverage);
  touchFeedback(6);
}

function sendTouchpadWheel(deltaX, deltaY, source = "touchpad-two-finger") {
  if (Math.abs(deltaX) < 1 && Math.abs(deltaY) < 1) return false;
  send("wheel", {
    deltaX: Math.round(deltaX),
    deltaY: Math.round(deltaY),
    source
  });
  return true;
}

function sendTouchpadScroll(currentAverage) {
  const gesture = state.touchpadScrollGesture;
  if (!gesture?.lastAverage || !currentAverage) return false;
  const dx = currentAverage.x - gesture.lastAverage.x;
  const dy = currentAverage.y - gesture.lastAverage.y;
  gesture.lastAverage = currentAverage;
  scheduleTouchpadScrollEdgeHold(currentAverage);
  if (Math.abs(dx) < 0.6 && Math.abs(dy) < 0.6) return false;
  return sendTouchpadWheel(-dx * 6 * state.scrollSpeed, -dy * 6 * state.scrollSpeed);
}

function touchpadScrollEdgeVector(point) {
  if (!point) return 0;
  const edge = Math.max(26, Math.min(point.width || 0, point.height || 0) * 0.13);
  const top = point.y < edge ? -((edge - point.y) / edge) : 0;
  const bottom = point.y > point.height - edge ? (point.y - (point.height - edge)) / edge : 0;
  return clamp(top + bottom, -1, 1);
}

function stopTouchpadScrollEdgeHold() {
  if (state.touchpadScrollEdgeTimer) {
    if (typeof cancelAnimationFrame === "function") {
      cancelAnimationFrame(state.touchpadScrollEdgeTimer);
    }
    clearTimeout(state.touchpadScrollEdgeTimer);
    state.touchpadScrollEdgeTimer = null;
  }
  state.touchpadScrollEdgeVector = 0;
  state.touchpadScrollEdgeLastAt = 0;
}

function scheduleTouchpadScrollEdgeHold(point) {
  const vector = touchpadScrollEdgeVector(point);
  if (!vector || state.touchpadPointers.size < 2 || !state.touchpadScrollGesture) {
    stopTouchpadScrollEdgeHold();
    return;
  }
  state.touchpadScrollEdgeVector += (vector - state.touchpadScrollEdgeVector) * TOUCHPAD_SCROLL_EDGE_SMOOTHING;
  if (state.touchpadScrollEdgeTimer) return;
  state.touchpadScrollEdgeLastAt = performance.now();
  const tick = () => {
    state.touchpadScrollEdgeTimer = null;
    if (state.touchpadPointers.size < 2 || !state.touchpadScrollGesture) {
      stopTouchpadScrollEdgeHold();
      return;
    }
    const average = averageTouchpadPointers();
    const nextVector = touchpadScrollEdgeVector(average);
    if (!nextVector) {
      stopTouchpadScrollEdgeHold();
      return;
    }
    state.touchpadScrollEdgeVector += (nextVector - state.touchpadScrollEdgeVector) * TOUCHPAD_SCROLL_EDGE_SMOOTHING;
    const now = performance.now();
    const dt = Math.min(42, Math.max(10, now - state.touchpadScrollEdgeLastAt || TOUCHPAD_EDGE_FRAME_MS));
    state.touchpadScrollEdgeLastAt = now;
    const intensity = Math.abs(state.touchpadScrollEdgeVector);
    const speed = (TOUCHPAD_SCROLL_EDGE_SPEED_MIN + TOUCHPAD_SCROLL_EDGE_SPEED_MAX * intensity) * state.scrollSpeed;
    sendTouchpadWheel(0, -state.touchpadScrollEdgeVector * speed * (dt / 1000) * 6, "touchpad-two-finger-edge");
    state.touchpadScrollEdgeTimer = typeof requestAnimationFrame === "function"
      ? requestAnimationFrame(tick)
      : setTimeout(tick, TOUCHPAD_EDGE_FRAME_MS);
  };
  state.touchpadScrollEdgeTimer = typeof requestAnimationFrame === "function"
    ? requestAnimationFrame(tick)
    : setTimeout(tick, TOUCHPAD_EDGE_FRAME_MS);
}

function clearTouchpadScrollGesture() {
  stopTouchpadScrollEdgeHold();
  state.touchpadScrollGesture = null;
  if (state.touchpadPointers.size === 0) {
    state.touchpadSuppressUntilAllLift = false;
  }
}

function sendTouchpadMove(point, lastPoint = state.touchpadLastPoint) {
  if (!point || !lastPoint) return;
  const rawDx = point.x - lastPoint.x;
  const rawDy = point.y - lastPoint.y;
  const dt = Math.max(8, Math.min(120, Number(point.at || performance.now()) - Number(lastPoint.at || performance.now())));
  const rawDistance = Math.hypot(rawDx, rawDy);
  const smoothing = clamp(TOUCHPAD_SMOOTHING_MIN + (rawDistance / 48) * (TOUCHPAD_SMOOTHING_MAX - TOUCHPAD_SMOOTHING_MIN), TOUCHPAD_SMOOTHING_MIN, TOUCHPAD_SMOOTHING_MAX);
  state.touchpadSmoothDx = state.touchpadSmoothDx + (rawDx - state.touchpadSmoothDx) * smoothing;
  state.touchpadSmoothDy = state.touchpadSmoothDy + (rawDy - state.touchpadSmoothDy) * smoothing;
  const acceleration = touchpadAcceleration(rawDx, rawDy, dt);
  const dx = state.touchpadSmoothDx * movementSensitivity() * acceleration * TOUCHPAD_VIRTUAL_GAIN;
  const dy = state.touchpadSmoothDy * movementSensitivity() * acceleration * TOUCHPAD_VIRTUAL_GAIN;
  if (Math.abs(dx) < 0.2 && Math.abs(dy) < 0.2) return;
  markCursorLensMoving();
  setTouchpadCursorHint(
    state.touchpadCursorX + (rawDx * TOUCHPAD_HINT_GAIN) / Math.max(1, point.width),
    state.touchpadCursorY + (rawDy * TOUCHPAD_HINT_GAIN) / Math.max(1, point.height)
  );
  sendTouchpadDelta(dx, dy);
}

function touchpadAcceleration(dx, dy, dt) {
  const velocity = Math.hypot(dx, dy) / Math.max(8, dt);
  return clamp(1 + Math.sqrt(velocity) * 0.58, 1, 2.25);
}

function sendTouchpadDelta(dx, dy, source = "touchpad") {
  if (Math.abs(dx) < 0.2 && Math.abs(dy) < 0.2) return false;
  if (source === "touchpad-edge-hold") markCursorLensMoving();
  state.touchpadSent += 1;
  state.touchpadLastError = "";
  const ok = socketOpen();
  send("pointer.move", {
    mode: "touchpad",
    dx,
    dy,
    source,
    dragging: Boolean(state.dragLock || state.touchpadDragActive)
  });
  if (!ok) state.touchpadLastError = "not connected";
  updateTouchpadStatus();
  return ok;
}

function moveTouchpadHintTowardPoint(point, gain = TOUCHPAD_HINT_GAIN) {
  if (!point) return;
  const targetX = point.x / Math.max(1, point.width);
  const targetY = point.y / Math.max(1, point.height);
  setTouchpadCursorHint(
    state.touchpadCursorX + (targetX - state.touchpadCursorX) * gain,
    state.touchpadCursorY + (targetY - state.touchpadCursorY) * gain
  );
}

function keepCanvasAlive() {
  if (document.hidden) return;
  if (!state.connected || !state.approved || !state.frame) return;
  const visibleAge = performance.now() - (state.lastDecodedFrameAt || state.lastFrameAt || state.connectedAt || performance.now());
  if (visibleAge > STREAM_WATCHDOG_MS) {
    assertLiveStreamVisible("canvas-keepalive");
  }
  if (state.frameImageReady && state.frameImage) {
    state.canvasKeepalivePaints += 1;
    drawFrame();
    return;
  }
  if (!state.frameImage && !state.frameImageReady && !state.pendingFrameImageSource) {
    kickBlankCanvasStream("canvas-keepalive-blank");
  }
}

function pulseTouchpadVfx(className = "touch-vfx") {
  if (!el.touchpadSurface) return;
  el.touchpadSurface.classList.remove("touch-vfx", "release-vfx");
  void el.touchpadSurface.offsetWidth;
  el.touchpadSurface.classList.add(className);
  setTimeout(() => {
    el.touchpadSurface?.classList.remove(className);
  }, className === "release-vfx" ? 240 : 180);
}

function centerTouchpadCursorHint() {
  if (!el.touchpadCursorHint) {
    setTouchpadCursorHint(0.5, 0.5);
    return;
  }
  el.touchpadCursorHint.classList.add("returning");
  setTouchpadCursorHint(0.5, 0.5);
  setTimeout(() => {
    el.touchpadCursorHint?.classList.remove("returning");
  }, 190);
}

function touchpadEdgeVector(point) {
  if (!point) return { x: 0, y: 0 };
  const edge = Math.max(24, Math.min(point.width, point.height) * 0.11);
  const left = point.x < edge ? -((edge - point.x) / edge) : 0;
  const right = point.x > point.width - edge ? (point.x - (point.width - edge)) / edge : 0;
  const top = point.y < edge ? -((edge - point.y) / edge) : 0;
  const bottom = point.y > point.height - edge ? (point.y - (point.height - edge)) / edge : 0;
  return {
    x: clamp(left + right, -1, 1),
    y: clamp(top + bottom, -1, 1)
  };
}

function stopTouchpadEdgeHold() {
  if (state.touchpadEdgeHoldTimer) {
    if (typeof cancelAnimationFrame === "function") {
      cancelAnimationFrame(state.touchpadEdgeHoldTimer);
    }
    clearTimeout(state.touchpadEdgeHoldTimer);
    state.touchpadEdgeHoldTimer = null;
  }
  state.touchpadEdgeHoldVector = { x: 0, y: 0 };
  state.touchpadEdgeHoldLastAt = 0;
}

function resetTouchpadSmoothing() {
  state.touchpadSmoothDx = 0;
  state.touchpadSmoothDy = 0;
}

function clearTouchpadLongPress() {
  clearTimeout(state.touchpadLongPressTimer);
  state.touchpadLongPressTimer = null;
}

function finishTouchpadDrag(point = state.touchpadLastPoint) {
  if (!state.touchpadDragActive) return;
  state.touchpadDragActive = false;
  send("pointer.up", {
    button: "left",
    mode: "touchpad",
    source: "touchpad-drag-end",
    x: point?.x,
    y: point?.y
  });
}

function startTouchpadDrag(source = "touchpad-drag") {
  if (state.touchpadDragActive) return;
  state.touchpadDragActive = true;
  touchFeedback([8, 30, 8]);
  send("pointer.down", {
    button: "left",
    mode: "touchpad",
    source
  });
}

function resetTouchpadGesture() {
  clearTouchpadLongPress();
  state.touchpadGesture = null;
}

function cancelActivePhoneInput(reason = "phone-cancel") {
  stopTouchpadEdgeHold();
  stopTouchpadScrollEdgeHold();
  resetTouchpadSmoothing();
  clearTouchpadLongPress();
  cancelTouchpadSingleClick();
  finishTouchpadDrag();
  centerTouchpadCursorHint();
  pulseTouchpadVfx("release-vfx");
  if (state.controlHoldActive) setControlHold(false, `${reason}-release`);
  state.touchpadPointerId = null;
  state.touchpadLastPoint = null;
  state.touchpadPointers.clear();
  clearTouchpadScrollGesture();
  state.touchpadSuppressUntilAllLift = false;
  state.touchpadGesture = null;
  el.touchpadSurface?.classList.remove("active");
  if (state.dragLock) {
    state.dragLock = false;
    send("pointer.cancelDrag", { reason });
  }
  flushPointerMove();
}

function scheduleTouchpadEdgeHold(point) {
  const vector = touchpadEdgeVector(point);
  if (!vector.x && !vector.y) {
    stopTouchpadEdgeHold();
    return;
  }
  state.touchpadEdgeHoldVector = {
    x: state.touchpadEdgeHoldVector.x + (vector.x - state.touchpadEdgeHoldVector.x) * TOUCHPAD_EDGE_SMOOTHING,
    y: state.touchpadEdgeHoldVector.y + (vector.y - state.touchpadEdgeHoldVector.y) * TOUCHPAD_EDGE_SMOOTHING
  };
  if (state.touchpadEdgeHoldTimer) return;
  state.touchpadEdgeHoldLastAt = performance.now();
  const tick = () => {
    state.touchpadEdgeHoldTimer = null;
    if (state.touchpadPointerId === null) {
      stopTouchpadEdgeHold();
      return;
    }
    const now = performance.now();
    const dt = Math.min(34, Math.max(8, now - state.touchpadEdgeHoldLastAt || TOUCHPAD_EDGE_FRAME_MS));
    state.touchpadEdgeHoldLastAt = now;
    const { x, y } = state.touchpadEdgeHoldVector;
    if (!x && !y) return;
    const intensity = Math.max(Math.abs(x), Math.abs(y));
    const speed = (TOUCHPAD_EDGE_SPEED_MIN + TOUCHPAD_EDGE_SPEED_MAX * intensity)
      * movementSensitivity()
      * TOUCHPAD_VIRTUAL_GAIN
      * TOUCHPAD_EDGE_GAIN;
    sendTouchpadDelta(x * speed * (dt / 1000), y * speed * (dt / 1000), "touchpad-edge-hold");
    state.touchpadEdgeHoldTimer = typeof requestAnimationFrame === "function"
      ? requestAnimationFrame(tick)
      : setTimeout(tick, TOUCHPAD_EDGE_FRAME_MS);
  };
  state.touchpadEdgeHoldTimer = typeof requestAnimationFrame === "function"
    ? requestAnimationFrame(tick)
    : setTimeout(tick, TOUCHPAD_EDGE_FRAME_MS);
}

function updateTouchpadStatus() {
  if (!el.touchpadStatus) return;
  const connected = state.connected ? "Connected" : "Not connected";
  const error = state.touchpadLastError ? ` - ${state.touchpadLastError}` : "";
  el.touchpadStatus.textContent = `${connected} - ${state.touchpadAcked}/${state.touchpadSent} moves${error}`;
}

function updateVisualViewportHeight() {
  const height = window.visualViewport?.height || window.innerHeight || 0;
  if (height > 0) {
    document.documentElement.style.setProperty("--visual-viewport-height", `${Math.round(height)}px`);
  }
  drawFrame();
}

function setNativeKeyboardOpen(open) {
  state.nativeKeyboardOpen = Boolean(open);
  el.controller.classList.toggle("keyboard-open", state.nativeKeyboardOpen);
  el.keyboardToggleBtn?.classList.toggle("active", state.nativeKeyboardOpen);
  if (el.keyboardToggleBtn) {
    el.keyboardToggleBtn.setAttribute("aria-pressed", state.nativeKeyboardOpen ? "true" : "false");
  }
  updateDiagnostics();
}

function focusNativeKeyboardBridge() {
  if (!el.nativeKeyboardInput) return;
  el.nativeKeyboardInput.value = "";
  try {
    el.nativeKeyboardInput.focus({ preventScroll: true });
  } catch {
    el.nativeKeyboardInput.focus();
  }
  setNativeKeyboardOpen(true);
  setTimeout(() => {
    if (!state.nativeKeyboardOpen || document.activeElement === el.nativeKeyboardInput) return;
    try {
      el.nativeKeyboardInput.focus({ preventScroll: true });
    } catch {
      el.nativeKeyboardInput.focus();
    }
  }, 80);
}

function toggleNativeKeyboard() {
  if (!el.nativeKeyboardInput) return;
  if (state.nativeKeyboardOpen && document.activeElement === el.nativeKeyboardInput) {
    el.nativeKeyboardInput.blur();
    setNativeKeyboardOpen(false);
    return;
  }
  document.getElementById("keyboardSheet")?.classList.remove("open");
  focusNativeKeyboardBridge();
}

function sendNativeKeyboardText(text) {
  if (!text) return;
  send(text.length > 1 ? "pasteText" : "text", { text });
}

function showPointerHalo(point) {
  if (!point || !state.showHalo) return;
  el.pointerHalo.style.left = `${point.x}px`;
  el.pointerHalo.style.top = `${point.y}px`;
  el.pointerHalo.classList.toggle("precision", state.precisionMode);
  el.pointerHalo.classList.remove("hidden");
}

function hidePointerHalo() {
  el.pointerHalo.classList.add("hidden");
}

function setPrecisionMode(enabled) {
  state.precisionMode = Boolean(enabled);
  el.precisionBtn?.classList.toggle("active", state.precisionMode);
  el.pointerHalo.classList.toggle("precision", state.precisionMode);
  touchFeedback(state.precisionMode ? 12 : 6);
  updateDiagnostics();
}

function pointerDistance(a, b) {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  return Math.hypot(dx, dy);
}

function averagePointers() {
  const points = [...state.activePointers.values()];
  if (!points.length) return null;
  return {
    x: points.reduce((sum, item) => sum + item.x, 0) / points.length,
    y: points.reduce((sum, item) => sum + item.y, 0) / points.length
  };
}

function twoPointerDistance() {
  const points = [...state.activePointers.values()];
  if (points.length < 2) return 0;
  return pointerDistance(points[0], points[1]);
}

function clearGestureTimers() {
  clearTimeout(state.longPressTimer);
  state.longPressTimer = null;
}

function sendTap(button = "left") {
  touchFeedback(button === "right" ? [10, 30, 10] : 8);
  send("pointer.click", { button });
}

function scheduleTouchpadSingleClick() {
  clearTimeout(state.pendingTapTimer);
  state.pendingTapTimer = setTimeout(() => {
    state.pendingTapTimer = null;
    sendTap("left");
  }, 260);
}

function cancelTouchpadSingleClick() {
  clearTimeout(state.pendingTapTimer);
  state.pendingTapTimer = null;
}

function sendDoubleTap(button = "left") {
  clearTimeout(state.pendingTapTimer);
  state.pendingTapTimer = null;
  touchFeedback([8, 30, 8]);
  send("pointer.doubleClick", { button });
}

function bindPointer() {
  el.canvas.addEventListener("pointerdown", (event) => {
    event.preventDefault();
    try {
      el.canvas.setPointerCapture(event.pointerId);
    } catch {
      // Synthetic browser tests may not register an active pointer; real touch events still capture normally.
    }
    const point = canvasPoint(event);
    state.activePointers.set(event.pointerId, point);
    showPointerHalo(point);
    state.lastPointer = point;
    state.gesture = {
      startedAt: performance.now(),
      startPoint: point,
      moved: false,
      longPressFired: false,
      twoFingerLast: averagePointers()
    };

    if (state.activePointers.size >= 2) {
      clearGestureTimers();
      state.pinchGesture = {
        startDistance: Math.max(1, twoPointerDistance()),
        startZoom: state.viewportZoom,
        lastAverage: averagePointers()
      };
    }
  });
  el.canvas.addEventListener("pointermove", (event) => {
    event.preventDefault();
    const point = canvasPoint(event);
    if (!state.activePointers.has(event.pointerId)) return;
    state.activePointers.set(event.pointerId, point);
    if (!state.lastPointer) {
      state.lastPointer = point;
      showPointerHalo(point);
      return;
    }

    if (state.activePointers.size >= 2) {
      clearGestureTimers();
      const avg = averagePointers();
      showPointerHalo(avg);
      if (!state.pinchGesture) {
        state.pinchGesture = {
          startDistance: Math.max(1, twoPointerDistance()),
          startZoom: state.viewportZoom,
          lastAverage: avg
        };
      }
      const pinchDistance = Math.max(1, twoPointerDistance());
      const zoomCandidate = state.pinchGesture.startZoom * (pinchDistance / state.pinchGesture.startDistance);
      setViewportZoom(zoomCandidate, { focalCanvasPoint: avg, follow: false });
      const panLast = state.pinchGesture.lastAverage || avg;
      panViewportByCanvasDelta(avg.x - panLast.x, avg.y - panLast.y);
      state.pinchGesture.lastAverage = avg;
      if (state.gesture) {
        state.gesture.twoFingerLast = avg;
        state.gesture.moved = true;
      }
      state.lastPointer = point;
      return;
    }

    const distance = pointerDistance(point, state.gesture?.startPoint || state.lastPointer);
    if (distance > 8) {
      clearGestureTimers();
      if (state.gesture) state.gesture.moved = true;
    }
    showPointerHalo(point);
    if (state.viewportZoom > 1.01) {
      panViewportByCanvasDelta(point.x - state.lastPointer.x, point.y - state.lastPointer.y);
      if (state.gesture) state.gesture.moved = true;
    }
    state.lastPointer = point;
  });
  el.canvas.addEventListener("pointerup", (event) => {
    event.preventDefault();
    const point = canvasPoint(event);
    showPointerHalo(point);
    state.activePointers.delete(event.pointerId);
    if (state.activePointers.size < 2) {
      state.pinchGesture = null;
    }
    clearGestureTimers();

    if (state.activePointers.size === 0) {
      state.lastPointer = null;
      state.gesture = null;
      state.pinchGesture = null;
      setTimeout(() => {
        if (!state.activePointers.size) hidePointerHalo();
      }, 260);
    }
  });
  el.canvas.addEventListener("pointercancel", () => {
    state.activePointers.clear();
    state.lastPointer = null;
    state.gesture = null;
    state.pinchGesture = null;
    clearGestureTimers();
    hidePointerHalo();
  });
  el.canvas.addEventListener("wheel", (event) => {
    event.preventDefault();
    if (event.ctrlKey) {
      const rect = el.canvas.getBoundingClientRect();
      setViewportZoom(state.viewportZoom + (-event.deltaY / 500), {
        focalCanvasPoint: {
          x: event.clientX - rect.left,
          y: event.clientY - rect.top
        },
        follow: false
      });
      return;
    }
    panViewportByCanvasDelta(-event.deltaX, -event.deltaY);
  }, { passive: false });
}

function bindTouchpad() {
  if (!el.touchpadSurface) return;
  el.touchpadSurface.addEventListener("dblclick", (event) => {
    event.preventDefault();
    event.stopPropagation();
  });
  el.touchpadSurface.addEventListener("touchstart", (event) => {
    if (event.cancelable) event.preventDefault();
  }, { passive: false });
  el.touchpadSurface.addEventListener("touchend", (event) => {
    if (event.cancelable) event.preventDefault();
  }, { passive: false });
  el.touchpadSurface.addEventListener("pointerdown", (event) => {
    event.preventDefault();
    try {
      el.touchpadSurface.setPointerCapture(event.pointerId);
    } catch {}
    const point = touchpadPoint(event);
    state.touchpadPointers.set(event.pointerId, point);
    if (state.touchpadPointerId !== null && state.touchpadPointerId !== event.pointerId) {
      startTouchpadScrollGesture();
      updateTouchpadStatus();
      return;
    }
    if (state.touchpadSuppressUntilAllLift) return;
    state.touchpadPointerId = event.pointerId;
    state.touchpadLastPoint = point;
    resetTouchpadSmoothing();
    const now = performance.now();
    const doubleTapCandidate = state.touchpadLastTapPoint
      && now - state.touchpadLastTapAt < 330
      && pointerDistance(state.touchpadLastPoint, state.touchpadLastTapPoint) < 44;
    if (doubleTapCandidate) cancelTouchpadSingleClick();
    state.touchpadGesture = {
      startedAt: now,
      startPoint: state.touchpadLastPoint,
      moved: false,
      longPressFired: false,
      doubleTapCandidate: Boolean(doubleTapCandidate)
    };
    el.touchpadSurface.classList.add("active");
    el.touchpadCursorHint?.classList.remove("returning");
    pulseTouchpadVfx("touch-vfx");
    moveTouchpadHintTowardPoint(state.touchpadLastPoint, 0.08);
    scheduleTouchpadEdgeHold(state.touchpadLastPoint);
    clearTouchpadLongPress();
    state.touchpadLongPressTimer = setTimeout(() => {
      if (!state.touchpadGesture || state.touchpadGesture.moved) return;
      state.touchpadGesture.longPressFired = true;
      sendTap("right");
      touchFeedback([10, 30, 10]);
      state.touchpadLastTapAt = 0;
      state.touchpadLastTapPoint = null;
    }, 420);
    updateTouchpadStatus();
    touchFeedback(4);
  });
  el.touchpadSurface.addEventListener("pointermove", (event) => {
    event.preventDefault();
    const point = touchpadPoint(event);
    if (state.touchpadPointers.has(event.pointerId)) {
      state.touchpadPointers.set(event.pointerId, point);
    }
    if (state.touchpadScrollGesture && state.touchpadPointers.size >= 2) {
      sendTouchpadScroll(averageTouchpadPointers());
      updateTouchpadStatus();
      return;
    }
    if (state.touchpadSuppressUntilAllLift) return;
    if (state.touchpadPointerId !== event.pointerId) return;
    const movedDistance = pointerDistance(point, state.touchpadGesture?.startPoint || state.touchpadLastPoint || point);
    if (movedDistance > 7 && state.touchpadGesture) {
      state.touchpadGesture.moved = true;
      clearTouchpadLongPress();
      if (state.touchpadGesture.doubleTapCandidate && !state.touchpadDragActive) {
        startTouchpadDrag("touchpad-double-tap-drag");
        state.touchpadLastTapAt = 0;
        state.touchpadLastTapPoint = null;
      }
    }
    const edgeVector = touchpadEdgeVector(point);
    if (edgeVector.x || edgeVector.y) {
      moveTouchpadHintTowardPoint(point, 0.12);
      scheduleTouchpadEdgeHold(point);
      state.touchpadLastPoint = point;
      return;
    }
    sendTouchpadMove(point);
    state.touchpadLastPoint = point;
    scheduleTouchpadEdgeHold(point);
  });
  el.touchpadSurface.addEventListener("pointerup", (event) => {
    event.preventDefault();
    const point = touchpadPoint(event);
    state.touchpadPointers.delete(event.pointerId);
    if (state.touchpadScrollGesture || state.touchpadSuppressUntilAllLift) {
      if (state.touchpadPointers.size < 2) clearTouchpadScrollGesture();
      if (state.touchpadPointers.size === 0) {
        state.touchpadPointerId = null;
        state.touchpadLastPoint = null;
        resetTouchpadGesture();
        el.touchpadSurface.classList.remove("active");
        centerTouchpadCursorHint();
        pulseTouchpadVfx("release-vfx");
      }
      updateTouchpadStatus();
      touchFeedback(3);
      return;
    }
    if (state.touchpadPointerId !== event.pointerId) return;
    const gesture = state.touchpadGesture;
    state.touchpadPointerId = null;
    state.touchpadLastPoint = null;
    resetTouchpadSmoothing();
    stopTouchpadEdgeHold();
    clearTouchpadLongPress();
    el.touchpadSurface.classList.remove("active");
    if (state.touchpadDragActive) {
      finishTouchpadDrag(point);
      state.touchpadLastTapAt = 0;
      state.touchpadLastTapPoint = null;
    } else if (gesture && !gesture.moved && !gesture.longPressFired) {
      if (gesture.doubleTapCandidate) {
        cancelTouchpadSingleClick();
        sendTap("right");
        state.touchpadLastTapAt = 0;
        state.touchpadLastTapPoint = null;
      } else {
        state.touchpadLastTapAt = performance.now();
        state.touchpadLastTapPoint = point;
        scheduleTouchpadSingleClick();
      }
    }
    centerTouchpadCursorHint();
    pulseTouchpadVfx("release-vfx");
    resetTouchpadGesture();
    updateTouchpadStatus();
    touchFeedback(3);
  });
  el.touchpadSurface.addEventListener("pointercancel", () => {
    cancelActivePhoneInput("touchpad-pointer-cancel");
  });
  el.leftClickPadBtn?.addEventListener("click", () => sendTap("left"));
  el.rightClickPadBtn?.addEventListener("click", () => sendTap("right"));
}

function bindControls() {
  document.querySelectorAll("[data-sheet]").forEach((button) => {
    button.addEventListener("click", () => {
      const nextSheet = button.dataset.sheet;
      if (state.activeSheetId === nextSheet) {
        closeSheets();
      } else {
        openSheet(nextSheet);
      }
    });
  });
  document.querySelectorAll("[data-close]").forEach((button) => {
    button.addEventListener("click", () => closeSheets());
  });
  document.querySelectorAll(".mode").forEach((button) => {
    button.addEventListener("click", () => {
      document.querySelectorAll(".mode").forEach((item) => item.classList.remove("active"));
      button.classList.add("active");
      state.inputMode = button.dataset.mode;
      touchFeedback(6);
    });
  });
  document.getElementById("dragLockBtn")?.addEventListener("click", () => {
    state.dragLock = !state.dragLock;
    document.getElementById("dragLockBtn")?.classList.toggle("active", state.dragLock);
    touchFeedback(state.dragLock ? [12, 35, 12] : 8);
    send(state.dragLock ? "pointer.down" : "pointer.cancelDrag", { button: "left", dragLock: true });
  });
  document.getElementById("rightClickBtn")?.addEventListener("click", () => {
    touchFeedback([10, 30, 10]);
    send("pointer.click", { button: "right" });
  });
  el.keyboardToggleBtn.addEventListener("pointerdown", (event) => {
    event.preventDefault();
    state.nativeKeyboardPointerToggleAt = performance.now();
    toggleNativeKeyboard();
  });
  el.keyboardToggleBtn.addEventListener("click", (event) => {
    if (performance.now() - state.nativeKeyboardPointerToggleAt < 500) {
      event.preventDefault();
      return;
    }
    toggleNativeKeyboard();
  });
  el.nativeKeyboardInput.addEventListener("focus", () => setNativeKeyboardOpen(true));
  el.nativeKeyboardInput.addEventListener("blur", () => {
    state.nativeKeyboardBlurredAt = Date.now();
    setNativeKeyboardOpen(false);
  });
  el.nativeKeyboardInput.addEventListener("keydown", (event) => {
    if (event.key === "Backspace" || event.key === "Enter" || event.key === "Tab" || event.key === "Escape") {
      event.preventDefault();
      send("key", { key: event.key === "Escape" ? "Esc" : event.key });
      el.nativeKeyboardInput.value = "";
    }
  });
  el.nativeKeyboardInput.addEventListener("beforeinput", (event) => {
    if (event.inputType === "insertLineBreak") {
      event.preventDefault();
      send("key", { key: "Enter" });
      el.nativeKeyboardInput.value = "";
    }
  });
  el.nativeKeyboardInput.addEventListener("input", () => {
    sendNativeKeyboardText(el.nativeKeyboardInput.value);
    el.nativeKeyboardInput.value = "";
  });
  el.precisionBtn?.addEventListener("click", () => {
    setPrecisionMode(!state.precisionMode);
  });
  el.disconnectBtn.addEventListener("click", () => {
    state.manualDisconnect = true;
    clearTimeout(state.reconnectTimer);
    send("session.disconnect", {});
    state.ws?.close();
  });
  el.qualitySelect.addEventListener("change", () => {
    send("stream.setQuality", { quality: el.qualitySelect.value });
  });
  el.sensitivity.addEventListener("input", () => {
    setPointerSensitivity(el.sensitivity.value);
  });
  el.scrollSpeed.addEventListener("input", () => {
    setScrollSpeed(el.scrollSpeed.value);
  });
  el.zoomRange.addEventListener("input", () => {
    setViewportZoom(el.zoomRange.value);
  });
  el.lensZoomRange?.addEventListener("input", () => {
    setCursorLensZoom(el.lensZoomRange.value);
  });
  el.lensSizeRange?.addEventListener("input", () => {
    setCursorLensSize(el.lensSizeRange.value);
  });
  el.resetZoomBtn.addEventListener("click", resetViewport);
  el.followCursorBtn?.addEventListener("click", () => {
    setZoomModeActive(!isZoomModeActive());
  });
  el.controlHoldBtn?.addEventListener("click", () => {
    setControlHold(!state.controlHoldActive);
  });
  el.windowsShortcutBtn?.addEventListener("click", () => runShortcut("windows"));
  el.codexShortcutBtn?.addEventListener("click", () => runShortcut("codex"));
  el.claudeShortcutBtn?.addEventListener("click", () => runShortcut("claude"));
  el.autoFollowCursor?.addEventListener("change", () => {
    setAutoFollowCursor(el.autoFollowCursor.checked, { autoZoom: true });
  });
  el.cursorLensEnabled?.addEventListener("change", () => {
    setCursorLensEnabled(el.cursorLensEnabled.checked);
  });
  el.cursorLensHold?.addEventListener("change", () => {
    setCursorLensHold(el.cursorLensHold.checked);
  });
  el.showHalo.addEventListener("change", () => {
    setHaloEnabled(el.showHalo.checked);
  });
  el.hapticsEnabled.addEventListener("change", () => {
    setHapticsEnabled(el.hapticsEnabled.checked);
  });
  el.calibrationToggleBtn?.addEventListener("click", () => {
    setCalibrationMode(!state.calibrationMode);
  });
  el.calibrationCaptureBtn?.addEventListener("click", () => {
    captureCalibrationPoint();
  });
  el.calibrationResetBtn?.addEventListener("click", () => {
    resetMonitorCalibration();
  });
  el.acceptanceMarkBtn?.addEventListener("click", () => {
    markAcceptanceProof();
  });
  el.acceptanceBannerMarkBtn?.addEventListener("click", () => {
    markAcceptanceProof();
  });
}

function runShortcut(name) {
  if (name === "windows") {
    send("key", { key: "Win", source: "shortcut-windows" });
    return;
  }
  if (name === "codex") {
    send("chord", { modifiers: ["Win"], key: "S", source: "shortcut-codex" });
    setTimeout(() => send("pasteText", { text: "Codex", source: "shortcut-codex" }), 170);
    setTimeout(() => send("key", { key: "Enter", source: "shortcut-codex" }), 430);
    return;
  }
  if (name === "claude") {
    send("chord", { modifiers: ["Win"], key: "R", source: "shortcut-claude" });
    setTimeout(() => send("pasteText", { text: "https://claude.ai/new", source: "shortcut-claude" }), 180);
    setTimeout(() => send("key", { key: "Enter", source: "shortcut-claude" }), 460);
  }
}

function buildKeyboard() {
  const modifiers = new Set(["Ctrl", "Alt", "Shift", "Win"]);
  const combos = new Map([
    ["Copy", { modifiers: ["Ctrl"], key: "C" }],
    ["Paste", { modifiers: ["Ctrl"], key: "V" }],
    ["Undo", { modifiers: ["Ctrl"], key: "Z" }],
    ["Redo", { modifiers: ["Ctrl"], key: "Y" }],
    ["Lock", { modifiers: ["Win"], key: "L" }]
  ]);
  const labels = new Map([
    ["Backspace", "Bksp"],
    ["Screenshot", "Shot"]
  ]);
  const keys = [
    "Esc", "Tab", "Enter", "Backspace", "Delete",
    "Ctrl", "Alt", "Shift", "Win",
    "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
    "Up", "Left", "Down", "Right", "Home", "End",
    "Copy", "Paste", "Undo", "Redo", "Screenshot", "Lock"
  ];
  for (const key of keys) {
    const button = document.createElement("button");
    button.textContent = labels.get(key) || key;
    button.title = key;
    button.addEventListener("click", () => {
      if (modifiers.has(key)) {
        if (state.latchedModifiers.has(key)) {
          state.latchedModifiers.delete(key);
        } else {
          state.latchedModifiers.add(key);
        }
        button.classList.toggle("active", state.latchedModifiers.has(key));
        updateDiagnostics();
        return;
      }
      if (combos.has(key)) {
        send("chord", combos.get(key));
        return;
      }
      if (state.latchedModifiers.size) {
        send("chord", { modifiers: [...state.latchedModifiers], key });
        state.latchedModifiers.clear();
        el.keyGrid.querySelectorAll(".active").forEach((item) => item.classList.remove("active"));
        updateDiagnostics();
        return;
      }
      send("key", { key });
    });
    el.keyGrid.appendChild(button);
  }
  el.textForm.addEventListener("submit", (event) => {
    event.preventDefault();
    const text = el.textInput.value;
    if (!text) return;
    send("pasteText", { text });
    el.textInput.value = "";
  });
}

function updateDiagnostics(lastAck = null) {
  const debug = debugSnapshot(lastAck);
  debug.bandwidthKbps = approximateFps() ? Math.round((debug.frameBytes * approximateFps() * 8) / 1024) : 0;
  debug.frameKB = Math.round(debug.frameBytes / 1024);
  el.diagnostics.textContent = JSON.stringify(debug, null, 2);
}

function debugSnapshot(lastAck = null) {
  const approxFps = approximateFps();
  const frameBytes = state.frame?.imageByteLength
    || (state.frame?.imageDataUrl
    ? Math.round(state.frame.imageDataUrl.length * 0.75)
    : JSON.stringify(state.frame || {}).length);
  const rect = el.canvas.getBoundingClientRect();
  const metrics = frameMetrics(state.frame, rect);
  const { width: sourceW, height: sourceH } = frameSourceSize(state.frame);
  const canvasCursor = activeDisplayCursor(state.frame)
    ? cursorCanvasPoint(state.frame, metrics, sourceW, sourceH)
    : null;
  return {
    connected: state.connected,
    sessionId: state.sessionId,
    monitor: state.selectedMonitorId,
    selectedMonitor: selectedMonitor(),
    frameGeometry: state.frame?.monitorGeometry || null,
    frameSize: state.frame ? { width: state.frame.width, height: state.frame.height } : null,
    bitmapSize: state.frameImage ? {
      width: state.frameImage.naturalWidth || 0,
      height: state.frameImage.naturalHeight || 0
    } : null,
    drawRect: {
      x: Math.round(metrics.dx * 100) / 100,
      y: Math.round(metrics.dy * 100) / 100,
      width: Math.round(metrics.drawW * 100) / 100,
      height: Math.round(metrics.drawH * 100) / 100
    },
    canvasCursor: canvasCursor ? {
      x: Math.round(canvasCursor.x * 100) / 100,
      y: Math.round(canvasCursor.y * 100) / 100,
      sourceX: Math.round(canvasCursor.sourceX * 100) / 100,
      sourceY: Math.round(canvasCursor.sourceY * 100) / 100
    } : null,
    frameId: state.frame?.frameId || 0,
    fpsApprox: approxFps,
    frameBytes,
    targetFps: state.streamStats.fpsTarget ?? null,
    presetFpsTarget: state.streamStats.presetFpsTarget || null,
    adaptiveMode: state.streamStats.adaptiveMode || "preset",
    rtcActive: state.rtcActive,
    rtcStatus: state.rtcStatus,
    rtcVideo: {
      width: state.rtcVideoWidth,
      height: state.rtcVideoHeight
    },
    streamVisible: state.streamVisible,
    visibleClients: state.streamStats.visibleClients ?? null,
    hiddenClients: state.streamStats.hiddenClients ?? null,
    hiddenFrameTicks: state.streamStats.hiddenFrameTicks || 0,
    streamWatchdogReconnects: state.streamWatchdogReconnects,
    streamWakePokes: state.streamWakePokes,
    streamWakeBurstCount: state.streamWakeBurstCount,
    frameDecodeRecoveries: state.frameDecodeRecoveries,
    frameBlobFallbacks: state.frameBlobFallbacks,
    skippedBlackFrames: state.skippedBlackFrames,
    streamWatchdogAgeMs: state.lastStreamWatchdogAt ? Math.round(performance.now() - state.lastStreamWatchdogAt) : null,
    lastError: state.lastError,
    edgePanLocalMoves: state.edgePanStats.localMoves,
    hostCaptureMs: state.streamStats.lastCaptureMs || 0,
    inputMode: state.inputMode,
    precisionMode: state.precisionMode,
    viewportZoom: state.viewportZoom,
    viewportPanX: Math.round(state.viewportPanX * 1000) / 1000,
    viewportPanY: Math.round(state.viewportPanY * 1000) / 1000,
    autoFollowCursor: state.autoFollowCursor,
    cursorLensEnabled: state.cursorLensEnabled,
    cursorMap: state.lastCursorMap,
    cursorSource: activeDisplayCursor(state.frame)?.source || null,
    ackCursorAgeMs: state.lastAckCursorAt ? Math.round(performance.now() - state.lastAckCursorAt) : null,
    calibration: {
      active: activeMonitorCalibration(),
      mode: state.calibrationMode,
      samples: state.calibrationSamples.length,
      signature: monitorCalibrationSignature()
    },
    scrollSpeed: state.scrollSpeed,
    showHalo: state.showHalo,
    hapticsEnabled: state.hapticsEnabled,
    hostClockSynced: state.hostClockSynced,
    hostClockOffsetMs: state.hostClockOffsetMs,
    hostClockSyncAgeMs: state.lastHostClockSyncAt ? Math.round(performance.now() - state.lastHostClockSyncAt) : null,
    nativeKeyboardOpen: state.nativeKeyboardOpen,
    touchpadCursorX: Math.round(state.touchpadCursorX * 1000) / 1000,
  touchpadCursorY: Math.round(state.touchpadCursorY * 1000) / 1000,
    touchpadPointers: state.touchpadPointers.size,
    touchpadScrolling: Boolean(state.touchpadScrollGesture),
  touchpadSent: state.touchpadSent,
    touchpadAcked: state.touchpadAcked,
    touchpadLastError: state.touchpadLastError,
    effectiveSensitivity: movementSensitivity(),
    touchpadVirtualGain: TOUCHPAD_VIRTUAL_GAIN,
    latchedModifiers: [...state.latchedModifiers],
    controlHoldActive: state.controlHoldActive,
    latencyMs: state.latency,
    inputRttMs: state.inputRttMs,
    pointerMoveQueued: state.pointerMoveStats.queued,
    pointerMoveSent: state.pointerMoveStats.sent,
    pointerMoveCoalesced: state.pointerMoveStats.coalesced,
    lastAck: lastAck || state.lastAck
  };
}

async function pollApproval() {
  if (!state.token) return;
  try {
    const session = await checkedApi(`/api/session?token=${encodeURIComponent(state.token)}`);
    state.approved = session.approved;
    if (session.approved) {
      el.pairStatus.textContent = "Approved. Connecting...";
      hideConnectionHelp();
      connectWebSocket();
    } else {
      el.pairStatus.textContent = "Waiting for laptop approval.";
      hideConnectionHelp();
      setTimeout(pollApproval, 1200);
    }
  } catch (error) {
    if (error.code === "SESSION_NOT_FOUND" || error.status === 404) {
      clearExpiredSavedSession(error);
      return;
    }
    el.pairStatus.textContent = error.message;
    showConnectionHelp(error, "approval");
  }
}

el.pairForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  try {
    el.pairStatus.textContent = "Pairing...";
    hideConnectionHelp();
    localStorage.setItem("remote-keep-device-signed-in", el.keepDeviceSignedIn?.checked ? "1" : "0");
    const result = await checkedApi("/api/pair", {
      method: "POST",
      body: JSON.stringify({
        pin: el.pin.value,
        deviceName: el.deviceName.value,
        keepSignedIn: Boolean(el.keepDeviceSignedIn?.checked)
      })
    });
    state.token = result.token;
    state.sessionId = result.sessionId;
    localStorage.setItem("remote-token", state.token);
    localStorage.setItem("remote-session-id", state.sessionId);
    pollApproval();
  } catch (error) {
    el.pairStatus.textContent = error.message;
    showConnectionHelp(error, "pair");
  }
});

el.forgetSession.addEventListener("click", forgetSavedSession);
if (el.keepDeviceSignedIn) {
  el.keepDeviceSignedIn.checked = localStorage.getItem("remote-keep-device-signed-in") === "1";
}
document.addEventListener("visibilitychange", () => {
  if (document.hidden) cancelActivePhoneInput("page-hidden");
  reportStreamVisibility(document.hidden);
  if (!document.hidden) {
    resumeLiveSession("visibility-return");
    setTimeout(() => assertLiveStreamVisible("visibility-return"), 80);
    setTimeout(() => startStreamWakeBurst("visibility-return-burst"), 120);
  }
});
window.addEventListener("pagehide", () => {
  cancelActivePhoneInput("pagehide");
  send("session.disconnect", { reason: "pagehide" });
});
window.visualViewport?.addEventListener("resize", updateVisualViewportHeight);
window.addEventListener("resize", updateVisualViewportHeight);
window.addEventListener("pageshow", () => {
  reportStreamVisibility(false);
  resumeLiveSession("pageshow");
  setTimeout(() => assertLiveStreamVisible("pageshow"), 80);
  setTimeout(() => startStreamWakeBurst("pageshow-burst"), 120);
});
window.addEventListener("focus", () => {
  reportStreamVisibility(false);
  resumeLiveSession("focus");
  setTimeout(() => assertLiveStreamVisible("focus"), 80);
  setTimeout(() => startStreamWakeBurst("focus-burst"), 120);
});
window.addEventListener("online", () => resumeLiveSession("online"));
setInterval(handleStreamWatchdogTick, STREAM_WATCHDOG_MS);
setInterval(keepCanvasAlive, CANVAS_KEEPALIVE_PAINT_MS);

bindPointer();
bindTouchpad();
bindControls();
buildKeyboard();
updateVisualViewportHeight();
updateZoomUi();
updatePreferenceUi();
updateCalibrationUi();
updateAcceptanceUi();

if (state.token) {
  pollApproval();
  setTimeout(() => resumeLiveSession("startup"), 250);
}

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/sw.js?v=68").then((registration) => {
    registration.update().catch(() => {});
    registration.addEventListener("updatefound", () => {
      const worker = registration.installing;
      if (!worker || !navigator.serviceWorker.controller) return;
      worker.addEventListener("statechange", () => {
        if (worker.state !== "installed") return;
        const reloadKey = "remote-controller-shell-v68-reloaded";
        if (sessionStorage.getItem(reloadKey) === "1") return;
        sessionStorage.setItem(reloadKey, "1");
        location.reload();
      });
    });
  }).catch(() => {});
}

window.__remoteControllerDebug = {
  state,
  send,
  syncHostClock,
  commandTimestamp,
  handleServerPacket,
  decodeBinaryStreamPacket,
  reportStreamVisibility,
  assertLiveStreamVisible,
  kickBlankCanvasStream,
  startStreamWakeBurst,
  stopStreamWakeBurst,
  resumeLiveSession,
  handleStreamWatchdogTick,
  flushPointerMove,
  setPrecisionMode,
  setControlHold,
  movementSensitivity,
  showPointerHalo,
  hidePointerHalo,
  setViewportZoom,
  setViewportPan,
  resetViewport,
  resetMonitorViewState,
  selectMonitor,
  verifySavedSessionBeforeReconnect,
  frameMetrics,
  normalizeCanvasPoint,
  isEdgePanPoint,
  handleEdgePan,
  sendTouchpadMove,
  sendTouchpadDelta,
  touchpadAcceleration,
  setTouchpadCursorHint,
  touchpadEdgeVector,
  scheduleTouchpadEdgeHold,
  stopTouchpadEdgeHold,
  averageTouchpadPointers,
  sendTouchpadScroll,
  cancelActivePhoneInput,
  updateRemoteCursorFromAck,
  activeDisplayCursor,
  mapHostCursorToFrame,
  normalizeIncomingFrame,
  cursorCanvasPoint,
  cursorSourcePoint,
  clearPendingFrameDecode,
  updateTouchpadStatus,
  debugSnapshot,
  setScrollSpeed,
  setPointerSensitivity,
  setAutoFollowCursor,
  setCursorLensEnabled,
  setCursorLensHold,
  setCursorLensZoom,
  setCursorLensSize,
  markCursorLensMoving,
  isCursorLensCurrentlyAllowed,
  monitorCalibrationSignature,
  activeMonitorCalibration,
  applyMonitorCalibrationToNormalized,
  buildCalibrationFromSamples,
  setCalibrationMode,
  captureCalibrationPoint,
  resetMonitorCalibration,
  updateCalibrationUi,
  setHaloEnabled,
  setHapticsEnabled,
  runShortcut,
  toggleNativeKeyboard,
  sendNativeKeyboardText,
  touchFeedback,
  normalizeAcceptanceGate,
  formatAcceptanceGate,
  acceptanceProofPayload,
  markAcceptanceProof,
  setAcceptanceProofStatus,
  getAcceptanceChecklistItems,
  acceptanceChecklistState,
  updateAcceptanceChecklistUi
};



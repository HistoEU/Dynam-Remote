"use strict";

const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { spawn, spawnSync } = require("node:child_process");
const QRCode = require("qrcode");

const { createCaptureAdapter, createCaptureDiagnostics } = require("./capture-adapter");
const { createInputAdapter } = require("./input-adapter");
const { getNetworkRisk, getNetworkValidation, getReachableAddresses, isAllowedRemoteAddress } = require("./network");
const { makeError, makeMessage, nextActionForCode, validateClientMessage } = require("./protocol");
const { createSessionStore, randomToken } = require("./session-store");
const { createSettingsStore } = require("./settings-store");
const { nextFrameDelayMs } = require("./frame-timing");
const { createRtcRoom } = require("./rtc-room");
const {
  isRtcCaptureFeatureEnabled,
  shouldAllowRtcCaptureOpen,
  shouldAutoLaunchRtcCapture
} = require("./rtc-autostart-policy");
const { acceptKey, decodeFrames, sendBinary: sendWsBinary, sendJson: sendWsJson } = require("./ws");

const PORT = Number(process.env.PORT || 4317);
const HOST = process.env.HOST || "::";
const PUBLIC_DIR = path.join(__dirname, "..", "public");
const DATA_DIR = path.join(__dirname, "..", "data");
const LATEST_PHONE_PROOF_PATH = path.join(DATA_DIR, "latest-phone-proof.json");
const CAPTURE_BROWSER_PROFILE_DIR = path.join(DATA_DIR, "capture-browser-profile");
const MAX_JSON_BODY_BYTES = 64 * 1024;
const NOISY_STATE_BROADCAST_MS = 250;
const RTC_CAPTURE_STALE_MS = 12000;
const CAPTURE_LAUNCH_INFLIGHT_MS = 8000;
const CAPTURE_SOURCE_CORRECTION_COOLDOWN_MS = 2600;
const hostKey = process.env.HOST_KEY || randomToken(18);
const publicUrl = process.env.PUBLIC_URL || "";
const captureMode = process.env.CAPTURE_MODE || "fake";
const rtcCaptureFeatureEnabled = isRtcCaptureFeatureEnabled();
const SECURITY_HEADERS = {
  "Content-Security-Policy": [
    "default-src 'self'",
    "base-uri 'self'",
    "script-src 'self'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob:",
    "connect-src 'self' ws: wss:",
    "worker-src 'self'",
    "manifest-src 'self'",
    "object-src 'none'",
    "frame-ancestors 'none'",
    "form-action 'self'"
  ].join("; "),
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY"
};

function derivePhoneAppVersion() {
  try {
    const serviceWorkerSource = fs.readFileSync(path.join(PUBLIC_DIR, "sw.js"), "utf8");
    const match = serviceWorkerSource.match(/remote-controller-shell-v(?<version>[0-9]+)/);
    return match?.groups?.version || "dev";
  } catch {
    return "dev";
  }
}

const phoneAppVersion = derivePhoneAppVersion();
const STREAM_BINARY_MAGIC = Buffer.from("RDCF", "ascii");
const settingsStore = createSettingsStore();
const persistedSettings = settingsStore.load();
const settings = {
  ...persistedSettings,
  qualityDefault: ["fast", "balanced", "sharp", "battery"].includes(process.env.QUALITY_DEFAULT)
    ? process.env.QUALITY_DEFAULT
    : persistedSettings.qualityDefault,
  inputSensitivityDefault: Number(process.env.INPUT_SENSITIVITY_DEFAULT || persistedSettings.inputSensitivityDefault),
  captureMode,
  publicUrl
};

function saveSettings() {
  const saved = settingsStore.save(settings);
  Object.assign(settings, saved, { captureMode, publicUrl });
  return settings;
}

function publicSettings() {
  return {
    qualityDefault: settings.qualityDefault,
    inputSensitivityDefault: settings.inputSensitivityDefault,
    trustedDevicesEnabled: settings.trustedDevicesEnabled,
    autoStart: settings.autoStart,
    captureMode: settings.captureMode,
    publicUrl: settings.publicUrl,
    trustedDeviceCount: settings.trustedDeviceKeys.length
  };
}

function machineAppMode() {
  return capture.mode === "screen" ? "milestone-2-screen-capture" : "milestone-1-fake-stream";
}

function displayAppMode() {
  return capture.mode === "screen" ? "Screen capture" : "Safe fallback stream";
}

const logs = [];
const clients = new Map();
let latestPhoneProofLog = loadLatestPhoneProofLog();
let capture = null;
let selectedMonitorId = "display-1";
let quality = settings.qualityDefault;
let inputMode = "touchpad";
let frameId = 0;
let captureInFlight = false;
let immediateFrameTimer = null;
let input = null;
let rtcRoom = null;
let inputActivityUntil = 0;
let lastInputAt = 0;
let stateBroadcastTimer = null;
let lastStateBroadcastAt = 0;
let lastAutoCaptureLaunchAt = 0;
const captureSourceOverrides = new Map();
const captureSourceCorrectionCounts = new Map();
const captureSourceCorrectionAt = new Map();
const captureLaunchState = {
  status: "idle",
  nonce: "",
  lastLaunchAt: 0,
  lastReason: "",
  mode: "",
  browserPath: "",
  captureUrl: "",
  autoStart: false,
  autoSelect: false,
  monitorId: "",
  captureSourceName: "",
  autoDetect: {
    status: "idle",
    reason: "",
    checkedAt: 0
  }
};
const diagnostics = {
  framesSent: 0,
  lastFrameBytes: 0,
  lastCaptureMs: 0,
  lastFrameAt: 0,
  droppedFrameTicks: 0,
  hiddenFrameTicks: 0,
  stateBroadcasts: 0,
  deferredStateBroadcasts: 0
};

function visibleClientCount() {
  return [...clients.values()].filter((client) => client.visible !== false).length;
}

function hiddenClientCount() {
  return [...clients.values()].filter((client) => client.visible === false).length;
}

function baseFrameIntervalMs() {
  return capture.intervalMsForQuality(quality);
}

function effectiveFrameIntervalMs() {
  if (clients.size > 0 && visibleClientCount() === 0) return quality === "battery" ? 900 : 180;
  if (Date.now() < inputActivityUntil) return Math.min(baseFrameIntervalMs(), quality === "battery" ? 260 : 120);
  if (visibleClientCount() > 0 && quality !== "battery") return Math.min(baseFrameIntervalMs(), 120);
  return baseFrameIntervalMs();
}

function adaptiveStreamMode() {
  if (clients.size > 0 && visibleClientCount() === 0) return "hidden";
  if (Date.now() < inputActivityUntil) return "responsive";
  if (visibleClientCount() > 0 && quality !== "battery" && baseFrameIntervalMs() > 180) return "steady";
  return "preset";
}

function markInputActivity(commandType) {
  lastInputAt = Date.now();
  inputActivityUntil = lastInputAt + (commandType === "pointer.down" || commandType === "pointer.move" ? 1800 : 900);
}

function isNoisyLogEvent(event) {
  return event === "input.real" || event === "input.dryRun";
}

function broadcastStateNow() {
  if (stateBroadcastTimer) {
    clearTimeout(stateBroadcastTimer);
    stateBroadcastTimer = null;
  }
  lastStateBroadcastAt = Date.now();
  diagnostics.stateBroadcasts += 1;
  broadcast(makeMessage("state", getPublicState()));
}

function scheduleStateBroadcast({ immediate = false } = {}) {
  if (immediate) {
    broadcastStateNow();
    return;
  }
  const elapsed = lastStateBroadcastAt ? Date.now() - lastStateBroadcastAt : NOISY_STATE_BROADCAST_MS;
  const delay = Math.max(0, NOISY_STATE_BROADCAST_MS - elapsed);
  if (delay === 0) {
    broadcastStateNow();
    return;
  }
  diagnostics.deferredStateBroadcasts += 1;
  if (stateBroadcastTimer) return;
  stateBroadcastTimer = setTimeout(() => {
    stateBroadcastTimer = null;
    broadcastStateNow();
  }, delay);
}

async function captureAndBroadcastFrame(reason = "scheduled") {
  const visibleClients = visibleClientCount();
  if (clients.size <= 0) {
    return false;
  }
  if (visibleClients <= 0) diagnostics.hiddenFrameTicks += 1;
  if (captureInFlight) {
    diagnostics.droppedFrameTicks += 1;
    return false;
  }
  captureInFlight = true;
  frameId += 1;
  const startedAt = Date.now();
  try {
    const frame = await capture.createFrame({ frameId, monitorId: selectedMonitorId, quality, inputMode });
    diagnostics.lastCaptureMs = Date.now() - startedAt;
    diagnostics.lastFrameAt = Date.now();
    diagnostics.lastFrameBytes = streamFrameWireBytes(frame);
    diagnostics.framesSent += 1;
    broadcastStreamFrame(frame);
    if (reason !== "scheduled") log("stream.frame.prime", { reason, frameId });
    return true;
  } catch (error) {
    log("stream.frame.failed", { reason, error: error.message });
    return false;
  } finally {
    captureInFlight = false;
  }
}

function scheduleImmediateFrame(reason = "phone-visible") {
  if (immediateFrameTimer) return;
  immediateFrameTimer = setTimeout(() => {
    immediateFrameTimer = null;
    captureAndBroadcastFrame(reason).catch((error) => {
      log("stream.frame.failed", { reason, error: error.message });
    });
  }, 0);
}

function log(event, detail = {}) {
  const entry = {
    id: crypto.randomUUID(),
    at: Date.now(),
    event,
    detail
  };
  logs.unshift(entry);
  logs.splice(160);
  scheduleStateBroadcast({ immediate: !isNoisyLogEvent(event) });
  return entry;
}

function loadLatestPhoneProofLog() {
  try {
    const parsed = JSON.parse(fs.readFileSync(LATEST_PHONE_PROOF_PATH, "utf8"));
    if (!parsed || parsed.event !== "acceptance.phoneMark" || !parsed.detail?.proof) return null;
    return parsed;
  } catch {
    return null;
  }
}

function saveLatestPhoneProofLog(entry) {
  if (!entry || entry.event !== "acceptance.phoneMark") return false;
  latestPhoneProofLog = entry;
  try {
    fs.mkdirSync(DATA_DIR, { recursive: true });
    fs.writeFileSync(LATEST_PHONE_PROOF_PATH, `${JSON.stringify(entry, null, 2)}\n`);
    return true;
  } catch (error) {
    log("acceptance.phoneProofPersistFailed", { error: error.message });
    return false;
  }
}

function exportedLogs() {
  if (!latestPhoneProofLog) return logs.slice();
  if (logs.some((entry) => entry.id === latestPhoneProofLog.id)) return logs.slice();
  return [latestPhoneProofLog, ...logs];
}

const sessions = createSessionStore({
  log,
  trustedDeviceKeys: settings.trustedDeviceKeys,
  trustedDevices: settings.trustedDevices,
  onTrustedDevicesChanged(devices) {
    settings.trustedDevices = devices;
    settings.trustedDeviceKeys = devices.map((item) => item.key);
    saveSettings();
  }
});
input = createInputAdapter({ enabled: process.env.REAL_INPUT === "1", log });
capture = createCaptureAdapter({
  mode: captureMode,
  log,
  cursorProvider: () => input.getCursorPosition()
});
selectedMonitorId = capture.getMonitors()[0]?.id || "display-1";
rtcRoom = createRtcRoom({
  send: (peer, message) => sendWsJson(peer.socket, message),
  log
});
let lastMonitorSignature = "";

function monitorSignature(monitors = capture.getMonitors()) {
  return monitors
    .map((monitor) => [
      monitor.id,
      monitor.sourceId || "",
      monitor.bounds?.left,
      monitor.bounds?.top,
      monitor.bounds?.width,
      monitor.bounds?.height,
      monitor.status || ""
    ].join(":"))
    .join("|");
}

async function refreshMonitorList(reason = "refresh") {
  if (typeof capture.refreshMonitors !== "function") return false;
  const before = monitorSignature();
  await capture.refreshMonitors();
  const monitors = capture.getMonitors();
  const after = monitorSignature(monitors);
  if (after && after !== before && after !== lastMonitorSignature) {
    lastMonitorSignature = after;
    if (!monitors.some((monitor) => monitor.id === selectedMonitorId)) {
      selectedMonitorId = monitors[0]?.id || "display-1";
    }
    log("capture.screen.monitorsRefreshed", { reason, monitors: monitors.length, selectedMonitorId });
    scheduleStateBroadcast({ immediate: true });
    return true;
  }
  lastMonitorSignature = after || lastMonitorSignature;
  return false;
}

function publicCaptureDiagnosticLaunchState() {
  return {
    status: captureLaunchState.status,
    lastLaunchAt: captureLaunchState.lastLaunchAt,
    autoStart: captureLaunchState.autoStart,
    autoSelect: captureLaunchState.autoSelect,
    monitorId: captureLaunchState.monitorId,
    captureSourceName: captureLaunchState.captureSourceName,
    autoDetect: captureLaunchState.autoDetect
  };
}

function currentCaptureDiagnostics(monitors, rtcStatus) {
  return createCaptureDiagnostics({
    monitors,
    selectedMonitorId,
    rtcState: rtcStatus,
    captureLaunch: publicCaptureDiagnosticLaunchState(),
    correctionCount: captureSourceCorrectionCounts.get(selectedMonitorId) || 0,
    now: Date.now(),
    staleAfterMs: RTC_CAPTURE_STALE_MS
  });
}

function getPublicState() {
  const monitors = capture.getMonitors();
  const addresses = getReachableAddresses(PORT, { publicUrl });
  const rtcStatus = rtcCaptureFeatureEnabled && rtcRoom
    ? rtcRoom.getState()
    : { available: false, state: "disabled", hostConnected: false, phoneConnected: false };
  return {
    app: {
      name: "Remote Controller",
      mode: machineAppMode(),
      displayMode: displayAppMode(),
      phoneAppVersion,
      uptimeSeconds: Math.round(process.uptime())
    },
    selectedMonitorId,
    monitors,
    streamStats: {
      quality,
      fpsTarget: clients.size > 0 && visibleClientCount() > 0 ? Math.round(1000 / effectiveFrameIntervalMs()) : 0,
      presetFpsTarget: Math.round(1000 / baseFrameIntervalMs()),
      adaptiveMode: adaptiveStreamMode(),
      frameId,
      transport: capture.mode === "screen" ? "native-websocket-binary-jpeg" : "native-websocket-json",
      source: capture.mode,
      framesSent: diagnostics.framesSent,
      lastFrameBytes: diagnostics.lastFrameBytes,
      lastCaptureMs: diagnostics.lastCaptureMs,
      droppedFrameTicks: diagnostics.droppedFrameTicks,
      hiddenFrameTicks: diagnostics.hiddenFrameTicks,
      stateBroadcasts: diagnostics.stateBroadcasts,
      deferredStateBroadcasts: diagnostics.deferredStateBroadcasts,
      stateBroadcastThrottleMs: NOISY_STATE_BROADCAST_MS,
      connectedClients: clients.size,
      visibleClients: visibleClientCount(),
      hiddenClients: hiddenClientCount()
    },
    rtcStatus,
    captureDiagnostics: currentCaptureDiagnostics(monitors, rtcStatus),
    inputMode,
    settings: publicSettings(),
    inputSafety: {
      mode: input.mode,
      enabled: input.isEnabled()
    },
    securityStatus: {
      pairing: sessions.getPairingState(),
      approvedSessions: sessions.listSessions().filter((item) => item.approved).length,
      pendingSessions: sessions.listSessions().filter((item) => !item.approved).length,
      networkRisk: getNetworkRisk(addresses),
      networkValidation: getNetworkValidation(addresses)
    },
    sessions: sessions.listSessions(),
    addresses,
    logs: exportedLogs().slice(0, 40),
    latestPhoneProof: latestPhoneProofLog
  };
}

function getHostState() {
  return {
    ...getPublicState(),
    trustedDevices: sessions.listTrustedDevices(),
    hostKey,
    hostUrl: `http://127.0.0.1:${PORT}/host?key=${encodeURIComponent(hostKey)}`,
    captureUrl: capturePageUrl(),
    captureLaunch: publicCaptureLaunchState()
  };
}

function getHealthState() {
  const addresses = getReachableAddresses(PORT, { publicUrl });
  return {
    app: {
      name: "Remote Controller",
      mode: machineAppMode(),
      displayMode: displayAppMode(),
      uptimeSeconds: Math.round(process.uptime())
    },
    networkRisk: getNetworkRisk(addresses),
    connectionSetup: getNetworkValidation(addresses),
    pairing: {
      available: true,
      rateLimit: sessions.getPairingState().rateLimit
    }
  };
}

function contentType(filePath) {
  if (filePath.endsWith(".html")) return "text/html; charset=utf-8";
  if (filePath.endsWith(".css")) return "text/css; charset=utf-8";
  if (filePath.endsWith(".js")) return "text/javascript; charset=utf-8";
  if (filePath.endsWith(".json")) return "application/json; charset=utf-8";
  if (filePath.endsWith(".svg")) return "image/svg+xml";
  return "application/octet-stream";
}

function send(res, status, body, headers = {}) {
  const payload = typeof body === "string" || Buffer.isBuffer(body) ? body : JSON.stringify(body, null, 2);
  res.writeHead(status, {
    ...SECURITY_HEADERS,
    "Content-Type": typeof body === "object" && !Buffer.isBuffer(body) ? "application/json; charset=utf-8" : "text/plain; charset=utf-8",
    "Cache-Control": "no-store",
    ...headers
  });
  res.end(payload);
}

function sendJson(res, status, body) {
  res.writeHead(status, {
    ...SECURITY_HEADERS,
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store"
  });
  res.end(JSON.stringify(body, null, 2));
}

function apiError(code, message, detail = null, recoverable = true, extra = {}) {
  return {
    ok: false,
    error: code,
    code,
    message,
    friendly: message,
    detail,
    recoverable,
    nextAction: nextActionForCode(code),
    ...extra
  };
}

function sendApiException(res, fallbackStatus, fallbackCode, error) {
  if (error.code === "PAYLOAD_TOO_LARGE") {
    return sendJson(res, 413, apiError("PAYLOAD_TOO_LARGE", error.message, { maxBytes: MAX_JSON_BODY_BYTES }));
  }
  return sendJson(res, fallbackStatus, apiError(fallbackCode, error.message));
}

function uniqueStrings(items = []) {
  return [...new Set(items.filter((item) => typeof item === "string" && item.trim()).map((item) => item.trim()))];
}

function captureSourceCandidatesForMonitor(monitorId = selectedMonitorId) {
  if (process.env.CAPTURE_AUTO_SOURCE) return [process.env.CAPTURE_AUTO_SOURCE];
  const monitors = capture?.getMonitors?.() || [];
  const monitor = monitors.find((item) => item.id === monitorId);
  const candidates = [];
  const displayMatch = String(monitor?.sourceId || "").match(/DISPLAY(\d+)/i);
  if (displayMatch) candidates.push(`Screen ${displayMatch[1]}`);
  if (monitors.length > 1) {
    const index = Math.max(0, monitors.findIndex((monitor) => monitor.id === monitorId));
    candidates.push(`Screen ${index + 1}`);
    for (let i = 1; i <= monitors.length; i += 1) candidates.push(`Screen ${i}`);
  }
  candidates.push("Entire screen");
  return uniqueStrings(candidates);
}

function captureSourceNameForMonitor(monitorId = selectedMonitorId) {
  if (process.env.CAPTURE_AUTO_SOURCE) return process.env.CAPTURE_AUTO_SOURCE;
  const override = captureSourceOverrides.get(monitorId);
  if (override) return override;
  return captureSourceCandidatesForMonitor(monitorId)[0] || "Entire screen";
}

function noteCaptureAutoDetect(status, reason = "") {
  captureLaunchState.autoDetect = {
    status,
    reason,
    checkedAt: Date.now()
  };
}

function capturePageUrl({ autoStart = false, monitorId = selectedMonitorId } = {}) {
  const url = new URL(`http://127.0.0.1:${PORT}/capture`);
  url.searchParams.set("key", hostKey);
  if (autoStart) url.searchParams.set("autostart", "1");
  if (monitorId) {
    url.searchParams.set("monitor", monitorId);
    url.searchParams.set("source", captureSourceNameForMonitor(monitorId));
  }
  return url.href;
}

function browserCandidates() {
  if (process.env.CAPTURE_BROWSER) return [process.env.CAPTURE_BROWSER];
  if (process.platform !== "win32") return [];
  const pathCandidates = [];
  for (const folder of String(process.env.PATH || "").split(path.delimiter)) {
    if (!folder) continue;
    pathCandidates.push(path.join(folder, "chrome.exe"));
    pathCandidates.push(path.join(folder, "msedge.exe"));
  }
  return [
    process.env.CHROME_PATH,
    process.env.MSEDGE_PATH,
    path.join(process.env.LOCALAPPDATA || "", "Google", "Chrome", "Application", "chrome.exe"),
    path.join(process.env.PROGRAMFILES || "", "Google", "Chrome", "Application", "chrome.exe"),
    path.join(process.env.ProgramW6432 || "", "Google", "Chrome", "Application", "chrome.exe"),
    path.join(process.env["PROGRAMFILES(X86)"] || "", "Google", "Chrome", "Application", "chrome.exe"),
    path.join(process.env.LOCALAPPDATA || "", "Microsoft", "Edge", "Application", "msedge.exe"),
    path.join(process.env.PROGRAMFILES || "", "Microsoft", "Edge", "Application", "msedge.exe"),
    path.join(process.env.ProgramW6432 || "", "Microsoft", "Edge", "Application", "msedge.exe"),
    path.join(process.env["PROGRAMFILES(X86)"] || "", "Microsoft", "Edge", "Application", "msedge.exe"),
    ...pathCandidates
  ].filter(Boolean);
}

function findCaptureBrowser() {
  for (const candidate of browserCandidates()) {
    try {
      if (fs.existsSync(candidate)) return candidate;
    } catch {}
  }
  return "";
}

function stopCaptureBrowserProcesses(reason = "capture-relaunch") {
  if (process.platform !== "win32") return { stopped: 0, reason, supported: false };
  const escapedProfile = CAPTURE_BROWSER_PROFILE_DIR.replace(/'/g, "''");
  const script = [
    "$ErrorActionPreference='SilentlyContinue'",
    `$profile='${escapedProfile}'`,
    "$matches = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($profile) }",
    "$count = 0",
    "foreach ($item in $matches) { Stop-Process -Id $item.ProcessId -Force -ErrorAction SilentlyContinue; $count += 1 }",
    "$count"
  ].join("; ");
  const result = spawnSync("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script], {
    encoding: "utf8",
    windowsHide: true,
    timeout: 5000
  });
  const stopped = Number(String(result.stdout || "").trim().split(/\s+/).pop() || 0);
  log("host.capture.browserStopped", { reason, stopped, error: result.error?.message || "" });
  return { stopped, reason, supported: true };
}

function hideCaptureBrowserWindow(reason = "capture-sharing") {
  if (process.platform !== "win32") return { ok: false, hidden: 0, reason, supported: false };
  const escapedProfile = CAPTURE_BROWSER_PROFILE_DIR.replace(/'/g, "''");
  const script = [
    "$ErrorActionPreference='SilentlyContinue'",
    `$profile='${escapedProfile}'`,
    "$source='using System; using System.Runtime.InteropServices; public class WinApi { [DllImport(\"user32.dll\")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow); [DllImport(\"user32.dll\")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags); }'",
    "Add-Type $source -ErrorAction SilentlyContinue",
    "$matches = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($profile) }",
    "$count = 0",
    "foreach ($item in $matches) { $p = Get-Process -Id $item.ProcessId -ErrorAction SilentlyContinue; if ($p -and $p.MainWindowHandle -ne 0) { [WinApi]::SetWindowPos($p.MainWindowHandle, [IntPtr]::Zero, -32000, -32000, 480, 360, 0x0040) | Out-Null; [WinApi]::ShowWindow($p.MainWindowHandle, 6) | Out-Null; $count += 1 } }",
    "$count"
  ].join("; ");
  const result = spawnSync("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script], {
    encoding: "utf8",
    windowsHide: true,
    timeout: 5000
  });
  const hidden = Number(String(result.stdout || "").trim().split(/\s+/).pop() || 0);
  log("host.capture.windowHidden", { reason, hidden, error: result.error?.message || "" });
  return { ok: true, hidden, reason, supported: true };
}

function scheduleCaptureWindowHide(reason = "capture-launch") {
  if (process.platform !== "win32") return;
  for (const delayMs of [250, 900, 1800, 3200]) {
    setTimeout(() => {
      try {
        hideCaptureBrowserWindow(`${reason}-${delayMs}ms`);
      } catch {}
    }, delayMs);
  }
}

function rtcHostMatchesMonitor(rtcState = rtcRoom?.getState(), monitorId = selectedMonitorId) {
  const monitors = capture?.getMonitors?.() || [];
  if (monitors.length <= 1) return true;
  const requestedMonitor = rtcState?.host?.capture?.requestedMonitor;
  return Boolean(requestedMonitor && requestedMonitor === monitorId);
}

function isFreshRtcHost(rtcState = rtcRoom?.getState(), monitorId = selectedMonitorId) {
  if (!rtcState?.hostConnected || !rtcState.host?.lastSeenAt) return false;
  if (!rtcHostMatchesMonitor(rtcState, monitorId)) return false;
  return Date.now() - Number(rtcState.host.lastSeenAt) <= RTC_CAPTURE_STALE_MS;
}

function clearStaleRtcHost(rtcState = rtcRoom?.getState(), reason = "stale-capture") {
  if (!rtcState?.hostConnected || isFreshRtcHost(rtcState)) return false;
  rtcRoom.disconnectPeer(rtcState.host.id, reason);
  log("rtc.host.staleCleared", {
    reason,
    peerId: rtcState.host.id,
    ageMs: Date.now() - Number(rtcState.host.lastSeenAt || 0),
    requestedMonitor: rtcState.host.capture?.requestedMonitor || "",
    selectedMonitorId
  });
  return true;
}

function publicCaptureLaunchState() {
  return {
    status: captureLaunchState.status,
    nonce: captureLaunchState.nonce,
    lastLaunchAt: captureLaunchState.lastLaunchAt,
    lastReason: captureLaunchState.lastReason,
    mode: captureLaunchState.mode,
    browserPath: captureLaunchState.browserPath,
    captureUrl: captureLaunchState.captureUrl,
    autoStart: captureLaunchState.autoStart,
    autoSelect: captureLaunchState.autoSelect,
    monitorId: captureLaunchState.monitorId,
    captureSourceName: captureLaunchState.captureSourceName,
    autoDetect: captureLaunchState.autoDetect,
    inFlight: captureLaunchState.status === "starting" && Date.now() - captureLaunchState.lastLaunchAt <= CAPTURE_LAUNCH_INFLIGHT_MS
  };
}

function markCaptureLaunch(result = {}) {
  captureLaunchState.status = "starting";
  captureLaunchState.nonce = randomToken(8);
  captureLaunchState.lastLaunchAt = Date.now();
  captureLaunchState.lastReason = result.reason || "";
  captureLaunchState.mode = result.mode || "";
  captureLaunchState.browserPath = result.browserPath || "";
  captureLaunchState.captureUrl = result.captureUrl || "";
  captureLaunchState.autoStart = Boolean(result.autoStart);
  captureLaunchState.autoSelect = Boolean(result.autoSelect);
  captureLaunchState.monitorId = result.monitorId || selectedMonitorId;
  captureLaunchState.captureSourceName = result.captureSourceName || captureSourceNameForMonitor(captureLaunchState.monitorId);
}

function markCaptureAlive(peer = null) {
  captureLaunchState.status = "alive";
  captureLaunchState.lastLaunchAt = Date.now();
  const captureMeta = peer?.metadata?.capture || peer?.capture || {};
  if (peer?.metadata?.captureUrl) captureLaunchState.captureUrl = peer.metadata.captureUrl;
  if (captureMeta.requestedMonitor) captureLaunchState.monitorId = captureMeta.requestedMonitor;
  if (captureMeta.requestedSource) captureLaunchState.captureSourceName = captureMeta.requestedSource;
}

function markCaptureIdle(reason = "idle") {
  captureLaunchState.status = "idle";
  captureLaunchState.lastReason = reason;
}

function captureLaunchInFlight() {
  return captureLaunchState.status === "starting" && Date.now() - captureLaunchState.lastLaunchAt <= CAPTURE_LAUNCH_INFLIGHT_MS;
}

function requestCaptureStart(reason = "server-request") {
  const sent = Boolean(rtcRoom?.sendToRole("host", {
    type: "rtc.startCapture",
    payload: {
      reason,
      autoStart: true,
      autoSelect: true
    }
  }));
  if (sent) log("host.capture.startRequested", { reason });
  return sent;
}

function captureSizeMismatch(captureMeta = {}, monitor = null) {
  if (!monitor?.bounds || !captureMeta?.sharing) return null;
  const actualW = Number(captureMeta.width || 0);
  const actualH = Number(captureMeta.height || 0);
  const expectedW = Number(monitor.bounds.width || 0);
  const expectedH = Number(monitor.bounds.height || 0);
  if (!actualW || !actualH || !expectedW || !expectedH) return null;
  const tolerance = 10;
  const direct = Math.abs(actualW - expectedW) <= tolerance && Math.abs(actualH - expectedH) <= tolerance;
  const rotated = Math.abs(actualW - expectedH) <= tolerance && Math.abs(actualH - expectedW) <= tolerance;
  return !(direct || rotated);
}

function cycleCaptureSourceForMonitor(monitorId = selectedMonitorId, reason = "auto-detect") {
  if (process.env.CAPTURE_AUTO_SOURCE) return null;
  const candidates = captureSourceCandidatesForMonitor(monitorId);
  if (candidates.length <= 1) return null;
  const now = Date.now();
  const lastAt = Number(captureSourceCorrectionAt.get(monitorId) || 0);
  if (now - lastAt < CAPTURE_SOURCE_CORRECTION_COOLDOWN_MS) return null;
  const current = captureSourceNameForMonitor(monitorId);
  const currentIndex = Math.max(0, candidates.indexOf(current));
  const count = Number(captureSourceCorrectionCounts.get(monitorId) || 0);
  if (count >= candidates.length * 2) {
    noteCaptureAutoDetect("needs-manual-check", `Tried ${candidates.length} capture sources for ${monitorId}.`);
    return null;
  }
  const next = candidates[(currentIndex + 1) % candidates.length];
  captureSourceOverrides.set(monitorId, next);
  captureSourceCorrectionCounts.set(monitorId, count + 1);
  captureSourceCorrectionAt.set(monitorId, now);
  noteCaptureAutoDetect("correcting", `${reason}: trying ${next}`);
  log("host.capture.sourceAutoCorrect", {
    reason,
    monitorId,
    previousSource: current,
    nextSource: next,
    candidates
  });
  return next;
}

function maybeCorrectCaptureSource(reason = "capture-check", rtcState = rtcRoom?.getState()) {
  if (!settings.autoStart || process.env.CAPTURE_AUTO_SOURCE) return false;
  const monitors = capture?.getMonitors?.() || [];
  if (monitors.length <= 1) {
    noteCaptureAutoDetect("single-monitor", "Only one monitor is visible to the host.");
    return false;
  }
  const host = rtcState?.host;
  const meta = host?.capture;
  if (!host || !meta?.sharing) return false;
  const monitor = monitors.find((item) => item.id === selectedMonitorId);
  if (!monitor) return false;
  const requestedMonitor = meta.requestedMonitor || "";
  const wrongRequestedMonitor = requestedMonitor && requestedMonitor !== selectedMonitorId;
  const wrongSize = captureSizeMismatch(meta, monitor);
  if (!wrongRequestedMonitor) {
    captureSourceCorrectionCounts.set(selectedMonitorId, 0);
    noteCaptureAutoDetect(wrongSize === true ? "size-mismatch" : "matched", wrongSize === true
      ? `Capture size ${meta.width}x${meta.height} does not match ${selectedMonitorId}; use the capture source controls if the phone shows the wrong display.`
      : `Capture matches ${selectedMonitorId}.`);
    return false;
  }
  const nextSource = cycleCaptureSourceForMonitor(
    selectedMonitorId,
    wrongRequestedMonitor ? `requested ${requestedMonitor || "unknown"} while selected ${selectedMonitorId}` : `size ${meta.width}x${meta.height} did not match selected monitor`
  );
  if (!nextSource) return false;
  setTimeout(() => {
    try {
      ensureCaptureBrowser({
        autoStart: true,
        autoSelect: true,
        force: true,
        monitorId: selectedMonitorId,
        reason: `auto-detect-${selectedMonitorId}-${nextSource.replace(/\s+/g, "-").toLowerCase()}`
      });
    } catch (error) {
      log("host.capture.sourceAutoCorrectFailed", { monitorId: selectedMonitorId, error: error.message });
    }
  }, 80);
  return true;
}

function openExternalUrl(targetUrl) {
  const platform = process.platform;
  let command = "";
  let args = [];
  if (platform === "win32") {
    command = "rundll32.exe";
    args = ["url.dll,FileProtocolHandler", targetUrl];
  } else if (platform === "darwin") {
    command = "open";
    args = [targetUrl];
  } else {
    command = "xdg-open";
    args = [targetUrl];
  }
  const child = spawn(command, args, { detached: true, stdio: "ignore" });
  child.unref();
  return { command, args, mode: "default-browser" };
}

function spawnCaptureBrowser({ autoStart = false, autoSelect = true, reason = "manual", monitorId = selectedMonitorId } = {}) {
  const targetUrl = capturePageUrl({ autoStart, monitorId });
  const captureSourceName = captureSourceNameForMonitor(monitorId);
  const browserPath = findCaptureBrowser();
  if (!browserPath) {
    const fallback = openExternalUrl(targetUrl);
    return { ...fallback, ok: true, captureUrl: targetUrl, autoStart, autoSelect: false, reason, monitorId, captureSourceName };
  }
  fs.mkdirSync(CAPTURE_BROWSER_PROFILE_DIR, { recursive: true });
  const args = [
    `--user-data-dir=${CAPTURE_BROWSER_PROFILE_DIR}`,
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-session-crashed-bubble",
    "--disable-infobars",
    "--use-fake-ui-for-media-stream",
    "--start-minimized",
    "--window-position=-32000,-32000",
    "--window-size=480,360"
  ];
  if (autoSelect) {
    args.push(`--auto-select-desktop-capture-source=${captureSourceName}`);
  }
  args.push(`--app=${targetUrl}`);
  const child = spawn(browserPath, args, { detached: true, stdio: "ignore" });
  child.unref();
  scheduleCaptureWindowHide(reason || "capture-launch");
  return {
    ok: true,
    captureUrl: targetUrl,
    browserPath,
    args,
    mode: "dedicated-chromium",
    autoStart,
    autoSelect,
    monitorId,
    captureSourceName,
    reason
  };
}

function ensureCaptureBrowser({ autoStart = true, autoSelect = true, reason = "manual", force = false, monitorId = selectedMonitorId } = {}) {
  const rtcState = rtcRoom ? rtcRoom.getState() : null;
  if (force) {
    if (rtcState?.hostConnected) {
      rtcRoom.disconnectPeer(rtcState.host.id, `${reason}-forced-relaunch`);
    }
    markCaptureIdle(`${reason}-forced-relaunch`);
    stopCaptureBrowserProcesses(`${reason}-forced-relaunch`);
  } else if (isFreshRtcHost(rtcState, monitorId)) {
    const sharing = Boolean(rtcState.host?.capture?.sharing);
    const startRequested = sharing ? false : requestCaptureStart(reason);
    if (sharing) scheduleCaptureWindowHide(`${reason}-existing-sharing`);
    return {
      ok: true,
      alreadyOpen: true,
      sharing,
      startRequested,
      captureUrl: capturePageUrl({ autoStart, monitorId }),
      mode: "existing-rtc-capture",
      autoStart,
      autoSelect,
      monitorId,
      captureSourceName: captureSourceNameForMonitor(monitorId),
      reason,
      captureLaunch: publicCaptureLaunchState()
    };
  } else if (rtcState?.hostConnected) {
    clearStaleRtcHost(rtcState, `${reason}-stale-or-wrong-monitor-relaunch`);
    markCaptureIdle(`${reason}-stale-relaunch`);
    stopCaptureBrowserProcesses(`${reason}-stale-relaunch`);
  }
  if (!force && captureLaunchInFlight()) {
    return {
      ok: true,
      launchInProgress: true,
      captureUrl: captureLaunchState.captureUrl || capturePageUrl({ autoStart, monitorId }),
      mode: captureLaunchState.mode || "starting",
      autoStart: captureLaunchState.autoStart,
      autoSelect: captureLaunchState.autoSelect,
      monitorId,
      captureSourceName: captureSourceNameForMonitor(monitorId),
      reason,
      captureLaunch: publicCaptureLaunchState()
    };
  }
  const result = spawnCaptureBrowser({ autoStart, autoSelect, reason, monitorId });
  markCaptureLaunch(result);
  return { ...result, launched: true, captureLaunch: publicCaptureLaunchState() };
}

function maybeAutoLaunchCapture(reason = "phone-connected") {
  if (!shouldAutoLaunchRtcCapture({ settings })) return false;
  const now = Date.now();
  if (now - lastAutoCaptureLaunchAt < 8000) return false;
  lastAutoCaptureLaunchAt = now;
  try {
    const result = ensureCaptureBrowser({ autoStart: true, autoSelect: true, reason });
    log("host.capture.autoOpened", {
      reason,
      mode: result.mode,
      alreadyOpen: Boolean(result.alreadyOpen),
      launchInProgress: Boolean(result.launchInProgress),
      launched: Boolean(result.launched),
      autoStart: result.autoStart,
      autoSelect: result.autoSelect,
      monitorId: result.monitorId || selectedMonitorId,
      captureSourceName: result.captureSourceName || captureSourceNameForMonitor(selectedMonitorId),
      browserPath: result.browserPath || ""
    });
    return true;
  } catch (error) {
    log("host.capture.autoOpenFailed", { reason, error: error.message });
    return false;
  }
}

function scheduleAutoLaunchCapture(reason = "phone-connected", delayMs = 150) {
  if (!shouldAutoLaunchRtcCapture({ settings })) return false;
  setTimeout(() => {
    try {
      maybeAutoLaunchCapture(reason);
    } catch (error) {
      log("host.capture.autoOpenFailed", { reason, error: error.message });
    }
  }, delayMs);
  return true;
}

function isAllowedRequest(req) {
  return isAllowedRemoteAddress(req.socket.remoteAddress, { allowPublic: Boolean(publicUrl) });
}

function rejectNetworkRequest(req, res) {
  log("network.blockedRemote", { remoteAddress: req.socket.remoteAddress });
  sendJson(res, 403, apiError(
    "NETWORK_NOT_ALLOWED",
    "Remote controller only accepts loopback, private LAN, or Tailscale clients unless public tunnel mode is explicitly configured.",
    { remoteAddress: req.socket.remoteAddress }
  ));
}

async function readJson(req, { maxBytes = MAX_JSON_BODY_BYTES } = {}) {
  const chunks = [];
  let totalBytes = 0;
  for await (const chunk of req) {
    totalBytes += chunk.length;
    if (totalBytes > maxBytes) {
      const error = new Error(`JSON request body is too large. Limit is ${maxBytes} bytes.`);
      error.code = "PAYLOAD_TOO_LARGE";
      throw error;
    }
    chunks.push(chunk);
  }
  if (!chunks.length) return {};
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

function serveStatic(req, res) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  let fileName = url.pathname === "/" ? "index.html" : url.pathname.slice(1);
  if (fileName === "host") fileName = "host.html";
  if (fileName === "capture") {
    if (!rtcCaptureFeatureEnabled) return send(res, 404, "Capture helper disabled");
    fileName = "capture.html";
  }
  if (!rtcCaptureFeatureEnabled && (fileName === "capture.html" || fileName === "capture.js")) {
    return send(res, 404, "Capture helper disabled");
  }
  const filePath = path.normalize(path.join(PUBLIC_DIR, fileName));
  if (!filePath.startsWith(PUBLIC_DIR)) return send(res, 403, "Forbidden");
  fs.readFile(filePath, (error, data) => {
    if (error) return send(res, 404, "Not found");
    res.writeHead(200, { ...SECURITY_HEADERS, "Content-Type": contentType(filePath), "Cache-Control": "no-store" });
    res.end(data);
  });
}

function requireHostKey(req, res) {
  const provided = req.headers["x-host-key"];
  if (provided !== hostKey) {
    sendJson(res, 403, apiError("BAD_HOST_KEY", "Host key is required for this action."));
    return false;
  }
  return true;
}

function handleApi(req, res) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  if (req.method === "GET" && url.pathname === "/api/health") {
    return sendJson(res, 200, {
      ok: true,
      protocol: 1,
      state: getHealthState()
    });
  }
  if (req.method === "GET" && url.pathname === "/api/host") {
    if (url.searchParams.get("key") !== hostKey && req.headers["x-host-key"] !== hostKey) {
      return sendJson(res, 403, apiError("BAD_HOST_KEY", "Host key is required for this action."));
    }
    return sendJson(res, 200, getHostState());
  }
  if (req.method === "POST" && url.pathname === "/api/open-capture") {
    if (!requireHostKey(req, res)) return;
    try {
      const autoStartRequested = url.searchParams.get("autostart") !== "0";
      if (!shouldAllowRtcCaptureOpen({ autoStartRequested, settings })) {
        const result = {
          ok: true,
          skipped: true,
          mode: "rtc-autostart-disabled",
          autoStart: false,
          autoSelect: false,
          reason: url.searchParams.get("reason") || "manual"
        };
        log("host.capture.openSkipped", result);
        return sendJson(res, 200, result);
      }
      const result = ensureCaptureBrowser({
        autoStart: autoStartRequested,
        autoSelect: url.searchParams.get("autoselect") !== "0",
        force: url.searchParams.get("force") === "1",
        monitorId: url.searchParams.get("monitor") || selectedMonitorId,
        reason: url.searchParams.get("reason") || "manual"
      });
      log("host.capture.opened", {
        captureUrl: result.captureUrl,
        mode: result.mode,
        alreadyOpen: Boolean(result.alreadyOpen),
        launchInProgress: Boolean(result.launchInProgress),
        launched: Boolean(result.launched),
        autoStart: result.autoStart,
        autoSelect: result.autoSelect,
        monitorId: result.monitorId || selectedMonitorId,
        captureSourceName: result.captureSourceName || captureSourceNameForMonitor(selectedMonitorId),
        browserPath: result.browserPath || ""
      });
      return sendJson(res, 200, result);
    } catch (error) {
      return sendJson(res, 500, apiError("OPEN_CAPTURE_FAILED", error.message));
    }
  }
  if (req.method === "POST" && url.pathname === "/api/hide-capture-window") {
    if (!requireHostKey(req, res)) return;
    try {
      const result = hideCaptureBrowserWindow(url.searchParams.get("reason") || "capture-sharing");
      return sendJson(res, 200, { ok: true, ...result });
    } catch (error) {
      return sendJson(res, 500, apiError("HIDE_CAPTURE_FAILED", error.message));
    }
  }
  if (req.method === "POST" && url.pathname === "/api/settings") {
    if (!requireHostKey(req, res)) return;
    readJson(req)
      .then((body) => {
        if (["fast", "balanced", "sharp", "battery"].includes(body.qualityDefault)) {
          settings.qualityDefault = body.qualityDefault;
          quality = body.qualityDefault;
        }
        if (Number.isFinite(Number(body.inputSensitivityDefault))) {
          settings.inputSensitivityDefault = Math.min(2.5, Math.max(0.35, Number(body.inputSensitivityDefault)));
        }
        if (typeof body.trustedDevicesEnabled === "boolean") {
          settings.trustedDevicesEnabled = body.trustedDevicesEnabled;
        }
        if (typeof body.autoStart === "boolean") {
          settings.autoStart = body.autoStart;
        }
        saveSettings();
        log("host.settings.updated", {
          qualityDefault: settings.qualityDefault,
          inputSensitivityDefault: settings.inputSensitivityDefault,
          trustedDevicesEnabled: settings.trustedDevicesEnabled
        });
        sendJson(res, 200, { ok: true, settings: publicSettings() });
      })
      .catch((error) => sendApiException(res, 400, "BAD_SETTINGS", error));
    return;
  }
  if (req.method === "GET" && url.pathname === "/api/logs") {
    if (url.searchParams.get("key") !== hostKey && req.headers["x-host-key"] !== hostKey) {
      return sendJson(res, 403, apiError("BAD_HOST_KEY", "Host key is required for this action."));
    }
    const exportBody = {
      exportedAt: new Date().toISOString(),
      state: getPublicState(),
      latestPhoneProof: latestPhoneProofLog,
      logs: exportedLogs()
    };
    res.writeHead(200, {
      ...SECURITY_HEADERS,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "Content-Disposition": `attachment; filename="remote-controller-logs-${Date.now()}.json"`
    });
    res.end(JSON.stringify(exportBody, null, 2));
    return;
  }
  if (req.method === "GET" && url.pathname === "/api/qr") {
    if (url.searchParams.get("key") !== hostKey && req.headers["x-host-key"] !== hostKey) {
      return sendJson(res, 403, apiError("BAD_HOST_KEY", "Host key is required for this action."));
    }
    const target = url.searchParams.get("url");
    if (!target || !/^https?:\/\//.test(target)) {
      return sendJson(res, 400, apiError("BAD_QR_URL", "QR URL must be an HTTP or HTTPS URL."));
    }
    QRCode.toString(target, { type: "svg", margin: 1, width: 168 })
      .then((svg) => {
        res.writeHead(200, { ...SECURITY_HEADERS, "Content-Type": "image/svg+xml", "Cache-Control": "no-store" });
        res.end(svg);
      })
      .catch((error) => sendJson(res, 500, apiError("QR_FAILED", error.message, null, true)));
    return;
  }
  if (req.method === "GET" && url.pathname === "/api/session") {
    const token = url.searchParams.get("token");
    const session = sessions.getSessionByToken(token);
    if (!session) return sendJson(res, 404, apiError("SESSION_NOT_FOUND", "Session was not found or has expired."));
    if (session.approved) scheduleAutoLaunchCapture("session-poll-approved", 50);
    return sendJson(res, 200, {
      id: session.id,
      approved: session.approved,
      connected: session.connected,
      permissions: session.permissions,
      trusted: session.trusted,
      allowedOrigin: session.allowedOrigin,
      expiresAt: session.expiresAt
    });
  }
  if (req.method === "POST" && url.pathname === "/api/pair") {
    readJson(req)
      .then((body) => {
        const result = sessions.createPendingSession({
          providedPin: String(body.pin || ""),
          deviceName: String(body.deviceName || "Phone").slice(0, 80),
          userAgent: req.headers["user-agent"],
          remoteAddress: req.socket.remoteAddress,
          origin: req.headers.origin,
          autoApproveTrusted: settings.trustedDevicesEnabled || Boolean(body.keepSignedIn),
          keepSignedIn: Boolean(body.keepSignedIn)
        });
        if (!result.ok) {
          const status = result.code === "PIN_RATE_LIMITED" ? 429 : 401;
          return sendJson(res, status, apiError(
            result.code || "PAIR_FAILED",
            result.message || "Pairing failed.",
            null,
            true,
            result
          ));
        }
        scheduleAutoLaunchCapture(
          result.session.approved ? "pair-auto-approved" : "pair-created",
          result.session.approved ? 50 : 700
        );
        sendJson(res, 202, {
          ok: true,
          sessionId: result.session.id,
          token: result.session.token,
          approved: result.session.approved,
          message: result.session.approved ? "Trusted device approved." : "Waiting for laptop approval."
        });
      })
      .catch((error) => sendApiException(res, 400, "BAD_JSON", error));
    return;
  }
  if (req.method === "POST" && url.pathname === "/api/approve") {
    if (!requireHostKey(req, res)) return;
    readJson(req)
      .then((body) => {
        const session = sessions.approveSession(String(body.sessionId || ""));
        if (!session) return sendJson(res, 404, apiError("SESSION_NOT_FOUND", "Session was not found or has expired."));
        if (settings.trustedDevicesEnabled || session.keepSignedIn) sessions.trustSession(session.id);
        scheduleAutoLaunchCapture("session-approved", 50);
        sendJson(res, 200, { ok: true, sessionId: session.id });
      })
      .catch((error) => sendApiException(res, 400, "BAD_JSON", error));
    return;
  }
  if (req.method === "POST" && url.pathname === "/api/revoke") {
    if (!requireHostKey(req, res)) return;
    readJson(req)
      .then((body) => sendJson(res, 200, { ok: sessions.revokeSession(String(body.sessionId || "")) }))
      .catch((error) => sendApiException(res, 400, "BAD_JSON", error));
    return;
  }
  if (req.method === "POST" && url.pathname === "/api/trusted-device/revoke") {
    if (!requireHostKey(req, res)) return;
    readJson(req)
      .then((body) => {
        const result = sessions.revokeTrustedDevice(String(body.deviceId || ""));
        if (!result.ok) return sendJson(res, 404, apiError("TRUSTED_DEVICE_NOT_FOUND", "Trusted device was not found."));
        const disconnected = disconnectRevokedSessionIds(result.revokedSessionIds);
        sendJson(res, 200, { ok: true, ...result, disconnected, trustedDevices: sessions.listTrustedDevices() });
      })
      .catch((error) => sendApiException(res, 400, "BAD_JSON", error));
    return;
  }
  if (req.method === "POST" && url.pathname === "/api/trusted-devices/clear") {
    if (!requireHostKey(req, res)) return;
    const result = sessions.clearTrustedDevices();
    const disconnected = disconnectRevokedSessionIds(result.revokedSessionIds);
    sendJson(res, 200, { ok: true, ...result, disconnected, trustedDevices: sessions.listTrustedDevices() });
    return;
  }
  if (req.method === "POST" && url.pathname === "/api/refresh-pin") {
    if (!requireHostKey(req, res)) return;
    return sendJson(res, 200, sessions.refreshPin());
  }
  if (req.method === "POST" && url.pathname === "/api/input-mode") {
    if (!requireHostKey(req, res)) return;
    readJson(req)
      .then(async (body) => {
        await input.setEnabled(Boolean(body.enabled));
        sendJson(res, 200, { ok: true, inputSafety: getPublicState().inputSafety });
      })
      .catch((error) => sendApiException(res, 400, "BAD_INPUT_MODE", error));
    return;
  }
  if (req.method === "POST" && url.pathname === "/api/safety-release") {
    if (!requireHostKey(req, res)) return;
    input.releaseAll()
      .then(() => {
        log("input.safetyRelease");
        sendJson(res, 200, { ok: true });
      })
      .catch((error) => sendJson(res, 500, apiError("SAFETY_RELEASE_FAILED", error.message)));
    return;
  }
  if (req.method === "POST" && url.pathname === "/api/kill-switch") {
    if (!requireHostKey(req, res)) return;
    Promise.resolve(input.setEnabled(false))
      .then(() => input.releaseAll())
      .then(() => {
        const disconnected = clients.size;
        for (const client of clients.values()) {
          client.socket.end();
        }
        const revoked = sessions.revokeAll("kill-switch");
        log("host.killSwitch", { disconnected, revoked });
        sendJson(res, 200, { ok: true, disconnected, revoked, inputSafety: getPublicState().inputSafety });
      })
      .catch((error) => sendJson(res, 500, apiError("KILL_SWITCH_FAILED", error.message)));
    return;
  }
  sendJson(res, 404, apiError("NOT_FOUND", "API endpoint was not found."));
}

function broadcast(message) {
  for (const client of clients.values()) {
    sendWsJson(client.socket, message);
  }
}

function streamFrameWirePayload(message) {
  const payload = message.payload || {};
  const { imageBuffer, ...wirePayload } = payload;
  if (Buffer.isBuffer(imageBuffer)) {
    wirePayload.binaryImage = {
      protocol: 1,
      frameId: wirePayload.frameId,
      mimeType: wirePayload.mimeType || "image/jpeg",
      byteLength: imageBuffer.length
    };
    wirePayload.imageByteLength = imageBuffer.length;
  }
  return wirePayload;
}

function streamFrameWireMessage(message) {
  return {
    ...message,
    payload: streamFrameWirePayload(message)
  };
}

function encodeBinaryStreamFrame(message) {
  const image = message.payload?.imageBuffer;
  if (!Buffer.isBuffer(image)) return null;
  const header = Buffer.from(JSON.stringify(streamFrameWireMessage(message)), "utf8");
  const prefix = Buffer.alloc(8);
  STREAM_BINARY_MAGIC.copy(prefix, 0);
  prefix.writeUInt32BE(header.length, 4);
  return Buffer.concat([prefix, header, image]);
}

function streamFrameWireBytes(message) {
  const binary = encodeBinaryStreamFrame(message);
  if (binary) return binary.length;
  return Buffer.byteLength(JSON.stringify(streamFrameWireMessage(message).payload || {}), "utf8");
}

function broadcastStreamFrame(message) {
  const binary = encodeBinaryStreamFrame(message);
  for (const client of clients.values()) {
    if (binary) {
      sendWsBinary(client.socket, binary);
    } else {
      sendWsJson(client.socket, streamFrameWireMessage(message));
    }
  }
}

function disconnectRevokedSessionIds(sessionIds = []) {
  const revoked = new Set(sessionIds);
  let disconnected = 0;
  for (const client of clients.values()) {
    if (!revoked.has(client.session.id)) continue;
    client.socket.end();
    disconnected += 1;
  }
  return disconnected;
}

function authorizeUpgrade(req) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const token = url.searchParams.get("token");
  const session = sessions.getSessionByToken(token);
  if (!session) return { ok: false, code: "SESSION_NOT_FOUND" };
  if (!session.approved) return { ok: false, code: "SESSION_NOT_APPROVED" };
  if (req.headers.origin && session.allowedOrigin && req.headers.origin !== session.allowedOrigin) {
    return { ok: false, code: "ORIGIN_NOT_ALLOWED" };
  }
  return { ok: true, session };
}

function authorizeRtcUpgrade(req) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const role = url.searchParams.get("role");
  if (role === "host") {
    const provided = url.searchParams.get("key") || req.headers["x-host-key"];
    if (provided !== hostKey) return { ok: false, code: "BAD_HOST_KEY" };
    return { ok: true, role, label: "Laptop capture page" };
  }
  if (role === "phone") {
    const token = url.searchParams.get("token");
    const session = sessions.getSessionByToken(token);
    if (!session) return { ok: false, code: "SESSION_NOT_FOUND" };
    if (!session.approved) return { ok: false, code: "SESSION_NOT_APPROVED" };
    if (req.headers.origin && session.allowedOrigin && req.headers.origin !== session.allowedOrigin) {
      return { ok: false, code: "ORIGIN_NOT_ALLOWED" };
    }
    return {
      ok: true,
      role,
      session,
      sessionId: session.id,
      label: session.deviceName || "Phone"
    };
  }
  return { ok: false, code: "BAD_RTC_ROLE" };
}

function requiredPermission(type) {
  if (type.startsWith("pointer.") || type === "wheel") return "pointer";
  if (["key", "keyDown", "keyUp", "chord"].includes(type)) return "keyboard";
  if (["text", "pasteText"].includes(type)) return "text";
  return null;
}

function sanitizeInputPayload(type, payload = {}) {
  if (type === "text" || type === "pasteText") {
    return {
      textLength: String(payload.text || "").length
    };
  }
  if (type === "chord") {
    return {
      modifiers: Array.isArray(payload.modifiers) ? payload.modifiers.map(String) : [],
      key: payload.key ? String(payload.key) : ""
    };
  }
  if (type === "key" || type === "keyDown" || type === "keyUp") {
    return {
      key: payload.key ? String(payload.key) : ""
    };
  }
  if (type === "wheel") {
    return {
      deltaX: Number(payload.deltaX || 0),
      deltaY: Number(payload.deltaY || 0),
      gesture: payload.gesture ? String(payload.gesture) : undefined
    };
  }
  if (type.startsWith("pointer.")) {
    return {
      mode: payload.mode ? String(payload.mode) : undefined,
      button: payload.button ? String(payload.button) : undefined,
      dx: Number(payload.dx || 0),
      dy: Number(payload.dy || 0),
      normalizedX: Number.isFinite(Number(payload.normalizedX)) ? Number(payload.normalizedX) : undefined,
      normalizedY: Number.isFinite(Number(payload.normalizedY)) ? Number(payload.normalizedY) : undefined,
      dragging: Boolean(payload.dragging || payload.dragLock)
    };
  }
  return {};
}

function cleanText(value, fallback = "", maxLength = 180) {
  const text = String(value || fallback || "").replace(/\s+/g, " ").trim();
  return text.slice(0, maxLength);
}

function cleanFiniteNumber(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function sanitizeAcceptancePayload(payload = {}) {
  const viewport = payload.viewport && typeof payload.viewport === "object" ? payload.viewport : {};
  const screen = payload.screen && typeof payload.screen === "object" ? payload.screen : {};
  const features = payload.features && typeof payload.features === "object" ? payload.features : {};
  const diagnostics = payload.diagnostics && typeof payload.diagnostics === "object" ? payload.diagnostics : {};
  const checklist = payload.checklist && typeof payload.checklist === "object" ? payload.checklist : null;
  const checklistItems = Array.isArray(checklist?.items) ? checklist.items.slice(0, 20) : [];
  const sanitizedChecklist = checklist ? {
    source: cleanText(checklist.source, "phone-ui", 40),
    gate: cleanText(checklist.gate, "", 40),
    requiredCount: cleanFiniteNumber(checklist.requiredCount),
    passedCount: cleanFiniteNumber(checklist.passedCount),
    complete: Boolean(checklist.complete),
    items: checklistItems.map((item) => ({
      id: cleanText(item?.id, "", 40),
      label: cleanText(item?.label, "", 220),
      checked: Boolean(item?.checked)
    }))
  } : null;
  return {
    marker: cleanText(payload.marker, "manual-phone-proof", 80),
    gate: cleanText(payload.gate, "", 40),
    step: cleanText(payload.step, "", 120),
    urlOrigin: cleanText(payload.urlOrigin, "", 160),
    urlPath: cleanText(payload.urlPath, "", 160),
    userAgent: cleanText(payload.userAgent, "", 220),
    viewport: {
      width: cleanFiniteNumber(viewport.width),
      height: cleanFiniteNumber(viewport.height),
      devicePixelRatio: cleanFiniteNumber(viewport.devicePixelRatio, 1),
      orientation: cleanText(viewport.orientation, "", 32)
    },
    screen: {
      width: cleanFiniteNumber(screen.width),
      height: cleanFiniteNumber(screen.height)
    },
    features: {
      touch: Boolean(features.touch),
      standalone: Boolean(features.standalone),
      serviceWorker: Boolean(features.serviceWorker),
      vibration: Boolean(features.vibration)
    },
    diagnostics: {
      frameId: cleanFiniteNumber(diagnostics.frameId),
      monitor: cleanText(diagnostics.monitor, "", 80),
      quality: cleanText(diagnostics.quality, "", 32),
      inputMode: cleanText(diagnostics.inputMode, "", 32),
      precisionMode: Boolean(diagnostics.precisionMode),
      viewportZoom: cleanFiniteNumber(diagnostics.viewportZoom, 1),
      fpsApprox: cleanFiniteNumber(diagnostics.fpsApprox),
      inputRttMs: cleanFiniteNumber(diagnostics.inputRttMs)
    },
    checklist: sanitizedChecklist
  };
}

function ackPayload(message, payload = {}) {
  return {
    ackType: message.type,
    sequence: message.sequence ?? null,
    ...payload
  };
}

async function handleClientMessage(client, raw) {
  let message;
  try {
    message = JSON.parse(raw);
  } catch {
    sendWsJson(client.socket, makeError("BAD_JSON", "Control message was not valid JSON."));
    return;
  }
  const validation = validateClientMessage(message, { lastSequence: client.lastSequence });
  if (!validation.ok) {
    sendWsJson(client.socket, makeError(validation.code, validation.message));
    return;
  }
  client.lastSequence = message.sequence;
  client.session.lastSeenAt = Date.now();
  const payload = message.payload || {};
  if (message.type === "monitor.select") {
    let availableMonitors = capture.getMonitors();
    let requestedMonitor = availableMonitors.find((monitor) => monitor.id === payload.monitorId);
    if (!requestedMonitor && typeof capture.refreshMonitors === "function") {
      await capture.refreshMonitors();
      availableMonitors = capture.getMonitors();
      requestedMonitor = availableMonitors.find((monitor) => monitor.id === payload.monitorId);
    }
    if (!requestedMonitor && typeof capture.rememberMonitor === "function") {
      requestedMonitor = capture.rememberMonitor(payload.monitor);
      availableMonitors = capture.getMonitors();
    }
    if (requestedMonitor) {
      const previousMonitorId = selectedMonitorId;
      selectedMonitorId = requestedMonitor.id;
      const captureSourceName = captureSourceNameForMonitor(selectedMonitorId);
      captureSourceCorrectionCounts.set(selectedMonitorId, 0);
      noteCaptureAutoDetect("switching", `Selecting ${selectedMonitorId} with ${captureSourceName}.`);
      log("monitor.select", {
        sessionId: client.session.id,
        monitorId: selectedMonitorId,
        captureSourceName,
        monitorCount: availableMonitors.length,
        sourceId: requestedMonitor.sourceId || ""
      });
      let centeredPointer = null;
      if (client.session.approved && client.session.permissions?.pointer) {
        try {
          centeredPointer = await input.centerOnMonitor(requestedMonitor);
          if (centeredPointer) {
            markInputActivity("pointer.move");
            log(input.isEnabled() ? "input.real" : "input.dryRun", {
              sessionId: client.session.id,
              commandType: "monitor.centerPointer",
              monitorId: selectedMonitorId
            });
          }
        } catch (error) {
          log("input.failed", {
            sessionId: client.session.id,
            commandType: "monitor.centerPointer",
            monitorId: selectedMonitorId,
            error: error.message
          });
        }
      }
      sendWsJson(client.socket, makeMessage("ack", ackPayload(message, {
        selectedMonitorId,
        captureSourceName,
        centeredPointer,
        coordinateSpace: centeredPointer ? "logical-desktop" : null
      })));
      scheduleStateBroadcast({ immediate: true });
      scheduleImmediateFrame(`monitor-select-${selectedMonitorId}`);
      if (previousMonitorId !== selectedMonitorId && shouldAutoLaunchRtcCapture({ settings }) && availableMonitors.length > 1) {
        setTimeout(() => {
          try {
            ensureCaptureBrowser({
              autoStart: true,
              autoSelect: true,
              force: true,
              monitorId: selectedMonitorId,
              reason: `monitor-select-${selectedMonitorId}`
            });
          } catch (error) {
            log("host.capture.monitorSwitchFailed", { monitorId: selectedMonitorId, error: error.message });
          }
        }, 50);
      }
      return;
    }
    sendWsJson(client.socket, makeError("BAD_MONITOR", "That monitor is not available."));
    return;
  }
  if (message.type === "capture.source") {
    const monitorId = String(payload.monitorId || selectedMonitorId);
    const sourceName = String(payload.sourceName || "").trim();
    const monitorExists = capture.getMonitors().some((monitor) => monitor.id === monitorId);
    const allowedSources = captureSourceCandidatesForMonitor(monitorId);
    const allowed = sourceName === "Auto" || allowedSources.includes(sourceName) || /^Screen\s+\d+$/i.test(sourceName) || sourceName === "Entire screen";
    if (!monitorExists || !allowed) {
      sendWsJson(client.socket, makeError("BAD_MONITOR", "That capture source is not available for this display."));
      return;
    }
    selectedMonitorId = monitorId;
    if (sourceName === "Auto") {
      captureSourceOverrides.delete(monitorId);
    } else {
      captureSourceOverrides.set(monitorId, sourceName);
    }
    captureSourceCorrectionCounts.set(monitorId, 0);
    noteCaptureAutoDetect("locked", `Using ${captureSourceNameForMonitor(monitorId)} for ${monitorId}.`);
    log("host.capture.sourceLocked", {
      sessionId: client.session.id,
      monitorId,
      sourceName: captureSourceNameForMonitor(monitorId)
    });
    sendWsJson(client.socket, makeMessage("ack", ackPayload(message, {
      selectedMonitorId,
      captureSourceName: captureSourceNameForMonitor(monitorId)
    })));
    scheduleStateBroadcast({ immediate: true });
    if (shouldAutoLaunchRtcCapture({ settings })) {
      setTimeout(() => {
        try {
          ensureCaptureBrowser({
            autoStart: true,
            autoSelect: true,
            force: true,
            monitorId,
            reason: `capture-source-${captureSourceNameForMonitor(monitorId).replace(/\s+/g, "-").toLowerCase()}`
          });
        } catch (error) {
          log("host.capture.sourceLockFailed", { monitorId, error: error.message });
        }
      }, 50);
    }
    return;
  }
  if (message.type === "stream.setQuality") {
    if (["fast", "balanced", "sharp", "battery"].includes(payload.quality)) {
      quality = payload.quality;
      log("stream.quality", { sessionId: client.session.id, quality });
      sendWsJson(client.socket, makeMessage("ack", ackPayload(message, { quality })));
      return;
    }
    sendWsJson(client.socket, makeError("BAD_QUALITY", "Unknown stream quality preset."));
    return;
  }
  if (message.type === "stream.visibility") {
    const visible = payload.visible !== undefined ? Boolean(payload.visible) : !Boolean(payload.hidden);
    client.visible = visible;
    log("stream.visibility", { sessionId: client.session.id, visible });
    sendWsJson(client.socket, makeMessage("ack", ackPayload(message, { visible })));
    if (visible) scheduleImmediateFrame(payload.reason || "phone-visible");
    return;
  }
  if (message.type === "acceptance.mark") {
    const proof = sanitizeAcceptancePayload(payload);
    const entry = log("acceptance.phoneMark", {
      sessionId: client.session.id,
      deviceName: client.session.deviceName,
      remoteAddress: client.session.remoteAddress,
      proof
    });
    saveLatestPhoneProofLog(entry);
    sendWsJson(client.socket, makeMessage("ack", ackPayload(message, { marker: proof.marker })));
    return;
  }
  if (message.type === "session.disconnect") {
    await input.releaseAll();
    log("session.disconnect.requested", { sessionId: client.session.id });
    client.socket.end();
    return;
  }
  if (message.type.startsWith("pointer.") || ["wheel", "key", "keyDown", "keyUp", "chord", "text", "pasteText"].includes(message.type)) {
    markInputActivity(message.type);
    const permission = requiredPermission(message.type);
    if (!client.session.approved || (permission && !client.session.permissions?.[permission])) {
      log("input.denied", { sessionId: client.session.id, commandType: message.type, permission });
      sendWsJson(client.socket, makeError("INPUT_DENIED", "This session is not allowed to send that input."));
      return;
    }
    const monitor = capture.getMonitors().find((item) => item.id === selectedMonitorId) || capture.getMonitors()[0];
    try {
      const ack = await input.handle(message, { monitor, inputMode, selectedMonitorId });
      log(ack.realInput ? "input.real" : "input.dryRun", {
        sessionId: client.session.id,
        commandType: message.type,
        input: sanitizeInputPayload(message.type, payload)
      });
      sendWsJson(client.socket, makeMessage("ack", ack));
    } catch (error) {
      log("input.failed", { sessionId: client.session.id, commandType: message.type, error: error.message });
      sendWsJson(client.socket, makeError("INPUT_FAILED", error.message));
    }
    return;
  }
  sendWsJson(client.socket, makeMessage("ack", { ackType: message.type }));
}

function acceptWebSocket(req, socket) {
  const key = req.headers["sec-websocket-key"];
  if (!key) {
    socket.destroy();
    return false;
  }
  socket.write(
    [
      "HTTP/1.1 101 Switching Protocols",
      "Upgrade: websocket",
      "Connection: Upgrade",
      `Sec-WebSocket-Accept: ${acceptKey(key)}`,
      "\r\n"
    ].join("\r\n")
  );
  socket.setNoDelay(true);
  return true;
}

function handleRtcUpgrade(req, socket) {
  if (!isAllowedRequest(req)) {
    log("network.blockedRemote", { remoteAddress: req.socket.remoteAddress, upgrade: true, endpoint: "rtc" });
    socket.write("HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n");
    socket.destroy();
    return;
  }
  const auth = authorizeRtcUpgrade(req);
  if (!auth.ok) {
    socket.write("HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n");
    socket.destroy();
    return;
  }
  if (!acceptWebSocket(req, socket)) return;
  const connected = rtcRoom.connectPeer({
    role: auth.role,
    socket,
    label: auth.label,
    sessionId: auth.sessionId || null,
    metadata: {
      remoteAddress: req.socket.remoteAddress,
      userAgent: req.headers["user-agent"] || "",
      captureUrl: auth.role === "host" ? new URL(req.url, `http://${req.headers.host}`).href : ""
    }
  });
  if (!connected.ok) {
    sendWsJson(socket, makeError(connected.code || "RTC_CONNECT_FAILED", connected.message || "RTC connection failed."));
    socket.end();
    return;
  }
  const peerId = connected.peer.id;
  if (auth.role === "host") markCaptureAlive(connected.peer);
  let buffer = Buffer.alloc(0);
  socket.on("data", (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    const decoded = decodeFrames(buffer);
    buffer = decoded.remaining;
    for (const message of decoded.messages) {
      if (message.type === "close") {
        socket.end();
      } else if (message.type === "text") {
        const result = rtcRoom.handleMessage(peerId, message.data);
        if (auth.role === "host" && result?.state) {
          const hostPeer = result.state.host;
          if (hostPeer) markCaptureAlive(hostPeer);
          maybeCorrectCaptureSource("rtc-host-metadata", result.state);
        }
      } else {
        sendWsJson(socket, makeError("BAD_RTC_FRAME", "RTC signaling only accepts text JSON frames."));
      }
    }
  });
  socket.on("close", () => {
    rtcRoom.disconnectPeer(peerId, "socket-closed");
    if (auth.role === "host") markCaptureIdle("socket-closed");
  });
  socket.on("error", () => {
    rtcRoom.disconnectPeer(peerId, "socket-error");
    if (auth.role === "host") markCaptureIdle("socket-error");
    socket.destroy();
  });
}

function handleUpgrade(req, socket) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  if (url.pathname === "/rtc") {
    if (!rtcCaptureFeatureEnabled) {
      socket.write("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n");
      socket.destroy();
      return;
    }
    handleRtcUpgrade(req, socket);
    return;
  }
  if (!req.url.startsWith("/ws")) {
    socket.destroy();
    return;
  }
  if (!isAllowedRequest(req)) {
    log("network.blockedRemote", { remoteAddress: req.socket.remoteAddress, upgrade: true });
    socket.write("HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n");
    socket.destroy();
    return;
  }
  const auth = authorizeUpgrade(req);
  if (!auth.ok) {
    socket.write("HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n");
    socket.destroy();
    return;
  }
  if (!acceptWebSocket(req, socket)) return;

  const clientId = crypto.randomUUID();
  auth.session.connected = true;
  clients.set(clientId, { id: clientId, socket, session: auth.session, buffer: Buffer.alloc(0), visible: true, lastSequence: 0 });
  log("session.connected", { sessionId: auth.session.id, deviceName: auth.session.deviceName });
  maybeAutoLaunchCapture("phone-control-socket-connected");
  sendWsJson(socket, makeMessage("hello", { clientId, state: getPublicState() }));
  scheduleImmediateFrame("socket-connected");

  socket.on("data", (chunk) => {
    const client = clients.get(clientId);
    if (!client) return;
    client.buffer = Buffer.concat([client.buffer, chunk]);
    const decoded = decodeFrames(client.buffer);
    client.buffer = decoded.remaining;
    for (const message of decoded.messages) {
      if (message.type === "close") {
        socket.end();
      } else {
        handleClientMessage(client, message.data);
      }
    }
  });
  socket.on("close", () => {
    const client = clients.get(clientId);
    if (client) {
      client.session.connected = false;
      clients.delete(clientId);
      input.releaseAll().catch(() => {});
      log("session.disconnected", { sessionId: client.session.id });
    }
  });
  socket.on("error", () => {
    socket.destroy();
  });
}

const server = http.createServer((req, res) => {
  if (!isAllowedRequest(req)) return rejectNetworkRequest(req, res);
  if (req.url.startsWith("/api/")) return handleApi(req, res);
  serveStatic(req, res);
});

server.on("upgrade", handleUpgrade);

function scheduleFramePump(delayMs = effectiveFrameIntervalMs()) {
  setTimeout(async () => {
    const tickStartedAt = Date.now();
    await captureAndBroadcastFrame("scheduled");
    scheduleFramePump(nextFrameDelayMs(effectiveFrameIntervalMs(), Date.now() - tickStartedAt));
  }, delayMs);
}

function onListening(host) {
  log("host.started", { port: PORT, host });
  if (!shouldAutoLaunchRtcCapture({ settings })) {
    stopCaptureBrowserProcesses("rtc-autostart-disabled-startup");
    setTimeout(() => {
      stopCaptureBrowserProcesses("rtc-autostart-disabled-delayed-startup");
    }, 2000);
  }
  lastMonitorSignature = monitorSignature();
  const addresses = getReachableAddresses(PORT, { publicUrl });
  console.log(`Remote Controller running on http://127.0.0.1:${PORT}`);
  console.log(`Host console: http://127.0.0.1:${PORT}/host?key=${hostKey}`);
  for (const address of addresses) {
    console.log(`${address.kind.toUpperCase()} ${address.name}: ${address.url}`);
  }
  scheduleFramePump();
  if (typeof capture.refreshMonitors === "function") {
    setTimeout(() => {
      refreshMonitorList("startup").catch((error) => {
        log("capture.screen.monitorRefreshFailed", { error: error.message });
      });
    }, 1200);
    setInterval(() => {
      refreshMonitorList("periodic").catch((error) => {
        log("capture.screen.monitorRefreshFailed", { error: error.message });
      });
    }, 8000);
  }
  if (shouldAutoLaunchRtcCapture({ settings })) {
    setTimeout(() => {
      maybeAutoLaunchCapture("host-startup");
    }, 900);
  }
}

function listen(host, fallbackHost = "") {
  const onListenError = (error) => {
    if (fallbackHost && (error.code === "EAFNOSUPPORT" || error.code === "EADDRNOTAVAIL")) {
      log("host.ipv6Fallback", { from: host, to: fallbackHost, code: error.code });
      listen(fallbackHost);
      return;
    }
    throw error;
  };

  server.once("error", onListenError);
  server.listen({ port: PORT, host, ipv6Only: false }, () => {
    server.off("error", onListenError);
    onListening(host);
  });
}

listen(HOST, process.env.HOST ? "" : "0.0.0.0");

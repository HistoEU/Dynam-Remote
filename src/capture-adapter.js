"use strict";

const screenshotDesktop = require("screenshot-desktop");

const { MONITORS: FAKE_MONITORS, createFakeFrame } = require("./fake-stream");
const { makeMessage } = require("./protocol");

const CAPTURE_TIMEOUT_MS = 2200;
const DEFAULT_STALE_CAPTURE_MS = 12000;

function withTimeout(promise, timeoutMs, message) {
  let timer = null;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(message)), timeoutMs);
  });
  return Promise.race([promise, timeout]).finally(() => {
    if (timer) clearTimeout(timer);
  });
}

function qualityToIntervalMs(quality) {
  if (quality === "fast") return 140;
  if (quality === "battery") return 1300;
  if (quality === "sharp") return 760;
  return 360;
}

function normalizeDisplay(display, index) {
  const left = Number(display.left || 0);
  const top = Number(display.top || 0);
  const width = Number(display.width || Math.max(1, Number(display.right || 0) - left));
  const height = Number(display.height || Math.max(1, Number(display.bottom || 0) - top));
  const scaleFactor = Number(display.dpiScale || 1);
  const scale = Number.isFinite(scaleFactor) && scaleFactor > 0 ? scaleFactor : 1;
  const friendlyName = display.name && !String(display.name).includes("\\\\.\\")
    ? display.name
    : `Display ${index + 1}`;
  return {
    id: `display-${index + 1}`,
    sourceId: display.id,
    name: friendlyName,
    bounds: {
      left,
      top,
      width,
      height
    },
    logicalBounds: {
      left: Math.round(left / scale),
      top: Math.round(top / scale),
      width: Math.round(width / scale),
      height: Math.round(height / scale)
    },
    scaleFactor: scale,
    primary: index === 0,
    orientation: width >= height ? "landscape" : "portrait",
    status: "screen"
  };
}

function normalizeRememberedMonitor(display = {}) {
  const id = String(display.id || "");
  if (!/^display-\d+$/.test(id)) return null;
  const bounds = display.bounds || {};
  const left = Number(bounds.left || 0);
  const top = Number(bounds.top || 0);
  const width = Number(bounds.width || 0);
  const height = Number(bounds.height || 0);
  if (!Number.isFinite(width) || !Number.isFinite(height) || width < 120 || height < 120) return null;
  const scaleFactor = Number(display.scaleFactor || 1);
  const scale = Number.isFinite(scaleFactor) && scaleFactor > 0 ? scaleFactor : 1;
  const sourceId = String(display.sourceId || `\\\\.\\DISPLAY${id.replace("display-", "")}`);
  return {
    id,
    sourceId,
    name: String(display.name || `Display ${id.replace("display-", "")}`).slice(0, 80),
    bounds: {
      left: Number.isFinite(left) ? left : 0,
      top: Number.isFinite(top) ? top : 0,
      width,
      height
    },
    logicalBounds: display.logicalBounds || {
      left: Math.round((Number.isFinite(left) ? left : 0) / scale),
      top: Math.round((Number.isFinite(top) ? top : 0) / scale),
      width: Math.round(width / scale),
      height: Math.round(height / scale)
    },
    scaleFactor: scale,
    primary: Boolean(display.primary),
    orientation: width >= height ? "landscape" : "portrait",
    status: "remembered"
  };
}

function cleanString(value, fallback = "", maxLength = 120) {
  return String(value || fallback || "").replace(/\s+/g, " ").trim().slice(0, maxLength);
}

function cleanNumber(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function monitorSummary(monitor = null) {
  if (!monitor) return null;
  return {
    id: cleanString(monitor.id, "", 80),
    sourceId: cleanString(monitor.sourceId, "", 80),
    name: cleanString(monitor.name, "Display", 80),
    bounds: {
      left: cleanNumber(monitor.bounds?.left),
      top: cleanNumber(monitor.bounds?.top),
      width: cleanNumber(monitor.bounds?.width),
      height: cleanNumber(monitor.bounds?.height)
    },
    logicalBounds: monitor.logicalBounds ? {
      left: cleanNumber(monitor.logicalBounds.left),
      top: cleanNumber(monitor.logicalBounds.top),
      width: cleanNumber(monitor.logicalBounds.width),
      height: cleanNumber(monitor.logicalBounds.height)
    } : null,
    scaleFactor: cleanNumber(monitor.scaleFactor, 1),
    primary: Boolean(monitor.primary),
    orientation: cleanString(monitor.orientation, "", 32),
    status: cleanString(monitor.status, "unknown", 40)
  };
}

function sizeFromMonitor(monitor = null) {
  return {
    width: Math.max(0, cleanNumber(monitor?.bounds?.width)),
    height: Math.max(0, cleanNumber(monitor?.bounds?.height))
  };
}

function captureSizeMismatches(expected = {}, actual = {}) {
  const expectedW = cleanNumber(expected.width);
  const expectedH = cleanNumber(expected.height);
  const actualW = cleanNumber(actual.width);
  const actualH = cleanNumber(actual.height);
  if (!expectedW || !expectedH || !actualW || !actualH) return false;
  const tolerance = 10;
  return !(Math.abs(actualW - expectedW) <= tolerance && Math.abs(actualH - expectedH) <= tolerance);
}

function findMonitor(monitors = [], monitorId = "") {
  return monitors.find((monitor) => monitor.id === monitorId) || null;
}

function createCaptureDiagnostics({
  monitors = [],
  selectedMonitorId = "",
  rtcState = {},
  captureLaunch = {},
  correctionCount = 0,
  now = Date.now(),
  staleAfterMs = DEFAULT_STALE_CAPTURE_MS
} = {}) {
  const safeMonitors = Array.isArray(monitors) ? monitors : [];
  const selectedMonitor = findMonitor(safeMonitors, selectedMonitorId) || safeMonitors[0] || null;
  const captureMeta = rtcState?.host?.capture || null;
  const launchMonitorId = cleanString(captureLaunch.monitorId || selectedMonitorId, "", 80);
  const reportedMonitorId = cleanString(captureMeta?.requestedMonitor || "", "", 80);
  const reportedMonitor = findMonitor(safeMonitors, reportedMonitorId);
  const actualSize = {
    width: Math.max(0, cleanNumber(captureMeta?.width)),
    height: Math.max(0, cleanNumber(captureMeta?.height))
  };
  const expectedSize = sizeFromMonitor(selectedMonitor);
  const updatedAt = cleanNumber(captureMeta?.updatedAt);
  const ageMs = updatedAt ? Math.max(0, now - updatedAt) : null;
  const stale = Boolean(captureMeta && ageMs !== null && ageMs > staleAfterMs);
  const autoDetect = captureLaunch.autoDetect && typeof captureLaunch.autoDetect === "object"
    ? captureLaunch.autoDetect
    : {};
  const correctionStatus = cleanString(autoDetect.status, "idle", 60);
  const divergence = [];

  if (!rtcState?.hostConnected || !rtcState?.host) {
    divergence.push("missing-rtc-host");
  } else if (!captureMeta?.sharing) {
    divergence.push("not-sharing");
  }
  if (reportedMonitorId && selectedMonitor?.id && reportedMonitorId !== selectedMonitor.id) {
    divergence.push("requested-monitor-mismatch");
  }
  if (captureMeta?.sharing && captureSizeMismatches(expectedSize, actualSize)) {
    divergence.push("capture-size-mismatch");
  }
  if (stale) divergence.push("stale-rtc-host");
  if (selectedMonitor?.status && selectedMonitor.status !== "screen" && selectedMonitor.status !== "fake") {
    divergence.push("selected-monitor-disconnected");
  }

  return {
    selectedInputMonitor: monitorSummary(selectedMonitor),
    requestedCapture: {
      monitorId: launchMonitorId,
      sourceName: cleanString(captureLaunch.captureSourceName || captureMeta?.requestedSource || "auto", "auto", 120),
      status: cleanString(captureLaunch.status, "idle", 40),
      autoStart: Boolean(captureLaunch.autoStart),
      autoSelect: Boolean(captureLaunch.autoSelect),
      lastLaunchAt: cleanNumber(captureLaunch.lastLaunchAt)
    },
    reportedCapture: {
      sharing: Boolean(captureMeta?.sharing),
      monitorId: reportedMonitorId,
      source: cleanString(captureMeta?.reportedSource || captureMeta?.displaySurface || "unknown", "unknown", 120),
      displaySurface: cleanString(captureMeta?.displaySurface, "", 80),
      width: actualSize.width,
      height: actualSize.height,
      frameRate: cleanNumber(captureMeta?.frameRate),
      connectionState: cleanString(captureMeta?.connectionState, "", 40),
      iceConnectionState: cleanString(captureMeta?.iceConnectionState, "", 40),
      firstFrameTimeMs: cleanNumber(captureMeta?.firstFrameTimeMs),
      fallbackReason: cleanString(captureMeta?.fallbackReason, "", 160),
      updatedAt
    },
    phoneVisibleDisplay: monitorSummary(reportedMonitor || selectedMonitor),
    expectedSize,
    actualSize,
    correction: {
      status: correctionStatus,
      reason: cleanString(autoDetect.reason, "", 180),
      checkedAt: cleanNumber(autoDetect.checkedAt),
      count: Math.max(0, cleanNumber(correctionCount)),
      needsManualAction: correctionStatus === "needs-manual-check"
    },
    staleCapture: {
      stale,
      ageMs,
      updatedAt,
      staleAfterMs
    },
    divergence: uniqueSorted(divergence)
  };
}

function uniqueSorted(items = []) {
  return [...new Set(items)].sort();
}

function createCaptureAdapter({ mode = "fake", log = () => {}, cursorProvider = null, screenshotProvider = screenshotDesktop } = {}) {
  let monitors = FAKE_MONITORS;
  const rememberedMonitors = new Map();
  let screenAvailable = false;
  let displayReady = Promise.resolve(false);

  function allMonitors() {
    const items = [...monitors];
    for (const monitor of rememberedMonitors.values()) {
      if (!items.some((item) => item.id === monitor.id)) items.push(monitor);
    }
    return items.sort((a, b) => {
      const aIndex = Number(String(a.id).replace("display-", "")) || 0;
      const bIndex = Number(String(b.id).replace("display-", "")) || 0;
      return aIndex - bIndex;
    });
  }

  function refreshMonitors() {
    if (mode !== "screen") return Promise.resolve(false);
    displayReady = screenshotProvider.listDisplays()
      .then((listed) => {
        if (Array.isArray(listed) && listed.length) {
          monitors = listed.map(normalizeDisplay);
          screenAvailable = true;
          log("capture.screen.available", { monitors: monitors.length });
          return true;
        }
        log("capture.screen.unavailable", { error: "No displays returned by screenshot-desktop." });
        return false;
      })
      .catch((error) => {
        screenAvailable = false;
        monitors = FAKE_MONITORS;
        log("capture.screen.unavailable", { error: error.message });
        return false;
      });
    return displayReady;
  }

  if (mode === "screen") {
    displayReady = refreshMonitors();
  }

  async function createFrame({ frameId, monitorId, quality, inputMode }) {
    if (mode === "screen" && !screenAvailable) {
      await displayReady;
    }
    if (!screenAvailable) {
      return createFakeFrame({ frameId, monitorId, quality, inputMode });
    }
    try {
      const monitor = allMonitors().find((item) => item.id === monitorId) || allMonitors()[0];
      const image = await withTimeout(
        screenshotProvider({ format: "jpg", screen: monitor.sourceId }),
        CAPTURE_TIMEOUT_MS,
        `Screen capture timed out after ${CAPTURE_TIMEOUT_MS}ms.`
      );
      let cursor = { x: Math.round(monitor.bounds.width / 2), y: Math.round(monitor.bounds.height / 2), visible: false };
      if (typeof cursorProvider === "function") {
        try {
          const point = await withTimeout(
            Promise.resolve(cursorProvider(monitor)),
            250,
            "Cursor read timed out."
          );
          if (point && Number.isFinite(Number(point.x)) && Number.isFinite(Number(point.y))) {
            const scale = Number(monitor.scaleFactor || 1);
            const logicalBounds = monitor.logicalBounds || monitor.bounds;
            const logicalX = Number(point.x) - Number(logicalBounds.left || 0);
            const logicalY = Number(point.y) - Number(logicalBounds.top || 0);
            cursor = {
              x: Math.round(logicalX),
              y: Math.round(logicalY),
              coordinateSpace: "logical-monitor",
              physicalX: Math.round(logicalX * scale),
              physicalY: Math.round(logicalY * scale),
              rawPoint: {
                x: Math.round(Number(point.x)),
                y: Math.round(Number(point.y)),
                coordinateSpace: "logical-desktop"
              },
              visible: true
            };
          }
        } catch {
          cursor.visible = false;
        }
      }
      return makeMessage("stream.frame", {
        frameId,
        monitorId: monitor.id,
        width: monitor.bounds.width,
        height: monitor.bounds.height,
        monitorGeometry: {
          id: monitor.id,
          sourceId: monitor.sourceId,
          name: monitor.name,
          bounds: monitor.bounds,
          logicalBounds: monitor.logicalBounds,
          scaleFactor: monitor.scaleFactor || 1,
          primary: Boolean(monitor.primary),
          orientation: monitor.orientation,
          captureSize: {
            width: monitor.bounds.width,
            height: monitor.bounds.height
          },
          captureMatchesBounds: true
        },
        scaleFactor: monitor.scaleFactor || 1,
        quality,
        inputMode,
        cursor,
        windows: [],
        desktopLabel: `${monitor.name} screen capture`,
        capturedAt: Date.now(),
        mimeType: "image/jpeg",
        imageBuffer: image,
        source: "screen"
      });
    } catch (error) {
      log("capture.screen.failed", { error: error.message });
      throw error;
    }
  }

  return {
    get mode() {
      return screenAvailable ? "screen" : "fake";
    },
    getMonitors: () => allMonitors(),
    refreshMonitors,
    rememberMonitor: (display) => {
      const monitor = normalizeRememberedMonitor(display);
      if (!monitor) return null;
      rememberedMonitors.set(monitor.id, monitor);
      log("capture.screen.monitorRemembered", { monitorId: monitor.id, sourceId: monitor.sourceId });
      return monitor;
    },
    intervalMsForQuality: qualityToIntervalMs,
    createFrame
  };
}

module.exports = {
  createCaptureAdapter,
  createCaptureDiagnostics,
  normalizeDisplay,
  normalizeRememberedMonitor,
  qualityToIntervalMs
};

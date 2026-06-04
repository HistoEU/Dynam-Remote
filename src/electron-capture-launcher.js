"use strict";

const fs = require("node:fs");
const path = require("node:path");

function cleanString(value, fallback = "", maxLength = 500) {
  return typeof value === "string" && value.trim()
    ? value.replace(/\s+/g, " ").trim().slice(0, maxLength)
    : fallback;
}

function safePathSegment(value, fallback = "default") {
  const cleaned = cleanString(value, fallback, 80)
    .replace(/[^a-z0-9_.-]/gi, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
  return cleaned || fallback;
}

function boundsFromMonitor(monitor = {}) {
  const bounds = monitor.bounds || monitor.logicalBounds || {};
  return {
    x: Number(bounds.x ?? bounds.left ?? 0),
    y: Number(bounds.y ?? bounds.top ?? 0),
    width: Number(bounds.width || 0),
    height: Number(bounds.height || 0)
  };
}

function boundsEqual(a = {}, b = {}, tolerance = 2) {
  return Math.abs(Number(a.x || 0) - Number(b.x || 0)) <= tolerance
    && Math.abs(Number(a.y || 0) - Number(b.y || 0)) <= tolerance
    && Math.abs(Number(a.width || 0) - Number(b.width || 0)) <= tolerance
    && Math.abs(Number(a.height || 0) - Number(b.height || 0)) <= tolerance;
}

function displayNumberFromSourceId(sourceId = "") {
  const match = String(sourceId || "").match(/DISPLAY(\d+)/i);
  return match ? match[1] : "";
}

function sourceWithReason(source, matchReason) {
  return source ? { ...source, matchReason } : null;
}

function selectElectronDesktopSource({
  sources = [],
  displays = [],
  monitor = {},
  requestedSourceName = ""
} = {}) {
  const screenSources = (Array.isArray(sources) ? sources : []).filter((source) => {
    const id = cleanString(source?.id, "", 120);
    return id.startsWith("screen:");
  });
  if (!screenSources.length) return null;

  const monitorBounds = boundsFromMonitor(monitor);
  const matchingDisplay = (Array.isArray(displays) ? displays : []).find((display) => {
    const displayBounds = boundsFromMonitor({ bounds: display?.bounds });
    return boundsEqual(displayBounds, monitorBounds);
  });
  if (matchingDisplay) {
    const displayId = String(matchingDisplay.id);
    const byDisplayId = screenSources.find((source) => String(source.display_id || "") === displayId);
    if (byDisplayId) return sourceWithReason(byDisplayId, "display-bounds");
  }

  const requestedName = cleanString(requestedSourceName, "", 120).toLowerCase();
  if (requestedName) {
    const byName = screenSources.find((source) => cleanString(source.name, "", 120).toLowerCase() === requestedName);
    if (byName) return sourceWithReason(byName, "source-name");
  }

  const displayNumber = displayNumberFromSourceId(monitor.sourceId);
  if (displayNumber) {
    const byDisplayNumber = screenSources.find((source) => cleanString(source.name, "", 120).toLowerCase() === `screen ${displayNumber}`);
    if (byDisplayNumber) return sourceWithReason(byDisplayNumber, "display-number");
  }

  return sourceWithReason(screenSources[0], "first-screen");
}

function buildElectronProfileDir({
  repoRoot = path.join(__dirname, ".."),
  monitorId = "default"
} = {}) {
  return path.join(repoRoot, "data", `electron-capture-profile-${safePathSegment(monitorId)}`);
}

function encodeArgValue(value) {
  return encodeURIComponent(String(value ?? ""));
}

function buildElectronCaptureArgs({
  appPath,
  hostUrl,
  hostKey,
  monitor = {},
  requestedSourceName = ""
} = {}) {
  const monitorBounds = boundsFromMonitor(monitor);
  return [
    appPath,
    `--host-url=${cleanString(hostUrl, "", 500)}`,
    `--host-key=${cleanString(hostKey, "", 160)}`,
    `--monitor-id=${cleanString(monitor.id, "", 80)}`,
    `--monitor-name=${encodeArgValue(cleanString(monitor.name, monitor.id || "Display", 120))}`,
    `--monitor-source-id=${encodeArgValue(cleanString(monitor.sourceId, "", 120))}`,
    `--monitor-bounds=${encodeArgValue(JSON.stringify(monitorBounds))}`,
    `--source-name=${cleanString(requestedSourceName, "", 120)}`
  ];
}

function findElectronBinary({
  cwd = path.join(__dirname, ".."),
  platform = process.platform,
  env = process.env,
  exists = fs.existsSync
} = {}) {
  if (env.ELECTRON_BINARY && exists(env.ELECTRON_BINARY)) return env.ELECTRON_BINARY;
  const candidates = platform === "win32"
    ? [
        path.join(cwd, "node_modules", "electron", "dist", "electron.exe"),
        path.join(cwd, "node_modules", ".bin", "electron.cmd")
      ]
    : [
        path.join(cwd, "node_modules", ".bin", "electron")
      ];
  return candidates.find((candidate) => exists(candidate)) || "";
}

module.exports = {
  boundsEqual,
  boundsFromMonitor,
  buildElectronCaptureArgs,
  buildElectronProfileDir,
  displayNumberFromSourceId,
  findElectronBinary,
  selectElectronDesktopSource
};

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { app, BrowserWindow, desktopCapturer, ipcMain, screen, session } = require("electron");
const { buildElectronProfileDir, selectElectronDesktopSource } = require("./electron-capture-launcher");

function argValue(name, fallback = "") {
  const prefix = `--${name}=`;
  const found = process.argv.find((arg) => arg.startsWith(prefix));
  return found ? found.slice(prefix.length) : fallback;
}

function decodeArg(value, fallback = "") {
  try {
    return decodeURIComponent(String(value || ""));
  } catch {
    return fallback;
  }
}

function parseJsonArg(value, fallback = null) {
  try {
    return JSON.parse(decodeArg(value, ""));
  } catch {
    return fallback;
  }
}

function buildConfig() {
  const monitorId = argValue("monitor-id", "display-1");
  const monitorName = decodeArg(argValue("monitor-name", monitorId), monitorId);
  const sourceId = decodeArg(argValue("monitor-source-id", ""), "");
  const bounds = parseJsonArg(argValue("monitor-bounds", ""), { x: 0, y: 0, width: 0, height: 0 });
  return {
    hostUrl: argValue("host-url", "http://127.0.0.1:4317"),
    hostKey: argValue("host-key", ""),
    monitorId,
    monitorName,
    monitorSourceId: sourceId,
    sourceName: argValue("source-name", monitorName),
    bounds,
    source: null
  };
}

function safeLog(event, payload = {}) {
  process.stdout.write(`${JSON.stringify({ event, at: Date.now(), ...payload })}\n`);
}

function configurePerMonitorProfile() {
  const profileDir = buildElectronProfileDir({
    repoRoot: path.join(__dirname, ".."),
    monitorId: argValue("monitor-id", "default")
  });
  const cacheDir = path.join(profileDir, "Cache");
  fs.mkdirSync(cacheDir, { recursive: true });
  app.setPath("userData", profileDir);
  app.commandLine.appendSwitch("user-data-dir", profileDir);
  app.commandLine.appendSwitch("disk-cache-dir", cacheDir);
  return { profileDir, cacheDir };
}

function createCaptureWindow(config) {
  const win = new BrowserWindow({
    width: 480,
    height: 360,
    show: false,
    skipTaskbar: true,
    webPreferences: {
      preload: path.join(__dirname, "electron-capture-preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      backgroundThrottling: false
    }
  });
  win.webContents.on("did-finish-load", () => {
    win.webContents.send("electron-capture-config", config);
  });
  win.webContents.on("console-message", (_event, level, message) => {
    safeLog("electron.capture.console", { level, message });
  });
  win.loadFile(path.join(__dirname, "electron-capture-renderer.html"));
  return win;
}

async function main() {
  const profile = configurePerMonitorProfile();
  app.commandLine.appendSwitch("autoplay-policy", "no-user-gesture-required");
  app.commandLine.appendSwitch("disable-background-timer-throttling");
  app.commandLine.appendSwitch("disable-renderer-backgrounding");
  app.commandLine.appendSwitch("disable-backgrounding-occluded-windows");
  await app.whenReady();

  const config = buildConfig();
  const sources = await desktopCapturer.getSources({
    types: ["screen"],
    thumbnailSize: { width: 0, height: 0 }
  });
  const displays = screen.getAllDisplays();
  const source = selectElectronDesktopSource({
    sources,
    displays,
    monitor: {
      id: config.monitorId,
      name: config.monitorName,
      sourceId: config.monitorSourceId,
      bounds: config.bounds
    },
    requestedSourceName: config.sourceName
  });
  if (!source) {
    safeLog("electron.capture.noSource", {
      monitorId: config.monitorId,
      sources: sources.map((item) => ({ id: item.id, name: item.name, display_id: item.display_id }))
    });
    app.exit(2);
    return;
  }
  config.source = {
    id: source.id,
    name: source.name,
    display_id: source.display_id,
    matchReason: source.matchReason
  };
  config.sourceName = `${source.name} (${config.monitorName})`;
  safeLog("electron.capture.sourceSelected", {
    monitorId: config.monitorId,
    source: config.source,
    profileDir: profile.profileDir,
    displays: displays.map((display) => ({ id: display.id, bounds: display.bounds, scaleFactor: display.scaleFactor }))
  });

  session.defaultSession.setDisplayMediaRequestHandler((_request, callback) => {
    callback({ video: source, audio: false });
  }, { useSystemPicker: false });

  ipcMain.on("electron-capture-status", (_event, message) => {
    safeLog("electron.capture.renderer", message || {});
  });

  createCaptureWindow(config);
}

main().catch((error) => {
  safeLog("electron.capture.failed", { error: error.message, stack: error.stack || "" });
  app.exit(1);
});

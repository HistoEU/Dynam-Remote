"use strict";

const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("electronCaptureHost", {
  onConfig(callback) {
    ipcRenderer.once("electron-capture-config", (_event, config) => callback(config));
  },
  report(event, payload = {}) {
    ipcRenderer.send("electron-capture-status", { event, payload, at: Date.now() });
  }
});

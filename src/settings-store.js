"use strict";

const fs = require("node:fs");
const path = require("node:path");

const DEFAULT_SETTINGS = {
  qualityDefault: "fast",
  inputSensitivityDefault: 1.55,
  trustedDevicesEnabled: false,
  autoStart: true,
  trustedDeviceKeys: [],
  trustedDevices: []
};

function cleanString(value, fallback = "", maxLength = 160) {
  if (typeof value !== "string") return fallback;
  return value.slice(0, maxLength);
}

function sanitizeTrustedDevice(value = {}) {
  if (!value || typeof value !== "object") return null;
  const key = cleanString(value.key || value.trustKey, "", 128);
  if (key.length <= 16) return null;
  return {
    key,
    deviceName: cleanString(value.deviceName, "Trusted phone", 80),
    remoteAddress: cleanString(value.remoteAddress, "", 80),
    trustedAt: Number.isFinite(Number(value.trustedAt)) ? Number(value.trustedAt) : Date.now(),
    lastSeenAt: Number.isFinite(Number(value.lastSeenAt)) ? Number(value.lastSeenAt) : Number(value.trustedAt || Date.now())
  };
}

function sanitizeSettings(value = {}) {
  const next = { ...DEFAULT_SETTINGS, ...value };
  if (!["fast", "balanced", "sharp", "battery"].includes(next.qualityDefault)) {
    next.qualityDefault = DEFAULT_SETTINGS.qualityDefault;
  }
  next.inputSensitivityDefault = Math.min(2.5, Math.max(0.35, Number(next.inputSensitivityDefault || 1)));
  next.trustedDevicesEnabled = typeof next.trustedDevicesEnabled === "boolean" ? next.trustedDevicesEnabled : false;
  next.autoStart = typeof next.autoStart === "boolean" ? next.autoStart : DEFAULT_SETTINGS.autoStart;
  const legacyKeys = Array.isArray(next.trustedDeviceKeys)
    ? [...new Set(next.trustedDeviceKeys.filter((item) => typeof item === "string" && item.length > 16))]
    : [];
  const trustedDeviceMap = new Map();
  for (const record of Array.isArray(next.trustedDevices) ? next.trustedDevices : []) {
    const sanitized = sanitizeTrustedDevice(record);
    if (sanitized) trustedDeviceMap.set(sanitized.key, sanitized);
  }
  for (const key of legacyKeys) {
    if (!trustedDeviceMap.has(key)) {
      trustedDeviceMap.set(key, sanitizeTrustedDevice({ key, deviceName: "Trusted phone" }));
    }
  }
  const trustedDevices = [...trustedDeviceMap.values()];
  const trustedDeviceKeys = trustedDevices.map((item) => item.key);
  return {
    qualityDefault: next.qualityDefault,
    inputSensitivityDefault: next.inputSensitivityDefault,
    trustedDevicesEnabled: next.trustedDevicesEnabled,
    autoStart: next.autoStart,
    trustedDeviceKeys,
    trustedDevices
  };
}

function createSettingsStore(filePath = path.join(__dirname, "..", "data", "host-settings.json")) {
  function load() {
    try {
      return sanitizeSettings(JSON.parse(fs.readFileSync(filePath, "utf8")));
    } catch {
      return sanitizeSettings();
    }
  }

  function save(settings) {
    const sanitized = sanitizeSettings(settings);
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, JSON.stringify(sanitized, null, 2));
    return sanitized;
  }

  return { filePath, load, save };
}

module.exports = { DEFAULT_SETTINGS, createSettingsStore, sanitizeSettings, sanitizeTrustedDevice };

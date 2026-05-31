"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const { createSettingsStore, sanitizeSettings } = require("../src/settings-store");

test("settings store persists sanitized daily-use settings", () => {
  const filePath = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "remote-settings-")), "settings.json");
  const store = createSettingsStore(filePath);

  const saved = store.save({
    qualityDefault: "sharp",
    inputSensitivityDefault: 99,
    trustedDevicesEnabled: true,
    autoStart: true,
    trustedDeviceKeys: ["short", "abcdefghijklmnopqrstuvwxyz123456"],
    trustedDevices: [{
      key: "abcdefghijklmnopqrstuvwxyz123456",
      deviceName: "Pixel",
      remoteAddress: "192.168.1.10",
      trustedAt: 1000,
      lastSeenAt: 2000
    }]
  });

  assert.equal(saved.qualityDefault, "sharp");
  assert.equal(saved.inputSensitivityDefault, 2.5);
  assert.equal(saved.trustedDevicesEnabled, true);
  assert.equal(saved.autoStart, true);
  assert.deepEqual(saved.trustedDeviceKeys, ["abcdefghijklmnopqrstuvwxyz123456"]);
  assert.deepEqual(saved.trustedDevices, [{
    key: "abcdefghijklmnopqrstuvwxyz123456",
    deviceName: "Pixel",
    remoteAddress: "192.168.1.10",
    trustedAt: 1000,
    lastSeenAt: 2000
  }]);
  assert.deepEqual(store.load(), saved);
});

test("invalid settings fall back to conservative defaults", () => {
  const sanitized = sanitizeSettings({
    qualityDefault: "ultra",
    inputSensitivityDefault: -3,
    trustedDevicesEnabled: "yes",
    trustedDeviceKeys: "bad"
  });

  assert.equal(sanitized.qualityDefault, "fast");
  assert.equal(sanitized.inputSensitivityDefault, 0.35);
  assert.equal(sanitized.trustedDevicesEnabled, false);
  assert.equal(sanitized.autoStart, true);
  assert.deepEqual(sanitized.trustedDeviceKeys, []);
  assert.deepEqual(sanitized.trustedDevices, []);
});

"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  buildElectronCaptureArgs,
  buildElectronProfileDir,
  selectElectronDesktopSource
} = require("../src/electron-capture-launcher");

test("electron desktop source selector matches a monitor by display bounds", () => {
  const sources = [
    { id: "screen:103:0", name: "Screen 1", display_id: "103" },
    { id: "screen:204:0", name: "Screen 2", display_id: "204" }
  ];
  const displays = [
    { id: 103, bounds: { x: 1920, y: 0, width: 1920, height: 1080 } },
    { id: 204, bounds: { x: -1920, y: 139, width: 1920, height: 1080 } }
  ];

  const selected = selectElectronDesktopSource({
    sources,
    displays,
    monitor: {
      id: "display-2",
      name: "Display 2",
      sourceId: "\\\\.\\DISPLAY2",
      bounds: { left: -1920, top: 139, width: 1920, height: 1080 }
    },
    requestedSourceName: "Screen 2"
  });

  assert.equal(selected.id, "screen:204:0");
  assert.equal(selected.matchReason, "display-bounds");
});

test("electron desktop source selector falls back to source name when bounds are unavailable", () => {
  const selected = selectElectronDesktopSource({
    sources: [
      { id: "screen:1:0", name: "Screen 1", display_id: "1" },
      { id: "screen:2:0", name: "Screen 2", display_id: "2" }
    ],
    displays: [],
    monitor: { id: "display-2", sourceId: "\\\\.\\DISPLAY2" },
    requestedSourceName: "Screen 2"
  });

  assert.equal(selected.id, "screen:2:0");
  assert.equal(selected.matchReason, "source-name");
});

test("electron capture launcher args carry monitor identity and bounds", () => {
  const args = buildElectronCaptureArgs({
    appPath: "C:\\repo\\src\\electron-capture-main.js",
    hostUrl: "http://127.0.0.1:4334",
    hostKey: "host-key",
    monitor: {
      id: "display-3",
      name: "Display 3",
      sourceId: "\\\\.\\DISPLAY3",
      bounds: { left: 0, top: 0, width: 1920, height: 1080 }
    },
    requestedSourceName: "Screen 3"
  });

  assert.equal(args[0], "C:\\repo\\src\\electron-capture-main.js");
  assert.equal(args.includes("--monitor-id=display-3"), true);
  assert.equal(args.includes("--host-url=http://127.0.0.1:4334"), true);
  assert.equal(args.includes("--host-key=host-key"), true);
  assert.equal(args.includes("--source-name=Screen 3"), true);
  assert.equal(args.some((arg) => arg.startsWith("--monitor-bounds=")), true);
});

test("electron capture profiles are isolated per monitor with safe folder names", () => {
  const first = buildElectronProfileDir({
    repoRoot: "C:\\repo",
    monitorId: "display-1"
  });
  const second = buildElectronProfileDir({
    repoRoot: "C:\\repo",
    monitorId: "display:2/side"
  });

  assert.equal(first, "C:\\repo\\data\\electron-capture-profile-display-1");
  assert.equal(second, "C:\\repo\\data\\electron-capture-profile-display-2-side");
  assert.notEqual(first, second);
});

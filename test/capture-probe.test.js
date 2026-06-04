"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  buildPowerShellProbeScript,
  createProbeMarkers,
  showCaptureProbe
} = require("../src/capture-probe");

const monitors = [
  { id: "display-1", sourceId: "\\\\.\\DISPLAY1", name: "Primary" },
  { id: "display-2", sourceId: "\\\\.\\DISPLAY2", name: "External" }
];

test("capture probe creates distinct monitor markers", () => {
  const markers = createProbeMarkers(monitors, "probe-test");

  assert.equal(markers.length, 2);
  assert.equal(markers[0].monitorId, "display-1");
  assert.equal(markers[0].sourceId, "\\\\.\\DISPLAY1");
  assert.equal(markers[0].label, "D1");
  assert.equal(markers[1].monitorId, "display-2");
  assert.equal(markers[1].sourceId, "\\\\.\\DISPLAY2");
  assert.equal(markers[1].label, "D2");
  assert.notEqual(markers[0].color, markers[1].color);
});

test("capture probe PowerShell script carries encoded monitor payload", () => {
  const markers = createProbeMarkers(monitors, "probe-script");
  const script = buildPowerShellProbeScript({ markers, durationMs: 1500 });

  assert.match(script, /FromBase64String/);
  assert.match(script, /System\.Windows\.Forms/);
  assert.match(script, /DeviceName/);
  assert.match(script, /TopMost/);
});

test("capture probe does not spawn marker UI on unsupported platforms", () => {
  let spawned = false;
  const result = showCaptureProbe({
    monitors,
    token: "probe-linux",
    platform: "linux",
    spawnImpl: () => {
      spawned = true;
    }
  });

  assert.equal(result.ok, false);
  assert.equal(result.supported, false);
  assert.equal(result.markers.length, 2);
  assert.equal(spawned, false);
});

test("capture probe spawns a detached marker process on Windows", () => {
  const calls = [];
  const result = showCaptureProbe({
    monitors,
    token: "probe-win",
    platform: "win32",
    spawnImpl: (command, args, options) => {
      calls.push({ command, args, options });
      return { pid: 1234, unref() {} };
    }
  });

  assert.equal(result.ok, true);
  assert.equal(result.supported, true);
  assert.equal(result.pid, 1234);
  assert.equal(calls[0].command, "powershell.exe");
  assert.equal(calls[0].options.detached, true);
  assert.equal(calls[0].options.windowsHide, true);
});

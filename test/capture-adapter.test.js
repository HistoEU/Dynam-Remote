"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  createCaptureDiagnostics,
  normalizeDisplay,
  normalizeRememberedMonitor,
  qualityToIntervalMs
} = require("../src/capture-adapter");
const { nextFrameDelayMs } = require("../src/frame-timing");

test("capture quality presets prioritize responsive phone control", () => {
  assert.equal(qualityToIntervalMs("fast"), 140);
  assert.equal(qualityToIntervalMs("balanced"), 360);
  assert.equal(qualityToIntervalMs("sharp"), 760);
  assert.equal(qualityToIntervalMs("battery"), 1300);
  assert.equal(Math.round(1000 / qualityToIntervalMs("fast")), 7);
});

test("frame scheduler compensates for capture time instead of adding it to the cadence", () => {
  assert.equal(nextFrameDelayMs(140, 55), 85);
  assert.equal(nextFrameDelayMs(140, 220), 24);
  assert.equal(nextFrameDelayMs(360, 90), 270);
});

test("capture diagnostics separate selected input, requested capture, and phone-visible display", () => {
  const monitors = [
    {
      id: "display-1",
      sourceId: "\\\\.\\DISPLAY1",
      name: "Laptop panel",
      bounds: { left: 0, top: 0, width: 1920, height: 1080 },
      scaleFactor: 1.25,
      status: "screen"
    },
    {
      id: "display-2",
      sourceId: "\\\\.\\DISPLAY2",
      name: "Portrait external",
      bounds: { left: 1920, top: -120, width: 1080, height: 1920 },
      scaleFactor: 1,
      status: "screen"
    }
  ];
  const now = 100000;

  const diagnostics = createCaptureDiagnostics({
    monitors,
    selectedMonitorId: "display-2",
    rtcState: {
      hostConnected: true,
      host: {
        capture: {
          sharing: true,
          requestedMonitor: "display-1",
          requestedSource: "Screen 1",
          reportedSource: "monitor",
          width: 1920,
          height: 1080,
          frameRate: 60,
          connectionState: "connected",
          iceConnectionState: "connected",
          firstFrameTimeMs: 318,
          updatedAt: now - 900
        }
      }
    },
    captureLaunch: {
      monitorId: "display-2",
      captureSourceName: "Screen 2",
      autoDetect: { status: "mismatch", reason: "Capture size mismatch.", checkedAt: now - 100 }
    },
    correctionCount: 1,
    now
  });

  assert.equal(diagnostics.selectedInputMonitor.id, "display-2");
  assert.equal(diagnostics.requestedCapture.monitorId, "display-2");
  assert.equal(diagnostics.requestedCapture.sourceName, "Screen 2");
  assert.equal(diagnostics.reportedCapture.monitorId, "display-1");
  assert.equal(diagnostics.reportedCapture.source, "monitor");
  assert.deepEqual(diagnostics.expectedSize, { width: 1080, height: 1920 });
  assert.deepEqual(diagnostics.actualSize, { width: 1920, height: 1080 });
  assert.equal(diagnostics.phoneVisibleDisplay.id, "display-1");
  assert.equal(diagnostics.correction.status, "mismatch");
  assert.equal(diagnostics.correction.count, 1);
  assert.equal(diagnostics.correction.needsManualAction, false);
  assert.deepEqual(diagnostics.divergence.sort(), ["capture-size-mismatch", "requested-monitor-mismatch"]);
});

test("capture diagnostics flag stale RTC capture and manual correction status", () => {
  const monitors = [
    {
      id: "display-1",
      sourceId: "\\\\.\\DISPLAY1",
      name: "Laptop panel",
      bounds: { left: 0, top: 0, width: 1920, height: 1080 },
      scaleFactor: 1,
      status: "screen"
    },
    {
      id: "display-2",
      sourceId: "\\\\.\\DISPLAY2",
      name: "External",
      bounds: { left: 1920, top: 0, width: 1920, height: 1080 },
      scaleFactor: 1,
      status: "remembered"
    }
  ];
  const now = 200000;

  const diagnostics = createCaptureDiagnostics({
    monitors,
    selectedMonitorId: "display-2",
    rtcState: {
      hostConnected: true,
      host: {
        capture: {
          sharing: true,
          requestedMonitor: "display-2",
          requestedSource: "Screen 2",
          reportedSource: "monitor",
          width: 1920,
          height: 1080,
          updatedAt: now - 13000,
          fallbackReason: "capture page disconnected"
        }
      }
    },
    captureLaunch: {
      monitorId: "display-2",
      captureSourceName: "Screen 2",
      autoDetect: { status: "needs-manual-check", reason: "Tried all source candidates.", checkedAt: now - 500 }
    },
    correctionCount: 3,
    now,
    staleAfterMs: 12000
  });

  assert.equal(diagnostics.staleCapture.stale, true);
  assert.equal(diagnostics.staleCapture.ageMs, 13000);
  assert.equal(diagnostics.correction.needsManualAction, true);
  assert.equal(diagnostics.reportedCapture.fallbackReason, "capture page disconnected");
  assert.equal(diagnostics.divergence.includes("stale-rtc-host"), true);
  assert.equal(diagnostics.divergence.includes("selected-monitor-disconnected"), true);
});

test("capture diagnostics reports verified monitor mismatches from video fingerprints", () => {
  const monitors = [
    {
      id: "display-1",
      sourceId: "\\\\.\\DISPLAY1",
      name: "Primary",
      bounds: { left: 0, top: 0, width: 1920, height: 1080 },
      scaleFactor: 1,
      status: "screen"
    },
    {
      id: "display-2",
      sourceId: "\\\\.\\DISPLAY2",
      name: "External",
      bounds: { left: 1920, top: 0, width: 1920, height: 1080 },
      scaleFactor: 1,
      status: "screen"
    }
  ];
  const now = 300000;

  const diagnostics = createCaptureDiagnostics({
    monitors,
    selectedMonitorId: "display-2",
    rtcState: {
      hostConnected: true,
      host: {
        capture: {
          sharing: true,
          requestedMonitor: "display-2",
          requestedSource: "Screen 2",
          reportedSource: "monitor",
          width: 1920,
          height: 1080,
          updatedAt: now - 400,
          verification: {
            status: "mismatch",
            requestedMonitor: "display-2",
            actualMonitorId: "display-1",
            score: 0.91,
            runnerUpMonitorId: "display-2",
            runnerUpScore: 0.54,
            comparedAt: now - 450
          }
        }
      }
    },
    captureLaunch: {
      monitorId: "display-2",
      captureSourceName: "Screen 2",
      autoDetect: { status: "correcting", reason: "Fingerprint matched display-1.", checkedAt: now - 300 }
    },
    correctionCount: 1,
    now
  });

  assert.equal(diagnostics.reportedCapture.verification.status, "mismatch");
  assert.equal(diagnostics.reportedCapture.verification.actualMonitorId, "display-1");
  assert.equal(diagnostics.phoneVisibleDisplay.id, "display-1");
  assert.equal(diagnostics.divergence.includes("capture-fingerprint-mismatch"), true);
});

test("display normalization keeps identical-resolution monitors distinct", () => {
  const left = normalizeDisplay({ id: "\\\\.\\DISPLAY5", name: "\\\\.\\DISPLAY5", left: -1920, top: 0, width: 1920, height: 1080 }, 0);
  const right = normalizeDisplay({ id: "\\\\.\\DISPLAY6", name: "\\\\.\\DISPLAY6", left: 0, top: 0, width: 1920, height: 1080 }, 1);

  assert.equal(left.id, "display-1");
  assert.equal(right.id, "display-2");
  assert.equal(left.sourceId, "\\\\.\\DISPLAY5");
  assert.equal(right.sourceId, "\\\\.\\DISPLAY6");
  assert.notDeepEqual(left.bounds, right.bounds);
  assert.equal(left.name, "Display 1");
  assert.equal(right.name, "Display 2");
});

test("remembered monitors preserve disconnected display identity for reconnect diagnostics", () => {
  const remembered = normalizeRememberedMonitor({
    id: "display-3",
    sourceId: "\\\\.\\DISPLAY3",
    name: "Side monitor",
    bounds: { left: 3840, top: 0, width: 1200, height: 1920 },
    scaleFactor: 1.5,
    primary: false
  });

  assert.equal(remembered.id, "display-3");
  assert.equal(remembered.sourceId, "\\\\.\\DISPLAY3");
  assert.equal(remembered.status, "remembered");
  assert.equal(remembered.orientation, "portrait");
  assert.deepEqual(remembered.logicalBounds, { left: 2560, top: 0, width: 800, height: 1280 });
});

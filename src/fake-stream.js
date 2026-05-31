"use strict";

const { makeMessage } = require("./protocol");

const MONITORS = [
  {
    id: "display-1",
    name: "Primary Display",
    bounds: { left: 0, top: 0, width: 1920, height: 1080 },
    logicalBounds: { left: 0, top: 0, width: 1920, height: 1080 },
    scaleFactor: 1,
    primary: true,
    orientation: "landscape",
    status: "fake"
  },
  {
    id: "display-2",
    name: "Second Display",
    bounds: { left: 1920, top: 0, width: 1600, height: 900 },
    logicalBounds: { left: 1920, top: 0, width: 1600, height: 900 },
    scaleFactor: 1,
    primary: false,
    orientation: "landscape",
    status: "fake"
  }
];

function createFakeFrame({ frameId, monitorId, quality, inputMode }) {
  const monitor = MONITORS.find((item) => item.id === monitorId) || MONITORS[0];
  const t = Date.now();
  const phase = (t / 1000) % 1000;
  return makeMessage("stream.frame", {
    frameId,
    monitorId: monitor.id,
    width: monitor.bounds.width,
    height: monitor.bounds.height,
    monitorGeometry: {
      id: monitor.id,
      name: monitor.name,
      bounds: monitor.bounds,
      logicalBounds: monitor.logicalBounds,
      scaleFactor: monitor.scaleFactor,
      primary: Boolean(monitor.primary),
      orientation: monitor.orientation,
      captureSize: {
        width: monitor.bounds.width,
        height: monitor.bounds.height
      },
      captureMatchesBounds: true
    },
    scaleFactor: monitor.scaleFactor,
    quality,
    inputMode,
    cursor: {
      x: Math.round((Math.sin(phase * 1.4) * 0.35 + 0.5) * monitor.bounds.width),
      y: Math.round((Math.cos(phase * 1.1) * 0.28 + 0.5) * monitor.bounds.height),
      coordinateSpace: "physical-frame",
      visible: true
    },
    windows: [
      { title: "Remote Controller", x: 110, y: 92, width: 760, height: 460, active: true },
      { title: "Diagnostics", x: 940, y: 160, width: 620, height: 360, active: false },
      { title: "Keyboard Test", x: 360, y: 640, width: 720, height: 270, active: false }
    ],
    desktopLabel: `${monitor.name} safe fallback stream`,
    capturedAt: t
  });
}

module.exports = { MONITORS, createFakeFrame };

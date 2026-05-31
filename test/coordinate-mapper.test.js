"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const { mapNormalizedToMonitor, mapRelativeDelta, normalizePoint } = require("../src/coordinate-mapper");

test("normalized direct-touch coordinates map into monitor bounds", () => {
  const monitor = {
    bounds: { left: -1920, top: 120, width: 1920, height: 1080 }
  };

  assert.deepEqual(mapNormalizedToMonitor({ normalizedX: 0, normalizedY: 0 }, monitor), {
    x: -1920,
    y: 120,
    normalizedX: 0,
    normalizedY: 0
  });
  assert.deepEqual(mapNormalizedToMonitor({ normalizedX: 0.5, normalizedY: 0.5 }, monitor), {
    x: -960,
    y: 660,
    normalizedX: 0.5,
    normalizedY: 0.5
  });
  assert.deepEqual(mapNormalizedToMonitor({ normalizedX: 1, normalizedY: 1 }, monitor), {
    x: 0,
    y: 1200,
    normalizedX: 1,
    normalizedY: 1
  });
});

test("coordinate mapper clamps out-of-range phone points", () => {
  assert.deepEqual(normalizePoint({ normalizedX: -2, normalizedY: 4 }), {
    normalizedX: 0,
    normalizedY: 1
  });
  assert.deepEqual(normalizePoint({ normalizedX: "bad", normalizedY: Infinity }), {
    normalizedX: 0.5,
    normalizedY: 0.5
  });
});

test("relative deltas preserve touchpad movement with sensitivity", () => {
  assert.deepEqual(mapRelativeDelta({ dx: 4, dy: -2 }, 1.5), { dx: 6, dy: -3 });
  assert.deepEqual(mapRelativeDelta({ dx: "bad", dy: 2 }, "bad"), { dx: 0, dy: 2 });
});

test("coordinate mapper supports stacked and side-by-side monitor bounds", () => {
  const primary = { id: "primary", bounds: { left: 0, top: 0, width: 2560, height: 1440 } };
  const leftDisplay = { id: "left", bounds: { left: -1920, top: 120, width: 1920, height: 1080 } };
  const stackedDisplay = { id: "stacked", bounds: { left: 400, top: -1200, width: 1600, height: 1200 } };

  assert.deepEqual(mapNormalizedToMonitor({ normalizedX: 0.25, normalizedY: 0.75 }, primary), {
    x: 640,
    y: 1080,
    normalizedX: 0.25,
    normalizedY: 0.75
  });
  assert.deepEqual(mapNormalizedToMonitor({ normalizedX: 0.25, normalizedY: 0.75 }, leftDisplay), {
    x: -1440,
    y: 930,
    normalizedX: 0.25,
    normalizedY: 0.75
  });
  assert.deepEqual(mapNormalizedToMonitor({ normalizedX: 0.25, normalizedY: 0.75 }, stackedDisplay), {
    x: 800,
    y: -300,
    normalizedX: 0.25,
    normalizedY: 0.75
  });
});

test("coordinate mapper handles portrait and differently scaled monitors by physical bounds", () => {
  const portrait = {
    id: "portrait",
    orientation: "portrait",
    scaleFactor: 1.5,
    bounds: { left: 2560, top: -240, width: 1080, height: 1920 }
  };
  const highDpi = {
    id: "high-dpi",
    orientation: "landscape",
    scaleFactor: 2,
    bounds: { left: -3000, top: -900, width: 3000, height: 2000 }
  };

  assert.deepEqual(mapNormalizedToMonitor({ normalizedX: 0.5, normalizedY: 0.25 }, portrait), {
    x: 3100,
    y: 240,
    normalizedX: 0.5,
    normalizedY: 0.25
  });
  assert.deepEqual(mapNormalizedToMonitor({ normalizedX: 0.9, normalizedY: 0.1 }, highDpi), {
    x: -300,
    y: -700,
    normalizedX: 0.9,
    normalizedY: 0.1
  });
});

test("coordinate mapper falls back safely for malformed monitor bounds", () => {
  assert.deepEqual(mapNormalizedToMonitor({ normalizedX: 0.5, normalizedY: 0.5 }, {
    bounds: { left: "bad", top: Infinity, width: 0, height: -100 }
  }), {
    x: 1,
    y: 1,
    normalizedX: 0.5,
    normalizedY: 0.5
  });
});

"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const { qualityToIntervalMs } = require("../src/capture-adapter");
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

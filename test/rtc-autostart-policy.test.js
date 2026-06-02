"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  isRtcCaptureFeatureEnabled,
  shouldAllowRtcCaptureOpen,
  shouldAutoLaunchRtcCapture
} = require("../src/rtc-autostart-policy");

test("RTC capture feature is off by default for the product stream", () => {
  assert.equal(isRtcCaptureFeatureEnabled({ env: {} }), false);
  assert.equal(isRtcCaptureFeatureEnabled({ env: { RTC_FEATURE_ENABLED: "0" } }), false);
  assert.equal(isRtcCaptureFeatureEnabled({ env: { RTC_FEATURE_ENABLED: "1" } }), true);
});

test("RTC capture helper auto-launch needs both feature and autostart flags", () => {
  assert.equal(shouldAutoLaunchRtcCapture({ settings: { autoStart: true }, env: {} }), false);
  assert.equal(shouldAutoLaunchRtcCapture({ settings: { autoStart: true }, env: { RTC_CAPTURE_AUTOSTART: "0" } }), false);
  assert.equal(shouldAutoLaunchRtcCapture({ settings: { autoStart: false }, env: { RTC_FEATURE_ENABLED: "1", RTC_CAPTURE_AUTOSTART: "1" } }), false);
  assert.equal(shouldAutoLaunchRtcCapture({ settings: { autoStart: true }, env: { RTC_CAPTURE_AUTOSTART: "1" } }), false);
  assert.equal(shouldAutoLaunchRtcCapture({ settings: { autoStart: true }, env: { RTC_FEATURE_ENABLED: "1", RTC_CAPTURE_AUTOSTART: "1" } }), true);
});

test("managed RTC capture open is blocked unless the feature is explicitly enabled", () => {
  assert.equal(shouldAllowRtcCaptureOpen({
    autoStartRequested: true,
    settings: { autoStart: true },
    env: {}
  }), false);
  assert.equal(shouldAllowRtcCaptureOpen({
    autoStartRequested: false,
    settings: { autoStart: true },
    env: {}
  }), false);
  assert.equal(shouldAllowRtcCaptureOpen({
    autoStartRequested: true,
    settings: { autoStart: true },
    env: { RTC_FEATURE_ENABLED: "1" }
  }), true);
});

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { shouldAllowRtcCaptureOpen, shouldAutoLaunchRtcCapture } = require("../src/rtc-autostart-policy");

test("RTC capture helper auto-launch is off unless explicitly enabled", () => {
  assert.equal(shouldAutoLaunchRtcCapture({ settings: { autoStart: true }, env: {} }), false);
  assert.equal(shouldAutoLaunchRtcCapture({ settings: { autoStart: true }, env: { RTC_CAPTURE_AUTOSTART: "0" } }), false);
  assert.equal(shouldAutoLaunchRtcCapture({ settings: { autoStart: false }, env: { RTC_CAPTURE_AUTOSTART: "1" } }), false);
  assert.equal(shouldAutoLaunchRtcCapture({ settings: { autoStart: true }, env: { RTC_CAPTURE_AUTOSTART: "1" } }), true);
});

test("managed RTC capture open blocks autostart launches by default", () => {
  assert.equal(shouldAllowRtcCaptureOpen({
    autoStartRequested: true,
    settings: { autoStart: true },
    env: {}
  }), false);
  assert.equal(shouldAllowRtcCaptureOpen({
    autoStartRequested: false,
    settings: { autoStart: true },
    env: {}
  }), true);
  assert.equal(shouldAllowRtcCaptureOpen({
    autoStartRequested: true,
    settings: { autoStart: true },
    env: { RTC_CAPTURE_AUTOSTART: "1" }
  }), true);
});

"use strict";

function shouldAutoLaunchRtcCapture({ settings = {}, env = process.env } = {}) {
  if (!settings.autoStart) return false;
  return env.RTC_CAPTURE_AUTOSTART === "1";
}

function shouldAllowRtcCaptureOpen({ autoStartRequested = false, settings = {}, env = process.env } = {}) {
  if (!autoStartRequested) return true;
  return shouldAutoLaunchRtcCapture({ settings, env });
}

module.exports = { shouldAllowRtcCaptureOpen, shouldAutoLaunchRtcCapture };

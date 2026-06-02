"use strict";

function isRtcCaptureFeatureEnabled({ env = process.env } = {}) {
  return env.RTC_FEATURE_ENABLED === "1";
}

function shouldAutoLaunchRtcCapture({ settings = {}, env = process.env } = {}) {
  if (!isRtcCaptureFeatureEnabled({ env })) return false;
  if (!settings.autoStart) return false;
  return env.RTC_CAPTURE_AUTOSTART === "1";
}

function shouldAllowRtcCaptureOpen({ autoStartRequested = false, settings = {}, env = process.env } = {}) {
  if (!isRtcCaptureFeatureEnabled({ env })) return false;
  return true;
}

module.exports = {
  isRtcCaptureFeatureEnabled,
  shouldAllowRtcCaptureOpen,
  shouldAutoLaunchRtcCapture
};

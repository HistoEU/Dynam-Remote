"use strict";

function nextFrameDelayMs(targetIntervalMs, elapsedMs, minimumDelayMs = 24) {
  const target = Math.max(1, Number(targetIntervalMs) || 1);
  const elapsed = Math.max(0, Number(elapsedMs) || 0);
  const minimum = Math.max(1, Number(minimumDelayMs) || 1);
  return Math.max(minimum, target - elapsed);
}

module.exports = { nextFrameDelayMs };

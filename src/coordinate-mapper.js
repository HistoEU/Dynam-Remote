"use strict";

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function finiteNumber(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function normalizePoint(point = {}) {
  return {
    normalizedX: clamp(finiteNumber(point.normalizedX, 0.5), 0, 1),
    normalizedY: clamp(finiteNumber(point.normalizedY, 0.5), 0, 1)
  };
}

function mapNormalizedToMonitor(point = {}, monitor = null) {
  const bounds = monitor?.bounds || { left: 0, top: 0, width: 1, height: 1 };
  const normalized = normalizePoint(point);
  const left = finiteNumber(bounds.left, 0);
  const top = finiteNumber(bounds.top, 0);
  const width = Math.max(1, finiteNumber(bounds.width, 1));
  const height = Math.max(1, finiteNumber(bounds.height, 1));
  return {
    x: Math.round(left + normalized.normalizedX * width),
    y: Math.round(top + normalized.normalizedY * height),
    normalizedX: normalized.normalizedX,
    normalizedY: normalized.normalizedY
  };
}

function mapRelativeDelta(payload = {}, sensitivity = 1) {
  return {
    dx: finiteNumber(payload.dx, 0) * finiteNumber(sensitivity, 1),
    dy: finiteNumber(payload.dy, 0) * finiteNumber(sensitivity, 1)
  };
}

module.exports = {
  clamp,
  finiteNumber,
  mapNormalizedToMonitor,
  mapRelativeDelta,
  normalizePoint
};

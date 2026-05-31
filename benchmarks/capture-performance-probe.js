"use strict";

const { performance } = require("node:perf_hooks");

const { createCaptureAdapter } = require("../src/capture-adapter");

function readArg(name, fallback = "") {
  const prefix = `--${name}=`;
  const found = process.argv.find((item) => item.startsWith(prefix));
  return found ? found.slice(prefix.length) : fallback;
}

function percentile(values, fraction) {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.min(sorted.length - 1, Math.max(0, Math.ceil(sorted.length * fraction) - 1));
  return sorted[index];
}

function average(values) {
  if (!values.length) return 0;
  return values.reduce((total, item) => total + item, 0) / values.length;
}

function frameBytes(frame = {}) {
  const payload = frame.payload || frame;
  if (Buffer.isBuffer(payload.imageBuffer)) return payload.imageBuffer.length;
  if (typeof payload.imageDataUrl === "string") return Math.round(payload.imageDataUrl.length * 0.75);
  return 0;
}

function summarizeMonitor(monitor = {}) {
  return {
    id: monitor.id || "",
    sourceId: monitor.sourceId || "",
    name: monitor.name || "",
    bounds: monitor.bounds || null,
    logicalBounds: monitor.logicalBounds || null,
    scaleFactor: monitor.scaleFactor || 1,
    primary: Boolean(monitor.primary),
    orientation: monitor.orientation || "",
    status: monitor.status || ""
  };
}

async function main() {
  const samples = Math.max(1, Math.min(120, Number(readArg("samples", "12")) || 12));
  const mode = readArg("mode", process.env.CAPTURE_MODE || "screen");
  const requestedMonitor = readArg("monitor", "");
  const quality = readArg("quality", "fast");
  const events = [];
  const capture = createCaptureAdapter({
    mode,
    log: (event, detail) => events.push({ event, detail })
  });

  if (typeof capture.refreshMonitors === "function") {
    await capture.refreshMonitors();
  }

  const monitors = capture.getMonitors();
  const monitor = monitors.find((item) => item.id === requestedMonitor) || monitors[0];
  const timings = [];
  const bytes = [];
  const sources = new Set();
  const startedAt = performance.now();
  const cpuStart = process.cpuUsage();

  for (let index = 0; index < samples; index += 1) {
    const frameStartedAt = performance.now();
    const frame = await capture.createFrame({
      frameId: index + 1,
      monitorId: monitor?.id || "display-1",
      quality,
      inputMode: "touchpad"
    });
    timings.push(performance.now() - frameStartedAt);
    bytes.push(frameBytes(frame));
    sources.add(frame.payload?.source || frame.source || capture.mode);
    if (frame.payload?.imageBuffer) frame.payload.imageBuffer = null;
    if (frame.imageBuffer) frame.imageBuffer = null;
  }

  const elapsedMs = performance.now() - startedAt;
  const cpu = process.cpuUsage(cpuStart);
  const memory = process.memoryUsage();
  const result = {
    ok: true,
    modeRequested: mode,
    modeObserved: capture.mode,
    monitor: summarizeMonitor(monitor),
    monitorCount: monitors.length,
    samples,
    elapsedMs: Math.round(elapsedMs),
    captureFps: Math.round((samples / Math.max(0.001, elapsedMs / 1000)) * 100) / 100,
    frameTimeMs: {
      average: Math.round(average(timings) * 100) / 100,
      p95: Math.round(percentile(timings, 0.95) * 100) / 100,
      min: Math.round(Math.min(...timings) * 100) / 100,
      max: Math.round(Math.max(...timings) * 100) / 100
    },
    frameBytes: {
      average: Math.round(average(bytes)),
      p95: Math.round(percentile(bytes, 0.95))
    },
    cpuMs: {
      user: Math.round(cpu.user / 1000),
      system: Math.round(cpu.system / 1000)
    },
    memoryBytes: {
      rss: memory.rss,
      heapUsed: memory.heapUsed
    },
    sourceModesObserved: [...sources],
    monitorIdentityStable: monitors.every((item) => item.id && item.bounds?.width && item.bounds?.height),
    cursorComposition: "not-measured-by-this-probe",
    gpu: "not-available-from-node-probe",
    fallbackBehavior: capture.mode === "screen" ? "screen-capture-active" : "safe-fallback-active",
    rawFramesWritten: false,
    events
  };

  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

main().catch((error) => {
  process.stderr.write(`${JSON.stringify({
    ok: false,
    error: error.message,
    rawFramesWritten: false
  }, null, 2)}\n`);
  process.exitCode = 1;
});

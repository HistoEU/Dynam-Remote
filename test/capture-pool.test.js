"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { createCapturePool } = require("../src/capture-pool");

function monitor(id) {
  return {
    id,
    name: id,
    bounds: { left: 0, top: 0, width: 1920, height: 1080 }
  };
}

test("capture pool creates one slot per monitor and marks verified streams usable", () => {
  let now = 1000;
  const pool = createCapturePool({ now: () => now, staleAfterMs: 5000 });
  pool.syncMonitors([monitor("display-1"), monitor("display-2")]);
  pool.markStarting("display-2", { sourceName: "Screen 2", captureUrl: "http://host/rtc?monitor=display-2" });
  pool.markAlive({
    peerId: "peer-2",
    monitorId: "display-2",
    capture: {
      sharing: true,
      requestedMonitor: "display-2",
      requestedSource: "Screen 2",
      verification: {
        status: "matched",
        actualMonitorId: "display-2",
        score: 0.91
      }
    }
  });

  const slot = pool.getSlot("display-2");
  assert.equal(slot.status, "verified");
  assert.equal(slot.peerId, "peer-2");
  assert.equal(slot.usable, true);
  assert.equal(pool.getUsableSlot("display-2").peerId, "peer-2");
});

test("capture pool rejects streams that visually match the wrong monitor", () => {
  const pool = createCapturePool({ now: () => 2000, staleAfterMs: 5000 });
  pool.syncMonitors([monitor("display-1"), monitor("display-2")]);
  pool.markAlive({
    peerId: "peer-wrong",
    monitorId: "display-2",
    capture: {
      sharing: true,
      requestedMonitor: "display-2",
      verification: {
        status: "mismatch",
        actualMonitorId: "display-1",
        score: 0.88
      }
    }
  });

  const slot = pool.getSlot("display-2");
  assert.equal(slot.status, "mismatch");
  assert.equal(slot.usable, false);
  assert.equal(pool.getUsableSlot("display-2"), null);
});

test("capture pool marks verified streams stale after the freshness window", () => {
  let now = 3000;
  const pool = createCapturePool({ now: () => now, staleAfterMs: 1000 });
  pool.syncMonitors([monitor("display-1")]);
  pool.markAlive({
    peerId: "peer-1",
    monitorId: "display-1",
    capture: {
      sharing: true,
      requestedMonitor: "display-1",
      verification: {
        status: "matched",
        actualMonitorId: "display-1"
      }
    }
  });
  assert.equal(pool.getUsableSlot("display-1").peerId, "peer-1");

  now = 5001;
  const stale = pool.getSlot("display-1");
  assert.equal(stale.status, "stale");
  assert.equal(stale.usable, false);
  assert.equal(pool.getUsableSlot("display-1"), null);
});

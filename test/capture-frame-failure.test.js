"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const { createCaptureAdapter } = require("../src/capture-adapter");

test("screen capture failures do not emit fake fallback frames", async () => {
  const events = [];
  const screenshotProvider = async () => {
    throw new Error("capture failed");
  };
  screenshotProvider.listDisplays = async () => [{
    id: "\\\\.\\DISPLAY2",
    name: "\\\\.\\DISPLAY2",
    left: 1920,
    top: 0,
    width: 1920,
    height: 1080
  }];
  const capture = createCaptureAdapter({
    mode: "screen",
    log(event, detail) {
      events.push({ event, detail });
    },
    screenshotProvider
  });

  await assert.rejects(
    capture.createFrame({ frameId: 1, monitorId: "display-1", quality: "fast", inputMode: "touchpad" }),
    /capture failed/
  );
  assert.equal(events.some((entry) => entry.event === "capture.screen.failed"), true);
});

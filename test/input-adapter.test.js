"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const { createInputAdapter } = require("../src/input-adapter");

test("input adapter defaults to dry-run and does not require native input provider", async () => {
  const input = createInputAdapter();
  assert.equal(input.mode, "dry-run");
  assert.equal(input.isEnabled(), false);

  const ack = await input.handle({
    protocolVersion: 1,
    type: "pointer.move",
    sequence: 7,
    timestamp: Date.now(),
    payload: { dx: 10, dy: 4 }
  });

  assert.equal(ack.ackType, "pointer.move");
  assert.equal(ack.dryRun, true);
  assert.equal(ack.realInput, false);
  assert.equal(ack.sequence, 7);
});

test("input adapter tracks and releases held mouse buttons and keys", async () => {
  const calls = [];
  const nativeProvider = {
    Button: { LEFT: "LEFT", RIGHT: "RIGHT" },
    Key: { LeftControl: "LeftControl", LeftShift: "LeftShift", C: "C" },
    mouse: {
      config: {},
      async pressButton(button) {
        calls.push(["mouse.pressButton", button]);
      },
      async releaseButton(button) {
        calls.push(["mouse.releaseButton", button]);
      }
    },
    keyboard: {
      config: {},
      async pressKey(...keys) {
        calls.push(["keyboard.pressKey", ...keys]);
      },
      async releaseKey(...keys) {
        calls.push(["keyboard.releaseKey", ...keys]);
      }
    }
  };
  const input = createInputAdapter({ enabled: true, nativeProvider });

  await input.handle({
    protocolVersion: 1,
    type: "pointer.down",
    sequence: 1,
    timestamp: Date.now(),
    payload: { button: "left" }
  });
  await input.handle({
    protocolVersion: 1,
    type: "keyDown",
    sequence: 2,
    timestamp: Date.now(),
    payload: { key: "Ctrl" }
  });
  await input.handle({
    protocolVersion: 1,
    type: "keyDown",
    sequence: 3,
    timestamp: Date.now(),
    payload: { key: "Shift" }
  });

  assert.deepEqual(input.getHeldState(), {
    buttons: ["LEFT"],
    keys: ["LeftControl", "LeftShift"]
  });

  await input.releaseAll();

  assert.deepEqual(input.getHeldState(), { buttons: [], keys: [] });
  assert.deepEqual(calls, [
    ["mouse.pressButton", "LEFT"],
    ["keyboard.pressKey", "LeftControl"],
    ["keyboard.pressKey", "LeftShift"],
    ["mouse.releaseButton", "LEFT"],
    ["keyboard.releaseKey", "LeftShift"],
    ["keyboard.releaseKey", "LeftControl"]
  ]);
});

test("input adapter removes held keys on explicit keyUp", async () => {
  const calls = [];
  const nativeProvider = {
    Button: { LEFT: "LEFT" },
    Key: { LeftControl: "LeftControl" },
    mouse: { config: {}, async releaseButton() {} },
    keyboard: {
      config: {},
      async pressKey(...keys) {
        calls.push(["keyboard.pressKey", ...keys]);
      },
      async releaseKey(...keys) {
        calls.push(["keyboard.releaseKey", ...keys]);
      }
    }
  };
  const input = createInputAdapter({ enabled: true, nativeProvider });

  await input.handle({
    protocolVersion: 1,
    type: "keyDown",
    sequence: 4,
    timestamp: Date.now(),
    payload: { key: "Ctrl" }
  });
  await input.handle({
    protocolVersion: 1,
    type: "keyUp",
    sequence: 5,
    timestamp: Date.now(),
    payload: { key: "Ctrl" }
  });

  assert.deepEqual(input.getHeldState(), { buttons: [], keys: [] });
  assert.deepEqual(calls, [
    ["keyboard.pressKey", "LeftControl"],
    ["keyboard.releaseKey", "LeftControl"]
  ]);
});

test("input adapter exposes the current cursor position for stream overlays", async () => {
  const nativeProvider = {
    Button: { LEFT: "LEFT" },
    Key: {},
    mouse: {
      config: {},
      async getPosition() {
        return { x: 420.4, y: 260.6 };
      },
      async setPosition() {},
      async releaseButton() {}
    },
    keyboard: { config: {}, async releaseKey() {} }
  };
  const input = createInputAdapter({ enabled: true, nativeProvider });

  const point = await input.getCursorPosition();

  assert.deepEqual(point, { x: 420, y: 261 });
});

test("input adapter maps direct touch into logical coordinates on scaled displays", async () => {
  const positions = [];
  const nativeProvider = {
    Button: { LEFT: "LEFT" },
    Key: {},
    Point: class Point {
      constructor(x, y) {
        this.x = x;
        this.y = y;
      }
    },
    mouse: {
      config: {},
      async getPosition() {
        return { x: 0, y: 0 };
      },
      async setPosition(point) {
        positions.push({ x: point.x, y: point.y });
      },
      async releaseButton() {}
    },
    keyboard: { config: {}, async releaseKey() {} }
  };
  const input = createInputAdapter({ enabled: true, nativeProvider });

  const ack = await input.handle({
    protocolVersion: 1,
    type: "pointer.move",
    sequence: 9,
    timestamp: Date.now(),
    payload: { mode: "direct", normalizedX: 1, normalizedY: 1 }
  }, {
    monitor: {
      bounds: { left: 0, top: 0, width: 2560, height: 1440 },
      scaleFactor: 1.25
    }
  });

  assert.deepEqual(positions.at(-1), { x: 2048, y: 1152 });
  assert.deepEqual(ack.point, { x: 2048, y: 1152 });
});

test("input adapter treats touchpad movement as relative even if visual normalized coordinates are present", async () => {
  const positions = [];
  const nativeProvider = {
    Button: { LEFT: "LEFT" },
    Key: {},
    Point: class Point {
      constructor(x, y) {
        this.x = x;
        this.y = y;
      }
    },
    mouse: {
      config: {},
      async getPosition() {
        return { x: 300, y: 400 };
      },
      async setPosition(point) {
        positions.push({ x: point.x, y: point.y });
      },
      async releaseButton() {}
    },
    keyboard: { config: {}, async releaseKey() {} }
  };
  const input = createInputAdapter({ enabled: true, nativeProvider });

  const ack = await input.handle({
    protocolVersion: 1,
    type: "pointer.move",
    sequence: 10,
    timestamp: Date.now(),
    payload: { mode: "touchpad", dx: 12, dy: -8, normalizedX: 0.5, normalizedY: 0.5 }
  }, {
    monitor: {
      bounds: { left: 0, top: 0, width: 2560, height: 1440 },
      scaleFactor: 1
    }
  });

  assert.deepEqual(positions.at(-1), { x: 312, y: 392 });
  assert.deepEqual(ack.point, { x: 312, y: 392 });
});

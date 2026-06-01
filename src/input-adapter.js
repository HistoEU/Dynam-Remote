"use strict";

const { mapNormalizedToMonitor } = require("./coordinate-mapper");

const KEY_MAP = {
  Esc: "Escape",
  Tab: "Tab",
  Enter: "Return",
  Backspace: "Backspace",
  Delete: "Delete",
  F5: "F5",
  Up: "Up",
  Left: "Left",
  Down: "Down",
  Right: "Right",
  Home: "Home",
  End: "End",
  Ctrl: "LeftControl",
  Alt: "LeftAlt",
  Shift: "LeftShift",
  Win: "LeftWin",
  Screenshot: "Print",
  Print: "Print"
};

const COMBOS = {
  Copy: ["LeftControl", "C"],
  Paste: ["LeftControl", "V"],
  Undo: ["LeftControl", "Z"],
  Redo: ["LeftControl", "Y"],
  Lock: ["LeftWin", "L"]
};

const DIRECT_KEY = {
  A: "a", B: "b", C: "c", D: "d", E: "e", F: "f", G: "g", H: "h", I: "i", J: "j", K: "k", L: "l", M: "m",
  N: "n", O: "o", P: "p", Q: "q", R: "r", S: "s", T: "t", U: "u", V: "v", W: "w", X: "x", Y: "y", Z: "z",
  F1: "f1", F2: "f2", F3: "f3", F4: "f4", F5: "f5", F6: "f6", F7: "f7", F8: "f8", F9: "f9", F10: "f10", F11: "f11", F12: "f12",
  Escape: "escape", Tab: "tab", Return: "return", Enter: "enter", Backspace: "backspace", Delete: "delete",
  Up: "up", Left: "left", Down: "down", Right: "right", Home: "home", End: "end",
  LeftControl: "control", LeftAlt: "alt", LeftShift: "shift", LeftWin: "win", Print: "printscreen"
};

function createDirectLibnutProvider() {
  const { libnut } = require("@nut-tree-fork/libnut/dist/import_libnut");
  const Button = { LEFT: "left", RIGHT: "right", MIDDLE: "middle" };
  class Point {
    constructor(x, y) {
      this.x = x;
      this.y = y;
    }
  }
  return {
    Button,
    Key: DIRECT_KEY,
    Point,
    mouse: {
      config: {},
      async setPosition(point) {
        libnut.moveMouse(Math.round(point.x), Math.round(point.y));
      },
      async getPosition() {
        return libnut.getMousePos();
      },
      async pressButton(button) {
        libnut.mouseToggle("down", button);
      },
      async releaseButton(button) {
        libnut.mouseToggle("up", button);
      },
      async click(button) {
        libnut.mouseClick(button);
      },
      async doubleClick(button) {
        libnut.mouseClick(button, true);
      },
      async scrollDown(amount) {
        libnut.scrollMouse(0, -amount);
      },
      async scrollUp(amount) {
        libnut.scrollMouse(0, amount);
      },
      async scrollRight(amount) {
        libnut.scrollMouse(amount, 0);
      },
      async scrollLeft(amount) {
        libnut.scrollMouse(-amount, 0);
      },
      async releaseButtonSafe(button) {
        try {
          libnut.mouseToggle("up", button);
        } catch {}
      }
    },
    keyboard: {
      config: {},
      async pressKey(...keys) {
        for (const key of keys) libnut.keyToggle(key, "down");
      },
      async releaseKey(...keys) {
        for (const key of keys) libnut.keyToggle(key, "up");
      },
      async type(text) {
        libnut.typeString(text);
      }
    }
  };
}

function createDryRunResult(message, extra = {}) {
  return {
    ackType: message.type,
    dryRun: true,
    realInput: false,
    sequence: message.sequence ?? null,
    ...extra
  };
}

function buttonName(button) {
  if (button === "right") return "RIGHT";
  if (button === "middle") return "MIDDLE";
  return "LEFT";
}

function createInputAdapter({ enabled = false, log = () => {}, nativeProvider = null } = {}) {
  let realEnabled = enabled;
  let nut = nativeProvider;
  let lastPointer = null;
  const pressedButtons = new Set();
  const pressedKeys = new Set();

  function loadNut() {
    if (nut) return nut;
    nut = createDirectLibnutProvider();
    nut.mouse.config.autoDelayMs = 0;
    nut.mouse.config.mouseSpeed = 12000;
    nut.keyboard.config.autoDelayMs = 0;
    return nut;
  }

  function monitorPoint(payload, monitor) {
    const point = mapNormalizedToMonitor(payload, monitor);
    const scale = Number(monitor?.scaleFactor || 1);
    if (!Number.isFinite(scale) || scale <= 1.01 || !monitor?.bounds) return point;
    const bounds = monitor.bounds;
    const logicalBounds = monitor.logicalBounds || {
      left: Number(bounds.left || 0) / scale,
      top: Number(bounds.top || 0) / scale
    };
    const physicalLeft = Number(bounds.left || 0);
    const physicalTop = Number(bounds.top || 0);
    const logicalLeft = Number(logicalBounds.left || 0);
    const logicalTop = Number(logicalBounds.top || 0);
    return {
      x: Math.round(logicalLeft + (point.x - physicalLeft) / scale),
      y: Math.round(logicalTop + (point.y - physicalTop) / scale)
    };
  }

  async function movePointer(payload, monitor) {
    const { mouse, Point } = loadNut();
    if (payload.mode === "direct") {
      const point = monitorPoint(payload, monitor);
      await mouse.setPosition(new Point(point.x, point.y));
      lastPointer = point;
      return point;
    }
    const current = await mouse.getPosition();
    const next = {
      x: Math.round(current.x + Number(payload.dx || 0)),
      y: Math.round(current.y + Number(payload.dy || 0))
    };
    await mouse.setPosition(new Point(next.x, next.y));
    lastPointer = next;
    return next;
  }

  async function centerOnMonitor(monitor) {
    if (!realEnabled) return null;
    const bounds = monitor?.bounds || {};
    const logicalBounds = monitor?.logicalBounds || bounds;
    const scale = Number(monitor?.scaleFactor || 1);
    const safeScale = Number.isFinite(scale) && scale > 0 ? scale : 1;
    const point = {
      x: Math.round(Number(logicalBounds.left || 0) + (Number(bounds.width || logicalBounds.width || 0) / safeScale / 2)),
      y: Math.round(Number(logicalBounds.top || 0) + (Number(bounds.height || logicalBounds.height || 0) / safeScale / 2))
    };
    const { mouse, Point } = loadNut();
    await mouse.setPosition(new Point(point.x, point.y));
    lastPointer = point;
    return point;
  }

  async function getCursorPosition() {
    if (!realEnabled) return lastPointer;
    try {
      const { mouse } = loadNut();
      const point = await mouse.getPosition();
      lastPointer = {
        x: Math.round(point.x),
        y: Math.round(point.y)
      };
      return lastPointer;
    } catch {
      return lastPointer;
    }
  }

  async function tapKey(key) {
    const { keyboard, Key } = loadNut();
    const combo = COMBOS[key];
    if (combo) {
      const keys = combo.map((item) => Key[item]).filter((item) => item !== undefined);
      await keyboard.pressKey(...keys);
      await keyboard.releaseKey(...keys.reverse());
      return;
    }
    const mapped = KEY_MAP[key] || key;
    const keyCode = Key[mapped];
    if (keyCode === undefined) {
      await keyboard.type(String(key).slice(0, 1));
      return;
    }
    await keyboard.pressKey(keyCode);
    await keyboard.releaseKey(keyCode);
  }

  function keyCode(name) {
    const { Key } = loadNut();
    const mapped = KEY_MAP[name] || name;
    return Key[mapped];
  }

  async function pressChord(modifiers, key) {
    const { keyboard } = loadNut();
    const keys = [...(modifiers || []), key].map((item) => keyCode(item)).filter((item) => item !== undefined);
    if (!keys.length) return;
    await keyboard.pressKey(...keys);
    await keyboard.releaseKey(...keys.reverse());
  }

  async function releaseAll() {
    if (!nut) return;
    const { mouse, keyboard, Button } = loadNut();
    for (const name of Array.from(pressedButtons)) {
      await mouse.releaseButton(Button[name]);
      pressedButtons.delete(name);
    }
    for (const code of Array.from(pressedKeys).reverse()) {
      await keyboard.releaseKey(code);
      pressedKeys.delete(code);
    }
  }

  async function handle(message, context = {}) {
    if (!realEnabled) {
      return createDryRunResult(message);
    }
    const payload = message.payload || {};
    const { mouse, keyboard, Button } = loadNut();

    if (message.type === "pointer.move") {
      const point = await movePointer(payload, context.monitor);
      return {
        ackType: message.type,
        dryRun: false,
        realInput: true,
        sequence: message.sequence ?? null,
        point,
        coordinateSpace: "logical-desktop",
        monitorId: context.monitor?.id || null
      };
    }
    if (message.type === "pointer.down") {
      if (payload.mode === "direct") await movePointer(payload, context.monitor);
      const btn = buttonName(payload.button);
      await mouse.pressButton(Button[btn]);
      pressedButtons.add(btn);
      return { ackType: message.type, dryRun: false, realInput: true, sequence: message.sequence ?? null, button: btn };
    }
    if (message.type === "pointer.up") {
      if (payload.mode === "direct") await movePointer(payload, context.monitor);
      const btn = buttonName(payload.button);
      await mouse.releaseButton(Button[btn]);
      pressedButtons.delete(btn);
      return { ackType: message.type, dryRun: false, realInput: true, sequence: message.sequence ?? null, button: btn };
    }
    if (message.type === "pointer.click") {
      await mouse.click(Button[buttonName(payload.button)]);
      return { ackType: message.type, dryRun: false, realInput: true, sequence: message.sequence ?? null };
    }
    if (message.type === "pointer.doubleClick") {
      await mouse.doubleClick(Button[buttonName(payload.button)]);
      return { ackType: message.type, dryRun: false, realInput: true, sequence: message.sequence ?? null };
    }
    if (message.type === "pointer.cancelDrag") {
      await releaseAll();
      return { ackType: message.type, dryRun: false, realInput: true, sequence: message.sequence ?? null };
    }
    if (message.type === "wheel") {
      const y = Number(payload.deltaY || 0);
      const x = Number(payload.deltaX || 0);
      if (y > 0) await mouse.scrollDown(Math.max(1, Math.round(Math.abs(y) / 120)));
      if (y < 0) await mouse.scrollUp(Math.max(1, Math.round(Math.abs(y) / 120)));
      if (x > 0) await mouse.scrollRight(Math.max(1, Math.round(Math.abs(x) / 120)));
      if (x < 0) await mouse.scrollLeft(Math.max(1, Math.round(Math.abs(x) / 120)));
      return { ackType: message.type, dryRun: false, realInput: true, sequence: message.sequence ?? null };
    }
    if (message.type === "key") {
      await tapKey(String(payload.key || ""));
      return { ackType: message.type, dryRun: false, realInput: true, sequence: message.sequence ?? null, key: payload.key };
    }
    if (message.type === "keyDown") {
      const code = keyCode(String(payload.key || ""));
      if (code !== undefined) {
        await keyboard.pressKey(code);
        pressedKeys.add(code);
      }
      return { ackType: message.type, dryRun: false, realInput: true, sequence: message.sequence ?? null, key: payload.key };
    }
    if (message.type === "keyUp") {
      const code = keyCode(String(payload.key || ""));
      if (code !== undefined) {
        await keyboard.releaseKey(code);
        pressedKeys.delete(code);
      }
      return { ackType: message.type, dryRun: false, realInput: true, sequence: message.sequence ?? null, key: payload.key };
    }
    if (message.type === "chord") {
      await pressChord(payload.modifiers || [], String(payload.key || ""));
      return { ackType: message.type, dryRun: false, realInput: true, sequence: message.sequence ?? null };
    }
    if (message.type === "text") {
      await keyboard.type(String(payload.text || "").slice(0, 500));
      return { ackType: message.type, dryRun: false, realInput: true, sequence: message.sequence ?? null };
    }
    if (message.type === "pasteText") {
      await keyboard.type(String(payload.text || "").slice(0, 5000));
      return { ackType: message.type, dryRun: false, realInput: true, sequence: message.sequence ?? null };
    }
    return createDryRunResult(message);
  }

  return {
    get mode() {
      return realEnabled ? "real" : "dry-run";
    },
    isEnabled: () => realEnabled,
    setEnabled(next) {
      realEnabled = Boolean(next);
      log(realEnabled ? "input.real.enabled" : "input.real.disabled");
      if (!realEnabled) return releaseAll();
      loadNut();
      return Promise.resolve();
    },
    releaseAll,
    centerOnMonitor,
    getCursorPosition,
    getHeldState: () => ({
      buttons: [...pressedButtons],
      keys: [...pressedKeys]
    }),
    handle
  };
}

module.exports = { createInputAdapter };

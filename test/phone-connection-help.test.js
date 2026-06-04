"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const { chromium } = require("playwright");

const baseUrl = process.env.BASE_URL || "http://127.0.0.1:4317";

test("phone pairing screen shows actionable connection diagnostics", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    await page.evaluate(() => {
      window.showConnectionHelp({
        code: "NETWORK_UNREACHABLE",
        status: 0,
        message: "Failed to fetch"
      }, "pair");
    });
    await page.waitForSelector("#connectionHelp:not(.hidden)", { timeout: 5000 });
    const helpText = await page.locator("#connectionHelp").innerText();
    assert.match(helpText, /Host not reachable/);
    assert.match(helpText, /same Wi-Fi/i);
    assert.match(helpText, /Tailscale/);
    assert.match(helpText, /port 4317/);
    await page.screenshot({
      path: path.join("output", "playwright", "phone-connection-help-network.png"),
      fullPage: true
    });
  } finally {
    await browser.close();
  }
});

test("phone acceptance mode labels proof gate from run-card URL", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(`${baseUrl}/?acceptance=1&gate=tailscale&step=physical-phone-proof`, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      const sent = [];
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      window.__remoteControllerDebug.state.ws = {
        readyState: WebSocket.OPEN,
        send(value) {
          sent.push(JSON.parse(value));
        }
      };
      document.querySelector('[data-sheet="settingsSheet"]').click();
      while (document.querySelector('#acceptanceChecklistItems input[type="checkbox"]:not(:checked)')) {
        document.querySelector('#acceptanceChecklistItems input[type="checkbox"]:not(:checked)').click();
      }
      const payload = window.__remoteControllerDebug.acceptanceProofPayload();
      window.__remoteControllerDebug.markAcceptanceProof();
      window.__remoteControllerDebug.setAcceptanceProofStatus("Proof marker saved in host logs.", true);
      const checklist = window.__remoteControllerDebug.acceptanceChecklistState();
      return {
        panelHidden: document.getElementById("acceptanceProofPanel").classList.contains("hidden"),
        gateLabel: document.getElementById("acceptanceGateLabel").textContent,
        stepLabel: document.getElementById("acceptanceStepLabel").textContent,
        buttonText: document.getElementById("acceptanceMarkBtn").textContent,
        checklistStatus: document.getElementById("acceptanceChecklistStatus").textContent,
        checklistRequired: checklist.requiredCount,
        checklistPassed: checklist.passedCount,
        checklistComplete: checklist.complete,
        payloadGate: payload.gate,
        payloadStep: payload.step,
        payloadChecklistComplete: payload.checklist.complete,
        payloadChecklistCount: payload.checklist.requiredCount,
        sentType: sent[0]?.type,
        sentGate: sent[0]?.payload?.gate,
        sentChecklistComplete: sent[0]?.payload?.checklist?.complete
      };
    });

    assert.equal(result.panelHidden, false);
    assert.equal(result.gateLabel, "Tailscale proof");
    assert.equal(result.stepLabel, "physical-phone-proof");
    assert.equal(result.buttonText, "Mark Tailscale Proof");
    assert.equal(result.checklistStatus, "9 / 9");
    assert.equal(result.checklistRequired, 9);
    assert.equal(result.checklistPassed, 9);
    assert.equal(result.checklistComplete, true);
    assert.equal(result.payloadGate, "tailscale");
    assert.equal(result.payloadStep, "physical-phone-proof");
    assert.equal(result.payloadChecklistComplete, true);
    assert.equal(result.payloadChecklistCount, 9);
    assert.equal(result.sentType, "acceptance.mark");
    assert.equal(result.sentGate, "tailscale");
    assert.equal(result.sentChecklistComplete, true);
  } finally {
    await browser.close();
  }
});

test("phone acceptance mode blocks proof marker until the checklist is complete", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(`${baseUrl}/?acceptance=1&gate=same-wifi&step=physical-phone-proof`, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      const sent = [];
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      window.__remoteControllerDebug.state.ws = {
        readyState: WebSocket.OPEN,
        send(value) {
          sent.push(JSON.parse(value));
        }
      };
      window.__remoteControllerDebug.updateAcceptanceChecklistUi();
      const before = window.__remoteControllerDebug.acceptanceChecklistState();
      const blocked = window.__remoteControllerDebug.markAcceptanceProof();
      const statusAfterBlocked = document.getElementById("acceptanceMarkStatus").textContent;
      const checklistText = document.getElementById("acceptanceChecklistItems").innerText;
      while (document.querySelector('#acceptanceChecklistItems input[type="checkbox"]:not(:checked)')) {
        document.querySelector('#acceptanceChecklistItems input[type="checkbox"]:not(:checked)').click();
      }
      const after = window.__remoteControllerDebug.acceptanceChecklistState();
      const sentAfterChecklist = window.__remoteControllerDebug.markAcceptanceProof();
      return {
        beforeRequired: before.requiredCount,
        beforePassed: before.passedCount,
        beforeComplete: before.complete,
        checklistText,
        blocked,
        statusAfterBlocked,
        afterPassed: after.passedCount,
        afterComplete: after.complete,
        sentAfterChecklist,
        sentCount: sent.length,
        sentChecklistCount: sent[0]?.payload?.checklist?.requiredCount,
        sentChecklistComplete: sent[0]?.payload?.checklist?.complete
      };
    });

    assert.equal(result.beforeRequired, 13);
    assert.equal(result.beforePassed, 0);
    assert.equal(result.beforeComplete, false);
    assert.match(result.checklistText, /single-tap left click/);
    assert.match(result.checklistText, /double-tap right click/);
    assert.match(result.checklistText, /double-tap drag/);
    assert.equal(result.blocked, false);
    assert.match(result.statusAfterBlocked, /Finish checklist first/);
    assert.equal(result.afterPassed, 13);
    assert.equal(result.afterComplete, true);
    assert.equal(result.sentAfterChecklist, true);
    assert.equal(result.sentCount, 1);
    assert.equal(result.sentChecklistCount, 13);
    assert.equal(result.sentChecklistComplete, true);
  } finally {
    await browser.close();
  }
});

test("phone input coalesces pointer moves but preserves critical command order", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      const sent = [];
      window.__remoteControllerDebug.state.ws = {
        readyState: WebSocket.OPEN,
        send(value) {
          sent.push(JSON.parse(value));
        }
      };
      window.__remoteControllerDebug.send("pointer.move", { dx: 1, dy: 2, normalizedX: 0.1, normalizedY: 0.2 });
      window.__remoteControllerDebug.send("pointer.move", { dx: 3, dy: 4, normalizedX: 0.2, normalizedY: 0.3 });
      window.__remoteControllerDebug.send("pointer.move", { dx: 5, dy: 6, normalizedX: 0.3, normalizedY: 0.4 });
      const beforeCritical = sent.length;
      window.__remoteControllerDebug.send("pointer.click", { button: "left" });
      return {
        beforeCritical,
        sent,
        stats: window.__remoteControllerDebug.state.pointerMoveStats
      };
    });

    assert.equal(result.beforeCritical, 0);
    assert.equal(result.sent.length, 2);
    assert.equal(result.sent[0].type, "pointer.move");
    assert.equal(result.sent[0].payload.dx, 9);
    assert.equal(result.sent[0].payload.dy, 12);
    assert.equal(result.sent[0].payload.normalizedX, 0.3);
    assert.equal(result.sent[0].payload.normalizedY, 0.4);
    assert.equal(result.sent[0].payload.coalescedCount, 3);
    assert.equal(result.sent[1].type, "pointer.click");
    assert.equal(result.stats.queued, 3);
    assert.equal(result.stats.sent, 1);
    assert.equal(result.stats.coalesced, 2);
  } finally {
    await browser.close();
  }
});

test("phone commands use the synced host clock for validation timestamps", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      const sent = [];
      window.__remoteControllerDebug.state.ws = {
        readyState: WebSocket.OPEN,
        send(value) {
          sent.push(JSON.parse(value));
        }
      };
      const phoneNow = Date.now();
      window.__remoteControllerDebug.syncHostClock({ timestamp: phoneNow - 120000 });
      const stampedBeforeSend = window.__remoteControllerDebug.commandTimestamp();
      window.__remoteControllerDebug.send("pointer.click", { button: "left" });
      return {
        phoneNow,
        hostClockSynced: window.__remoteControllerDebug.state.hostClockSynced,
        hostClockOffsetMs: window.__remoteControllerDebug.state.hostClockOffsetMs,
        stampedBeforeSend,
        sentTimestamp: sent[0]?.timestamp,
        sentType: sent[0]?.type
      };
    });

    assert.equal(result.hostClockSynced, true);
    assert.ok(result.hostClockOffsetMs <= -119000);
    assert.ok(result.stampedBeforeSend <= result.phoneNow - 119000);
    assert.equal(result.sentType, "pointer.click");
    assert.ok(result.sentTimestamp <= result.phoneNow - 119000);
  } finally {
    await browser.close();
  }
});

test("phone display gestures zoom and pan the screen without sending laptop input", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const sent = [];
      window.__remoteControllerDebug.state.ws = {
        readyState: WebSocket.OPEN,
        send(value) {
          sent.push(JSON.parse(value));
        }
      };
      window.__remoteControllerDebug.state.frame = {
        width: 1920,
        height: 1080,
        desktopLabel: "Gesture test",
        windows: [],
        cursor: { x: 960, y: 540 }
      };
      const canvas = document.getElementById("streamCanvas");
      const first = { bubbles: true, pointerId: 1, pointerType: "touch", clientX: 130, clientY: 180 };
      const second = { bubbles: true, pointerId: 2, pointerType: "touch", clientX: 260, clientY: 180 };
      canvas.dispatchEvent(new PointerEvent("pointerdown", first));
      canvas.dispatchEvent(new PointerEvent("pointerdown", second));
      canvas.dispatchEvent(new PointerEvent("pointermove", { ...first, clientX: 90, clientY: 180 }));
      canvas.dispatchEvent(new PointerEvent("pointermove", { ...second, clientX: 300, clientY: 180 }));
      canvas.dispatchEvent(new PointerEvent("pointerup", { ...second, clientX: 300, clientY: 180 }));
      const zoomAfterPinch = window.__remoteControllerDebug.state.viewportZoom;
      const panDown = { bubbles: true, pointerId: 1, pointerType: "touch", clientX: 210, clientY: 180 };
      const panMove = { bubbles: true, pointerId: 1, pointerType: "touch", clientX: 160, clientY: 180 };
      canvas.dispatchEvent(new PointerEvent("pointerdown", panDown));
      canvas.dispatchEvent(new PointerEvent("pointermove", panMove));
      canvas.dispatchEvent(new PointerEvent("pointerup", panMove));

      return {
        zoomAfterPinch,
        panX: window.__remoteControllerDebug.state.viewportPanX,
        sent: sent.map((item) => ({ type: item.type, payload: item.payload }))
      };
    });

    assert.ok(result.zoomAfterPinch > 1.2);
    assert.ok(result.panX > 0);
    assert.equal(result.sent.length, 0);
  } finally {
    await browser.close();
  }
});

test("phone display stage can be pushed over black without sending laptop input", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const sent = [];
      window.__remoteControllerDebug.state.ws = {
        readyState: WebSocket.OPEN,
        send(value) {
          sent.push(JSON.parse(value));
        }
      };
      window.__remoteControllerDebug.state.frame = {
        width: 1920,
        height: 1080,
        desktopLabel: "Black stage test",
        windows: [],
        cursor: { x: 960, y: 540, coordinateSpace: "physical-frame", visible: true }
      };
      window.__remoteControllerDebug.resetViewport();
      window.__remoteControllerDebug.drawFrame();
      const canvas = document.getElementById("streamCanvas");
      canvas.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, pointerId: 21, pointerType: "touch", clientX: 110, clientY: 130 }));
      canvas.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, pointerId: 22, pointerType: "touch", clientX: 250, clientY: 130 }));
      canvas.dispatchEvent(new PointerEvent("pointermove", { bubbles: true, pointerId: 21, pointerType: "touch", clientX: 210, clientY: 175 }));
      canvas.dispatchEvent(new PointerEvent("pointermove", { bubbles: true, pointerId: 22, pointerType: "touch", clientX: 350, clientY: 175 }));
      canvas.dispatchEvent(new PointerEvent("pointerup", { bubbles: true, pointerId: 21, pointerType: "touch", clientX: 210, clientY: 175 }));
      canvas.dispatchEvent(new PointerEvent("pointerup", { bubbles: true, pointerId: 22, pointerType: "touch", clientX: 350, clientY: 175 }));
      window.__remoteControllerDebug.drawFrame();

      const snapshot = window.__remoteControllerDebug.displayStageSnapshot();
      const blackPoint = window.__remoteControllerDebug.normalizeCanvasPoint({ x: 6, y: 6 });
      const ctx = canvas.getContext("2d");
      const pixel = [...ctx.getImageData(6, 6, 1, 1).data];
      return {
        snapshot,
        blackPoint,
        pixel,
        sent: sent.map((item) => item.type)
      };
    });

    assert.ok(result.snapshot.stagePanX > 80);
    assert.ok(result.snapshot.stagePanY > 25);
    assert.ok(result.snapshot.stageRect.left > 60);
    assert.ok(result.snapshot.stageRect.top > 20);
    assert.equal(result.blackPoint.insideStage, false);
    assert.deepEqual(result.pixel.slice(0, 3), [0, 0, 0]);
    assert.equal(result.sent.includes("pointer.move"), false);
  } finally {
    await browser.close();
  }
});

test("phone portrait layout exposes a laptop-style touchpad below the monitor", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const sent = [];
      window.__remoteControllerDebug.state.ws = {
        readyState: WebSocket.OPEN,
        send(value) {
          sent.push(JSON.parse(value));
        }
      };
      const pad = document.getElementById("touchpadSurface");
      const rect = pad.getBoundingClientRect();
      const down = { bubbles: true, pointerId: 8, pointerType: "touch", clientX: rect.left + rect.width * 0.42, clientY: rect.top + rect.height * 0.42 };
      const move = { bubbles: true, pointerId: 8, pointerType: "touch", clientX: rect.left + rect.width * 0.58, clientY: rect.top + rect.height * 0.58 };
      pad.dispatchEvent(new PointerEvent("pointerdown", down));
      pad.dispatchEvent(new PointerEvent("pointermove", move));
      window.__remoteControllerDebug.flushPointerMove();
      pad.dispatchEvent(new PointerEvent("pointerup", move));
      const canvasRect = document.getElementById("streamCanvas").getBoundingClientRect();
      const padRect = pad.getBoundingClientRect();
      const railButtons = [...document.querySelectorAll(".control-rail button")].map((button) => {
        const rect = button.getBoundingClientRect();
        return { text: button.textContent.trim(), width: Math.round(rect.width), height: Math.round(rect.height) };
      });
      return {
        canvasTop: canvasRect.top,
        canvasBottom: canvasRect.bottom,
        padTop: padRect.top,
        padHeight: padRect.height,
        padVisible: getComputedStyle(document.getElementById("touchpadArea")).display !== "none",
        clickButtonsVisible: Boolean(document.getElementById("leftClickPadBtn") || document.getElementById("rightClickPadBtn")),
        debugStatusVisible: Boolean(document.getElementById("touchpadStatus")),
        railButtons,
        sent: sent.map((item) => ({ type: item.type, payload: item.payload }))
      };
    });

    assert.equal(result.padVisible, true);
    assert.ok(result.canvasTop > 0);
    assert.ok(result.padTop >= result.canvasBottom - 1);
      const move = result.sent.find((item) => item.type === "pointer.move" && item.payload.source === "touchpad");
      assert.ok(move);
      assert.equal(move.payload.mode, "touchpad");
    assert.ok(move.payload.dx > 0);
    assert.ok(move.payload.dy > 0);
    assert.equal(result.sent.filter((item) => item.type === "pointer.move" && item.payload.source === "touchpad").length, 1);
    assert.equal(result.clickButtonsVisible, false);
    assert.ok(result.padHeight < 330);
    assert.equal(result.debugStatusVisible, false);
    assert.deepEqual(result.railButtons.map((button) => button.text), ["Keys", "Zoom", "Display", "Settings", "Ctrl", "Win", "Codex", "Claude"]);
    assert.ok(Math.max(...result.railButtons.map((button) => button.width)) - Math.min(...result.railButtons.map((button) => button.width)) <= 1);
  } finally {
    await browser.close();
  }
});

test("phone landscape and narrow layouts keep controls out of the screen capture", async () => {
  const browser = await chromium.launch();
  try {
    const checkViewport = async ({ width, height, screenshotName }) => {
      const page = await browser.newPage({
        viewport: { width, height },
        isMobile: true,
        hasTouch: true
      });
      await page.goto(baseUrl, { waitUntil: "load" });
      const result = await page.evaluate(() => {
        document.getElementById("pairing").classList.add("hidden");
        document.getElementById("controller").classList.remove("hidden");
        window.__remoteControllerDebug.state.frame = {
          width: 1920,
          height: 1080,
          desktopLabel: "Layout test",
          windows: [],
          cursor: { x: 960, y: 540, coordinateSpace: "physical-frame", visible: true }
        };
        window.__remoteControllerDebug.handleServerPacket({
          type: "state",
          payload: {
            state: {
              selectedMonitorId: "display-1",
              monitors: [{
                id: "display-1",
                name: "Display 1",
                bounds: { left: 0, top: 0, width: 1920, height: 1080 },
                logicalBounds: { left: 0, top: 0, width: 1920, height: 1080 },
                scaleFactor: 1,
                orientation: "landscape",
                primary: true,
                status: "screen"
              }],
              streamStats: { quality: "fast", fpsTarget: 7, presetFpsTarget: 7, adaptiveMode: "preset" }
            }
          }
        });
        window.__remoteControllerDebug.resetViewport();
        const top = document.querySelector(".top-strip").getBoundingClientRect();
        const canvas = document.getElementById("streamCanvas").getBoundingClientRect();
        const rail = document.querySelector(".control-rail").getBoundingClientRect();
        const touchpad = document.getElementById("touchpadArea").getBoundingClientRect();
        const buttons = [...document.querySelectorAll(".control-rail button")].map((button) => {
          const rect = button.getBoundingClientRect();
          return {
            text: button.textContent.trim(),
            width: rect.width,
            height: rect.height,
            overflows: button.scrollWidth > Math.ceil(button.clientWidth) || button.scrollHeight > Math.ceil(button.clientHeight)
          };
        });
        const touchpadVisible = getComputedStyle(document.getElementById("touchpadArea")).display !== "none";
        const topVisible = getComputedStyle(document.querySelector(".top-strip")).display !== "none";
        return {
          orientation: window.innerWidth > window.innerHeight ? "landscape" : "portrait",
          topVisible,
          topBottom: top.bottom,
          canvasTop: canvas.top,
          canvasBottom: canvas.bottom,
          canvasHeight: canvas.height,
          railTop: rail.top,
          railBottom: rail.bottom,
          railLeft: rail.left,
          canvasRight: canvas.right,
          touchpadLeft: touchpad.left,
          touchpadTop: touchpad.top,
          touchpadBottom: touchpad.bottom,
          touchpadHeight: touchpad.height,
          viewportHeight: window.innerHeight,
          buttons,
          touchpadVisible
        };
      });
      await page.screenshot({
        path: path.join("output", "playwright", screenshotName),
        fullPage: false
      });
      await page.close();
      return result;
    };

    const landscape = await checkViewport({
      width: 844,
      height: 390,
      screenshotName: "phone-landscape-layout-vqa.png"
    });
    const narrow = await checkViewport({
      width: 320,
      height: 740,
      screenshotName: "phone-narrow-layout-vqa.png"
    });

    assert.equal(landscape.orientation, "landscape");
    assert.equal(landscape.topVisible, false);
    assert.equal(landscape.touchpadVisible, true);
    assert.ok(landscape.topBottom <= landscape.canvasTop + 1);
    assert.ok(landscape.canvasRight <= landscape.touchpadLeft + 1);
    assert.ok(landscape.touchpadBottom <= landscape.railTop + 1);
    assert.ok(landscape.railBottom <= landscape.viewportHeight + 1);
    assert.ok(landscape.canvasHeight >= 210);
    assert.ok(landscape.touchpadHeight >= 180);
    assert.equal(landscape.buttons.some((button) => button.overflows), false);

    assert.equal(narrow.orientation, "portrait");
    assert.equal(narrow.topVisible, true);
    assert.equal(narrow.touchpadVisible, true);
    assert.ok(narrow.topBottom <= narrow.canvasTop + 1);
    assert.ok(narrow.canvasBottom <= narrow.railTop + 1);
    assert.ok(narrow.railBottom <= narrow.viewportHeight + 1);
    assert.ok(narrow.canvasHeight >= 170);
    assert.equal(narrow.buttons.some((button) => button.overflows), false);
  } finally {
    await browser.close();
  }
});

test("phone touchpad maps single tap left, double tap right, hold right, and double-tap drag", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const sent = [];
      window.__remoteControllerDebug.state.ws = {
        readyState: WebSocket.OPEN,
        send(value) {
          sent.push(JSON.parse(value));
        }
      };
      const pad = document.getElementById("touchpadSurface");
      const rect = pad.getBoundingClientRect();
      const point = (x, y) => ({
        x: rect.left + rect.width * x,
        y: rect.top + rect.height * y
      });
      const tap = (pointerId, x, y) => {
        const where = point(x, y);
        const event = { bubbles: true, pointerId, pointerType: "touch", clientX: where.x, clientY: where.y };
        pad.dispatchEvent(new PointerEvent("pointerdown", event));
        pad.dispatchEvent(new PointerEvent("pointerup", event));
      };
      tap(30, 0.42, 0.48);
      await new Promise((resolve) => setTimeout(resolve, 310));

      tap(31, 0.46, 0.5);
      await new Promise((resolve) => setTimeout(resolve, 80));
      tap(32, 0.465, 0.505);

      await new Promise((resolve) => setTimeout(resolve, 80));
      const holdPoint = point(0.52, 0.55);
      const hold = { bubbles: true, pointerId: 33, pointerType: "touch", clientX: holdPoint.x, clientY: holdPoint.y };
      pad.dispatchEvent(new PointerEvent("pointerdown", hold));
      await new Promise((resolve) => setTimeout(resolve, 460));
      pad.dispatchEvent(new PointerEvent("pointerup", hold));

      await new Promise((resolve) => setTimeout(resolve, 80));
      tap(34, 0.5, 0.56);
      await new Promise((resolve) => setTimeout(resolve, 80));
      const dragStart = point(0.505, 0.565);
      const dragEnd = point(0.72, 0.59);
      const dragTap = { bubbles: true, pointerId: 35, pointerType: "touch", clientX: dragStart.x, clientY: dragStart.y };
      pad.dispatchEvent(new PointerEvent("pointerdown", dragTap));
      pad.dispatchEvent(new PointerEvent("pointermove", { ...dragTap, clientX: dragEnd.x, clientY: dragEnd.y }));
      pad.dispatchEvent(new PointerEvent("pointerup", { ...dragTap, clientX: dragEnd.x, clientY: dragEnd.y }));

      return sent.map((item) => ({ type: item.type, payload: item.payload }));
    });

    assert.equal(result.some((item) => item.type === "pointer.click" && item.payload.button === "left"), true);
    assert.equal(result.filter((item) => item.type === "pointer.click" && item.payload.button === "right").length >= 2, true);
    assert.equal(result.some((item) => item.type === "pointer.down" && item.payload.source === "touchpad-double-tap-drag"), true);
    assert.equal(result.some((item) => item.type === "pointer.move" && item.payload.dragging === true), true);
    assert.equal(result.some((item) => item.type === "pointer.up" && item.payload.source === "touchpad-drag-end"), true);
  } finally {
    await browser.close();
  }
});

test("phone rail shortcuts open Windows, Codex, and Claude on the laptop", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const sent = await page.evaluate(async () => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const sent = [];
      window.__remoteControllerDebug.state.ws = {
        readyState: WebSocket.OPEN,
        send(value) {
          sent.push(JSON.parse(value));
        }
      };
      document.getElementById("windowsShortcutBtn").click();
      document.getElementById("codexShortcutBtn").click();
      document.getElementById("claudeShortcutBtn").click();
      await new Promise((resolve) => setTimeout(resolve, 540));
      return sent.map((item) => ({ type: item.type, payload: item.payload }));
    });

    assert.equal(sent.some((item) => item.type === "key" && item.payload.key === "Win"), true);
    assert.equal(sent.some((item) => item.type === "chord" && item.payload.key === "S" && item.payload.source === "shortcut-codex"), true);
    assert.equal(sent.some((item) => item.type === "pasteText" && item.payload.text === "Codex"), true);
    assert.equal(sent.some((item) => item.type === "chord" && item.payload.key === "R" && item.payload.source === "shortcut-claude"), true);
    assert.equal(sent.some((item) => item.type === "pasteText" && item.payload.text === "https://claude.ai/new"), true);
    assert.equal(sent.filter((item) => item.type === "key" && item.payload.key === "Enter").length >= 2, true);
  } finally {
    await browser.close();
  }
});

test("phone rail Control button holds and releases Ctrl for clicks and drags", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const sent = [];
      window.__remoteControllerDebug.state.ws = {
        readyState: WebSocket.OPEN,
        send(value) {
          sent.push(JSON.parse(value));
        }
      };
      const button = document.getElementById("controlHoldBtn");
      button.click();
      const pressed = {
        active: button.classList.contains("active"),
        aria: button.getAttribute("aria-pressed"),
        state: window.__remoteControllerDebug.state.controlHoldActive
      };
      window.__remoteControllerDebug.cancelActivePhoneInput("test-cancel");
      return {
        pressed,
        releasedState: window.__remoteControllerDebug.state.controlHoldActive,
        releasedActive: button.classList.contains("active"),
        sent: sent.map((item) => ({ type: item.type, payload: item.payload }))
      };
    });

    assert.equal(result.pressed.active, true);
    assert.equal(result.pressed.aria, "true");
    assert.equal(result.pressed.state, true);
    assert.equal(result.releasedState, false);
    assert.equal(result.releasedActive, false);
    assert.equal(result.sent.some((item) => item.type === "keyDown" && item.payload.key === "Ctrl"), true);
    assert.equal(result.sent.some((item) => item.type === "keyUp" && item.payload.key === "Ctrl"), true);
  } finally {
    await browser.close();
  }
});

test("phone touchpad supports two-finger scrolling and releases active drag on page hide", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const sent = [];
      window.__remoteControllerDebug.state.ws = {
        readyState: WebSocket.OPEN,
        send(value) {
          sent.push(JSON.parse(value));
        }
      };
      window.__remoteControllerDebug.setScrollSpeed(1.5);
      const pad = document.getElementById("touchpadSurface");
      const first = { bubbles: true, pointerId: 101, pointerType: "touch", clientX: 150, clientY: 520 };
      const second = { bubbles: true, pointerId: 102, pointerType: "touch", clientX: 230, clientY: 520 };
      pad.dispatchEvent(new PointerEvent("pointerdown", first));
      pad.dispatchEvent(new PointerEvent("pointerdown", second));
      pad.dispatchEvent(new PointerEvent("pointermove", { ...first, clientY: 490 }));
      pad.dispatchEvent(new PointerEvent("pointermove", { ...second, clientY: 490 }));
      pad.dispatchEvent(new PointerEvent("pointerup", { ...first, clientY: 490 }));
      pad.dispatchEvent(new PointerEvent("pointerup", { ...second, clientY: 490 }));

      await new Promise((resolve) => setTimeout(resolve, 60));
      const rect = pad.getBoundingClientRect();
      const holdY = rect.bottom - 8;
      const holdFirst = { bubbles: true, pointerId: 111, pointerType: "touch", clientX: rect.left + rect.width * 0.42, clientY: holdY };
      const holdSecond = { bubbles: true, pointerId: 112, pointerType: "touch", clientX: rect.left + rect.width * 0.58, clientY: holdY };
      pad.dispatchEvent(new PointerEvent("pointerdown", holdFirst));
      pad.dispatchEvent(new PointerEvent("pointerdown", holdSecond));
      await new Promise((resolve) => setTimeout(resolve, 220));
      pad.dispatchEvent(new PointerEvent("pointerup", holdFirst));
      pad.dispatchEvent(new PointerEvent("pointerup", holdSecond));

      await new Promise((resolve) => setTimeout(resolve, 60));
      const firstTap = { bubbles: true, pointerId: 103, pointerType: "touch", clientX: 192, clientY: 560 };
      pad.dispatchEvent(new PointerEvent("pointerdown", firstTap));
      pad.dispatchEvent(new PointerEvent("pointerup", firstTap));
      await new Promise((resolve) => setTimeout(resolve, 80));
      const dragDown = { bubbles: true, pointerId: 104, pointerType: "touch", clientX: 194, clientY: 562 };
      pad.dispatchEvent(new PointerEvent("pointerdown", dragDown));
      pad.dispatchEvent(new PointerEvent("pointermove", { ...dragDown, clientX: 252 }));
      window.dispatchEvent(new Event("pagehide"));
      window.__remoteControllerDebug.flushPointerMove();

      return sent.map((item) => ({ type: item.type, payload: item.payload }));
    });

    assert.equal(result.some((item) => item.type === "wheel" && item.payload.source === "touchpad-two-finger"), true);
    assert.equal(result.some((item) => item.type === "wheel" && item.payload.deltaY > 0), true);
    assert.equal(result.some((item) => item.type === "wheel" && item.payload.source === "touchpad-two-finger-edge"), true);
    assert.equal(result.some((item) => item.type === "wheel" && item.payload.source === "touchpad-two-finger-edge" && item.payload.deltaY < 0), true);
    assert.equal(result.some((item) => item.type === "pointer.down" && item.payload.source === "touchpad-double-tap-drag"), true);
    assert.equal(result.some((item) => item.type === "pointer.up" && item.payload.source === "touchpad-drag-end"), true);
    assert.equal(result.some((item) => item.type === "session.disconnect" && item.payload.reason === "pagehide"), true);
  } finally {
    await browser.close();
  }
});

test("phone touchpad supports full-range hint movement and edge-hold cursor drift", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const sent = [];
      window.__remoteControllerDebug.state.ws = {
        readyState: WebSocket.OPEN,
        send(value) {
          sent.push(JSON.parse(value));
        }
      };
      window.__remoteControllerDebug.setTouchpadCursorHint(1, 1);
      const bottom = {
        x: window.__remoteControllerDebug.state.touchpadCursorX,
        y: window.__remoteControllerDebug.state.touchpadCursorY
      };
      const pad = document.getElementById("touchpadSurface");
      const rect = pad.getBoundingClientRect();
      const down = {
        bubbles: true,
        pointerId: 17,
        pointerType: "touch",
        clientX: rect.right - 3,
        clientY: rect.bottom - 3
      };
      pad.dispatchEvent(new PointerEvent("pointerdown", down));
      await new Promise((resolve) => setTimeout(resolve, 270));
      pad.dispatchEvent(new PointerEvent("pointerup", down));
      const edgeMoves = sent.filter((item) => item.type === "pointer.move" && item.payload.source === "touchpad-edge-hold");
      return {
        bottom,
        afterRelease: {
          x: window.__remoteControllerDebug.state.touchpadCursorX,
          y: window.__remoteControllerDebug.state.touchpadCursorY,
          returning: document.getElementById("touchpadCursorHint").classList.contains("returning"),
          releaseVfx: pad.classList.contains("release-vfx")
        },
        edgeMoves: edgeMoves.map((item) => item.payload)
      };
    });

    assert.ok(result.bottom.x >= 0.98);
    assert.ok(result.bottom.y >= 0.98);
    assert.ok(result.afterRelease.x > 0.49 && result.afterRelease.x < 0.51);
    assert.ok(result.afterRelease.y > 0.49 && result.afterRelease.y < 0.51);
    assert.equal(result.afterRelease.returning, true);
    assert.equal(result.afterRelease.releaseVfx, true);
    assert.ok(result.edgeMoves.length >= 4);
    assert.ok(result.edgeMoves.some((payload) => payload.dx > 0 && payload.dy > 0));
    assert.ok(result.edgeMoves.every((payload) => Math.abs(payload.dx) < 70 && Math.abs(payload.dy) < 70));
    assert.ok(result.edgeMoves.every((payload) => !("normalizedX" in payload) && !("normalizedY" in payload)));
  } finally {
    await browser.close();
  }
});

test("phone touchpad hint eases toward the finger instead of jumping", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const pad = document.getElementById("touchpadSurface");
      const rect = pad.getBoundingClientRect();
      window.__remoteControllerDebug.setTouchpadCursorHint(0.5, 0.5);
      const down = {
        bubbles: true,
        pointerId: 44,
        pointerType: "touch",
        clientX: rect.left + rect.width * 0.9,
        clientY: rect.top + rect.height * 0.92
      };
      pad.dispatchEvent(new PointerEvent("pointerdown", down));
      const afterDown = {
        x: window.__remoteControllerDebug.state.touchpadCursorX,
        y: window.__remoteControllerDebug.state.touchpadCursorY
      };
      const move = {
        ...down,
        clientX: rect.left + rect.width * 0.91,
        clientY: rect.top + rect.height * 0.94
      };
      pad.dispatchEvent(new PointerEvent("pointermove", move));
      const afterMove = {
        x: window.__remoteControllerDebug.state.touchpadCursorX,
        y: window.__remoteControllerDebug.state.touchpadCursorY
      };
      return { afterDown, afterMove };
    });

    assert.ok(result.afterDown.x > 0.52 && result.afterDown.x < 0.56);
    assert.ok(result.afterDown.y > 0.52 && result.afterDown.y < 0.56);
    assert.ok(result.afterMove.x < 0.62);
    assert.ok(result.afterMove.y < 0.62);
  } finally {
    await browser.close();
  }
});

test("phone touchpad movement curve accelerates fast swipes while preserving precision mode", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const sent = [];
      window.__remoteControllerDebug.state.ws = {
        readyState: WebSocket.OPEN,
        send(value) {
          sent.push(JSON.parse(value));
        }
      };
      window.__remoteControllerDebug.setPointerSensitivity(2);
      const slow = window.__remoteControllerDebug.touchpadAcceleration(10, 0, 100);
      const fast = window.__remoteControllerDebug.touchpadAcceleration(50, 0, 20);
      const normal = window.__remoteControllerDebug.movementSensitivity();
      window.__remoteControllerDebug.setPointerSensitivity(1);
      window.__remoteControllerDebug.sendTouchpadMove(
        { x: 30, y: 0, width: 300, height: 180, at: 116 },
        { x: 0, y: 0, width: 300, height: 180, at: 100 }
      );
      await new Promise((resolve) => requestAnimationFrame(resolve));
      const virtualMove = sent.find((item) => item.type === "pointer.move")?.payload || null;
      window.__remoteControllerDebug.setPointerSensitivity(2);
      window.__remoteControllerDebug.setPrecisionMode(true);
      const precise = window.__remoteControllerDebug.movementSensitivity();
      return { slow, fast, normal, precise, virtualMove };
    });

    assert.ok(result.slow >= 1);
    assert.ok(result.fast > result.slow);
    assert.ok(result.fast <= 2.45);
    assert.equal(result.normal, 2);
    assert.equal(result.precise, 0.7);
    assert.ok(result.virtualMove.dx > 40);
    assert.equal(result.virtualMove.source, "touchpad");
    assert.equal("normalizedX" in result.virtualMove, false);
    assert.equal("normalizedY" in result.virtualMove, false);
  } finally {
    await browser.close();
  }
});

test("phone updates the display cursor immediately and pans zoomed view toward it", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      window.__remoteControllerDebug.state.monitors = [{
        id: "display-1",
        bounds: { left: 100, top: 200, width: 2560, height: 1440 },
        logicalBounds: { left: 100, top: 200, width: 2560, height: 1440 }
      }];
      window.__remoteControllerDebug.state.selectedMonitorId = "display-1";
      window.__remoteControllerDebug.state.frame = {
        width: 2560,
        height: 1440,
        desktopLabel: "Cursor ack",
        windows: [],
        cursor: { x: 0, y: 0, visible: false }
      };
      window.__remoteControllerDebug.setViewportZoom(2);
      window.__remoteControllerDebug.setViewportPan(0, 0);
      window.__remoteControllerDebug.updateRemoteCursorFromAck({ point: { x: 2400, y: 1300 } });
      return {
        cursor: window.__remoteControllerDebug.state.frame.cursor,
        panX: window.__remoteControllerDebug.state.viewportPanX,
        panY: window.__remoteControllerDebug.state.viewportPanY
      };
    });

    assert.equal(result.cursor.x, 2300);
    assert.equal(result.cursor.y, 1100);
    assert.equal(result.cursor.visible, true);
    assert.equal(result.cursor.source, "ack");
    assert.ok(result.panX > 0.25);
    assert.ok(result.panY > 0.25);
  } finally {
    await browser.close();
  }
});

test("phone display cursor prefers the current stream cursor over movement ack metadata", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const debug = window.__remoteControllerDebug;
      debug.state.monitors = [{
        id: "display-1",
        bounds: { left: 0, top: 0, width: 2560, height: 1440 },
        logicalBounds: { left: 0, top: 0, width: 2048, height: 1152 },
        scaleFactor: 1.25
      }];
      debug.state.selectedMonitorId = "display-1";
      debug.state.frame = {
        width: 2560,
        height: 1440,
        desktopLabel: "Cursor ack",
        windows: [],
        cursor: { x: 0, y: 0, visible: false }
      };
      debug.updateRemoteCursorFromAck({ point: { x: 1800, y: 700 }, coordinateSpace: "logical-desktop" });
      const ackCursor = { ...debug.activeDisplayCursor(debug.state.frame) };
      debug.state.frame = debug.normalizeIncomingFrame({
        width: 2560,
        height: 1440,
        desktopLabel: "Delayed frame cursor",
        windows: [],
        cursor: { x: 80, y: 80, coordinateSpace: "physical-frame", visible: true }
      });
      const activeCursor = debug.activeDisplayCursor(debug.state.frame);
      const streamCursor = debug.state.frame.cursor;
      const snapshot = debug.debugSnapshot();
      return {
        ackCursor,
        activeCursor,
        streamCursor,
        snapshotCursorSource: snapshot.cursorSource,
        snapshotSourceX: snapshot.canvasCursor?.sourceX,
        snapshotSourceY: snapshot.canvasCursor?.sourceY
      };
    });

    assert.equal(result.ackCursor.source, "ack");
    assert.equal(result.activeCursor.source, "frame");
    assert.equal(result.streamCursor.source, "frame");
    assert.equal(result.snapshotCursorSource, "frame");
    assert.equal(result.snapshotSourceX, result.streamCursor.x);
    assert.equal(result.snapshotSourceY, result.streamCursor.y);
  } finally {
    await browser.close();
  }
});

test("phone zoom follow uses fresh pointer ack while RTC video has no native frame", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const debug = window.__remoteControllerDebug;
      debug.state.monitors = [{
        id: "display-2",
        name: "Display 2",
        bounds: { left: 1920, top: 131, width: 1920, height: 1080 },
        logicalBounds: { left: 1920, top: 131, width: 1920, height: 1080 },
        scaleFactor: 1,
        orientation: "landscape",
        status: "screen"
      }];
      debug.state.selectedMonitorId = "display-2";
      debug.state.frame = null;
      debug.state.frameImage = null;
      debug.state.frameImageReady = false;
      debug.state.rtcActive = true;
      debug.state.rtcVideoWidth = 1920;
      debug.state.rtcVideoHeight = 1080;
      debug.setAutoFollowCursor(true);
      debug.setViewportZoom(2);
      debug.updateRemoteCursorFromAck({
        point: { x: 3360, y: 940 },
        coordinateSpace: "logical-desktop"
      });
      const snapshot = debug.debugSnapshot();
      return {
        cursor: debug.activeDisplayCursor(null),
        lastAckCursor: debug.state.lastAckCursor,
        panX: debug.state.viewportPanX,
        panY: debug.state.viewportPanY,
        canvasCursor: snapshot.canvasCursor,
        drawRect: snapshot.drawRect,
        frameSize: snapshot.frameSize,
        rtcVideo: snapshot.rtcVideo
      };
    });

    assert.equal(result.frameSize, null);
    assert.deepEqual(result.rtcVideo, { width: 1920, height: 1080 });
    assert.equal(result.cursor.source, "ack");
    assert.equal(result.lastAckCursor.x, 1440);
    assert.equal(result.lastAckCursor.y, 809);
    assert.ok(result.panX > 0.45);
    assert.ok(result.panY > 0.45);
    assert.ok(result.canvasCursor.x > result.drawRect.x + result.drawRect.width * 0.7);
    assert.ok(result.canvasCursor.y > result.drawRect.y + result.drawRect.height * 0.7);
  } finally {
    await browser.close();
  }
});

test("phone cursor overlay compensates for Windows display scaling and can disable follow mode", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      window.__remoteControllerDebug.state.monitors = [{
        id: "display-1",
        bounds: { left: 0, top: 0, width: 2560, height: 1440 },
        logicalBounds: { left: 0, top: 0, width: 2048, height: 1152 },
        scaleFactor: 1.25
      }];
      window.__remoteControllerDebug.state.selectedMonitorId = "display-1";
      window.__remoteControllerDebug.state.frame = {
        width: 2560,
        height: 1440,
        desktopLabel: "Scaled display",
        windows: [],
        cursor: { x: 0, y: 0, visible: false }
      };
      window.__remoteControllerDebug.setViewportZoom(2);
      window.__remoteControllerDebug.setViewportPan(0, 0);
      window.__remoteControllerDebug.updateRemoteCursorFromAck({ point: { x: 2048, y: 1152 } });
      const scaledCursor = { ...window.__remoteControllerDebug.state.frame.cursor };
      const followedPanY = window.__remoteControllerDebug.state.viewportPanY;
      window.__remoteControllerDebug.setAutoFollowCursor(false);
      window.__remoteControllerDebug.setViewportPan(0, 0);
      window.__remoteControllerDebug.updateRemoteCursorFromAck({ point: { x: 2048, y: 1152 } });
      return {
        scaledCursor,
        followedPanY,
        disabledPanY: window.__remoteControllerDebug.state.viewportPanY,
        followPressed: document.getElementById("followCursorBtn").getAttribute("aria-pressed"),
        checkbox: document.getElementById("autoFollowCursor").checked
      };
    });

    assert.equal(result.scaledCursor.x, 2560);
    assert.equal(result.scaledCursor.y, 1440);
    assert.equal(result.scaledCursor.visible, true);
    assert.equal(result.scaledCursor.source, "ack");
    assert.ok(result.followedPanY > 0.4);
    assert.equal(result.disabledPanY, 0);
    assert.equal(result.followPressed, "false");
    assert.equal(result.checkbox, false);
  } finally {
    await browser.close();
  }
});

test("phone zoom follow centers the free axis and clamps only the true screen edge", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      window.__remoteControllerDebug.state.monitors = [{
        id: "display-1",
        bounds: { left: 0, top: 0, width: 2560, height: 1440 },
        logicalBounds: { left: 0, top: 0, width: 2048, height: 1152 },
        scaleFactor: 1.25
      }];
      window.__remoteControllerDebug.state.selectedMonitorId = "display-1";
      window.__remoteControllerDebug.state.frame = {
        width: 2560,
        height: 1440,
        desktopLabel: "Bottom edge follow",
        windows: [],
        cursor: { x: 1280, y: 1440, coordinateSpace: "physical-frame", visible: true }
      };
      window.__remoteControllerDebug.setAutoFollowCursor(true);
      window.__remoteControllerDebug.setViewportZoom(2);
      const visible = 1 / window.__remoteControllerDebug.state.viewportZoom;
      const panX = window.__remoteControllerDebug.state.viewportPanX;
      const panY = window.__remoteControllerDebug.state.viewportPanY;
      const cursorLocalX = (0.5 - panX) / visible;
      const cursorLocalY = (1 - panY) / visible;
      return {
        zoom: window.__remoteControllerDebug.state.viewportZoom,
        panX,
        panY,
        cursorLocalX,
        cursorLocalY
      };
    });

    assert.equal(result.zoom, 2);
    assert.ok(Math.abs(result.cursorLocalX - 0.5) < 0.01);
    assert.ok(result.cursorLocalY > 0.98);
    assert.ok(result.panY > 0.49);
    assert.ok(result.panY <= 0.5);
  } finally {
    await browser.close();
  }
});

test("phone normalizes scaled stream-frame cursor metadata before drawing", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      window.__remoteControllerDebug.state.monitors = [{
        id: "display-1",
        bounds: { left: 0, top: 0, width: 2560, height: 1440 },
        logicalBounds: { left: 0, top: 0, width: 2048, height: 1152 },
        scaleFactor: 1.25
      }];
      window.__remoteControllerDebug.state.selectedMonitorId = "display-1";
      const frame = window.__remoteControllerDebug.normalizeIncomingFrame({
        monitorId: "display-1",
        width: 2560,
        height: 1440,
        desktopLabel: "Scaled stream cursor",
        windows: [],
        cursor: {
          x: 2048,
          y: 1152,
          coordinateSpace: "logical-monitor",
          visible: true
        }
      });
      window.__remoteControllerDebug.state.frame = frame;
      window.__remoteControllerDebug.setViewportZoom(2);
      window.__remoteControllerDebug.setViewportPan(0, 0);
      window.__remoteControllerDebug.setAutoFollowCursor(true);
      return {
        cursor: frame.cursor,
        normalized: window.__remoteControllerDebug.state.lastCursorMap.output,
        panY: window.__remoteControllerDebug.state.viewportPanY
      };
    });

    assert.equal(result.cursor.x, 2560);
    assert.equal(result.cursor.y, 1440);
    assert.equal(result.cursor.coordinateSpace, "physical-frame");
    assert.equal(result.normalized.normalizedY, 1);
    assert.ok(result.panY > 0.45);
  } finally {
    await browser.close();
  }
});

test("phone monitor selection resets stale zoom and cursor without blanking the last frame", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const sent = [];
      window.__remoteControllerDebug.state.ws = {
        readyState: WebSocket.OPEN,
        send(value) {
          sent.push(JSON.parse(value));
        }
      };
      window.__remoteControllerDebug.state.monitors = [
        {
          id: "display-1",
          name: "Display 1",
          bounds: { left: 0, top: 0, width: 2560, height: 1440 },
          logicalBounds: { left: 0, top: 0, width: 2048, height: 1152 },
          scaleFactor: 1.25,
          orientation: "landscape",
          primary: true,
          status: "screen"
        },
        {
          id: "display-2",
          name: "Display 2",
          bounds: { left: 2560, top: -220, width: 1920, height: 1080 },
          logicalBounds: { left: 2048, top: -220, width: 1920, height: 1080 },
          scaleFactor: 1,
          orientation: "landscape",
          primary: false,
          status: "screen"
        }
      ];
      window.__remoteControllerDebug.state.selectedMonitorId = "display-1";
      window.__remoteControllerDebug.state.frame = {
        frameId: 77,
        monitorId: "display-1",
        width: 2560,
        height: 1440,
        cursor: { x: 2400, y: 1300, coordinateSpace: "physical-frame", visible: true },
        windows: [],
        monitorGeometry: { id: "display-1", captureSize: { width: 2560, height: 1440 } }
      };
      window.__remoteControllerDebug.setViewportZoom(2);
      window.__remoteControllerDebug.setViewportPan(0.4, 0.35);
      window.__remoteControllerDebug.state.lastCursorMap = { stale: true };
      window.__remoteControllerDebug.state.lastCursorLensBox = { stale: true };
      window.__remoteControllerDebug.setTouchpadCursorHint(0.92, 0.87);
      const changed = window.__remoteControllerDebug.selectMonitor("display-2");
      const debug = window.__remoteControllerDebug.debugSnapshot();
      return {
        changed,
        selected: window.__remoteControllerDebug.state.selectedMonitorId,
        zoom: window.__remoteControllerDebug.state.viewportZoom,
        panX: window.__remoteControllerDebug.state.viewportPanX,
        panY: window.__remoteControllerDebug.state.viewportPanY,
        frame: window.__remoteControllerDebug.state.frame,
        cursorMap: window.__remoteControllerDebug.state.lastCursorMap,
        lensBox: window.__remoteControllerDebug.state.lastCursorLensBox,
        touchpadX: window.__remoteControllerDebug.state.touchpadCursorX,
        touchpadY: window.__remoteControllerDebug.state.touchpadCursorY,
        sent: sent.map((item) => ({ type: item.type, payload: item.payload })),
        debugMonitor: debug.selectedMonitor.id,
        debugFrame: debug.frameSize
      };
    });

    assert.equal(result.changed, true);
    assert.equal(result.selected, "display-2");
    assert.equal(result.zoom, 1);
    assert.equal(result.panX, 0);
    assert.equal(result.panY, 0);
    assert.equal(result.frame.frameId, 77);
    assert.equal(result.frame.monitorId, "display-1");
    assert.equal(result.cursorMap, null);
    assert.equal(result.lensBox, null);
    assert.equal(result.touchpadX, 0.5);
    assert.equal(result.touchpadY, 0.5);
    assert.equal(result.sent.some((item) => item.type === "monitor.select" && item.payload.monitorId === "display-2"), true);
    assert.equal(result.debugMonitor, "display-2");
    assert.deepEqual(result.debugFrame, { width: 2560, height: 1440 });
  } finally {
    await browser.close();
  }
});

test("phone monitor selection restarts RTC for the selected display", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const debug = window.__remoteControllerDebug;
      const OriginalWebSocket = window.WebSocket;
      const sent = [];
      const rtcSent = [];
      const opened = [];
      class FakeWebSocket {
        static CONNECTING = OriginalWebSocket.CONNECTING;
        static OPEN = OriginalWebSocket.OPEN;
        static CLOSING = OriginalWebSocket.CLOSING;
        static CLOSED = OriginalWebSocket.CLOSED;

        constructor(url) {
          this.url = String(url);
          this.readyState = FakeWebSocket.CONNECTING;
          this.binaryType = "";
          this.listeners = {};
          opened.push(this.url);
          setTimeout(() => {
            this.readyState = FakeWebSocket.OPEN;
            for (const listener of this.listeners.open || []) listener({ type: "open" });
          }, 0);
        }

        addEventListener(type, listener) {
          this.listeners[type] ||= [];
          this.listeners[type].push(listener);
        }

        send() {}

        close() {
          this.readyState = FakeWebSocket.CLOSED;
          for (const listener of this.listeners.close || []) listener({ type: "close" });
        }
      }
      window.WebSocket = FakeWebSocket;
      try {
        debug.state.token = "token";
        debug.state.approved = true;
        debug.state.connected = true;
        debug.state.ws = {
          readyState: FakeWebSocket.OPEN,
          send(value) {
            sent.push(JSON.parse(value));
          }
        };
        debug.state.rtcWs = {
          readyState: FakeWebSocket.OPEN,
          send(value) {
            rtcSent.push(JSON.parse(value));
          },
          close() {
            rtcSent.push({ type: "closed" });
          }
        };
        debug.state.rtcActive = true;
        debug.state.rtcPc = { close() { rtcSent.push({ type: "pc.closed" }); } };
        debug.state.rtcVideoWidth = 1920;
        debug.state.rtcVideoHeight = 1080;
        debug.state.monitors = [
          {
            id: "display-1",
            name: "Display 1",
            bounds: { left: 0, top: 0, width: 1920, height: 1080 },
            logicalBounds: { left: 0, top: 0, width: 1920, height: 1080 },
            scaleFactor: 1,
            orientation: "landscape",
            primary: true,
            status: "screen"
          },
          {
            id: "display-2",
            name: "Display 2",
            bounds: { left: 1920, top: 0, width: 1920, height: 1080 },
            logicalBounds: { left: 1920, top: 0, width: 1920, height: 1080 },
            scaleFactor: 1,
            orientation: "landscape",
            primary: false,
            status: "screen"
          }
        ];
        debug.state.selectedMonitorId = "display-1";
        const now = performance.now();
        const changed = debug.selectMonitor("display-2");
        const afterSwitch = {
          changed,
          selected: debug.state.selectedMonitorId,
          rtcWs: debug.state.rtcWs,
          rtcPc: debug.state.rtcPc,
          rtcActive: debug.state.rtcActive,
          streamVisible: debug.state.streamVisible,
          blockedForMs: Math.round(Number(debug.state.rtcReconnectSuppressedUntil || 0) - now),
          reconnectScheduled: Boolean(debug.state.rtcReconnectTimer),
          sent: sent.map((item) => ({ type: item.type, payload: item.payload })),
          rtcSent: rtcSent.map((item) => ({ type: item.type, payload: item.payload }))
        };
        await new Promise((resolve) => setTimeout(resolve, 1050));
        return {
          ...afterSwitch,
          opened,
          rtcAfterReconnect: Boolean(debug.state.rtcWs)
        };
      } finally {
        window.WebSocket = OriginalWebSocket;
      }
    });

    assert.equal(result.changed, true);
    assert.equal(result.selected, "display-2");
    assert.equal(result.rtcWs, null);
    assert.equal(result.rtcPc, null);
    assert.equal(result.rtcActive, false);
    assert.equal(result.streamVisible, true);
    assert.ok(result.blockedForMs >= 300);
    assert.ok(result.blockedForMs < 3000);
    assert.equal(result.reconnectScheduled, true);
    assert.equal(result.opened.some((url) => url.includes("/rtc?role=phone")), true);
    assert.equal(result.rtcAfterReconnect, true);
    assert.equal(result.rtcSent.some((item) => item.type === "rtc.stop" && item.payload.reason === "monitor-switch"), true);
    assert.equal(result.sent.some((item) => item.type === "stream.visibility" && item.payload.visible === true), true);
    assert.equal(result.sent.some((item) => item.type === "monitor.select" && item.payload.monitorId === "display-2"), true);
  } finally {
    await browser.close();
  }
});

test("phone starts high-quality RTC video by default", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      const debug = window.__remoteControllerDebug;
      const OriginalWebSocket = window.WebSocket;
      const opened = [];
      class FakeWebSocket {
        static CONNECTING = OriginalWebSocket.CONNECTING;
        static OPEN = OriginalWebSocket.OPEN;
        static CLOSING = OriginalWebSocket.CLOSING;
        static CLOSED = OriginalWebSocket.CLOSED;

        constructor(url) {
          this.url = String(url);
          this.readyState = FakeWebSocket.CONNECTING;
          this.binaryType = "";
          this.listeners = {};
          opened.push(this.url);
          setTimeout(() => {
            this.readyState = FakeWebSocket.OPEN;
            for (const listener of this.listeners.open || []) listener({ type: "open" });
          }, 0);
        }

        addEventListener(type, listener) {
          this.listeners[type] ||= [];
          this.listeners[type].push(listener);
        }

        send() {}

        close() {
          this.readyState = FakeWebSocket.CLOSED;
          for (const listener of this.listeners.close || []) listener({ type: "close" });
        }
      }
      window.WebSocket = FakeWebSocket;
      try {
        debug.state.token = "phone-token";
        debug.state.approved = true;
        debug.connectWebSocket();
        await new Promise((resolve) => setTimeout(resolve, 30));
        return {
          rtcEnabled: debug.shouldUseRtcReceiver(),
          opened
        };
      } finally {
        window.WebSocket = OriginalWebSocket;
      }
    });

    assert.equal(result.rtcEnabled, true);
    assert.equal(result.opened.some((url) => url.includes("/ws?token=")), true);
    assert.equal(result.opened.some((url) => url.includes("/rtc?role=phone")), true);
  } finally {
    await browser.close();
  }
});

test("phone ignores stale server monitor state while a display switch is pending", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const debug = window.__remoteControllerDebug;
      const sent = [];
      const monitors = [
        {
          id: "display-1",
          name: "Display 1",
          bounds: { left: 0, top: 0, width: 1920, height: 1080 },
          logicalBounds: { left: 0, top: 0, width: 1920, height: 1080 },
          scaleFactor: 1,
          orientation: "landscape",
          primary: true,
          status: "screen"
        },
        {
          id: "display-2",
          name: "Display 2",
          bounds: { left: 1920, top: 0, width: 1920, height: 1080 },
          logicalBounds: { left: 1920, top: 0, width: 1920, height: 1080 },
          scaleFactor: 1,
          orientation: "landscape",
          primary: false,
          status: "screen"
        }
      ];
      debug.state.token = "token";
      debug.state.approved = true;
      debug.state.connected = true;
      debug.state.ws = {
        readyState: WebSocket.OPEN,
        send(value) {
          sent.push(JSON.parse(value));
        }
      };
      debug.state.monitors = monitors;
      debug.state.selectedMonitorId = "display-1";
      debug.selectMonitor("display-2");
      const selectedAfterTap = debug.state.selectedMonitorId;
      debug.handleServerPacket({
        type: "state",
        payload: {
          selectedMonitorId: "display-1",
          monitors,
          streamStats: { quality: "fast" }
        }
      });
      const selectedAfterStaleState = debug.state.selectedMonitorId;
      const pendingAfterStaleState = debug.state.pendingMonitorSelectionId;
      debug.handleServerPacket({
        type: "ack",
        payload: {
          ackType: "monitor.select",
          selectedMonitorId: "display-2"
        }
      });
      debug.handleServerPacket({
        type: "state",
        payload: {
          selectedMonitorId: "display-2",
          monitors,
          streamStats: { quality: "fast" }
        }
      });
      return {
        selectedAfterTap,
        selectedAfterStaleState,
        selectedAfterConfirm: debug.state.selectedMonitorId,
        pendingAfterStaleState,
        pendingAfterConfirm: debug.state.pendingMonitorSelectionId,
        monitorSelectSent: sent.some((item) => item.type === "monitor.select" && item.payload.monitorId === "display-2")
      };
    });

    assert.equal(result.selectedAfterTap, "display-2");
    assert.equal(result.selectedAfterStaleState, "display-2");
    assert.equal(result.selectedAfterConfirm, "display-2");
    assert.equal(result.pendingAfterStaleState, "display-2");
    assert.equal(result.pendingAfterConfirm, "");
    assert.equal(result.monitorSelectSent, true);
  } finally {
    await browser.close();
  }
});

test("phone monitor selection briefly pauses RTC before reconnecting to the new capture", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const debug = window.__remoteControllerDebug;
      debug.state.token = "token";
      debug.state.approved = true;
      debug.state.connected = true;
      debug.state.ws = {
        readyState: WebSocket.OPEN,
        send() {}
      };
      debug.state.rtcWs = {
        readyState: WebSocket.OPEN,
        send() {},
        close() {}
      };
      debug.state.rtcActive = true;
      debug.state.rtcPc = { close() {} };
      debug.state.monitors = [
        {
          id: "display-1",
          name: "Display 1",
          bounds: { left: 0, top: 0, width: 1920, height: 1080 },
          logicalBounds: { left: 0, top: 0, width: 1920, height: 1080 },
          scaleFactor: 1,
          orientation: "landscape",
          primary: true,
          status: "screen"
        },
        {
          id: "display-2",
          name: "Display 2",
          bounds: { left: 1920, top: 0, width: 1920, height: 1080 },
          logicalBounds: { left: 1920, top: 0, width: 1920, height: 1080 },
          scaleFactor: 1,
          orientation: "landscape",
          primary: false,
          status: "screen"
        }
      ];
      debug.state.selectedMonitorId = "display-1";
      const now = performance.now();
      debug.selectMonitor("display-2");
      return {
        blockedForMs: Math.round(Number(debug.state.rtcReconnectSuppressedUntil || 0) - now),
        reason: debug.state.rtcReconnectSuppressedReason || "",
        rtcWs: debug.state.rtcWs,
        streamVisible: debug.state.streamVisible,
        reconnectScheduled: Boolean(debug.state.rtcReconnectTimer)
      };
    });

    assert.equal(result.rtcWs, null);
    assert.equal(result.streamVisible, true);
    assert.ok(result.blockedForMs >= 300);
    assert.ok(result.blockedForMs < 3000);
    assert.equal(result.reason, "monitor-switch");
    assert.equal(result.reconnectScheduled, true);
  } finally {
    await browser.close();
  }
});

test("phone monitor selection ack moves the visible cursor to the new display center", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const debug = window.__remoteControllerDebug;
      debug.state.monitors = [{
        id: "display-2",
        name: "Display 2",
        bounds: { left: -1920, top: 139, width: 1920, height: 1080 },
        logicalBounds: { left: -1920, top: 139, width: 1920, height: 1080 },
        scaleFactor: 1,
        orientation: "landscape",
        status: "screen"
      }];
      debug.state.selectedMonitorId = "display-2";
      debug.state.frame = null;
      debug.handleServerPacket({
        type: "ack",
        payload: {
          ackType: "monitor.select",
          centeredPointer: { x: -960, y: 679 },
          coordinateSpace: "logical-desktop"
        }
      });
      return {
        cursor: debug.activeDisplayCursor(null),
        snapshot: debug.debugSnapshot()
      };
    });

    assert.equal(result.cursor.source, "ack");
    assert.equal(result.cursor.x, 960);
    assert.equal(result.cursor.y, 540);
    assert.ok(result.snapshot.canvasCursor.x > result.snapshot.drawRect.x + result.snapshot.drawRect.width * 0.45);
    assert.ok(result.snapshot.canvasCursor.x < result.snapshot.drawRect.x + result.snapshot.drawRect.width * 0.55);
  } finally {
    await browser.close();
  }
});

test("phone wide desktop mode follows the cursor into adjacent monitors without recentering", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      const sent = [];
      const debug = window.__remoteControllerDebug;
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      debug.state.ws = {
        readyState: WebSocket.OPEN,
        send(value) {
          sent.push(JSON.parse(value));
        }
      };
      debug.state.monitors = [
        {
          id: "display-1",
          name: "Display 1",
          bounds: { left: 0, top: 0, width: 1920, height: 1080 },
          logicalBounds: { left: 0, top: 0, width: 1920, height: 1080 },
          scaleFactor: 1
        },
        {
          id: "display-2",
          name: "Display 2",
          bounds: { left: 1920, top: 0, width: 1920, height: 1080 },
          logicalBounds: { left: 1920, top: 0, width: 1920, height: 1080 },
          scaleFactor: 1
        }
      ];
      debug.state.selectedMonitorId = "display-1";
      debug.state.frame = {
        monitorId: "display-1",
        width: 1920,
        height: 1080,
        windows: [],
        cursor: { x: 1912, y: 540, coordinateSpace: "physical-frame", visible: true }
      };
      debug.setWideDesktopMode(true);
      debug.updateRemoteCursorFromAck({
        ackType: "pointer.move",
        point: { x: 1998, y: 540 },
        coordinateSpace: "logical-desktop"
      });
      const monitorSelect = sent.find((item) => item.type === "monitor.select");
      return {
        enabled: debug.state.wideDesktopMode,
        selectedMonitorId: debug.state.selectedMonitorId,
        monitorSelect,
        cursor: debug.state.lastAckCursor
      };
    });

    assert.equal(result.enabled, true);
    assert.equal(result.selectedMonitorId, "display-2");
    assert.equal(result.monitorSelect.payload.monitorId, "display-2");
    assert.equal(result.monitorSelect.payload.centerPointer, false);
    assert.equal(result.monitorSelect.payload.reason, "wide-desktop-cursor");
    assert.equal(result.cursor.source, "ack");
    assert.ok(result.cursor.x < 120);
    assert.equal(result.cursor.y, 540);
  } finally {
    await browser.close();
  }
});

test("phone ignores stale stream frames from the previous monitor after a display switch", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const debug = window.__remoteControllerDebug;
      debug.state.monitors = [
        {
          id: "display-1",
          name: "Display 1",
          bounds: { left: 1920, top: 131, width: 1920, height: 1080 },
          logicalBounds: { left: 1920, top: 131, width: 1920, height: 1080 },
          scaleFactor: 1,
          orientation: "landscape",
          status: "screen"
        },
        {
          id: "display-2",
          name: "Display 2",
          bounds: { left: -1920, top: 139, width: 1920, height: 1080 },
          logicalBounds: { left: -1920, top: 139, width: 1920, height: 1080 },
          scaleFactor: 1,
          orientation: "landscape",
          status: "screen"
        }
      ];
      debug.state.selectedMonitorId = "display-2";
      debug.handleServerPacket({
        type: "stream.frame",
        payload: {
          frameId: 10,
          monitorId: "display-2",
          width: 1920,
          height: 1080,
          cursor: { x: 960, y: 540, visible: true },
          windows: [],
          capturedAt: Date.now()
        }
      });
      const before = {
        frameId: debug.state.frame.frameId,
        monitorId: debug.state.frame.monitorId,
        cursor: debug.activeDisplayCursor(debug.state.frame)
      };
      debug.handleServerPacket({
        type: "stream.frame",
        payload: {
          frameId: 11,
          monitorId: "display-1",
          width: 1920,
          height: 1080,
          cursor: { x: 40, y: 40, visible: true },
          windows: [],
          capturedAt: Date.now()
        }
      });
      return {
        before,
        after: {
          frameId: debug.state.frame.frameId,
          monitorId: debug.state.frame.monitorId,
          cursor: debug.activeDisplayCursor(debug.state.frame)
        }
      };
    });

    assert.equal(result.before.frameId, 10);
    assert.equal(result.after.frameId, 10);
    assert.equal(result.after.monitorId, "display-2");
    assert.equal(result.after.cursor.x, 960);
    assert.equal(result.after.cursor.y, 540);
  } finally {
    await browser.close();
  }
});

test("phone debug snapshot exposes frame geometry, draw rectangle, and canvas cursor", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      window.__remoteControllerDebug.state.monitors = [{
        id: "display-1",
        name: "Display 1",
        bounds: { left: 0, top: 0, width: 2560, height: 1440 },
        logicalBounds: { left: 0, top: 0, width: 2048, height: 1152 },
        scaleFactor: 1.25,
        orientation: "landscape",
        primary: true,
        status: "screen"
      }];
      window.__remoteControllerDebug.state.selectedMonitorId = "display-1";
      window.__remoteControllerDebug.state.frame = window.__remoteControllerDebug.normalizeIncomingFrame({
        frameId: 88,
        monitorId: "display-1",
        width: 2560,
        height: 1440,
        windows: [],
        monitorGeometry: {
          id: "display-1",
          bounds: { left: 0, top: 0, width: 2560, height: 1440 },
          logicalBounds: { left: 0, top: 0, width: 2048, height: 1152 },
          scaleFactor: 1.25,
          captureSize: { width: 2560, height: 1440 },
          captureMatchesBounds: true
        },
        cursor: {
          x: 2048,
          y: 1152,
          coordinateSpace: "logical-monitor",
          physicalX: 2560,
          physicalY: 1440,
          visible: true
        }
      });
      window.__remoteControllerDebug.setViewportZoom(1);
      const debug = window.__remoteControllerDebug.debugSnapshot();
      return {
        frameId: debug.frameId,
        geometry: debug.frameGeometry,
        selectedScale: debug.selectedMonitor.scaleFactor,
        drawRect: debug.drawRect,
        canvasCursor: debug.canvasCursor,
        cursorMap: debug.cursorMap.output
      };
    });

    assert.equal(result.frameId, 88);
    assert.equal(result.geometry.captureMatchesBounds, true);
    assert.equal(result.geometry.captureSize.width, 2560);
    assert.equal(result.selectedScale, 1.25);
    assert.ok(result.drawRect.width > 0);
    assert.ok(result.drawRect.height > 0);
    assert.equal(result.cursorMap.normalizedY, 1);
    assert.ok(result.canvasCursor.x >= result.drawRect.x + result.drawRect.width - 1);
    assert.ok(result.canvasCursor.y >= result.drawRect.y + result.drawRect.height - 1);
  } finally {
    await browser.close();
  }
});

test("phone monitor calibration captures four targets and corrects cursor overlay mapping", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      localStorage.removeItem("remote-monitor-calibrations");
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const debug = window.__remoteControllerDebug;
      debug.state.monitorCalibrations = {};
      debug.state.monitors = [{
        id: "display-1",
        sourceId: "\\\\.\\DISPLAY1",
        bounds: { left: 0, top: 0, width: 1000, height: 500 },
        logicalBounds: { left: 0, top: 0, width: 800, height: 400 },
        scaleFactor: 1.25
      }];
      debug.state.selectedMonitorId = "display-1";
      debug.state.frame = {
        monitorId: "display-1",
        width: 1000,
        height: 500,
        desktopLabel: "Calibration test",
        windows: [],
        monitorGeometry: {
          id: "display-1",
          sourceId: "\\\\.\\DISPLAY1",
          captureSize: { width: 1000, height: 500 },
          logicalBounds: { left: 0, top: 0, width: 800, height: 400 },
          scaleFactor: 1.25
        },
        cursor: { x: 0, y: 0, coordinateSpace: "physical-frame", visible: true }
      };
      const observed = [
        { x: 0.10, y: 0.10 },
        { x: 0.90, y: 0.10 },
        { x: 0.10, y: 0.90 },
        { x: 0.90, y: 0.90 }
      ];
      debug.setCalibrationMode(true);
      for (const point of observed) {
        debug.state.frame.cursor = {
          x: point.x * 1000,
          y: point.y * 500,
          coordinateSpace: "physical-frame",
          visible: true
        };
        debug.captureCalibrationPoint();
      }
      const beforeSaveText = document.getElementById("calibrationCaptureBtn").textContent;
      debug.captureCalibrationPoint();
      const calibration = debug.activeMonitorCalibration();
      const mapped = debug.mapHostCursorToFrame({
        x: 900,
        y: 450,
        coordinateSpace: "physical-frame",
        visible: true
      }, debug.state.monitors[0], debug.state.frame);
      debug.state.frame.cursor = mapped;
      await new Promise((resolve) => requestAnimationFrame(resolve));
      const snapshot = debug.debugSnapshot();
      return {
        beforeSaveText,
        status: document.getElementById("calibrationStatus").textContent,
        calibration,
        mapped,
        snapshotCalibration: snapshot.calibration,
        stored: JSON.parse(localStorage.getItem("remote-monitor-calibrations") || "{}")
      };
    });

    assert.equal(result.beforeSaveText, "Save Calibration");
    assert.match(result.status, /Calibration saved|Calibrated/);
    assert.equal(result.calibration.enabled, true);
    assert.ok(Math.abs(result.calibration.transform.scaleX - 1.15) < 0.02);
    assert.ok(Math.abs(result.calibration.transform.scaleY - 1.1) < 0.02);
    assert.equal(result.mapped.x, 960);
    assert.equal(result.mapped.y, 470);
    assert.equal(result.mapped.normalizedX, 0.96);
    assert.ok(Math.abs(result.mapped.normalizedY - 0.94) < 0.000001);
    assert.equal(result.snapshotCalibration.active.enabled, true);
    assert.equal(Object.keys(result.stored).length, 1);
  } finally {
    await browser.close();
  }
});

test("phone calibration mode samples raw cursor data when an old calibration exists", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      localStorage.removeItem("remote-monitor-calibrations");
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const debug = window.__remoteControllerDebug;
      debug.state.monitorCalibrations = {};
      debug.state.monitors = [{
        id: "display-1",
        sourceId: "\\\\.\\DISPLAY1",
        bounds: { left: 0, top: 0, width: 1000, height: 500 },
        logicalBounds: { left: 0, top: 0, width: 800, height: 400 },
        scaleFactor: 1.25
      }];
      debug.state.selectedMonitorId = "display-1";
      debug.state.frame = {
        monitorId: "display-1",
        width: 1000,
        height: 500,
        desktopLabel: "Recalibration test",
        windows: [],
        monitorGeometry: {
          id: "display-1",
          sourceId: "\\\\.\\DISPLAY1",
          captureSize: { width: 1000, height: 500 },
          logicalBounds: { left: 0, top: 0, width: 800, height: 400 },
          scaleFactor: 1.25
        },
        cursor: { x: 0, y: 0, coordinateSpace: "physical-frame", visible: true }
      };
      const signature = debug.monitorCalibrationSignature();
      debug.state.monitorCalibrations[signature] = {
        id: "old-calibration",
        enabled: true,
        signature,
        transform: { scaleX: 1.2, scaleY: 1.2, offsetX: -0.06, offsetY: -0.06 },
        samples: []
      };
      debug.state.frame.cursor = debug.mapHostCursorToFrame({
        x: 200,
        y: 100,
        coordinateSpace: "physical-frame",
        visible: true
      }, debug.state.monitors[0], debug.state.frame);
      const before = {
        x: debug.state.frame.cursor.x,
        y: debug.state.frame.cursor.y,
        applied: debug.state.lastCursorMap.calibration.applied
      };
      debug.setCalibrationMode(true);
      const afterMode = {
        x: debug.state.frame.cursor.x,
        y: debug.state.frame.cursor.y,
        applied: debug.state.lastCursorMap.calibration.applied
      };
      debug.captureCalibrationPoint();
      return {
        before,
        afterMode,
        sample: debug.state.calibrationSamples[0],
        status: document.getElementById("calibrationStatus").textContent
      };
    });

    assert.equal(result.before.applied, true);
    assert.equal(result.before.x, 180);
    assert.equal(result.before.y, 90);
    assert.equal(result.afterMode.applied, false);
    assert.equal(result.afterMode.x, 200);
    assert.equal(result.afterMode.y, 100);
    assert.ok(Math.abs(result.sample.observedX - 0.2) < 0.000001);
    assert.ok(Math.abs(result.sample.observedY - 0.2) < 0.000001);
    assert.match(result.status, /Aim Top right|Captured Top left/);
  } finally {
    await browser.close();
  }
});

test("phone rescales cursor overlay when decoded bitmap size differs from monitor metadata", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const source = document.createElement("canvas");
      source.width = 320;
      source.height = 180;
      const sourceCtx = source.getContext("2d");
      sourceCtx.fillStyle = "#080604";
      sourceCtx.fillRect(0, 0, 320, 180);
      sourceCtx.fillStyle = "#d6a84a";
      sourceCtx.fillRect(306, 166, 14, 14);
      const dataUrl = source.toDataURL("image/png");
      window.__remoteControllerDebug.state.monitors = [{
        id: "display-1",
        name: "Scaled Capture",
        bounds: { left: 0, top: 0, width: 640, height: 360 },
        logicalBounds: { left: 0, top: 0, width: 640, height: 360 },
        scaleFactor: 1,
        status: "screen"
      }];
      window.__remoteControllerDebug.state.selectedMonitorId = "display-1";
      window.__remoteControllerDebug.handleServerPacket({
        type: "stream.frame",
        payload: {
          frameId: 91,
          monitorId: "display-1",
          width: 640,
          height: 360,
          monitorGeometry: {
            id: "display-1",
            captureSize: { width: 640, height: 360 },
            bounds: { left: 0, top: 0, width: 640, height: 360 },
            logicalBounds: { left: 0, top: 0, width: 640, height: 360 },
            scaleFactor: 1,
            captureMatchesBounds: false
          },
          imageDataUrl: dataUrl,
          windows: [],
          cursor: { x: 640, y: 360, coordinateSpace: "physical-frame", visible: true },
          capturedAt: Date.now()
        }
      });
      await new Promise((resolve) => {
        const started = performance.now();
        const wait = () => {
          if (window.__remoteControllerDebug.state.frameImageReady || performance.now() - started > 2000) {
            resolve();
            return;
          }
          requestAnimationFrame(wait);
        };
        wait();
      });
      const debug = window.__remoteControllerDebug.debugSnapshot();
      return {
        cursor: window.__remoteControllerDebug.state.frame.cursor,
        bitmapSize: debug.bitmapSize,
        drawRect: debug.drawRect,
        canvasCursor: debug.canvasCursor,
        cursorMap: debug.cursorMap
      };
    });

    assert.equal(result.bitmapSize.width, 320);
    assert.equal(result.bitmapSize.height, 180);
    assert.equal(result.cursor.x, 320);
    assert.equal(result.cursor.y, 180);
    assert.equal(result.cursorMap.output.physicalX, 640);
    assert.equal(result.cursorMap.output.physicalY, 360);
    assert.equal(result.cursorMap.output.normalizedY, 1);
    assert.ok(result.canvasCursor.x >= result.drawRect.x + result.drawRect.width - 1);
    assert.ok(result.canvasCursor.y >= result.drawRect.y + result.drawRect.height - 1);
  } finally {
    await browser.close();
  }
});

test("phone follow control auto-zooms and draws a cursor lens", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const source = document.createElement("canvas");
      source.width = 256;
      source.height = 144;
      const srcCtx = source.getContext("2d");
      const gradient = srcCtx.createLinearGradient(0, 0, 256, 144);
      gradient.addColorStop(0, "#111111");
      gradient.addColorStop(1, "#d6a84a");
      srcCtx.fillStyle = gradient;
      srcCtx.fillRect(0, 0, 256, 144);
      srcCtx.fillStyle = "#ffffff";
      srcCtx.fillRect(116, 62, 24, 20);
      const image = new Image();
      const dataUrl = source.toDataURL("image/png");
      await new Promise((resolve) => {
        image.onload = resolve;
        image.src = dataUrl;
      });
      window.__remoteControllerDebug.state.frameImage = image;
      window.__remoteControllerDebug.state.frameImageReady = true;
      window.__remoteControllerDebug.state.monitors = [{
        id: "display-1",
        bounds: { left: 0, top: 0, width: 256, height: 144 },
        logicalBounds: { left: 0, top: 0, width: 256, height: 144 },
        scaleFactor: 1
      }];
      window.__remoteControllerDebug.state.selectedMonitorId = "display-1";
      window.__remoteControllerDebug.state.frame = window.__remoteControllerDebug.normalizeIncomingFrame({
        monitorId: "display-1",
        width: 256,
        height: 144,
        imageDataUrl: dataUrl,
        desktopLabel: "Lens test",
        windows: [],
        cursor: { x: 128, y: 72, coordinateSpace: "physical-frame", visible: true }
      });
      window.__remoteControllerDebug.setViewportZoom(1);
      window.__remoteControllerDebug.setAutoFollowCursor(false);
      document.getElementById("followCursorBtn").click();
      await new Promise((resolve) => requestAnimationFrame(resolve));
      const canvas = document.getElementById("streamCanvas");
      const ctx = canvas.getContext("2d");
      const pixels = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
      let goldPixels = 0;
      for (let i = 0; i < pixels.length; i += 4) {
        if (pixels[i] > 170 && pixels[i + 1] > 120 && pixels[i + 1] < 230 && pixels[i + 2] < 120) goldPixels += 1;
      }
      const on = {
        zoom: window.__remoteControllerDebug.state.viewportZoom,
        follow: window.__remoteControllerDebug.state.autoFollowCursor,
        lens: window.__remoteControllerDebug.state.cursorLensEnabled,
        pressed: document.getElementById("followCursorBtn").getAttribute("aria-pressed"),
        lensBox: window.__remoteControllerDebug.state.lastCursorLensBox,
        goldPixels
      };
      document.getElementById("followCursorBtn").click();
      await new Promise((resolve) => requestAnimationFrame(resolve));
      return {
        ...on,
        off: {
          zoom: window.__remoteControllerDebug.state.viewportZoom,
          follow: window.__remoteControllerDebug.state.autoFollowCursor,
          lens: window.__remoteControllerDebug.state.cursorLensEnabled,
          pressed: document.getElementById("followCursorBtn").getAttribute("aria-pressed"),
          lensBox: window.__remoteControllerDebug.state.lastCursorLensBox,
          checkbox: document.getElementById("cursorLensEnabled").checked
        }
      };
    });

    assert.ok(result.zoom >= 1.69);
    assert.equal(result.follow, true);
    assert.equal(result.lens, true);
    assert.equal(result.pressed, "true");
    assert.ok(Math.abs(result.lensBox.dotX - (result.lensBox.x + result.lensBox.width / 2)) < 0.5);
    assert.ok(Math.abs(result.lensBox.dotY - (result.lensBox.y + result.lensBox.height / 2)) < 0.5);
    assert.ok(Math.abs(result.lensBox.cursorX - (result.lensBox.x + result.lensBox.width / 2)) < 32);
    assert.ok(Math.abs(result.lensBox.cursorY - (result.lensBox.y + result.lensBox.height / 2)) < 32);
    assert.ok(result.goldPixels > 60);
    assert.equal(result.off.zoom, 1);
    assert.equal(result.off.follow, false);
    assert.equal(result.off.lens, false);
    assert.equal(result.off.pressed, "false");
    assert.equal(result.off.lensBox, null);
    assert.equal(result.off.checkbox, false);
  } finally {
    await browser.close();
  }
});

test("phone settings sliders visibly change cursor lens size and magnification", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const source = document.createElement("canvas");
      source.width = 640;
      source.height = 360;
      const srcCtx = source.getContext("2d");
      for (let x = 0; x < source.width; x += 16) {
        for (let y = 0; y < source.height; y += 16) {
          srcCtx.fillStyle = ((x + y) / 16) % 2 === 0 ? "#d6a84a" : "#111111";
          srcCtx.fillRect(x, y, 16, 16);
        }
      }
      srcCtx.fillStyle = "#ffffff";
      srcCtx.fillRect(300, 160, 40, 40);
      const image = new Image();
      const dataUrl = source.toDataURL("image/png");
      await new Promise((resolve) => {
        image.onload = resolve;
        image.src = dataUrl;
      });
      const debug = window.__remoteControllerDebug;
      debug.state.frameImage = image;
      debug.state.frameImageReady = true;
      debug.state.monitors = [{
        id: "display-1",
        bounds: { left: 0, top: 0, width: 640, height: 360 },
        logicalBounds: { left: 0, top: 0, width: 640, height: 360 },
        scaleFactor: 1
      }];
      debug.state.selectedMonitorId = "display-1";
      debug.state.frame = debug.normalizeIncomingFrame({
        monitorId: "display-1",
        width: 640,
        height: 360,
        imageDataUrl: dataUrl,
        cursor: { x: 320, y: 180, coordinateSpace: "physical-frame", visible: true }
      });
      debug.setViewportZoom(1.8);
      debug.setAutoFollowCursor(true);
      debug.setCursorLensEnabled(true);
      debug.setCursorLensSize(0.7);
      debug.setCursorLensZoom(1.2);
      await new Promise((resolve) => requestAnimationFrame(resolve));
      const small = { ...debug.state.lastCursorLensBox };

      document.querySelector('[data-sheet="settingsSheet"]').click();
      const size = document.getElementById("lensSizeRange");
      const zoom = document.getElementById("lensZoomRange");
      size.value = "1.3";
      size.dispatchEvent(new Event("input", { bubbles: true }));
      zoom.value = "4.2";
      zoom.dispatchEvent(new Event("input", { bubbles: true }));
      await new Promise((resolve) => requestAnimationFrame(resolve));
      const large = { ...debug.state.lastCursorLensBox };

      return {
        sizeLabel: document.getElementById("lensSizeValue").textContent,
        zoomLabel: document.getElementById("lensZoomValue").textContent,
        stateSize: debug.state.cursorLensSize,
        stateZoom: debug.state.cursorLensZoom,
        small,
        large
      };
    });

    assert.equal(result.sizeLabel, "130%");
    assert.equal(result.zoomLabel, "420%");
    assert.equal(result.stateSize, 1.3);
    assert.equal(result.stateZoom, 4.2);
    assert.ok(result.large.width > result.small.width * 1.25);
    assert.ok(result.large.height > result.small.height * 1.25);
    assert.ok(result.large.sourceLensW < result.small.sourceLensW * 0.5);
    assert.ok(result.large.sourceLensH < result.small.sourceLensH * 0.6);
  } finally {
    await browser.close();
  }
});

test("phone keeps the last decoded screen visible while the next frame is pending", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const source = document.createElement("canvas");
      source.width = 240;
      source.height = 135;
      const srcCtx = source.getContext("2d");
      srcCtx.fillStyle = "#d6a84a";
      srcCtx.fillRect(0, 0, source.width, source.height);
      srcCtx.fillStyle = "#050403";
      srcCtx.fillRect(80, 36, 80, 60);
      const image = new Image();
      const dataUrl = source.toDataURL("image/png");
      await new Promise((resolve) => {
        image.onload = resolve;
        image.src = dataUrl;
      });
      const debug = window.__remoteControllerDebug;
      debug.state.frameImage = image;
      debug.state.frameImageReady = true;
      debug.state.frame = {
        monitorId: "display-1",
        width: 240,
        height: 135,
        imageDataUrl: dataUrl,
        windows: [],
        cursor: { x: 120, y: 68, coordinateSpace: "physical-frame", visible: true }
      };
      debug.setViewportPan(0, 0);
      debug.state.frameImageReady = false;
      debug.setViewportPan(0, 0);
      await new Promise((resolve) => requestAnimationFrame(resolve));
      const canvas = document.getElementById("streamCanvas");
      const ctx = canvas.getContext("2d");
      const pixels = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
      let goldPixels = 0;
      let blackPixels = 0;
      for (let i = 0; i < pixels.length; i += 4) {
        if (pixels[i] > 170 && pixels[i + 1] > 110 && pixels[i + 1] < 230 && pixels[i + 2] < 130) goldPixels += 1;
        if (pixels[i] < 8 && pixels[i + 1] < 8 && pixels[i + 2] < 8) blackPixels += 1;
      }
      return { goldPixels, blackPixels, totalPixels: pixels.length / 4 };
    });

    assert.ok(result.goldPixels > 1200);
    assert.ok(result.blackPixels < result.totalPixels * 0.75);
  } finally {
    await browser.close();
  }
});

test("phone commits pure black decoded frames so the live stream cannot freeze", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const makeFrame = (fill, accent) => {
        const source = document.createElement("canvas");
        source.width = 240;
        source.height = 135;
        const srcCtx = source.getContext("2d");
        srcCtx.fillStyle = fill;
        srcCtx.fillRect(0, 0, source.width, source.height);
        if (accent) {
          srcCtx.fillStyle = accent;
          srcCtx.fillRect(60, 36, 120, 60);
        }
        return source.toDataURL("image/png");
      };
      const good = makeFrame("#d6a84a", "#050403");
      const black = makeFrame("#000000", "");
      const debug = window.__remoteControllerDebug;
      debug.handleServerPacket({
        type: "stream.frame",
        payload: {
          frameId: 101,
          monitorId: "display-1",
          width: 240,
          height: 135,
          imageDataUrl: good,
          windows: [],
          cursor: { x: 120, y: 68, coordinateSpace: "physical-frame", visible: true },
          capturedAt: Date.now()
        }
      });
      await new Promise((resolve) => {
        const started = performance.now();
        const wait = () => {
          if (debug.state.frameImageReady || performance.now() - started > 2000) return resolve();
          requestAnimationFrame(wait);
        };
        wait();
      });
      const sourceBefore = debug.state.frameImageSource;
      debug.handleServerPacket({
        type: "stream.frame",
        payload: {
          frameId: 102,
          monitorId: "display-1",
          width: 240,
          height: 135,
          imageDataUrl: black,
          windows: [],
          cursor: { x: 120, y: 68, coordinateSpace: "physical-frame", visible: true },
          capturedAt: Date.now()
        }
      });
      await new Promise((resolve) => setTimeout(resolve, 220));
      const canvas = document.getElementById("streamCanvas");
      const ctx = canvas.getContext("2d");
      const pixels = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
      let goldPixels = 0;
      let blackPixels = 0;
      for (let i = 0; i < pixels.length; i += 4) {
        if (pixels[i] > 170 && pixels[i + 1] > 110 && pixels[i + 1] < 230 && pixels[i + 2] < 130) goldPixels += 1;
        if (pixels[i] < 8 && pixels[i + 1] < 8 && pixels[i + 2] < 8) blackPixels += 1;
      }
      return {
        sourceBefore,
        sourceAfter: debug.state.frameImageSource,
        skipped: debug.state.skippedBlackFrames,
        errorCode: debug.state.lastError?.code || "",
        frameId: debug.state.frame?.frameId,
        goldPixels,
        blackPixels,
        totalPixels: pixels.length / 4
      };
    });

    assert.notEqual(result.sourceAfter, result.sourceBefore);
    assert.equal(result.skipped, 0);
    assert.notEqual(result.errorCode, "BLANK_FRAME_SKIPPED");
    assert.equal(result.frameId, 102);
    assert.ok(result.blackPixels > result.totalPixels * 0.45);
  } finally {
    await browser.close();
  }
});

test("phone accepts very dark but valid desktop frames instead of freezing the old screen", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      const debug = window.__remoteControllerDebug;
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const makeFrame = (background, text) => {
        const source = document.createElement("canvas");
        source.width = 320;
        source.height = 180;
        const sourceCtx = source.getContext("2d");
        sourceCtx.fillStyle = background;
        sourceCtx.fillRect(0, 0, source.width, source.height);
        sourceCtx.fillStyle = "#272727";
        sourceCtx.fillRect(20, 24, 250, 54);
        sourceCtx.fillStyle = "#3a3a3a";
        sourceCtx.font = "12px sans-serif";
        sourceCtx.fillText(text, 28, 56);
        return source.toDataURL("image/png");
      };
      const first = makeFrame("#111111", "first dark frame");
      const second = makeFrame("#050505", "valid dark update");
      debug.handleServerPacket({
        type: "stream.frame",
        payload: {
          frameId: 201,
          width: 320,
          height: 180,
          imageDataUrl: first,
          windows: [],
          desktopLabel: "Dark frame one",
          cursor: { x: 120, y: 68, coordinateSpace: "physical-frame", visible: true },
          capturedAt: Date.now()
        }
      });
      await new Promise((resolve) => {
        const started = performance.now();
        const tick = () => {
          if (debug.state.frameImageReady || performance.now() - started > 2000) return resolve();
          requestAnimationFrame(tick);
        };
        tick();
      });
      debug.handleServerPacket({
        type: "stream.frame",
        payload: {
          frameId: 202,
          width: 320,
          height: 180,
          imageDataUrl: second,
          windows: [],
          desktopLabel: "Dark frame two",
          cursor: { x: 124, y: 70, coordinateSpace: "physical-frame", visible: true },
          capturedAt: Date.now()
        }
      });
      await new Promise((resolve) => {
        const started = performance.now();
        const tick = () => {
          if (debug.state.frameImageSource === second || performance.now() - started > 2000) return resolve();
          requestAnimationFrame(tick);
        };
        tick();
      });
      return {
        frameId: debug.state.frame?.frameId,
        sourceIsSecond: debug.state.frameImageSource === second,
        skipped: debug.state.skippedBlackFrames,
        lastError: debug.state.lastError?.code || null
      };
    });

    assert.equal(result.frameId, 202);
    assert.equal(result.sourceIsSecond, true);
    assert.equal(result.skipped, 0);
    assert.notEqual(result.lastError, "BLANK_FRAME_SKIPPED");
  } finally {
    await browser.close();
  }
});

test("phone cursor lens keeps the gold cursor centered at bottom-right frame edge", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const source = document.createElement("canvas");
      source.width = 320;
      source.height = 180;
      const srcCtx = source.getContext("2d");
      srcCtx.fillStyle = "#050403";
      srcCtx.fillRect(0, 0, 320, 180);
      srcCtx.fillStyle = "#d6a84a";
      srcCtx.fillRect(304, 164, 16, 16);
      const image = new Image();
      const dataUrl = source.toDataURL("image/png");
      await new Promise((resolve) => {
        image.onload = resolve;
        image.src = dataUrl;
      });
      window.__remoteControllerDebug.state.frameImage = image;
      window.__remoteControllerDebug.state.frameImageReady = true;
      window.__remoteControllerDebug.state.monitors = [{
        id: "display-1",
        bounds: { left: 0, top: 0, width: 320, height: 180 },
        logicalBounds: { left: 0, top: 0, width: 320, height: 180 },
        scaleFactor: 1
      }];
      window.__remoteControllerDebug.state.selectedMonitorId = "display-1";
      window.__remoteControllerDebug.state.frame = window.__remoteControllerDebug.normalizeIncomingFrame({
        monitorId: "display-1",
        width: 320,
        height: 180,
        imageDataUrl: dataUrl,
        desktopLabel: "Lens edge test",
        windows: [],
        cursor: { x: 320, y: 180, coordinateSpace: "physical-frame", visible: true }
      });
      window.__remoteControllerDebug.setViewportZoom(1);
      window.__remoteControllerDebug.setAutoFollowCursor(true);
      window.__remoteControllerDebug.setCursorLensEnabled(true);
      await new Promise((resolve) => requestAnimationFrame(resolve));
      const box = window.__remoteControllerDebug.state.lastCursorLensBox;
      const canvas = document.getElementById("streamCanvas");
      const pixels = canvas.getContext("2d").getImageData(
        Math.round(box.dotX) - 2,
        Math.round(box.dotY) - 2,
        5,
        5
      ).data;
      let centerGoldPixels = 0;
      for (let i = 0; i < pixels.length; i += 4) {
        if (pixels[i] > 170 && pixels[i + 1] > 120 && pixels[i + 1] < 230 && pixels[i + 2] < 140) centerGoldPixels += 1;
      }
      return { box, centerGoldPixels };
    });

    assert.equal(result.box.cursorCentered, true);
    assert.ok(Math.abs(result.box.dotX - (result.box.x + result.box.width / 2)) < 0.5);
    assert.ok(Math.abs(result.box.dotY - (result.box.y + result.box.height / 2)) < 0.5);
    assert.equal(result.box.imageCursorX, 320);
    assert.equal(result.box.imageCursorY, 180);
    assert.ok(result.centerGoldPixels > 4);
  } finally {
    await browser.close();
  }
});

test("phone stream keeps the last good frame while the next image is still loading", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const source = document.createElement("canvas");
      source.width = 320;
      source.height = 180;
      const srcCtx = source.getContext("2d");
      srcCtx.fillStyle = "#16110a";
      srcCtx.fillRect(0, 0, 320, 180);
      srcCtx.fillStyle = "#d6a84a";
      srcCtx.fillRect(138, 72, 44, 36);
      const goodFrame = source.toDataURL("image/png");
      window.__remoteControllerDebug.state.monitors = [{
        id: "display-1",
        bounds: { left: 0, top: 0, width: 320, height: 180 },
        logicalBounds: { left: 0, top: 0, width: 320, height: 180 },
        scaleFactor: 1
      }];
      window.__remoteControllerDebug.state.selectedMonitorId = "display-1";
      window.__remoteControllerDebug.handleServerPacket({
        type: "stream.frame",
        payload: {
          monitorId: "display-1",
          width: 320,
          height: 180,
          imageDataUrl: goodFrame,
          cursor: { x: 160, y: 90, coordinateSpace: "physical-frame", visible: true },
          capturedAt: Date.now()
        }
      });
      await new Promise((resolve) => {
        const started = performance.now();
        const wait = () => {
          if (window.__remoteControllerDebug.state.frameImageReady || performance.now() - started > 2000) {
            resolve();
            return;
          }
          requestAnimationFrame(wait);
        };
        wait();
      });
      const readyBefore = window.__remoteControllerDebug.state.frameImageReady;
      const sourceBefore = window.__remoteControllerDebug.state.frameImageSource;
      window.__remoteControllerDebug.handleServerPacket({
        type: "stream.frame",
        payload: {
          monitorId: "display-1",
          width: 320,
          height: 180,
          imageDataUrl: "data:image/png;base64,this-is-not-a-valid-png",
          cursor: { x: 168, y: 96, coordinateSpace: "physical-frame", visible: true },
          capturedAt: Date.now()
        }
      });
      const readyImmediatelyAfter = window.__remoteControllerDebug.state.frameImageReady;
      const sourceImmediatelyAfter = window.__remoteControllerDebug.state.frameImageSource;
      await new Promise((resolve) => setTimeout(resolve, 80));
      return {
        readyBefore,
        readyImmediatelyAfter,
        readyAfterError: window.__remoteControllerDebug.state.frameImageReady,
        sourceStayed: sourceBefore === sourceImmediatelyAfter,
        imageStillPresent: Boolean(window.__remoteControllerDebug.state.frameImage)
      };
    });

    assert.equal(result.readyBefore, true);
    assert.equal(result.readyImmediatelyAfter, true);
    assert.equal(result.readyAfterError, true);
    assert.equal(result.sourceStayed, true);
    assert.equal(result.imageStillPresent, true);
  } finally {
    await browser.close();
  }
});

test("phone stream still loads frames when Image.decode rejects before load", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const source = document.createElement("canvas");
      source.width = 320;
      source.height = 180;
      const srcCtx = source.getContext("2d");
      srcCtx.fillStyle = "#050403";
      srcCtx.fillRect(0, 0, 320, 180);
      srcCtx.fillStyle = "#d6a84a";
      srcCtx.fillRect(132, 66, 56, 48);
      const frameImage = source.toDataURL("image/png");
      const debug = window.__remoteControllerDebug;
      const originalDecode = Image.prototype.decode;
      Image.prototype.decode = function decodeRejectsBeforeLoad() {
        return Promise.reject(new Error("mobile decode rejected before load"));
      };
      try {
        debug.state.monitors = [{
          id: "display-1",
          bounds: { left: 0, top: 0, width: 320, height: 180 },
          logicalBounds: { left: 0, top: 0, width: 320, height: 180 },
          scaleFactor: 1
        }];
        debug.state.selectedMonitorId = "display-1";
        debug.handleServerPacket({
          type: "stream.frame",
          payload: {
            monitorId: "display-1",
            width: 320,
            height: 180,
            imageDataUrl: frameImage,
            cursor: { x: 160, y: 90, coordinateSpace: "physical-frame", visible: true },
            capturedAt: Date.now()
          }
        });
        await new Promise((resolve) => {
          const started = performance.now();
          const wait = () => {
            if (debug.state.frameImageSource === frameImage || performance.now() - started > 2500) {
              resolve();
              return;
            }
            requestAnimationFrame(wait);
          };
          wait();
        });
        return {
          ready: debug.state.frameImageReady,
          sourceLoaded: debug.state.frameImageSource === frameImage,
          decodeErrors: debug.state.frameDecodeErrors,
          pendingCleared: !debug.state.pendingFrameImageSource
        };
      } finally {
        Image.prototype.decode = originalDecode;
      }
    });

    assert.equal(result.ready, true);
    assert.equal(result.sourceLoaded, true);
    assert.equal(result.decodeErrors, 0);
    assert.equal(result.pendingCleared, true);
  } finally {
    await browser.close();
  }
});

test("phone stream falls back to a data URL when mobile blob image decoding fails", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const source = document.createElement("canvas");
      source.width = 320;
      source.height = 180;
      const srcCtx = source.getContext("2d");
      srcCtx.fillStyle = "#050403";
      srcCtx.fillRect(0, 0, 320, 180);
      srcCtx.fillStyle = "#d6a84a";
      srcCtx.fillRect(124, 64, 72, 52);
      const goodBlob = await new Promise((resolve) => source.toBlob(resolve, "image/png"));
      const badUrl = URL.createObjectURL(new Blob(["not a real image"], { type: "image/png" }));
      const debug = window.__remoteControllerDebug;
      debug.state.monitors = [{
        id: "display-1",
        bounds: { left: 0, top: 0, width: 320, height: 180 },
        logicalBounds: { left: 0, top: 0, width: 320, height: 180 },
        scaleFactor: 1
      }];
      debug.state.selectedMonitorId = "display-1";
      debug.handleServerPacket({
        type: "stream.frame",
        payload: {
          monitorId: "display-1",
          width: 320,
          height: 180,
          imageObjectUrl: badUrl,
          imageBlob: goodBlob,
          cursor: { x: 160, y: 90, coordinateSpace: "physical-frame", visible: true },
          capturedAt: Date.now()
        }
      });
      await new Promise((resolve) => {
        const started = performance.now();
        const wait = () => {
          if ((debug.state.frameImageReady && debug.state.frameImageSource.startsWith("data:image/")) || performance.now() - started > 3500) {
            resolve();
            return;
          }
          requestAnimationFrame(wait);
        };
        wait();
      });
      return {
        ready: debug.state.frameImageReady,
        sourceIsDataUrl: debug.state.frameImageSource.startsWith("data:image/png;"),
        fallbacks: debug.state.frameBlobFallbacks,
        decodeErrors: debug.state.frameDecodeErrors,
        pendingCleared: !debug.state.pendingFrameImageSource
      };
    });

    assert.equal(result.ready, true);
    assert.equal(result.sourceIsDataUrl, true);
    assert.equal(result.fallbacks >= 1, true);
    assert.equal(result.decodeErrors >= 1, true);
    assert.equal(result.pendingCleared, true);
  } finally {
    await browser.close();
  }
});

test("phone stream does not starve image decoding when frames arrive faster than mobile decode", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const makeFrame = (color) => {
        const source = document.createElement("canvas");
        source.width = 320;
        source.height = 180;
        const srcCtx = source.getContext("2d");
        srcCtx.fillStyle = color;
        srcCtx.fillRect(0, 0, 320, 180);
        return source.toDataURL("image/png");
      };
      const first = makeFrame("#14100a");
      const second = makeFrame("#d6a84a");
      window.__remoteControllerDebug.state.monitors = [{
        id: "display-1",
        bounds: { left: 0, top: 0, width: 320, height: 180 },
        logicalBounds: { left: 0, top: 0, width: 320, height: 180 },
        scaleFactor: 1
      }];
      window.__remoteControllerDebug.state.selectedMonitorId = "display-1";
      window.__remoteControllerDebug.handleServerPacket({
        type: "stream.frame",
        payload: {
          monitorId: "display-1",
          width: 320,
          height: 180,
          imageDataUrl: first,
          cursor: { x: 160, y: 90, coordinateSpace: "physical-frame", visible: true },
          capturedAt: Date.now()
        }
      });
      window.__remoteControllerDebug.handleServerPacket({
        type: "stream.frame",
        payload: {
          monitorId: "display-1",
          width: 320,
          height: 180,
          imageDataUrl: second,
          cursor: { x: 170, y: 95, coordinateSpace: "physical-frame", visible: true },
          capturedAt: Date.now()
        }
      });
      const queuedImmediately = window.__remoteControllerDebug.state.queuedFrameImageSource === second;
      await new Promise((resolve) => {
        const started = performance.now();
        const wait = () => {
          if (
            window.__remoteControllerDebug.state.frameImageSource === second ||
            performance.now() - started > 2500
          ) {
            resolve();
            return;
          }
          requestAnimationFrame(wait);
        };
        wait();
      });
      return {
        queuedImmediately,
        ready: window.__remoteControllerDebug.state.frameImageReady,
        finalSourceIsNewest: window.__remoteControllerDebug.state.frameImageSource === second,
        pendingCleared: !window.__remoteControllerDebug.state.pendingFrameImageSource,
        queuedCleared: !window.__remoteControllerDebug.state.queuedFrameImageSource
      };
    });

    assert.equal(result.queuedImmediately, true);
    assert.equal(result.ready, true);
    assert.equal(result.finalSourceIsNewest, true);
    assert.equal(result.pendingCleared, true);
    assert.equal(result.queuedCleared, true);
  } finally {
    await browser.close();
  }
});

test("phone recovers when a frame decode gets stuck before loading", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const source = document.createElement("canvas");
      source.width = 320;
      source.height = 180;
      const srcCtx = source.getContext("2d");
      srcCtx.fillStyle = "#d6a84a";
      srcCtx.fillRect(0, 0, 320, 180);
      const goodFrame = source.toDataURL("image/png");
      const debug = window.__remoteControllerDebug;
      debug.state.monitors = [{
        id: "display-1",
        bounds: { left: 0, top: 0, width: 320, height: 180 },
        logicalBounds: { left: 0, top: 0, width: 320, height: 180 },
        scaleFactor: 1
      }];
      debug.state.selectedMonitorId = "display-1";
      debug.state.pendingFrameImage = new Image();
      debug.state.pendingFrameImageSource = "stuck-frame";
      debug.state.pendingFrameImageStartedAt = performance.now() - 4000;
      debug.handleServerPacket({
        type: "stream.frame",
        payload: {
          monitorId: "display-1",
          width: 320,
          height: 180,
          imageDataUrl: goodFrame,
          cursor: { x: 160, y: 90, coordinateSpace: "physical-frame", visible: true },
          capturedAt: Date.now()
        }
      });
      await new Promise((resolve) => {
        const started = performance.now();
        const wait = () => {
          if (debug.state.frameImageSource === goodFrame || performance.now() - started > 2500) {
            resolve();
            return;
          }
          requestAnimationFrame(wait);
        };
        wait();
      });
      return {
        ready: debug.state.frameImageReady,
        finalSourceIsNewest: debug.state.frameImageSource === goodFrame,
        pendingCleared: !debug.state.pendingFrameImageSource,
        decodedAtSet: debug.state.lastDecodedFrameAt > 0
      };
    });

    assert.equal(result.ready, true);
    assert.equal(result.finalSourceIsNewest, true);
    assert.equal(result.pendingCleared, true);
    assert.equal(result.decodedAtSet, true);
  } finally {
    await browser.close();
  }
});

test("phone cursor lens keeps the real mouse centered inside the zoom box", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const source = document.createElement("canvas");
      source.width = 640;
      source.height = 360;
      const srcCtx = source.getContext("2d");
      srcCtx.fillStyle = "#080604";
      srcCtx.fillRect(0, 0, 640, 360);
      srcCtx.fillStyle = "#d6a84a";
      srcCtx.fillRect(558, 296, 18, 18);
      const frameImage = source.toDataURL("image/png");
      const debug = window.__remoteControllerDebug;
      debug.state.monitors = [{
        id: "display-1",
        bounds: { left: 0, top: 0, width: 640, height: 360 },
        logicalBounds: { left: 0, top: 0, width: 640, height: 360 },
        scaleFactor: 1
      }];
      debug.state.selectedMonitorId = "display-1";
      debug.state.autoFollowCursor = true;
      debug.state.cursorLensEnabled = true;
      debug.state.viewportZoom = 2;
      debug.state.viewportPanX = 0;
      debug.state.viewportPanY = 0;
      debug.handleServerPacket({
        type: "stream.frame",
        payload: {
          monitorId: "display-1",
          width: 640,
          height: 360,
          imageDataUrl: frameImage,
          cursor: { x: 567, y: 305, coordinateSpace: "physical-frame", visible: true },
          capturedAt: Date.now()
        }
      });
      await new Promise((resolve) => {
        const started = performance.now();
        const wait = () => {
          if (debug.state.lastCursorLensBox || performance.now() - started > 2500) {
            resolve();
            return;
          }
          requestAnimationFrame(wait);
        };
        wait();
      });
      const box = debug.state.lastCursorLensBox;
      return {
        hasBox: Boolean(box),
        cursorCentered: Boolean(box?.cursorCentered),
        dotCenteredX: box ? Math.abs(box.dotX - (box.x + box.width / 2)) < 0.01 : false,
        dotCenteredY: box ? Math.abs(box.dotY - (box.y + box.height / 2)) < 0.01 : false,
        sourceCursorX: Math.round(box?.sourceCursorX || 0),
        sourceCursorY: Math.round(box?.sourceCursorY || 0)
      };
    });

    assert.equal(result.hasBox, true);
    assert.equal(result.cursorCentered, true);
    assert.equal(result.dotCenteredX, true);
    assert.equal(result.dotCenteredY, true);
    assert.equal(result.sourceCursorX, 567);
    assert.equal(result.sourceCursorY, 305);
  } finally {
    await browser.close();
  }
});

test("phone cursor lens stays centered and visible when auto-follow view is off", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const source = document.createElement("canvas");
      source.width = 640;
      source.height = 360;
      const srcCtx = source.getContext("2d");
      srcCtx.fillStyle = "#080604";
      srcCtx.fillRect(0, 0, 640, 360);
      srcCtx.fillStyle = "#d6a84a";
      srcCtx.fillRect(296, 160, 32, 32);
      const debug = window.__remoteControllerDebug;
      debug.state.monitors = [{
        id: "display-1",
        bounds: { left: 0, top: 0, width: 640, height: 360 },
        logicalBounds: { left: 0, top: 0, width: 640, height: 360 },
        scaleFactor: 1
      }];
      debug.state.selectedMonitorId = "display-1";
      debug.state.autoFollowCursor = false;
      debug.state.cursorLensEnabled = true;
      debug.state.viewportZoom = 1;
      debug.handleServerPacket({
        type: "stream.frame",
        payload: {
          monitorId: "display-1",
          width: 640,
          height: 360,
          imageDataUrl: source.toDataURL("image/png"),
          cursor: { x: 312, y: 176, coordinateSpace: "physical-frame", visible: true },
          capturedAt: Date.now()
        }
      });
      await new Promise((resolve) => {
        const started = performance.now();
        const wait = () => {
          if (debug.state.lastCursorLensBox || performance.now() - started > 2500) {
            resolve();
            return;
          }
          requestAnimationFrame(wait);
        };
        wait();
      });
      const box = debug.state.lastCursorLensBox;
      return {
        hasBox: Boolean(box),
        autoFollowCursor: debug.state.autoFollowCursor,
        cursorCentered: Boolean(box?.cursorCentered),
        dotCenteredX: box ? Math.abs(box.dotX - (box.x + box.width / 2)) < 0.01 : false,
        dotCenteredY: box ? Math.abs(box.dotY - (box.y + box.height / 2)) < 0.01 : false,
        width: Math.round(box?.width || 0),
        height: Math.round(box?.height || 0)
      };
    });

    assert.equal(result.hasBox, true);
    assert.equal(result.autoFollowCursor, false);
    assert.equal(result.cursorCentered, true);
    assert.equal(result.dotCenteredX, true);
    assert.equal(result.dotCenteredY, true);
    assert.equal(result.width >= 170, true);
    assert.equal(result.height > 95, true);
  } finally {
    await browser.close();
  }
});

test("phone watchdog wakes a stalled visible stream without dropping the control socket", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      const sent = [];
      let closeCount = 0;
      const debug = window.__remoteControllerDebug;
      debug.state.token = "watchdog-token";
      debug.state.approved = true;
      debug.state.connected = true;
      debug.state.connectedAt = performance.now() - 12000;
      debug.state.lastFrameAt = performance.now() - 6000;
      debug.state.frame = null;
      debug.state.ws = {
        readyState: WebSocket.OPEN,
        send(raw) {
          sent.push(JSON.parse(raw));
        },
        close() {
          closeCount += 1;
          this.readyState = WebSocket.CLOSED;
        }
      };
      debug.handleStreamWatchdogTick();
      const watchdogMessage = sent.find((item) => item.payload?.reason === "watchdog");
      const first = {
        sent: sent.map((item) => item.type),
        payload: watchdogMessage?.payload,
        wakeBurstSent: sent.some((item) => item.payload?.reason === "watchdog-burst"),
        status: document.getElementById("connectionState").textContent,
        reconnects: debug.state.streamWatchdogReconnects,
        visible: debug.state.streamVisible
      };
      debug.state.lastFrameAt = performance.now() - 13000;
      debug.state.ws.readyState = WebSocket.OPEN;
      debug.handleStreamWatchdogTick();
      return {
        first,
        closeCount,
        reconnects: debug.state.streamWatchdogReconnects,
        lastError: debug.state.lastError
      };
    });

    assert.equal(result.first.sent.every((type) => type === "stream.visibility"), true);
    assert.equal(result.first.sent.length >= 1, true);
    assert.equal(result.first.payload.visible, true);
    assert.equal(result.first.payload.reason, "watchdog");
    assert.equal(result.first.wakeBurstSent, true);
    assert.equal(result.first.status, "Waking screen stream");
    assert.equal(result.first.visible, true);
    assert.equal(result.closeCount, 0);
    assert.equal(result.reconnects, 1);
    assert.equal(result.lastError.code, "STREAM_STALLED");
  } finally {
    await browser.close();
  }
});

test("phone watchdog keeps the socket open when the initial screen frame never arrives", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      const sent = [];
      let closeCount = 0;
      const debug = window.__remoteControllerDebug;
      debug.state.token = "initial-frame-token";
      debug.state.approved = true;
      debug.state.connected = true;
      debug.state.connectedAt = performance.now() - 7200;
      debug.state.lastFrameAt = 0;
      debug.state.lastDecodedFrameAt = 0;
      debug.state.frame = null;
      debug.state.frameImageReady = false;
      debug.state.ws = {
        readyState: WebSocket.OPEN,
        send(raw) {
          sent.push(JSON.parse(raw));
        },
        close() {
          closeCount += 1;
          this.readyState = WebSocket.CLOSED;
        }
      };
      debug.handleStreamWatchdogTick();
      return {
        closeCount,
        sent: sent.map((item) => item.payload?.reason),
        status: document.getElementById("connectionState").textContent,
        reconnects: debug.state.streamWatchdogReconnects,
        wakePokes: debug.state.streamWakePokes,
        lastError: debug.state.lastError
      };
    });

    assert.equal(result.closeCount, 0);
    assert.equal(result.reconnects, 1);
    assert.ok(result.wakePokes >= 1);
    assert.ok(result.sent.includes("initial-frame-watchdog"));
    assert.equal(result.status, "Waking screen stream");
    assert.equal(result.lastError.code, "STREAM_INITIAL_FRAME_MISSING");
  } finally {
    await browser.close();
  }
});

test("phone resume path wakes a blank visible stream without waiting for user input", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(async () => {
      const sent = [];
      const debug = window.__remoteControllerDebug;
      debug.state.token = "resume-token";
      debug.state.approved = true;
      debug.state.connected = true;
      debug.state.frame = null;
      debug.state.frameImageReady = false;
      debug.state.ws = {
        readyState: WebSocket.OPEN,
        send(raw) {
          sent.push(JSON.parse(raw));
        }
      };
      debug.resumeLiveSession("manual-resume");
      await new Promise((resolve) => setTimeout(resolve, 980));
      debug.stopStreamWakeBurst();
      return {
        reasons: sent.map((item) => item.payload?.reason).filter(Boolean),
        visibleFlags: sent.map((item) => item.payload?.visible),
        status: document.getElementById("connectionState").textContent
      };
    });

    assert.ok(result.reasons.includes("manual-resume"));
    assert.ok(result.reasons.includes("manual-resume-burst"));
    assert.ok(result.reasons.includes("manual-resume-probe"));
    assert.equal(result.visibleFlags.every((item) => item === true), true);
    assert.equal(result.status, "Starting screen stream");
  } finally {
    await browser.close();
  }
});

test("phone keyboard button toggles native keyboard bridge and forwards typed keys", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    await page.evaluate(() => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const sent = [];
      window.__nativeKeyboardSent = sent;
      window.__remoteControllerDebug.state.ws = {
        readyState: WebSocket.OPEN,
        send(value) {
          sent.push(JSON.parse(value));
        }
      };
    });
    await page.locator("#keyboardToggleBtn").click();
    await page.keyboard.type("hi");
    await page.keyboard.press("Backspace");
    const result = await page.evaluate(() => ({
      activeAfterOpen: document.getElementById("keyboardToggleBtn").classList.contains("active"),
      keyboardOpen: window.__remoteControllerDebug.state.nativeKeyboardOpen,
      sent: window.__nativeKeyboardSent.map((item) => ({ type: item.type, payload: item.payload }))
    }));
    await page.locator("#keyboardToggleBtn").click();
    const closed = await page.evaluate(() => ({
      activeAfterClose: document.getElementById("keyboardToggleBtn").classList.contains("active"),
      keyboardOpen: window.__remoteControllerDebug.state.nativeKeyboardOpen
    }));

    assert.equal(result.activeAfterOpen, true);
    assert.equal(result.keyboardOpen, true);
    assert.equal(result.sent.some((item) => ["text", "pasteText"].includes(item.type) && /h|hi/.test(item.payload.text)), true);
    assert.equal(result.sent.some((item) => item.type === "key" && item.payload.key === "Backspace"), true);
    assert.equal(closed.activeAfterClose, false);
    assert.equal(closed.keyboardOpen, false);
  } finally {
    await browser.close();
  }
});

test("phone portrait stream aligns the captured desktop to the top", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      window.__remoteControllerDebug.state.frame = {
        width: 1920,
        height: 1080,
        desktopLabel: "Top aligned",
        windows: [],
        cursor: { x: 960, y: 540 }
      };
      const rect = document.getElementById("streamCanvas").getBoundingClientRect();
      return window.__remoteControllerDebug.frameMetrics(window.__remoteControllerDebug.state.frame, rect);
    });

    assert.equal(result.dy, 0);
    assert.ok(result.drawH > 0);
  } finally {
    await browser.close();
  }
});

test("phone stops reconnect loop when a saved session is expired", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    await page.route("**/api/session?**", (route) => route.fulfill({
      status: 404,
      contentType: "application/json",
      body: JSON.stringify({
        ok: false,
        error: "SESSION_NOT_FOUND",
        code: "SESSION_NOT_FOUND",
        message: "Session was not found or has expired.",
        friendly: "Session was not found or has expired.",
        recoverable: true,
        nextAction: "Forget the saved phone session, pair again with the current PIN, and approve it on the laptop."
      })
    }));
    const result = await page.evaluate(async () => {
      window.__remoteControllerDebug.state.token = "expired-token";
      window.__remoteControllerDebug.state.manualDisconnect = false;
      window.__remoteControllerDebug.state.reconnectAttempts = 3;
      const canReconnect = await window.__remoteControllerDebug.verifySavedSessionBeforeReconnect();
      return {
        canReconnect,
        manualDisconnect: window.__remoteControllerDebug.state.manualDisconnect,
        reconnectAttempts: window.__remoteControllerDebug.state.reconnectAttempts,
        token: window.__remoteControllerDebug.state.token,
        pairingVisible: !document.getElementById("pairing").classList.contains("hidden"),
        helpVisible: !document.getElementById("connectionHelp").classList.contains("hidden"),
        helpText: document.getElementById("connectionHelp").innerText
      };
    });

    assert.equal(result.canReconnect, false);
    assert.equal(result.manualDisconnect, true);
    assert.equal(result.reconnectAttempts, 0);
    assert.equal(result.token, "");
    assert.equal(result.pairingVisible, true);
    assert.equal(result.helpVisible, true);
    assert.match(result.helpText, /Saved session expired/);
    assert.match(result.helpText, /old saved session was cleared/);
  } finally {
    await browser.close();
  }
});

test("phone precision mode lowers movement sensitivity and shows halo state", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      window.__remoteControllerDebug.state.sensitivity = 2;
      window.__remoteControllerDebug.setPrecisionMode(true);
      window.__remoteControllerDebug.showPointerHalo({ x: 195, y: 420 });
      return {
        precisionMode: window.__remoteControllerDebug.state.precisionMode,
        effectiveSensitivity: window.__remoteControllerDebug.movementSensitivity(),
        haloVisible: !document.getElementById("pointerHalo").classList.contains("hidden"),
        haloPrecision: document.getElementById("pointerHalo").classList.contains("precision")
      };
    });

    assert.equal(result.precisionMode, true);
    assert.equal(result.effectiveSensitivity, 0.7);
    assert.equal(result.haloVisible, true);
    assert.equal(result.haloPrecision, true);
    await page.screenshot({
      path: path.join("output", "playwright", "phone-precision-halo.png"),
      fullPage: false
    });
  } finally {
    await browser.close();
  }
});

test("phone zoomed viewport maps direct touch through the visible crop", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      window.__remoteControllerDebug.state.frame = {
        width: 1000,
        height: 500,
        desktopLabel: "Zoom test",
        windows: [],
        cursor: { x: 500, y: 250 }
      };
      window.__remoteControllerDebug.setViewportZoom(2);
      window.__remoteControllerDebug.setViewportPan(0.25, 0.25);
      document.querySelector('[data-sheet="settingsSheet"]').click();
      const metrics = window.__remoteControllerDebug.frameMetrics();
      const mapped = window.__remoteControllerDebug.normalizeCanvasPoint({
        x: metrics.dx + metrics.drawW / 2,
        y: metrics.dy + metrics.drawH / 2
      });
      return {
        zoom: window.__remoteControllerDebug.state.viewportZoom,
        panX: window.__remoteControllerDebug.state.viewportPanX,
        panY: window.__remoteControllerDebug.state.viewportPanY,
        zoomLabel: document.getElementById("zoomValue").textContent,
        settingsOpen: document.getElementById("settingsSheet").classList.contains("open"),
        mapped
      };
    });

    assert.equal(result.zoom, 2);
    assert.equal(result.panX, 0.25);
    assert.equal(result.panY, 0.25);
    assert.equal(result.zoomLabel, "200%");
    assert.equal(result.settingsOpen, true);
    assert.ok(Math.abs(result.mapped.normalizedX - 0.5) < 0.02);
    assert.ok(Math.abs(result.mapped.normalizedY - 0.5) < 0.02);
    await page.waitForTimeout(220);
    await page.screenshot({
      path: path.join("output", "playwright", "phone-zoom-viewport.png"),
      fullPage: false
    });
  } finally {
    await browser.close();
  }
});

test("phone focal zoom keeps the touched canvas point anchored", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      window.__remoteControllerDebug.state.monitors = [{
        id: "display-1",
        bounds: { left: 0, top: 0, width: 1920, height: 1080 },
        logicalBounds: { left: 0, top: 0, width: 1920, height: 1080 },
        scaleFactor: 1
      }];
      window.__remoteControllerDebug.state.selectedMonitorId = "display-1";
      window.__remoteControllerDebug.state.frame = {
        width: 1920,
        height: 1080,
        desktopLabel: "Focal zoom test",
        windows: [],
        cursor: { x: 1400, y: 520, coordinateSpace: "physical-frame", visible: true }
      };
      window.__remoteControllerDebug.setViewportZoom(1);
      const metrics = window.__remoteControllerDebug.frameMetrics();
      const focal = {
        x: metrics.dx + metrics.drawW * 0.72,
        y: metrics.dy + metrics.drawH * 0.31
      };
      const before = window.__remoteControllerDebug.normalizeCanvasPoint(focal);
      window.__remoteControllerDebug.setViewportZoom(2.35, { focalCanvasPoint: focal, follow: false });
      const after = window.__remoteControllerDebug.normalizeCanvasPoint(focal);
      return {
        before,
        after,
        zoom: window.__remoteControllerDebug.state.viewportZoom,
        panX: window.__remoteControllerDebug.state.viewportPanX,
        panY: window.__remoteControllerDebug.state.viewportPanY,
        followPaused: window.__remoteControllerDebug.state.followPausedUntil > performance.now()
      };
    });

    assert.equal(result.zoom, 2.35);
    assert.ok(result.panX > 0);
    assert.ok(result.panY > 0);
    assert.ok(Math.abs(result.before.normalizedX - result.after.normalizedX) < 0.002);
    assert.ok(Math.abs(result.before.normalizedY - result.after.normalizedY) < 0.002);
    assert.equal(result.followPaused, true);
  } finally {
    await browser.close();
  }
});

test("phone focal zoom supports deep inspection without losing the anchor", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      window.__remoteControllerDebug.state.frame = {
        width: 2560,
        height: 1440,
        desktopLabel: "Deep focal zoom",
        windows: [],
        cursor: { x: 1720, y: 760, coordinateSpace: "physical-frame", visible: true }
      };
      window.__remoteControllerDebug.resetViewport();
      const metrics = window.__remoteControllerDebug.frameMetrics();
      const focal = {
        x: metrics.dx + metrics.drawW * 0.67,
        y: metrics.dy + metrics.drawH * 0.58
      };
      const before = window.__remoteControllerDebug.normalizeCanvasPoint(focal);
      window.__remoteControllerDebug.setViewportZoom(4.5, { focalCanvasPoint: focal, follow: false });
      const after = window.__remoteControllerDebug.normalizeCanvasPoint(focal);
      const snapshot = window.__remoteControllerDebug.displayStageSnapshot();
      return {
        before,
        after,
        zoom: window.__remoteControllerDebug.state.viewportZoom,
        zoomSliderMax: document.getElementById("zoomRange").max,
        lensSliderMax: document.getElementById("lensZoomRange").max,
        snapshot
      };
    });

    assert.equal(result.zoom, 4.5);
    assert.equal(result.zoomSliderMax, "5");
    assert.equal(result.lensSliderMax, "5");
    assert.ok(result.snapshot.stageRect.width > result.snapshot.baseRect.width * 4);
    assert.ok(Math.abs(result.before.normalizedX - result.after.normalizedX) < 0.002);
    assert.ok(Math.abs(result.before.normalizedY - result.after.normalizedY) < 0.002);
  } finally {
    await browser.close();
  }
});

test("phone settings expose scroll speed, halo toggle, and haptic toggle", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      const vibrateCalls = [];
      Object.defineProperty(navigator, "vibrate", {
        configurable: true,
        value(pattern) {
          vibrateCalls.push(pattern);
          return true;
        }
      });
      window.__remoteControllerDebug.setScrollSpeed(1.75);
      window.__remoteControllerDebug.setHaloEnabled(false);
      window.__remoteControllerDebug.showPointerHalo({ x: 120, y: 300 });
      const haloHiddenAfterDisable = document.getElementById("pointerHalo").classList.contains("hidden");
      window.__remoteControllerDebug.setHaloEnabled(true);
      window.__remoteControllerDebug.showPointerHalo({ x: 120, y: 300 });
      const haloVisibleAfterEnable = !document.getElementById("pointerHalo").classList.contains("hidden");
      window.__remoteControllerDebug.setHapticsEnabled(false);
      const hapticOff = window.__remoteControllerDebug.touchFeedback(9);
      window.__remoteControllerDebug.setHapticsEnabled(true);
        const hapticOn = window.__remoteControllerDebug.touchFeedback(9);
        document.querySelector('[data-sheet="settingsSheet"]').click();
        const proofPayload = window.__remoteControllerDebug.acceptanceProofPayload({ gate: "same-wifi", step: "browser-proof" });
        return {
          scrollSpeed: window.__remoteControllerDebug.state.scrollSpeed,
          scrollLabel: document.getElementById("scrollSpeedValue").textContent,
          proofButtonText: document.getElementById("acceptanceMarkBtn").textContent,
          proofGate: proofPayload.gate,
          proofStep: proofPayload.step,
          proofTouch: proofPayload.features.touch,
          proofWidth: proofPayload.viewport.width,
          haloHiddenAfterDisable,
          haloVisibleAfterEnable,
        hapticOff,
        hapticOn,
        hapticsEnabled: window.__remoteControllerDebug.state.hapticsEnabled,
        vibrateCalls,
        storedScroll: localStorage.getItem("remote-scroll-speed"),
        storedHalo: localStorage.getItem("remote-show-halo"),
        storedHaptics: localStorage.getItem("remote-haptics")
      };
    });

      assert.equal(result.scrollSpeed, 1.75);
      assert.equal(result.scrollLabel, "175%");
      assert.equal(result.proofButtonText, "Mark Proof");
      assert.equal(result.proofGate, "same-wifi");
      assert.equal(result.proofStep, "browser-proof");
      assert.equal(result.proofTouch, true);
      assert.equal(result.proofWidth, 390);
    assert.equal(result.haloHiddenAfterDisable, true);
    assert.equal(result.haloVisibleAfterEnable, true);
    assert.equal(result.hapticOff, false);
    assert.equal(result.hapticOn, true);
    assert.equal(result.hapticsEnabled, true);
    assert.deepEqual(result.vibrateCalls, [9]);
    assert.equal(result.storedScroll, "1.75");
    assert.equal(result.storedHalo, "1");
    assert.equal(result.storedHaptics, "1");
    await page.waitForTimeout(220);
    await page.screenshot({
      path: path.join("output", "playwright", "phone-settings-control-preferences.png"),
      fullPage: false
    });
  } finally {
    await browser.close();
  }
});

test("phone reports controller visibility as active so mobile Safari cannot pause the stream", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      const sent = [];
      window.__remoteControllerDebug.state.ws = {
        readyState: WebSocket.OPEN,
        send(value) {
          sent.push(JSON.parse(value));
        }
      };
      window.__remoteControllerDebug.reportStreamVisibility(true);
      window.__remoteControllerDebug.reportStreamVisibility(false);
      return {
        streamVisible: window.__remoteControllerDebug.state.streamVisible,
        sent
      };
    });

    assert.equal(result.streamVisible, true);
    assert.equal(result.sent.length, 2);
    assert.equal(result.sent[0].type, "stream.visibility");
    assert.deepEqual(result.sent[0].payload, { visible: true, hidden: false });
    assert.equal(result.sent[1].type, "stream.visibility");
    assert.deepEqual(result.sent[1].payload, { visible: true, hidden: false });
  } finally {
    await browser.close();
  }
});

test("phone edge-pan moves a zoomed viewport without sending cursor input", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });
    const result = await page.evaluate(() => {
      document.getElementById("pairing").classList.add("hidden");
      document.getElementById("controller").classList.remove("hidden");
      window.__remoteControllerDebug.state.frame = {
        width: 1000,
        height: 500,
        desktopLabel: "Edge pan test",
        windows: [{ title: "Viewport", x: 520, y: 220, width: 160, height: 90, active: true }],
        cursor: { x: 700, y: 260 }
      };
      window.__remoteControllerDebug.setViewportZoom(2);
      window.__remoteControllerDebug.setViewportPan(0.35, 0.25);
      window.__remoteControllerDebug.state.inputMode = "touchpad";
      const sent = [];
      window.__remoteControllerDebug.state.ws = {
        readyState: WebSocket.OPEN,
        send(value) {
          sent.push(JSON.parse(value));
        }
      };
      const before = {
        panX: window.__remoteControllerDebug.state.viewportPanX,
        localMoves: window.__remoteControllerDebug.state.edgePanStats.localMoves
      };
      const handled = window.__remoteControllerDebug.handleEdgePan({ x: 12, y: 100 }, { x: 62, y: 100 });
      const edge = window.__remoteControllerDebug.isEdgePanPoint({ x: 12, y: 100 });
      const center = window.__remoteControllerDebug.isEdgePanPoint({ x: 195, y: 100 });
      document.querySelector('[data-sheet="settingsSheet"]').click();
      return {
        handled,
        edge,
        center,
        before,
        after: {
          panX: window.__remoteControllerDebug.state.viewportPanX,
          localMoves: window.__remoteControllerDebug.state.edgePanStats.localMoves
        },
        sent
      };
    });

    assert.equal(result.handled, true);
    assert.equal(result.edge, true);
    assert.equal(result.center, false);
    assert.equal(result.after.panX > result.before.panX, true);
    assert.equal(result.after.localMoves, result.before.localMoves + 1);
    assert.equal(result.sent.length, 0);
    await page.waitForTimeout(220);
    await page.screenshot({
      path: path.join("output", "playwright", "phone-edge-pan-viewport.png"),
      fullPage: false
    });
  } finally {
    await browser.close();
  }
});

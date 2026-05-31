"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { chromium } = require("playwright");

const root = path.resolve(__dirname, "..");
const outputDir = path.resolve(root, process.env.OUTPUT_DIR || path.join("output", "acceptance"));
const baseUrl = process.env.BASE_URL || "http://127.0.0.1:4317";
const hostKey = process.env.HOST_KEY || "dev-host-key";

async function api(route, options = {}) {
  const response = await fetch(`${baseUrl}${route}`, {
    headers: { "content-type": "application/json", ...(options.headers || {}) },
    ...options
  });
  const text = await response.text();
  const body = text ? JSON.parse(text) : {};
  if (!response.ok) {
    throw new Error(`${route} failed: ${response.status} ${JSON.stringify(body)}`);
  }
  return body;
}

function timestamp() {
  const now = new Date();
  const pad = (value) => String(value).padStart(2, "0");
  return [
    now.getFullYear(),
    pad(now.getMonth() + 1),
    pad(now.getDate()),
    "-",
    pad(now.getHours()),
    pad(now.getMinutes()),
    pad(now.getSeconds())
  ].join("");
}

async function main() {
  fs.mkdirSync(outputDir, { recursive: true });
  const stamp = timestamp();
  const screenshotPath = path.join(outputDir, `live-phone-visual-proof-${stamp}.png`);
  const latestScreenshotPath = path.join(outputDir, "live-phone-visual-proof-latest.png");
  const jsonPath = path.join(outputDir, `live-phone-visual-proof-${stamp}.json`);
  const latestJsonPath = path.join(outputDir, "live-phone-visual-proof-latest.json");

  const pin = await api("/api/refresh-pin", {
    method: "POST",
    headers: { "x-host-key": hostKey },
    body: "{}"
  });
  const beforeHost = await api(`/api/host?key=${encodeURIComponent(hostKey)}`);
  const pair = await api("/api/pair", {
    method: "POST",
    body: JSON.stringify({ pin: pin.pin, deviceName: "Visual Proof Phone" })
  });
  await api("/api/approve", {
    method: "POST",
    headers: { "x-host-key": hostKey },
    body: JSON.stringify({ sessionId: pair.sessionId })
  });

  const browser = await chromium.launch();
  let proof;
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true,
      deviceScaleFactor: 3
    });
    await page.addInitScript(({ token, sessionId }) => {
      localStorage.setItem("remote-token", token);
      localStorage.setItem("remote-session-id", sessionId);
      localStorage.setItem("remote-auto-follow-cursor", "1");
      localStorage.setItem("remote-cursor-lens", "1");
    }, { token: pair.token, sessionId: pair.sessionId });

    const response = await page.goto(`${baseUrl}/?v=visual-proof-${Date.now()}`, { waitUntil: "load" });
    assert.equal(response.ok(), true);
    await page.waitForFunction(() => {
      const debug = window.__remoteControllerDebug;
      const state = debug?.state;
      return Boolean(
        state?.connected
        && state?.frame?.binaryTransport
        && state?.frame?.imageByteLength > 1000
        && state?.frameImageReady
        && state?.frameImage?.naturalWidth > 0
      );
    }, null, { timeout: 10000 });

    await page.evaluate(() => {
      const debug = window.__remoteControllerDebug;
      debug.setCursorLensEnabled(true);
      debug.setAutoFollowCursor(true, { autoZoom: true });
      debug.setViewportZoom(1, { follow: false, pauseFollow: false });
      debug.state.followPausedUntil = 0;
      debug.send("pointer.move", {
        mode: "direct",
        normalizedX: 0.985,
        normalizedY: 0.985,
        source: "visual-bottom-edge-proof"
      });
      debug.flushPointerMove();
      debug.handleStreamWatchdogTick();
    });
    await page.waitForFunction(() => {
      const debug = window.__remoteControllerDebug;
      const snapshot = debug?.debugSnapshot?.();
      const cursor = snapshot?.canvasCursor;
      const draw = snapshot?.drawRect;
      const frame = snapshot?.frameSize;
      return Boolean(
        cursor
        && draw
        && frame
        && cursor.sourceY >= frame.height * 0.94
        && cursor.y >= draw.y + draw.height * 0.9
      );
    }, null, { timeout: 5000 });
    const bottomEdgeProof = await page.evaluate(() => {
      const debug = window.__remoteControllerDebug;
      const snapshot = debug.debugSnapshot();
      const cursor = snapshot.canvasCursor || null;
      const draw = snapshot.drawRect || null;
      const frame = snapshot.frameSize || null;
      return {
        cursor,
        draw,
        frame,
        sourceNearBottom: Boolean(cursor && frame && cursor.sourceY >= frame.height * 0.94),
        canvasNearBottom: Boolean(cursor && draw && cursor.y >= draw.y + draw.height * 0.9),
        normalizedY: frame && cursor ? cursor.sourceY / Math.max(1, frame.height) : 0
      };
    });
    await page.evaluate(() => {
      const debug = window.__remoteControllerDebug;
      debug.setViewportZoom(Math.max(debug.state.viewportZoom, 1.85), { follow: true, pauseFollow: false });
      debug.state.followPausedUntil = 0;
      debug.handleStreamWatchdogTick();
    });
    await page.waitForFunction(() => {
      const debug = window.__remoteControllerDebug;
      debug?.state && debug.setCursorLensEnabled(true);
      debug?.state && debug.setAutoFollowCursor(true, { autoZoom: true });
      debug?.state && debug.handleStreamWatchdogTick();
      return Boolean(debug?.state?.lastCursorLensBox?.cursorCentered && debug?.state?.frameImageReady);
    }, null, { timeout: 5000 });
    await page.screenshot({ path: screenshotPath, fullPage: true });
    fs.copyFileSync(screenshotPath, latestScreenshotPath);

    proof = await page.evaluate((bottomEdgeProof) => {
      const debug = window.__remoteControllerDebug;
      const state = debug.state;
      const canvas = document.getElementById("streamCanvas");
      const ctx = canvas.getContext("2d", { willReadFrequently: true });
      const sample = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
      let activePixels = 0;
      let goldPixels = 0;
      for (let index = 0; index < sample.length; index += 16) {
        const r = sample[index];
        const g = sample[index + 1];
        const b = sample[index + 2];
        if (r + g + b > 32) activePixels += 1;
        if (r > 150 && g > 100 && g < 230 && b < 120) goldPixels += 1;
      }
      const totalSamples = sample.length / 16;
      const lens = state.lastCursorLensBox || null;
      const debugSnapshot = debug.debugSnapshot();
      return {
        connected: state.connected,
        approved: state.approved,
        frameId: state.frame?.frameId || 0,
        binaryTransport: Boolean(state.frame?.binaryTransport),
        frameImageReady: state.frameImageReady,
        frameImageSource: state.frameImageSource || "",
        imageByteLength: state.frame?.imageByteLength || 0,
        naturalWidth: state.frameImage?.naturalWidth || 0,
        naturalHeight: state.frameImage?.naturalHeight || 0,
        canvasWidth: canvas.width,
        canvasHeight: canvas.height,
        viewportZoom: state.viewportZoom,
        autoFollowCursor: state.autoFollowCursor,
        cursorLensEnabled: state.cursorLensEnabled,
        cursorLensBox: lens,
        cursorCenteredInLens: Boolean(lens?.cursorCentered),
        bottomEdgeProof,
        bottomEdgeCursorVisible: Boolean(bottomEdgeProof.sourceNearBottom && bottomEdgeProof.canvasNearBottom),
        activePixelRatio: totalSamples ? activePixels / totalSamples : 0,
        goldPixelSamples: goldPixels,
        debugSnapshot
      };
    }, bottomEdgeProof);
    await page.evaluate(() => {
      const debug = window.__remoteControllerDebug;
      debug?.send?.("pointer.move", {
        mode: "direct",
        normalizedX: 0.5,
        normalizedY: 0.5,
        source: "visual-bottom-edge-restore"
      });
      debug?.flushPointerMove?.();
    }).catch(() => null);
  } finally {
    await browser.close();
    await api("/api/revoke", {
      method: "POST",
      headers: { "x-host-key": hostKey },
      body: JSON.stringify({ sessionId: pair.sessionId })
    }).catch(() => null);
  }

  const afterHost = await api(`/api/host?key=${encodeURIComponent(hostKey)}`);
  const result = {
    ok: true,
    generatedAt: new Date().toISOString(),
    baseUrl,
    phoneAppVersion: afterHost.app?.phoneAppVersion || beforeHost.app?.phoneAppVersion || "",
    screenshotPath,
    latestScreenshotPath,
    jsonPath,
    latestJsonPath,
    hostMode: afterHost.app?.mode || "",
    streamStats: afterHost.streamStats,
    visual: proof
  };

  assert.equal(result.phoneAppVersion !== "", true);
  assert.equal(proof.connected, true);
  assert.equal(proof.binaryTransport, true);
  assert.equal(proof.frameImageReady, true);
  assert.equal(proof.imageByteLength > 1000, true);
  assert.equal(proof.naturalWidth > 0, true);
  assert.equal(proof.naturalHeight > 0, true);
  assert.equal(proof.cursorLensEnabled, true);
  assert.equal(proof.autoFollowCursor, true);
  assert.equal(proof.cursorCenteredInLens, true);
  assert.equal(proof.bottomEdgeCursorVisible, true);
  assert.equal(proof.bottomEdgeProof.sourceNearBottom, true);
  assert.equal(proof.bottomEdgeProof.canvasNearBottom, true);
  assert.equal(proof.activePixelRatio > 0.01, true);
  assert.equal(proof.goldPixelSamples > 0, true);
  assert.equal(fs.statSync(screenshotPath).size > 2000, true);

  fs.writeFileSync(jsonPath, `${JSON.stringify(result, null, 2)}\n`);
  fs.writeFileSync(latestJsonPath, `${JSON.stringify(result, null, 2)}\n`);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exit(1);
});

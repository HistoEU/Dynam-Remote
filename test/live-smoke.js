"use strict";

const assert = require("node:assert/strict");
const { chromium } = require("playwright");

const baseUrl = process.env.BASE_URL || "http://127.0.0.1:4317";
const hostKey = process.env.HOST_KEY || "dev-host-key";

async function api(path, options = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    headers: { "content-type": "application/json", ...(options.headers || {}) },
    ...options
  });
  const body = await response.json();
  if (!response.ok) {
    throw new Error(`${path} failed: ${response.status} ${JSON.stringify(body)}`);
  }
  return body;
}

function waitForSocket(socket, eventName, timeoutMs = 4000) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(`Timed out waiting for ${eventName}`)), timeoutMs);
    socket.addEventListener(eventName, (event) => {
      clearTimeout(timeout);
      resolve(event);
    }, { once: true });
  });
}

function waitForMessage(messages, predicate, timeoutMs = 5000, label = "matching WebSocket message") {
  const existing = messages.find(predicate);
  if (existing) return Promise.resolve(existing);
  return new Promise((resolve, reject) => {
    const started = Date.now();
    const timer = setInterval(() => {
      const found = messages.find(predicate);
      if (found) {
        clearInterval(timer);
        resolve(found);
        return;
      }
      if (Date.now() - started > timeoutMs) {
        clearInterval(timer);
        const seen = messages.map((msg) => `${msg.type}${msg.payload?.code ? `:${msg.payload.code}` : ""}${msg.payload?.friendly ? `:${msg.payload.friendly}` : ""}`).join(", ");
        reject(new Error(`Timed out waiting for ${label}. Saw: ${seen}`));
      }
    }, 25);
  });
}

async function closeSocket(socket, timeoutMs = 1000) {
  if (socket.readyState === WebSocket.CLOSED) return;
  const closed = waitForSocket(socket, "close", timeoutMs).catch(() => null);
  socket.close();
  await closed;
}

async function parseSocketPacket(data) {
  if (typeof data === "string") return JSON.parse(data);
  const buffer = data instanceof ArrayBuffer ? data : await data.arrayBuffer();
  const bytes = new Uint8Array(buffer);
  assert.equal(String.fromCharCode(bytes[0], bytes[1], bytes[2], bytes[3]), "RDCF");
  const headerLength = new DataView(buffer).getUint32(4);
  const header = JSON.parse(new TextDecoder().decode(bytes.subarray(8, 8 + headerLength)));
  const imageBytes = bytes.byteLength - 8 - headerLength;
  header.payload.imageByteLength = imageBytes;
  header.payload.binaryTransport = true;
  return header;
}

async function verifyPhonePageRendersBinaryStream() {
  const host = await api(`/api/host?key=${encodeURIComponent(hostKey)}`);
  await api("/api/settings", {
    method: "POST",
    headers: { "x-host-key": hostKey },
    body: JSON.stringify({
      trustedDevicesEnabled: false,
      qualityDefault: host.settings.qualityDefault,
      inputSensitivityDefault: host.settings.inputSensitivityDefault
    })
  });
  const pair = await api("/api/pair", {
    method: "POST",
    body: JSON.stringify({ pin: host.securityStatus.pairing.pin, deviceName: "Render Smoke Phone" })
  });
  await api("/api/approve", {
    method: "POST",
    headers: { "x-host-key": hostKey },
    body: JSON.stringify({ sessionId: pair.sessionId })
  });

  const browser = await chromium.launch();
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
    }, { token: pair.token, sessionId: pair.sessionId });
    const response = await page.goto(`${baseUrl}/?v=render-smoke-${Date.now()}`, { waitUntil: "load" });
    assert.equal(response.ok(), true);
    assert.match(response.headers()["content-security-policy"] || "", /img-src 'self' data: blob:/);
    await page.waitForFunction(() => {
      const state = window.__remoteControllerDebug?.state;
      return Boolean(
        state?.connected
        && state?.frame?.binaryTransport
        && state?.frame?.imageByteLength > 1000
        && state?.frameImageReady
        && state?.frameImageSource?.startsWith("blob:")
        && state?.frameImage?.naturalWidth > 0
      );
    }, null, { timeout: 9000 });
    const renderState = await page.evaluate(() => {
      const state = window.__remoteControllerDebug.state;
      return {
        connected: state.connected,
        frameId: state.frame?.frameId || 0,
        binaryTransport: state.frame?.binaryTransport,
        imageByteLength: state.frame?.imageByteLength,
        imageSource: state.frameImageSource,
        naturalWidth: state.frameImage?.naturalWidth || 0,
        naturalHeight: state.frameImage?.naturalHeight || 0,
        canvasWidth: document.getElementById("streamCanvas").width,
        canvasHeight: document.getElementById("streamCanvas").height
      };
    });
    assert.equal(renderState.connected, true);
    assert.equal(renderState.binaryTransport, true);
    assert.match(renderState.imageSource, /^blob:/);
    assert.equal(renderState.naturalWidth > 0, true);
    assert.equal(renderState.naturalHeight > 0, true);
    assert.equal(renderState.canvasWidth > 0, true);
    assert.equal(renderState.canvasHeight > 0, true);
    return renderState;
  } finally {
    await browser.close();
    await api("/api/revoke", {
      method: "POST",
      headers: { "x-host-key": hostKey },
      body: JSON.stringify({ sessionId: pair.sessionId })
    }).catch(() => null);
    await api("/api/settings", {
      method: "POST",
      headers: { "x-host-key": hostKey },
      body: JSON.stringify({
        trustedDevicesEnabled: host.settings.trustedDevicesEnabled,
        qualityDefault: host.settings.qualityDefault,
        inputSensitivityDefault: host.settings.inputSensitivityDefault
      })
    }).catch(() => null);
  }
}

async function main() {
  const health = await api("/api/health");
  assert.equal(health.ok, true);
  assert.equal(health.protocol, 1);
  assert.equal(health.state.monitors, undefined);
  assert.equal(health.state.logs, undefined);
  assert.equal(health.state.sessions, undefined);
  assert.equal(health.state.settings, undefined);
  assert.equal(typeof health.state.connectionSetup.sameWifi.status, "string");
  assert.equal(typeof health.state.connectionSetup.tailscale.status, "string");

  const appShell = await fetch(`${baseUrl}/`);
  assert.equal(appShell.ok, true);
  assert.equal(appShell.headers.get("x-content-type-options"), "nosniff");
  assert.equal(appShell.headers.get("referrer-policy"), "no-referrer");
  const csp = appShell.headers.get("content-security-policy") || "";
  assert.match(csp, /default-src 'self'/);
  assert.match(csp, /script-src 'self'/);
  assert.match(csp, /img-src 'self' data: blob:/);
  assert.match(csp, /connect-src 'self' ws: wss:/);
  assert.match(csp, /frame-ancestors 'none'/);

  const forbiddenHost = await fetch(`${baseUrl}/api/host`);
  assert.equal(forbiddenHost.status, 403);
  const forbiddenHostBody = await forbiddenHost.json();
  assert.equal(forbiddenHostBody.error, "BAD_HOST_KEY");
  assert.equal(forbiddenHostBody.code, "BAD_HOST_KEY");
  assert.equal(forbiddenHostBody.recoverable, true);
  assert.match(forbiddenHostBody.nextAction, /host console|host key/i);

  const oversizedPair = await fetch(`${baseUrl}/api/pair`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ pin: "000000", deviceName: "x".repeat(70 * 1024) })
  });
  assert.equal(oversizedPair.status, 413);
  const oversizedPairBody = await oversizedPair.json();
  assert.equal(oversizedPairBody.error, "PAYLOAD_TOO_LARGE");
  assert.equal(oversizedPairBody.code, "PAYLOAD_TOO_LARGE");
  assert.equal(oversizedPairBody.detail.maxBytes, 64 * 1024);
  assert.match(oversizedPairBody.nextAction, /normal phone request/i);

  const initialHost = await api(`/api/host?key=${encodeURIComponent(hostKey)}`);
  assert.equal(initialHost.monitors.length >= 1, true);
  assert.ok(initialHost.settings);
  const dryRunMode = await api("/api/input-mode", {
    method: "POST",
    headers: { "x-host-key": hostKey },
    body: JSON.stringify({ enabled: false })
  });
  assert.equal(dryRunMode.inputSafety.enabled, false);

  const manifest = await api("/manifest.json");
  assert.equal(manifest.display, "standalone");
  assert.equal(manifest.icons.length >= 1, true);

  const swResponse = await fetch(`${baseUrl}/sw.js`);
  assert.equal(swResponse.ok, true);
  const swSource = await swResponse.text();
  assert.equal(swSource.includes("CACHE_NAME"), true);
  const shellAssets = swSource.match(/const SHELL_ASSETS = \[([\s\S]*?)\];/)?.[1] || "";
  assert.equal(shellAssets.includes('"/host.html"'), false);
  assert.equal(shellAssets.includes('"/host.js"'), false);
  assert.match(swSource, /url\.search/);
  assert.match(swSource, /event\.request\.method !== "GET"/);

  const updatedSettings = await api("/api/settings", {
    method: "POST",
    headers: { "x-host-key": hostKey },
    body: JSON.stringify({ qualityDefault: "balanced", inputSensitivityDefault: 1.15, trustedDevicesEnabled: true })
  });
  assert.equal(updatedSettings.ok, true);
  assert.equal(updatedSettings.settings.qualityDefault, "balanced");
  assert.equal(updatedSettings.settings.inputSensitivityDefault, 1.15);
  assert.equal(updatedSettings.settings.trustedDevicesEnabled, true);
  await api("/api/trusted-devices/clear", {
    method: "POST",
    headers: { "x-host-key": hostKey },
    body: "{}"
  });
  const targetMonitorId = initialHost.monitors.at(-1).id;

  const pin = initialHost.securityStatus.pairing.pin;
  const pair = await api("/api/pair", {
    method: "POST",
    body: JSON.stringify({ pin, deviceName: "Smoke Test Phone" })
  });
  assert.equal(pair.ok, true);
  assert.equal(pair.approved, false);
  assert.ok(pair.token);

  const beforeApproval = await api(`/api/session?token=${encodeURIComponent(pair.token)}`);
  assert.equal(beforeApproval.approved, false);

  const approval = await api("/api/approve", {
    method: "POST",
    headers: { "x-host-key": hostKey },
    body: JSON.stringify({ sessionId: pair.sessionId })
  });
  assert.equal(approval.ok, true);

  const approved = await api(`/api/session?token=${encodeURIComponent(pair.token)}`);
  assert.equal(approved.approved, true);
  assert.equal(approved.permissions.pointer, true);
  assert.equal(approved.permissions.keyboard, true);
  assert.equal(approved.permissions.text, true);
  const phoneRenderState = await verifyPhonePageRendersBinaryStream();

  const wsUrl = baseUrl.replace(/^http/, "ws") + `/ws?token=${encodeURIComponent(pair.token)}`;
  const socket = new WebSocket(wsUrl);
  socket.binaryType = "arraybuffer";
  const open = waitForSocket(socket, "open");
  await open;

  const messages = [];
  socket.addEventListener("message", (event) => {
    void parseSocketPacket(event.data).then((packet) => messages.push(packet));
  });

  await waitForMessage(messages, (msg) => msg.type === "hello", 5000, "initial hello");
  const initialFrame = await waitForMessage(messages, (msg) => msg.type === "stream.frame", 5000, "initial stream frame");
  assert.equal(initialFrame.payload.binaryTransport, true);
  assert.equal(initialFrame.payload.imageByteLength > 0, true);

  socket.send(JSON.stringify({
    protocolVersion: 1,
    type: "pointer.move",
    sequence: 1,
    timestamp: Date.now(),
    payload: { mode: "touchpad", dx: 12, dy: 4, normalizedX: 0.25, normalizedY: 0.5 }
  }));
  socket.send(JSON.stringify({
    protocolVersion: 1,
    type: "key",
    sequence: 2,
    timestamp: Date.now(),
    payload: { key: "Esc" }
  }));
  socket.send(JSON.stringify({
    protocolVersion: 1,
    type: "pointer.doubleClick",
    sequence: 3,
    timestamp: Date.now(),
    payload: { button: "left" }
  }));
  socket.send(JSON.stringify({
    protocolVersion: 1,
    type: "chord",
    sequence: 4,
    timestamp: Date.now(),
    payload: { modifiers: ["Ctrl"], key: "C" }
  }));
  socket.send(JSON.stringify({
    protocolVersion: 1,
    type: "pasteText",
    sequence: 5,
    timestamp: Date.now(),
    payload: { text: "smoke text" }
  }));
  socket.send(JSON.stringify({
    protocolVersion: 1,
    type: "pointer.cancelDrag",
    sequence: 6,
    timestamp: Date.now(),
    payload: {}
  }));
  socket.send(JSON.stringify({
    protocolVersion: 1,
    type: "monitor.select",
    sequence: 7,
    timestamp: Date.now(),
    payload: { monitorId: targetMonitorId }
  }));
  socket.send(JSON.stringify({
    protocolVersion: 1,
    type: "stream.setQuality",
    sequence: 8,
    timestamp: Date.now(),
    payload: { quality: "fast" }
  }));
  socket.send(JSON.stringify({
    protocolVersion: 1,
    type: "acceptance.mark",
    sequence: 9,
    timestamp: Date.now(),
    payload: {
      marker: "manual-phone-proof",
      gate: "same-wifi",
      step: "live-smoke",
      urlOrigin: baseUrl,
      urlPath: "/",
      userAgent: "Smoke Test Agent",
      viewport: { width: 390, height: 844, devicePixelRatio: 2, orientation: "portrait-primary" },
      screen: { width: 390, height: 844 },
      features: { touch: true, standalone: false, serviceWorker: true, vibration: false },
      diagnostics: { frameId: 1, monitor: targetMonitorId, quality: "fast", inputMode: "touchpad", precisionMode: false, viewportZoom: 1, fpsApprox: 2, inputRttMs: 12 }
    }
  }));

  await new Promise((resolve) => setTimeout(resolve, 500));
  assert.equal(messages.some((msg) => msg.type === "ack" && msg.payload.ackType === "pointer.move" && msg.payload.dryRun), true);
  assert.equal(messages.some((msg) => msg.type === "ack" && msg.payload.ackType === "key" && msg.payload.dryRun), true);
  assert.equal(messages.some((msg) => msg.type === "ack" && msg.payload.ackType === "pointer.doubleClick" && msg.payload.dryRun), true);
  assert.equal(messages.some((msg) => msg.type === "ack" && msg.payload.ackType === "chord" && msg.payload.dryRun), true);
  assert.equal(messages.some((msg) => msg.type === "ack" && msg.payload.ackType === "pasteText" && msg.payload.dryRun), true);
  assert.equal(messages.some((msg) => msg.type === "ack" && msg.payload.ackType === "pointer.cancelDrag" && msg.payload.dryRun), true);
  assert.equal(messages.some((msg) => msg.type === "ack" && msg.payload.ackType === "monitor.select" && msg.payload.sequence === 7 && msg.payload.selectedMonitorId === targetMonitorId), true);
  assert.equal(messages.some((msg) => msg.type === "ack" && msg.payload.ackType === "stream.setQuality" && msg.payload.sequence === 8 && msg.payload.quality === "fast"), true);
  assert.equal(messages.some((msg) => msg.type === "ack" && msg.payload.ackType === "acceptance.mark" && msg.payload.sequence === 9 && msg.payload.marker === "manual-phone-proof"), true);

  for (let sequence = 10; sequence < 28; sequence += 1) {
    socket.send(JSON.stringify({
      protocolVersion: 1,
      type: "pointer.move",
      sequence,
      timestamp: Date.now(),
      payload: { mode: "touchpad", dx: 4, dy: 3, source: "input-burst-smoke" }
    }));
  }
  await waitForMessage(messages, (msg) => msg.type === "ack" && msg.payload.ackType === "pointer.move" && msg.payload.sequence === 27, 5000, "pointer burst ack");
  await new Promise((resolve) => setTimeout(resolve, 300));

  await closeSocket(socket);

  const reconnect = new WebSocket(wsUrl);
  reconnect.binaryType = "arraybuffer";
  const reconnectMessages = [];
  reconnect.addEventListener("message", (event) => {
    void parseSocketPacket(event.data).then((packet) => reconnectMessages.push(packet));
  });
  await waitForSocket(reconnect, "open");
  await waitForMessage(reconnectMessages, (msg) => msg.type === "hello", 5000, "reconnect hello");
  await waitForMessage(reconnectMessages, (msg) => msg.type === "stream.frame", 5000, "reconnect stream frame");

  const beforeHidden = await api(`/api/host?key=${encodeURIComponent(hostKey)}`);
  reconnect.send(JSON.stringify({
    protocolVersion: 1,
    type: "stream.visibility",
    sequence: 19,
    timestamp: Date.now(),
    payload: { visible: false, hidden: true }
  }));
  await waitForMessage(reconnectMessages, (msg) => msg.type === "ack" && msg.payload.ackType === "stream.visibility" && msg.payload.sequence === 19 && msg.payload.visible === false, 5000, "stream visibility ack");
  await new Promise((resolve) => setTimeout(resolve, 700));

  const finalState = await api(`/api/host?key=${encodeURIComponent(hostKey)}`);
  assert.equal(finalState.selectedMonitorId, targetMonitorId);
  assert.equal(finalState.logs.some((entry) => entry.event === "input.dryRun"), true);
  const proofLog = finalState.latestPhoneProof;
  assert.equal(Boolean(proofLog), true);
  assert.equal(proofLog.detail.proof.viewport.width, 390);
  assert.equal(proofLog.detail.proof.features.touch, true);
  assert.equal(proofLog.detail.proof.urlPath, "/");
  assert.equal(finalState.latestPhoneProof.event, "acceptance.phoneMark");
  assert.equal(finalState.latestPhoneProof.detail.proof.marker, "manual-phone-proof");
  assert.equal(finalState.streamStats.quality, "fast");
  assert.equal(typeof finalState.streamStats.lastCaptureMs, "number");
  assert.equal(finalState.streamStats.framesSent >= 1, true);
  assert.equal(finalState.streamStats.stateBroadcastThrottleMs, 250);
  assert.equal(finalState.streamStats.deferredStateBroadcasts >= 1, true);
  assert.equal(["responsive", "preset", "idle", "hidden"].includes(finalState.streamStats.adaptiveMode), true);
  assert.equal(typeof finalState.streamStats.presetFpsTarget, "number");
  assert.equal(typeof finalState.streamStats.fpsTarget, "number");
  assert.equal(finalState.streamStats.visibleClients + finalState.streamStats.hiddenClients >= 1, true);
  assert.equal(typeof finalState.streamStats.hiddenFrameTicks, "number");
  assert.equal(finalState.streamStats.framesSent >= beforeHidden.streamStats.framesSent, true);
  assert.equal(typeof finalState.securityStatus.networkValidation.sameWifi.detail, "string");
  assert.equal(Array.isArray(finalState.trustedDevices), true);
  assert.equal(finalState.trustedDevices.length >= 1, true);
  assert.equal(Object.hasOwn(finalState.trustedDevices[0], "key"), false);

  const trustRevoke = await api("/api/trusted-device/revoke", {
    method: "POST",
    headers: { "x-host-key": hostKey },
    body: JSON.stringify({ deviceId: finalState.trustedDevices[0].id })
  });
  assert.equal(trustRevoke.ok, true);
  assert.equal(trustRevoke.trustedDevices.length, 0);
  assert.equal(trustRevoke.revokedSessions >= 1, true);

  const disabledTrust = await api("/api/settings", {
    method: "POST",
    headers: { "x-host-key": hostKey },
    body: JSON.stringify({ trustedDevicesEnabled: false, qualityDefault: "balanced", inputSensitivityDefault: 1.15 })
  });
  assert.equal(disabledTrust.settings.trustedDevicesEnabled, false);

  const exportedLogs = await api(`/api/logs?key=${encodeURIComponent(hostKey)}`);
  assert.equal(Array.isArray(exportedLogs.logs), true);
  assert.equal(exportedLogs.logs.length >= 1, true);
  assert.equal(exportedLogs.logs.some((entry) => entry.event === "monitor.select"), true);
  assert.equal(exportedLogs.latestPhoneProof.event, "acceptance.phoneMark");
  assert.equal(exportedLogs.logs.some((entry) => entry.id === exportedLogs.latestPhoneProof.id), true);
  assert.equal(exportedLogs.state.streamStats.source, finalState.streamStats.source);
  assert.equal(JSON.stringify(exportedLogs).includes("smoke text"), false);
  const pasteLog = exportedLogs.logs.find((entry) => entry.event === "input.dryRun" && entry.detail.commandType === "pasteText");
  assert.equal(pasteLog.detail.input.textLength, "smoke text".length);
  assert.equal(Object.hasOwn(pasteLog.detail.input, "text"), false);

  await closeSocket(reconnect);
  const kill = await api("/api/kill-switch", {
    method: "POST",
    headers: { "x-host-key": hostKey },
    body: "{}"
  });
  assert.equal(kill.ok, true);
  assert.equal(kill.inputSafety.enabled, false);
  console.log(JSON.stringify({
    ok: true,
    sessionId: pair.sessionId,
    framesSeen: messages.filter((msg) => msg.type === "stream.frame").length + reconnectMessages.filter((msg) => msg.type === "stream.frame").length,
    dryRunLogs: finalState.logs.filter((entry) => entry.event === "input.dryRun").length,
    selectedMonitorId: finalState.selectedMonitorId,
    quality: finalState.streamStats.quality,
    reconnectFramesSeen: reconnectMessages.filter((msg) => msg.type === "stream.frame").length,
    phoneRenderFrameId: phoneRenderState.frameId,
    continuousStream: finalState.streamStats.fpsTarget > 0,
    killSwitch: kill.ok
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

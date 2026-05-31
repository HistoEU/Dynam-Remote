"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { chromium } = require("playwright");

const baseUrl = process.env.BASE_URL || "http://127.0.0.1:4317";

test("phone decodes binary JPEG stream packets into image-backed frames", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true
    });
    await page.goto(baseUrl, { waitUntil: "load" });

    const result = await page.evaluate(async () => {
      const header = {
        protocolVersion: 1,
        type: "stream.frame",
        timestamp: Date.now(),
        payload: {
          frameId: 42,
          monitorId: "display-1",
          width: 2,
          height: 2,
          scaleFactor: 1,
          quality: "fast",
          inputMode: "touchpad",
          cursor: { x: 1, y: 1, coordinateSpace: "physical-frame", visible: true },
          windows: [],
          desktopLabel: "Binary Test",
          capturedAt: Date.now(),
          mimeType: "image/jpeg",
          binaryImage: { protocol: 1, frameId: 42, mimeType: "image/jpeg", byteLength: 4 },
          source: "screen"
        }
      };
      const headerBytes = new TextEncoder().encode(JSON.stringify(header));
      const imageBytes = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
      const packet = new Uint8Array(8 + headerBytes.length + imageBytes.length);
      packet.set([0x52, 0x44, 0x43, 0x46], 0);
      new DataView(packet.buffer).setUint32(4, headerBytes.length);
      packet.set(headerBytes, 8);
      packet.set(imageBytes, 8 + headerBytes.length);

      const decoded = await window.__remoteControllerDebug.decodeBinaryStreamPacket(packet.buffer);
      window.__remoteControllerDebug.handleServerPacket(decoded);
      return {
        type: decoded.type,
        frameId: window.__remoteControllerDebug.state.frame.frameId,
        binaryTransport: window.__remoteControllerDebug.state.frame.binaryTransport,
        imageByteLength: window.__remoteControllerDebug.state.frame.imageByteLength,
        objectUrl: window.__remoteControllerDebug.state.frame.imageObjectUrl
      };
    });

    assert.equal(result.type, "stream.frame");
    assert.equal(result.frameId, 42);
    assert.equal(result.binaryTransport, true);
    assert.equal(result.imageByteLength, 4);
    assert.match(result.objectUrl, /^blob:/);
  } finally {
    await browser.close();
  }
});

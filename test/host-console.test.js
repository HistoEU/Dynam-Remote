"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const { chromium } = require("playwright");

const baseUrl = process.env.BASE_URL || "http://127.0.0.1:4317";
const hostKey = process.env.HOST_KEY || "dev-host-key";

async function api(pathname, options = {}) {
  const response = await fetch(`${baseUrl}${pathname}`, {
    headers: { "content-type": "application/json", ...(options.headers || {}) },
    ...options
  });
  const body = await response.json();
  if (!response.ok) {
    throw new Error(`${pathname} failed: ${response.status} ${JSON.stringify(body)}`);
  }
  return body;
}

test("host console exposes copyable phone URLs next to QR codes", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
    await page.goto(`${baseUrl}/host?key=${encodeURIComponent(hostKey)}`, { waitUntil: "load" });
    await page.waitForSelector("[data-copy-url]", { timeout: 5000 });
    await page.evaluate(() => {
      window.__copiedHostUrls = [];
      Object.defineProperty(navigator, "clipboard", {
        configurable: true,
        value: {
          async writeText(value) {
            window.__copiedHostUrls.push(value);
          }
        }
      });
    });

    const firstButton = page.locator("[data-copy-url]").first();
    const url = await firstButton.getAttribute("data-copy-url");
    await firstButton.click();

    const result = await page.evaluate(async () => {
      const state = await fetch(`/api/host?key=${encodeURIComponent(new URLSearchParams(location.search).get("key") || "")}`).then((response) => response.json());
      return {
        copied: window.__copiedHostUrls,
        status: document.querySelector(".address-copy-status")?.textContent || "",
        qrCount: document.querySelectorAll(".address-qr").length,
        copyButtonCount: document.querySelectorAll("[data-copy-url]").length,
        featuredText: document.getElementById("featuredPhoneLink")?.innerText || "",
        featuredUrl: document.querySelector("#featuredPhoneLink [data-copy-url]")?.dataset.copyUrl || "",
        copiedUrls: Array.from(document.querySelectorAll("[data-copy-url]")).map((button) => button.dataset.copyUrl || ""),
        addressQrUrls: Array.from(document.querySelectorAll(".address-qr")).map((img) => new URL(img.src).searchParams.get("url") || ""),
        appVersion: state.app.phoneAppVersion
      };
    });

    assert.ok(url.startsWith("http"));
    assert.deepEqual(result.copied, [url]);
    assert.equal(result.status, "Copied");
    assert.equal(result.qrCount >= 1, true);
    assert.equal(result.copyButtonCount >= 1, true);
    assert.match(result.featuredText, /Paste this on your phone/);
    assert.match(result.featuredUrl, new RegExp(`v=${result.appVersion}`));
    assert.match(result.featuredUrl, /acceptance=1/);
    assert.match(result.featuredUrl, /gate=same-wifi/);
    assert.equal(result.copiedUrls.every((item) => item.includes(`v=${result.appVersion}`)), true);
    assert.equal(result.addressQrUrls.every((item) => item.includes(`v=${result.appVersion}`)), true);

    await page.screenshot({
      path: path.join("output", "playwright", "host-console-copy-addresses.png"),
      fullPage: true
    });
  } finally {
    await browser.close();
  }
});

test("host console labels recommended, secondary, and Tailscale phone URLs", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
    await page.goto(`${baseUrl}/host?key=${encodeURIComponent(hostKey)}`, { waitUntil: "load" });
    await page.waitForSelector("[data-copy-url]", { timeout: 5000 });

    const guidance = await page.evaluate(async () => {
      const state = await fetch(`/api/host?key=${encodeURIComponent(new URLSearchParams(location.search).get("key") || "")}`).then((response) => response.json());
      return {
        ethernet: window.__remoteHostDebug.getAddressGuidance({ kind: "lan", name: "Ethernet", url: "http://192.168.0.7:4317" }),
        nord: window.__remoteHostDebug.getAddressGuidance({ kind: "lan", name: "NordLynx", url: "http://10.5.0.2:4317" }),
        tailscale: window.__remoteHostDebug.getAddressGuidance({ kind: "tailscale", name: "Tailscale", url: "http://100.80.1.2:4317" }),
        versioned: window.__remoteHostDebug.versionPhoneUrl("http://192.168.0.7:4317"),
        preservesVersion: window.__remoteHostDebug.versionPhoneUrl("http://192.168.0.7:4317?v=76"),
        apiVersion: state.app.phoneAppVersion,
        visibleBadgeCount: document.querySelectorAll(".address-badge").length
      };
    });

    assert.equal(guidance.ethernet.label, "Recommended");
    assert.equal(guidance.nord.label, "Secondary");
    assert.equal(guidance.tailscale.label, "Different Wi-Fi");
    assert.equal(guidance.versioned, `http://192.168.0.7:4317/?v=${guidance.apiVersion}`);
    assert.equal(guidance.preservesVersion, "http://192.168.0.7:4317/?v=76");
    assert.equal(guidance.visibleBadgeCount >= 1, true);
  } finally {
    await browser.close();
  }
});

test("host console renders phone-supplied names as text", async () => {
  const initialHost = await api(`/api/host?key=${encodeURIComponent(hostKey)}`);
  const maliciousName = "\"><img src=x onerror=\"window.__hostConsoleXss=1\">";
  const pair = await api("/api/pair", {
    method: "POST",
    body: JSON.stringify({ pin: initialHost.securityStatus.pairing.pin, deviceName: maliciousName })
  });

  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
    await page.addInitScript(() => {
      window.__hostConsoleXss = 0;
    });
    await page.goto(`${baseUrl}/host?key=${encodeURIComponent(hostKey)}`, { waitUntil: "load" });
    await page.waitForSelector("[data-revoke]", { timeout: 5000 });
    const result = await page.evaluate(() => ({
      xss: window.__hostConsoleXss,
      sessionText: document.getElementById("sessionList").innerText,
      injectedImages: document.querySelectorAll("#sessionList img").length
    }));

    assert.equal(result.xss, 0);
    assert.equal(result.injectedImages, 0);
    assert.match(result.sessionText, /<img src=x onerror=/);
  } finally {
    await api("/api/revoke", {
      method: "POST",
      headers: { "x-host-key": hostKey },
      body: JSON.stringify({ sessionId: pair.sessionId })
    }).catch(() => {});
    await browser.close();
  }
});

test("host console summarizes latest phone proof marker", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
    await page.goto(`${baseUrl}/host?key=${encodeURIComponent(hostKey)}`, { waitUntil: "load" });
    await page.waitForSelector("#latestProof", { state: "attached", timeout: 5000 });
    const result = await page.evaluate(() => {
      window.__remoteHostDebug.renderLatestProof([
        {
          at: Date.now(),
          event: "acceptance.phoneMark",
          detail: {
            proof: {
              gate: "same-wifi",
              step: "physical-phone-proof",
              urlOrigin: "http://192.168.0.7:4317",
              viewport: { width: 390, height: 844 },
              diagnostics: { monitor: "display-1", fpsApprox: 12.5 },
              checklist: {
                gate: "same-wifi",
                requiredCount: 13,
                passedCount: 13,
                complete: true,
                items: Array.from({ length: 13 }, (_, index) => ({
                  id: `same-wifi-${index + 1}`,
                  label: `Checklist item ${index + 1}`,
                  checked: true
                }))
              }
            }
          }
        }
      ]);
      const incomplete = window.__remoteHostDebug.formatProofChecklist({
        requiredCount: 9,
        passedCount: 8,
        complete: false,
        items: Array.from({ length: 9 }, (_, index) => ({ checked: index < 8 }))
      });
      const missing = window.__remoteHostDebug.formatProofChecklist(null);
      return {
        text: document.getElementById("latestProof").innerText,
        incompleteChecklist: incomplete.summary,
        missingChecklist: missing.summary,
        latestGate: window.__remoteHostDebug.latestProofLog([
          { event: "other", detail: {} },
          { event: "acceptance.phoneMark", detail: { proof: { gate: "tailscale" } } }
        ]).detail.proof.gate,
        preferredPhysicalGate: window.__remoteHostDebug.latestProofLog([
          {
            at: Date.now(),
            event: "acceptance.phoneMark",
            detail: { proof: { gate: "same-wifi", step: "live-smoke" } }
          },
          {
            at: Date.now() - 1,
            event: "acceptance.phoneMark",
            detail: {
              proof: {
                gate: "tailscale",
                step: "physical-phone-proof",
                checklist: {
                  gate: "tailscale",
                  requiredCount: 9,
                  passedCount: 9,
                  complete: true,
                  items: Array.from({ length: 9 }, () => ({ checked: true }))
                }
              }
            }
          }
        ]).detail.proof.gate
      };
    });

    assert.match(result.text, /saved/);
    assert.match(result.text, /same-wifi/);
    assert.match(result.text, /physical-phone-proof/);
    assert.match(result.text, /192\.168\.0\.7/);
    assert.match(result.text, /390 x 844/);
    assert.match(result.text, /13 \/ 13 complete/);
    assert.match(result.text, /Checked Items/);
    assert.equal(result.incompleteChecklist, "8 / 9 incomplete");
    assert.equal(result.missingChecklist, "missing");
    assert.equal(result.latestGate, "tailscale");
    assert.equal(result.preferredPhysicalGate, "tailscale");
  } finally {
    await browser.close();
  }
});

test("host console exposes gate-aware physical proof links", async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
    await page.goto(`${baseUrl}/host?key=${encodeURIComponent(hostKey)}`, { waitUntil: "load" });
    await page.waitForSelector("#proofLinkList", { timeout: 5000 });
    const result = await page.evaluate(() => {
      const links = window.__remoteHostDebug.getProofLinks([
        { kind: "lan", name: "Ethernet", url: "http://192.168.0.7:4317" },
        { kind: "lan", name: "NordLynx", url: "http://10.5.0.2:4317" },
        { kind: "tailscale", name: "Tailscale", url: "http://100.80.1.2:4317" }
      ]);
      return {
        links,
        addQuery: window.__remoteHostDebug.addAcceptanceQuery("http://192.168.0.7:4317", "same-wifi"),
        visibleText: document.getElementById("proofLinkList").innerText,
      copyUrls: Array.from(document.querySelectorAll("#proofLinkList [data-copy-url]")).map((button) => button.dataset.copyUrl)
    };
  });

    assert.equal(result.links.length, 2);
    assert.equal(await page.evaluate(() => window.__remoteHostDebug.getPrimaryPhoneLink([
      { kind: "lan", name: "Ethernet", url: "http://192.168.0.7:4317" },
      { kind: "lan", name: "NordLynx", url: "http://10.5.0.2:4317" }
    ]).url.includes("192.168.0.7")), true);
    assert.equal(result.links[0].gate, "same-wifi");
    assert.match(result.links[0].url, /acceptance=1/);
    assert.match(result.links[0].url, /v=\d+/);
    assert.match(result.links[0].url, /gate=same-wifi/);
    assert.equal(result.links[0].url.includes("10.5.0.2"), false);
    assert.equal(result.links[1].gate, "tailscale");
    assert.match(result.links[1].url, /gate=tailscale/);
    assert.match(result.addQuery, /step=physical-phone-proof/);
    assert.match(result.addQuery, /v=\d+/);
    assert.match(result.visibleText, /Same-Wi-Fi Proof|No proof links/);
    assert.equal(result.copyUrls.every((url) => url.includes("acceptance=1")), true);
  } finally {
    await browser.close();
  }
});

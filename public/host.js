"use strict";

const params = new URLSearchParams(location.search);
const hostKey = params.get("key") || "";
let phoneAppVersion = "dev";
let lastAutoCaptureUiAttemptAt = 0;
const el = {
  hostStatus: document.getElementById("hostStatus"),
  pinBox: document.getElementById("pinBox"),
  pinTimer: document.getElementById("pinTimer"),
  rateLimitState: document.getElementById("rateLimitState"),
  featuredPhoneLink: document.getElementById("featuredPhoneLink"),
  rtcStatusText: document.getElementById("rtcStatusText"),
  captureVideoLink: document.getElementById("captureVideoLink"),
  openCaptureWindow: document.getElementById("openCaptureWindow"),
  captureLaunchStatus: document.getElementById("captureLaunchStatus"),
  addressList: document.getElementById("addressList"),
  sessionList: document.getElementById("sessionList"),
  inputModeState: document.getElementById("inputModeState"),
  networkRiskState: document.getElementById("networkRiskState"),
  connectionSetup: document.getElementById("connectionSetup"),
  latestProof: document.getElementById("latestProof"),
  proofLinkList: document.getElementById("proofLinkList"),
  toggleInput: document.getElementById("toggleInput"),
  safetyRelease: document.getElementById("safetyRelease"),
  killSwitch: document.getElementById("killSwitch"),
  settingsForm: document.getElementById("settingsForm"),
  defaultQuality: document.getElementById("defaultQuality"),
  defaultSensitivity: document.getElementById("defaultSensitivity"),
  trustedDevices: document.getElementById("trustedDevices"),
  autoStart: document.getElementById("autoStart"),
  trustedDeviceList: document.getElementById("trustedDeviceList"),
  clearTrustedDevices: document.getElementById("clearTrustedDevices"),
  logList: document.getElementById("logList"),
  exportLogs: document.getElementById("exportLogs"),
  refreshPin: document.getElementById("refreshPin")
};

async function hostApi(path, options = {}) {
  const response = await fetch(path, {
    headers: {
      "Content-Type": "application/json",
      "x-host-key": hostKey,
      ...(options.headers || {})
    },
    ...options
  });
  const data = await response.json();
  if (!response.ok) {
    const message = data.nextAction
      ? `${data.message || data.error || "Host request failed"} ${data.nextAction}`
      : data.message || data.error || "Host request failed";
    const error = new Error(message);
    error.code = data.code || data.error;
    error.nextAction = data.nextAction;
    throw error;
  }
  return data;
}

function versionPhoneUrl(url) {
  const base = String(url || "");
  const version = phoneAppVersion || "dev";
  try {
    const phoneUrl = new URL(base, window.location.origin);
    if (!phoneUrl.searchParams.has("v")) phoneUrl.searchParams.set("v", version);
    return phoneUrl.href;
  } catch {
    if (/(\?|&)v=/.test(base)) return base;
    return `${base}${base.includes("?") ? "&" : "?"}v=${version}`;
  }
}

function createAddressRow(address) {
  const item = document.createElement("div");
  const guidance = getAddressGuidance(address);
  const phoneUrl = versionPhoneUrl(address.url);
  item.className = `address-row ${guidance.className}`;

  const details = document.createElement("div");
  const title = document.createElement("strong");
  title.textContent = `${String(address.kind || "").toUpperCase()} ${address.name || "Address"}`;
  const badge = document.createElement("small");
  badge.className = `address-badge ${guidance.className}`;
  badge.textContent = guidance.label;
  const url = document.createElement("span");
  url.textContent = phoneUrl;
  const note = document.createElement("small");
  note.className = "address-note";
  note.textContent = guidance.detail;
  details.append(title, badge, url, note);

  const actions = document.createElement("div");
  actions.className = "address-actions";
  const copy = document.createElement("button");
  copy.className = "subtle";
  copy.type = "button";
  copy.textContent = "Copy";
  copy.dataset.copyUrl = phoneUrl;
  copy.title = `Copy ${address.kind || "phone"} URL`;
  const status = document.createElement("small");
  status.className = "address-copy-status";
  status.setAttribute("aria-live", "polite");
  actions.append(copy, status);

  const qr = document.createElement("img");
  qr.alt = "";
  qr.className = "address-qr";
  qr.src = `/api/qr?key=${encodeURIComponent(hostKey)}&url=${encodeURIComponent(phoneUrl)}`;

  item.append(details, actions, qr);
  return item;
}

function getPrimaryPhoneLink(addresses = []) {
  const links = getProofLinks(addresses);
  return links.find((link) => link.gate === "same-wifi") || links[0] || null;
}

function renderFeaturedPhoneLink(addresses = []) {
  if (!el.featuredPhoneLink) return;
  el.featuredPhoneLink.textContent = "";
  const link = getPrimaryPhoneLink(addresses);
  if (!link) {
    const empty = document.createElement("p");
    empty.textContent = "No phone link is ready yet. Start the host and refresh this page.";
    el.featuredPhoneLink.appendChild(empty);
    return;
  }

  const label = document.createElement("small");
  label.className = "address-badge recommended";
  label.textContent = link.gate === "same-wifi" ? "Same Wi-Fi" : "Phone URL";
  const instruction = document.createElement("p");
  instruction.textContent = "Paste this on your phone, or scan the QR code.";
  const url = document.createElement("code");
  url.className = "featured-phone-url";
  url.textContent = link.url;

  const actions = document.createElement("div");
  actions.className = "featured-phone-actions";
  const copy = document.createElement("button");
  copy.className = "subtle";
  copy.type = "button";
  copy.textContent = "Copy Phone Link";
  copy.dataset.copyUrl = link.url;
  copy.title = "Copy the phone URL";
  const status = document.createElement("small");
  status.className = "address-copy-status";
  status.setAttribute("aria-live", "polite");
  actions.append(copy, status);

  const qr = document.createElement("img");
  qr.alt = "Phone link QR code";
  qr.className = "featured-phone-qr";
  qr.src = `/api/qr?key=${encodeURIComponent(hostKey)}&url=${encodeURIComponent(link.url)}`;

  el.featuredPhoneLink.append(label, instruction, url, actions, qr);
}

function isVpnLikeAddress(address) {
  return /(vpn|nord|lynx|wireguard|zerotier|hamachi|tap|tun|wg)/i.test(address?.name || "");
}

function addAcceptanceQuery(url, gate) {
  const base = versionPhoneUrl(url);
  try {
    const proofUrl = new URL(base, window.location.origin);
    proofUrl.searchParams.set("acceptance", "1");
    proofUrl.searchParams.set("gate", gate);
    proofUrl.searchParams.set("step", "physical-phone-proof");
    return proofUrl.href;
  } catch {
    const separator = base.includes("?") ? "&" : "?";
    return `${base}${separator}acceptance=1&gate=${encodeURIComponent(gate)}&step=physical-phone-proof`;
  }
}

function getProofLinks(addresses = []) {
  const lan = (addresses || []).filter((address) => address.kind === "lan");
  const recommendedLan = lan.filter((address) => !isVpnLikeAddress(address));
  const sameWifiSources = recommendedLan.length ? recommendedLan : lan;
  const tailscaleSources = (addresses || []).filter((address) => address.kind === "tailscale");
  return [
    ...sameWifiSources.map((address) => ({
      gate: "same-wifi",
      label: "Same-Wi-Fi Proof",
      source: address.name || "LAN",
      url: addAcceptanceQuery(address.url, "same-wifi")
    })),
    ...tailscaleSources.map((address) => ({
      gate: "tailscale",
      label: "Tailscale Proof",
      source: address.name || "Tailscale",
      url: addAcceptanceQuery(address.url, "tailscale")
    }))
  ];
}

function getAddressGuidance(address) {
  if (address?.kind === "tailscale") {
    return {
      label: "Different Wi-Fi",
      className: "different-wifi",
      detail: "Use this only for the Tailscale/different-Wi-Fi gate."
    };
  }
  if (address?.kind === "lan" && isVpnLikeAddress(address)) {
    return {
      label: "Secondary",
      className: "secondary",
      detail: "VPN-like private adapter. Try the recommended same-Wi-Fi URL first."
    };
  }
  if (address?.kind === "lan") {
    return {
      label: "Recommended",
      className: "recommended",
      detail: "Best first choice for the same-Wi-Fi phone run."
    };
  }
  return {
    label: "Advanced",
    className: "secondary",
    detail: "Use only when this is the intentional phone network path."
  };
}

function createSessionRow(session) {
  const item = document.createElement("div");
  item.className = "session-row";

  const details = document.createElement("div");
  const name = document.createElement("strong");
  name.textContent = session.deviceName || "Phone";
  const meta = document.createElement("span");
  const expires = session.expiresAt ? new Date(session.expiresAt).toLocaleDateString() : "unknown expiry";
  const trust = session.trusted ? "trusted" : "manual approval";
  meta.textContent = `${session.remoteAddress || ""} ${session.connected ? "connected" : "idle"} - ${trust} - expires ${expires}`;
  const origin = document.createElement("small");
  origin.textContent = session.allowedOrigin || "no origin recorded";
  details.append(name, document.createElement("br"), meta, document.createElement("br"), origin);
  item.appendChild(details);

  if (!session.approved) {
    const approve = document.createElement("button");
    approve.textContent = "Approve";
    approve.dataset.approve = session.id;
    item.appendChild(approve);
  }
  const revoke = document.createElement("button");
  revoke.className = "danger";
  revoke.textContent = "Revoke";
  revoke.dataset.revoke = session.id;
  item.appendChild(revoke);
  return item;
}

function createTrustedDeviceRow(device) {
  const item = document.createElement("div");
  item.className = "trusted-device-row";

  const details = document.createElement("div");
  const name = document.createElement("strong");
  name.textContent = device.deviceName || "Trusted phone";
  const address = document.createElement("span");
  address.textContent = device.remoteAddress || "no address recorded";
  const dates = document.createElement("small");
  const trustedAt = device.trustedAt ? new Date(device.trustedAt).toLocaleString() : "unknown";
  const lastSeenAt = device.lastSeenAt ? new Date(device.lastSeenAt).toLocaleString() : "never";
  dates.textContent = `trusted ${trustedAt} - last seen ${lastSeenAt}`;
  details.append(name, document.createElement("br"), address, document.createElement("br"), dates);

  const revoke = document.createElement("button");
  revoke.className = "danger";
  revoke.textContent = "Revoke";
  revoke.dataset.revokeTrusted = device.id;
  item.append(details, revoke);
  return item;
}

function createLogRow(entry) {
  const item = document.createElement("div");
  item.className = "log-row";
  const title = document.createElement("strong");
  title.textContent = `${new Date(entry.at).toLocaleTimeString()} ${entry.event}`;
  const detail = document.createElement("span");
  detail.textContent = JSON.stringify(entry.detail);
  item.append(title, detail);
  return item;
}

function isPhysicalProofEntry(entry) {
  const proof = entry?.detail?.proof || {};
  return entry?.event === "acceptance.phoneMark" && proof.step === "physical-phone-proof";
}

function isCompletePhysicalProofEntry(entry) {
  const proof = entry?.detail?.proof || {};
  const checklist = formatProofChecklist(proof.checklist || {});
  return isPhysicalProofEntry(entry) && checklist.complete;
}

function latestProofLog(logs = []) {
  const marks = (logs || []).filter((entry) => entry.event === "acceptance.phoneMark" && entry.detail?.proof);
  return marks.find(isCompletePhysicalProofEntry) || marks.find(isPhysicalProofEntry) || marks[0] || null;
}

function appendProofRow(parent, label, value) {
  const row = document.createElement("div");
  row.className = "proof-row";
  const key = document.createElement("span");
  key.textContent = label;
  const text = document.createElement("strong");
  text.textContent = value || "none";
  row.append(key, text);
  parent.appendChild(row);
}

function formatProofChecklist(checklist = {}) {
  const safeChecklist = checklist && typeof checklist === "object" ? checklist : {};
  const required = Number(safeChecklist.requiredCount || 0);
  const passed = Number(safeChecklist.passedCount || 0);
  const items = Array.isArray(safeChecklist.items) ? safeChecklist.items : [];
  const checkedItems = items.filter((item) => item?.checked === true).length;
  const complete = safeChecklist.complete === true && required > 0 && passed === required && checkedItems === required;
  return {
    complete,
    summary: required > 0 ? `${passed} / ${required}${complete ? " complete" : " incomplete"}` : "missing",
    checkedItems,
    required
  };
}

function renderLatestProof(logs = []) {
  el.latestProof.textContent = "";
  const entry = latestProofLog(logs);
  if (!entry) {
    const empty = document.createElement("p");
    empty.textContent = "No phone proof marker has been saved yet.";
    el.latestProof.appendChild(empty);
    return;
  }

  const proof = entry.detail?.proof || {};
  const checklist = formatProofChecklist(proof.checklist);
  const isPhysical = isPhysicalProofEntry(entry);
  const isCompletePhysical = isCompletePhysicalProofEntry(entry);
  const status = document.createElement("div");
  status.className = "proof-status";
  const badge = document.createElement("span");
  badge.className = `status-pill ${isCompletePhysical ? "ready" : "warning"}`;
  badge.textContent = isCompletePhysical ? "physical saved" : isPhysical ? "needs checklist" : "not physical";
  const time = document.createElement("span");
  time.textContent = new Date(entry.at).toLocaleString();
  status.append(badge, time);
  el.latestProof.appendChild(status);

  appendProofRow(el.latestProof, "Gate", proof.gate || "missing");
  appendProofRow(el.latestProof, "Origin", proof.urlOrigin || "");
  appendProofRow(el.latestProof, "Step", proof.step || "");
  appendProofRow(el.latestProof, "Viewport", proof.viewport ? `${proof.viewport.width || 0} x ${proof.viewport.height || 0}` : "");
  appendProofRow(el.latestProof, "Monitor", proof.diagnostics?.monitor || "");
  appendProofRow(el.latestProof, "FPS", proof.diagnostics?.fpsApprox !== undefined ? String(proof.diagnostics.fpsApprox) : "");
  appendProofRow(el.latestProof, "Checklist", checklist.summary);
  appendProofRow(el.latestProof, "Checked Items", checklist.required > 0 ? `${checklist.checkedItems} / ${checklist.required}` : "missing");
}

function createProofLinkRow(link) {
  const item = document.createElement("div");
  item.className = `proof-link-row ${link.gate}`;

  const details = document.createElement("div");
  const title = document.createElement("strong");
  title.textContent = link.label;
  const source = document.createElement("small");
  source.textContent = link.source;
  const url = document.createElement("span");
  url.textContent = link.url;
  details.append(title, document.createElement("br"), source, document.createElement("br"), url);

  const actions = document.createElement("div");
  actions.className = "address-actions";
  const copy = document.createElement("button");
  copy.className = "subtle";
  copy.type = "button";
  copy.textContent = "Copy";
  copy.dataset.copyUrl = link.url;
  copy.title = `Copy ${link.label} URL`;
  const status = document.createElement("small");
  status.className = "address-copy-status";
  status.setAttribute("aria-live", "polite");
  actions.append(copy, status);

  const qr = document.createElement("img");
  qr.alt = "";
  qr.className = "address-qr";
  qr.src = `/api/qr?key=${encodeURIComponent(hostKey)}&url=${encodeURIComponent(link.url)}`;

  item.append(details, actions, qr);
  return item;
}

function renderProofLinks(addresses = []) {
  el.proofLinkList.textContent = "";
  const links = getProofLinks(addresses);
  if (!links.length) {
    const empty = document.createElement("p");
    empty.textContent = "No proof links are currently available.";
    el.proofLinkList.appendChild(empty);
    return;
  }
  for (const link of links) {
    el.proofLinkList.appendChild(createProofLinkRow(link));
  }
}

function createConnectionCard(item) {
  const card = document.createElement("div");
  card.className = "connection-card";
  const statusClass = item.status === "ready" ? "ready" : item.status === "testing-only" ? "warning" : "missing";

  const head = document.createElement("div");
  head.className = "connection-card-head";
  const label = document.createElement("strong");
  label.textContent = item.label || "Connection";
  const status = document.createElement("span");
  status.className = `status-pill ${statusClass}`;
  status.textContent = item.status || "missing";
  head.append(label, status);

  const detail = document.createElement("p");
  detail.textContent = item.detail || "";
  card.append(head, detail);

  if (item.url) {
    const code = document.createElement("code");
    code.textContent = item.url;
    card.appendChild(code);
  }

  const list = document.createElement("ul");
  for (const check of item.checks || []) {
    const li = document.createElement("li");
    li.textContent = check;
    list.appendChild(li);
  }
  card.appendChild(list);
  return card;
}

async function copyAddressToClipboard(button) {
  const url = button.dataset.copyUrl;
  const status = button.parentElement?.querySelector(".address-copy-status");
  try {
    await navigator.clipboard.writeText(url);
    if (status) status.textContent = "Copied";
  } catch {
    if (status) status.textContent = "Copy failed";
  }
}

function render(state) {
  phoneAppVersion = state.app?.phoneAppVersion || phoneAppVersion || "dev";
  const modeLabel = state.app.displayMode || state.app.mode;
  el.hostStatus.textContent = `${modeLabel} - uptime ${state.app.uptimeSeconds}s - ${state.streamStats.connectedClients} client(s) - ${state.streamStats.lastCaptureMs}ms capture`;
  el.pinBox.textContent = state.securityStatus.pairing.pin;
  el.pinTimer.textContent = `${state.securityStatus.pairing.secondsRemaining}s remaining`;
  const limit = state.securityStatus.pairing.rateLimit;
  el.rateLimitState.textContent = `${limit.recentFailures} recent wrong PIN attempt(s), ${limit.lockedRemotes} locked remote(s)`;
  el.addressList.textContent = "";
  renderFeaturedPhoneLink(state.addresses || []);
  renderRtcStatus(state);
  for (const address of state.addresses) {
    el.addressList.appendChild(createAddressRow(address));
  }
  renderProofLinks(state.addresses || []);
  el.sessionList.textContent = "";
  for (const session of state.sessions) {
    el.sessionList.appendChild(createSessionRow(session));
  }
  const inputEnabled = Boolean(state.inputSafety?.enabled);
  el.inputModeState.textContent = inputEnabled
    ? "Real input is enabled. Phone commands can move the mouse and type."
    : "Dry-run is active. Phone commands are logged but not injected.";
  el.toggleInput.textContent = inputEnabled ? "Disable Real Input" : "Enable Real Input";
  el.toggleInput.classList.toggle("danger", inputEnabled);
  const risk = state.securityStatus.networkRisk;
  el.networkRiskState.textContent = `${risk.level}: ${risk.message}`;
  el.networkRiskState.className = risk.level === "public-tunnel" ? "risk danger-text" : "risk";
  renderConnectionSetup(state.securityStatus.networkValidation);
  renderLatestProof(state.logs || []);
  el.defaultQuality.value = state.settings?.qualityDefault || "balanced";
  el.defaultSensitivity.value = String(state.settings?.inputSensitivityDefault || 1);
  el.trustedDevices.checked = Boolean(state.settings?.trustedDevicesEnabled);
  el.autoStart.checked = Boolean(state.settings?.autoStart);
  renderTrustedDevices(state.trustedDevices || []);
  el.logList.textContent = "";
  for (const entry of state.logs) {
    el.logList.appendChild(createLogRow(entry));
  }
}

function renderRtcStatus(state) {
  const rtc = state.rtcStatus || {};
  if (el.rtcStatusText) {
    const host = rtc.hostConnected ? "capture page ready" : "capture page closed";
    const phone = rtc.phoneConnected ? "phone ready" : "phone waiting";
    const capture = state.rtcStatus?.host?.capture || {};
    const diagnostics = state.captureDiagnostics || {};
    const source = diagnostics.requestedCapture?.sourceName || state.captureLaunch?.captureSourceName || capture.requestedSource || "auto";
    const reported = diagnostics.reportedCapture?.source || capture.reportedSource || capture.displaySurface || "unknown";
    const monitor = diagnostics.selectedInputMonitor?.id || state.captureLaunch?.monitorId || capture.requestedMonitor || state.selectedMonitorId || "display";
    const visible = diagnostics.phoneVisibleDisplay?.id || capture.requestedMonitor || monitor;
    const autoDetect = diagnostics.correction || state.captureLaunch?.autoDetect;
    const detectText = autoDetect?.status && autoDetect.status !== "idle" ? ` - ${autoDetect.status}` : "";
    const divergence = Array.isArray(diagnostics.divergence) && diagnostics.divergence.length
      ? ` - ${diagnostics.divergence.join(", ")}`
      : "";
    const actualSize = diagnostics.actualSize?.width && diagnostics.actualSize?.height
      ? ` - ${diagnostics.actualSize.width}x${diagnostics.actualSize.height}`
      : "";
    const modeHint = rtc.hostConnected
      ? `input ${monitor}, phone ${visible}, requested ${source}, reported ${reported}${actualSize}${detectText}${divergence}`
      : "open capture window for smooth video";
    el.rtcStatusText.textContent = `${rtc.state || "idle"} - ${host} - ${phone} - ${modeHint}`;
  }
  if (el.captureVideoLink) {
    el.captureVideoLink.textContent = state.captureLaunch?.inFlight ? "Launching" : "Use Existing";
  }
  const hasPhoneSession = Number(state.securityStatus?.approvedSessions || 0) > 0
    || Number(state.securityStatus?.pendingSessions || 0) > 0
    || Number(state.streamStats?.connectedClients || 0) > 0;
  const shouldAutoLaunch = Boolean(state.settings?.autoStart)
    && hasPhoneSession
    && !rtc.hostConnected
    && !state.captureLaunch?.inFlight;
  const now = Date.now();
  if (shouldAutoLaunch && now - lastAutoCaptureUiAttemptAt > 8000) {
    lastAutoCaptureUiAttemptAt = now;
    launchManagedCapture().catch(() => {});
  }
}

function renderTrustedDevices(devices = []) {
  el.trustedDeviceList.textContent = "";
  el.clearTrustedDevices.disabled = devices.length === 0;
  if (!devices.length) {
    const empty = document.createElement("div");
    empty.className = "trusted-device-row empty";
    const text = document.createElement("span");
    text.textContent = "No trusted phones yet.";
    empty.appendChild(text);
    el.trustedDeviceList.appendChild(empty);
    return;
  }
  for (const device of devices) {
    el.trustedDeviceList.appendChild(createTrustedDeviceRow(device));
  }
}

function renderConnectionSetup(validation = {}) {
  el.connectionSetup.textContent = "";
  for (const key of ["sameWifi", "tailscale", "tunnel"]) {
    const item = validation[key];
    if (!item) continue;
    el.connectionSetup.appendChild(createConnectionCard(item));
  }
}

async function refresh() {
  try {
    const state = await hostApi(`/api/host?key=${encodeURIComponent(hostKey)}`);
    render(state);
  } catch (error) {
    el.hostStatus.textContent = error.message;
  }
}

document.addEventListener("click", async (event) => {
  const approveId = event.target.dataset?.approve;
  const revokeId = event.target.dataset?.revoke;
  const trustedId = event.target.dataset?.revokeTrusted;
  const copyUrl = event.target.dataset?.copyUrl;
  if (copyUrl) {
    await copyAddressToClipboard(event.target);
    return;
  }
  if (approveId) {
    await hostApi("/api/approve", { method: "POST", body: JSON.stringify({ sessionId: approveId }) });
    refresh();
  }
  if (revokeId) {
    await hostApi("/api/revoke", { method: "POST", body: JSON.stringify({ sessionId: revokeId }) });
    refresh();
  }
  if (trustedId) {
    await hostApi("/api/trusted-device/revoke", { method: "POST", body: JSON.stringify({ deviceId: trustedId }) });
    refresh();
  }
});

el.refreshPin.addEventListener("click", async () => {
  await hostApi("/api/refresh-pin", { method: "POST", body: "{}" });
  refresh();
});

async function launchManagedCapture({ force = false } = {}) {
  if (el.captureLaunchStatus) el.captureLaunchStatus.textContent = "Opening capture window...";
  try {
    const suffix = force ? "&force=1" : "";
    const result = await hostApi(`/api/open-capture?autostart=1&autoselect=1${suffix}`, { method: "POST", body: "{}" });
    if (el.captureLaunchStatus) {
      el.captureLaunchStatus.textContent = result.skipped
        ? "Stable screen stream is active. Low-latency video autostart is disabled for this run."
        : result.alreadyOpen
        ? result.sharing
          ? "Capture is already running and will be reused."
          : result.startRequested
          ? "Capture window is open; start request sent to it."
          : "Capture window is open but not sharing yet."
        : result.launchInProgress
        ? "Capture is already launching. Wait a moment; no extra windows were opened."
        : result.autoSelect
        ? "Opened with auto-select. If Chrome still shows a picker, choose Entire Screen once."
        : "Opened. Click Start Low-Latency Video and choose your screen.";
    }
  } catch (error) {
    if (el.captureLaunchStatus) el.captureLaunchStatus.textContent = error.message;
  }
}

el.openCaptureWindow?.addEventListener("click", async () => {
  await launchManagedCapture();
});

el.captureVideoLink?.addEventListener("click", async () => {
  await launchManagedCapture();
});

el.exportLogs.addEventListener("click", () => {
  location.href = `/api/logs?key=${encodeURIComponent(hostKey)}`;
});

el.toggleInput.addEventListener("click", async () => {
  const state = await hostApi(`/api/host?key=${encodeURIComponent(hostKey)}`);
  await hostApi("/api/input-mode", {
    method: "POST",
    body: JSON.stringify({ enabled: !state.inputSafety?.enabled })
  });
  refresh();
});

el.safetyRelease.addEventListener("click", async () => {
  await hostApi("/api/safety-release", { method: "POST", body: "{}" });
  refresh();
});

el.killSwitch.addEventListener("click", async () => {
  await hostApi("/api/kill-switch", { method: "POST", body: "{}" });
  refresh();
});

el.clearTrustedDevices.addEventListener("click", async () => {
  await hostApi("/api/trusted-devices/clear", { method: "POST", body: "{}" });
  refresh();
});

el.settingsForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  await hostApi("/api/settings", {
    method: "POST",
    body: JSON.stringify({
      qualityDefault: el.defaultQuality.value,
      inputSensitivityDefault: Number(el.defaultSensitivity.value),
      trustedDevicesEnabled: el.trustedDevices.checked,
      autoStart: el.autoStart.checked
    })
  });
  refresh();
});

refresh();
setInterval(refresh, 1200);

window.__remoteHostDebug = {
  copyAddressToClipboard,
  versionPhoneUrl,
  addAcceptanceQuery,
  getProofLinks,
  getPrimaryPhoneLink,
  getAddressGuidance,
  renderFeaturedPhoneLink,
  isVpnLikeAddress,
  latestProofLog,
  formatProofChecklist,
  renderLatestProof
};

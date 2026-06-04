"use strict";

const { spawn } = require("node:child_process");

const PROBE_COLORS = [
  "#ff2d55",
  "#34c759",
  "#0a84ff",
  "#ffcc00",
  "#bf5af2",
  "#ff9f0a"
];

function cleanString(value, fallback = "", maxLength = 120) {
  const text = String(value || fallback || "").replace(/\s+/g, " ").trim();
  return text.slice(0, maxLength);
}

function cleanDuration(value, fallback = 3400) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(900, Math.min(8000, Math.round(number)));
}

function createProbeToken(now = () => Date.now()) {
  return `probe-${now().toString(36)}`;
}

function createProbeMarkers(monitors = [], token = createProbeToken()) {
  return (Array.isArray(monitors) ? monitors : [])
    .filter((monitor) => monitor?.id)
    .map((monitor, index) => ({
      monitorId: cleanString(monitor.id, `display-${index + 1}`, 80),
      sourceId: cleanString(monitor.sourceId, "", 120),
      name: cleanString(monitor.name, `Display ${index + 1}`, 80),
      index,
      color: PROBE_COLORS[index % PROBE_COLORS.length],
      label: `D${index + 1}`,
      token: cleanString(token, "", 80)
    }));
}

function buildPowerShellProbeScript({ markers = [], durationMs = 3400 } = {}) {
  const payload = {
    durationMs: cleanDuration(durationMs),
    markers: markers.map((marker) => ({
      monitorId: marker.monitorId,
      sourceId: marker.sourceId,
      index: marker.index,
      color: marker.color,
      label: marker.label,
      token: marker.token
    }))
  };
  const encodedPayload = Buffer.from(JSON.stringify(payload), "utf8").toString("base64");
  return [
    "$ErrorActionPreference='SilentlyContinue'",
    "Add-Type -AssemblyName System.Windows.Forms",
    "Add-Type -AssemblyName System.Drawing",
    `$payloadJson=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${encodedPayload}'))`,
    "$payload=$payloadJson | ConvertFrom-Json",
    "$screens=[System.Windows.Forms.Screen]::AllScreens",
    "$forms=New-Object System.Collections.Generic.List[System.Windows.Forms.Form]",
    "foreach ($marker in $payload.markers) {",
    "  $screen=$screens | Where-Object { $_.DeviceName -eq $marker.sourceId } | Select-Object -First 1",
    "  if (-not $screen) { $idx=[int]$marker.index; if ($idx -ge 0 -and $idx -lt $screens.Length) { $screen=$screens[$idx] } }",
    "  if (-not $screen) { continue }",
    "  $bounds=$screen.Bounds",
    "  $w=[Math]::Max(260,[Math]::Min(560,[Math]::Round($bounds.Width*0.26)))",
    "  $h=[Math]::Max(140,[Math]::Min(280,[Math]::Round($bounds.Height*0.20)))",
    "  $x=$bounds.Left+[Math]::Max(24,[Math]::Round($bounds.Width*0.035))",
    "  $y=$bounds.Top+[Math]::Max(24,[Math]::Round($bounds.Height*0.045))",
    "  $form=New-Object System.Windows.Forms.Form",
    "  $form.FormBorderStyle=[System.Windows.Forms.FormBorderStyle]::None",
    "  $form.StartPosition=[System.Windows.Forms.FormStartPosition]::Manual",
    "  $form.ShowInTaskbar=$false",
    "  $form.TopMost=$true",
    "  $form.Opacity=0.96",
    "  $form.BackColor=[System.Drawing.ColorTranslator]::FromHtml([string]$marker.color)",
    "  $form.Left=$x; $form.Top=$y; $form.Width=$w; $form.Height=$h",
    "  $label=New-Object System.Windows.Forms.Label",
    "  $label.Dock=[System.Windows.Forms.DockStyle]::Fill",
    "  $label.TextAlign=[System.Drawing.ContentAlignment]::MiddleCenter",
    "  $label.Font=New-Object System.Drawing.Font('Segoe UI',42,[System.Drawing.FontStyle]::Bold)",
    "  $label.ForeColor=[System.Drawing.Color]::White",
    "  $label.BackColor=[System.Drawing.Color]::Transparent",
    "  $label.Text=[string]$marker.label",
    "  $form.Controls.Add($label)",
    "  $form.Show()",
    "  $forms.Add($form) | Out-Null",
    "}",
    "$timer=New-Object System.Windows.Forms.Timer",
    "$timer.Interval=[int]$payload.durationMs",
    "$timer.Add_Tick({ foreach ($form in $forms) { $form.Close() }; [System.Windows.Forms.Application]::ExitThread() })",
    "$timer.Start()",
    "[System.Windows.Forms.Application]::Run()"
  ].join("; ");
}

function showCaptureProbe({
  monitors = [],
  token = createProbeToken(),
  durationMs = 3400,
  platform = process.platform,
  spawnImpl = spawn,
  log = () => {}
} = {}) {
  const markers = createProbeMarkers(monitors, token);
  const cleanMs = cleanDuration(durationMs);
  if (platform !== "win32") {
    return { ok: false, supported: false, token, durationMs: cleanMs, markers };
  }
  if (!markers.length) {
    return { ok: false, supported: true, token, durationMs: cleanMs, markers, error: "No monitor markers available." };
  }
  const script = buildPowerShellProbeScript({ markers, durationMs: cleanMs });
  const child = spawnImpl("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script], {
    detached: true,
    stdio: "ignore",
    windowsHide: true
  });
  if (typeof child.unref === "function") child.unref();
  log("capture.probe.shown", { token, monitors: markers.length, durationMs: cleanMs, pid: child.pid || null });
  return { ok: true, supported: true, token, durationMs: cleanMs, markers, pid: child.pid || null };
}

module.exports = {
  buildPowerShellProbeScript,
  createProbeMarkers,
  createProbeToken,
  showCaptureProbe
};

# Packaging Notes

The current build runs from source. The daily-use target is a small host app with a tray icon, start/stop control, clear addresses, and no hidden background control state.

## Current Developer Run

```powershell
npm install
npm run qa
npm run dependency:audit:save
$env:HOST_KEY='dev-host-key'
npm start
```

`npm start` is the normal release-like launch path and forces screen capture, real input, and fast quality. Use `npm run start:fake` only when troubleshooting without exposing the real desktop.

Then open:

```text
http://127.0.0.1:4317/host?key=dev-host-key
```

## Tray Host Run

The current daily-use shell is `scripts/tray-host.ps1`.

```powershell
npm run tray
```

The tray menu starts the host hidden and provides:

- Open Host Console
- Copy Recommended Phone URLs
- Copy All Phone URLs
- Start Host
- Stop Host
- Release Buttons
- Set Input Dry-Run
- Enable Real Input
- Stop All Control
- Exit Tray

## Desktop Shortcut

For daily use without remembering a terminal command, install a normal non-elevated Windows shortcut that starts the tray host:

```powershell
npm run shortcut:install
```

The shortcut points to `scripts\tray-host.ps1`, keeps the working directory at the project root, starts in screen capture mode, and leaves firewall, auto-start, and physical proof state untouched. It can also be installed into the Start Menu:

```powershell
npm run shortcut:install -- -Scope StartMenu
```

Validate the shortcut target without creating or changing a shortcut:

```powershell
npm run shortcut:selftest
```

## Auto-Start

The current free auto-start path uses a per-user Windows Scheduled Task named `RemoteControllerHost`. It starts the tray host at user logon, which then starts the remote-control host hidden and exposes the tray controls.

Install the logon task:

```powershell
npm run autostart:install
```

Remove the logon task:

```powershell
npm run autostart:uninstall
```

Validate the generated task command without installing anything:

```powershell
npm run autostart:selftest
```

The install self-test currently resolves this command shape:

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "...\scripts\tray-host.ps1" -NodePath "node" -HostKey "dev-host-key" -CaptureMode screen
```

Keep this as an explicit user action. Do not silently install auto-start from the phone UI or from the normal server start path.

## Firewall

Same-Wi-Fi phone access can be blocked by Windows Firewall even when the host process is working. Keep firewall changes explicit:

```powershell
npm run firewall:status
npm run firewall:handoff
npm run firewall:install
npm run firewall:remove
```

The install command creates an inbound TCP `4317` allow rule for Private/Domain profiles with remote addresses limited to `LocalSubnet`, Tailscale IPv4 `100.64.0.0/10`, and Tailscale IPv6 `fd7a:115c:a1e0::/48`. It requires elevated PowerShell. The handoff command is the safer operator path: it writes timestamped/latest JSON, Markdown, and `.ps1` artifacts with the exact elevated install command, copies that command, and does not mutate firewall state or mark physical proof complete. The guided phone acceptance runner records firewall status in its summary JSON.

## Acceptance Evidence

Generate a manual phone-test evidence report before and after same-Wi-Fi or Tailscale testing:

```powershell
npm run acceptance:report -- -Gate same-wifi -Phase pre
npm run acceptance:report -- -Gate same-wifi -Phase post
npm run acceptance:report -- -Gate tailscale -Phase pre
npm run acceptance:report -- -Gate tailscale -Phase post
```

Reports are written to:

```text
output/acceptance/
```

Keep the generated Markdown/JSON reports, the auto-exported `*-host-logs.json`, the Tailscale CLI IPv4/IPv6 snapshot when available, the `acceptance.phoneMark` log entry created from the phone proof banner or Settings sheet, and any phone screenshots/photos from the physical run.

Keep the generated `acceptance-doctor-*.md` and `.json` readiness reports too; they record host health, phone URLs, firewall state, and Tailscale readiness before the physical run starts.

For a guided real-device run that starts the screen-capture host when needed, preflights the selected LAN/Tailscale `/api/health` URL, prints the host console and phone URLs, creates pre/post reports, writes per-step pass/fail notes, and saves selected-gate verifier output after the run:

```powershell
npm run acceptance:doctor -- -Gate same-wifi
npm run acceptance:ready -- -Gate same-wifi
npm run acceptance:next
npm run acceptance:refresh -- -NoOpen
npm run acceptance:prepare -- -Gate same-wifi
npm run acceptance:phone -- -Gate same-wifi
# Keep the host running here if the Tailscale gate still needs proof.
npm run acceptance:doctor -- -Gate tailscale
npm run acceptance:ready -- -Gate tailscale
npm run acceptance:next
npm run acceptance:prepare -- -Gate tailscale
npm run acceptance:phone -- -Gate tailscale
# Stop only after this is the last remaining physical gate.
npm run acceptance:stop -- -Gate tailscale
```

Use `npm run acceptance:phone -- -Gate <gate> -RequireReady` when you want the runner to stop before the manual checklist if the selected gate has readiness doctor failures, no selected-gate phone URL, or no passing selected-gate URL preflight.

After the guided run, verify the saved evidence bundle again if you attached extra phone screenshots/photos or want a fresh timestamp:

```powershell
npm run acceptance:verify -- -Gate same-wifi
npm run acceptance:verify -- -Gate tailscale
npm run evidence:bundle
npm run completion:audit:save
```

After both real phone runs pass, the safest one-command finish is:

```powershell
npm run acceptance:finalize
```

That command saves both gate verifier outputs, writes the evidence bundle, saves the whole-manual completion audit, and writes `physical-evidence-finalization-*.json` plus `.md`. It intentionally does not run readiness or refresh after proof, which keeps the latest manual summaries current for the verifier. The next-action checklist, dashboard, and handoff pages point to this command as the final finish step after both physical gates pass.

The QA command saves `qa-report-*.json` and `.md` under `output\acceptance`, proving the automated tests and script self-tests ran against a screen-capture host. It also records an operator artifact snapshot for the latest dashboard, handoff, evidence bundle, refresh, firewall handoff, completion audit, physical finalization files, and desktop shortcut self-test so the final audit can prove QA was run with the acceptance surface already present. The evidence bundle command saves current verifier JSON outputs for both gates before indexing artifacts, and it also indexes the latest QA report, dependency audit report, firewall handoff JSON/Markdown/script artifacts, and physical finalization JSON/Markdown artifacts. Those verifier files can be failing evidence while physical phone proof is still incomplete; they are still useful because they preserve the exact remaining blockers.

The physical evidence verifier also rejects stale manual summaries when a newer selected-gate readiness run exists. After the real phone run passes, verify and bundle that evidence before running a new readiness refresh, so the proof summary remains current for the readiness artifact it is being checked against.

The dependency audit command saves `dependency-audit-*.json` and `.md` under `output\acceptance`. It fails on high or critical advisories and records the current moderate real-input dependency advisories as reviewed packaging risk.

To keep supporting phone screenshots/photos with the evidence bundle, attach each image explicitly:

```powershell
npm run acceptance:attach -- -Gate same-wifi -EvidencePath "C:\path\to\phone-photo.jpg" -Label "same-wifi-proof"
npm run acceptance:attach -- -Gate tailscale -EvidencePath "C:\path\to\tailscale-phone-photo.jpg" -Label "tailscale-proof"
```

The phone client now includes installable PWA metadata and a service worker for the app shell. Dynamic control APIs and stream data are not cached.

Host settings are persisted in:

```text
data/host-settings.json
```

This file may include trusted-device fingerprints. The host API exposes only a trusted-device count, not the raw fingerprints.

## Daily Build Requirements

- Start and stop the host without keeping a terminal in front.
- Provide a non-elevated Desktop/Start Menu shortcut installer for the tray host so daily launch does not depend on remembering developer commands.
- Show or copy the current LAN and Tailscale URLs.
- Show in-app connection setup status for same-Wi-Fi, Tailscale, and testing-only public tunnel paths.
- Show current pairing PIN and pending sessions.
- Provide Input Safety controls: dry-run, real input, release buttons, stop all control.
- Provide simple host settings for default quality, default sensitivity, trusted-device mode, auto-start preference, and log export.
- Provide trusted-device management for listing redacted trusted phones, revoking one phone, and clearing all trusted phones.
- Provide a repeatable manual acceptance report for same-Wi-Fi and Tailscale evidence, including auto-exported host logs when the host is reachable and local `tailscale ip -4/-6` output when the CLI is available.
- Provide a physical-run readiness doctor so host health, phone URLs, firewall state, and Tailscale readiness can be checked before starting the real-device checklist.
- Provide prepare/stop commands so a physical acceptance host session can be started non-interactively, recorded with JSON plus Markdown/HTML run cards containing PID/URLs/inline QR codes/QR SVG files/doctor evidence, and stopped safely afterward.
- Provide a one-command ready wrapper that prepares the host, opens or records the current HTML run card, saves the current readiness artifact before watcher verification, runs a watcher snapshot, and saves final readiness JSON for the physical-run evidence folder.
- Provide a next-actions checklist writer that reads the ready artifacts and saves concise operator JSON/Markdown before the physical phone run.
- Provide a dependency-audit command that saves package risk evidence and fails if high or critical advisories appear before a daily-use release.
- Provide a refresh command that regenerates bootstrap, Tailscale setup-check, readiness, next-action, initial evidence-bundle, dashboard, handoff, final evidence-bundle, dependency-audit, completion-audit, and post-audit evidence-bundle artifacts in the correct order while preserving the physical-only incomplete state.
- Provide a no-refresh finalization command that verifies both completed physical gates, bundles evidence, saves the completion audit, and records the final artifact paths without creating a newer readiness run.
- Keep operator-facing final commands aligned to that no-refresh finalization command after both physical gates pass.
- Provide an attachment command for phone screenshots/photos so supporting images are copied into `output\acceptance`, hashed, and indexed without replacing verifier evidence.
- Keep daily-use tray URL copying aligned with physical-run guidance: recommend normal same-Wi-Fi LAN URLs first, keep VPN-like/private adapter URLs available only through the all-URLs troubleshooting path, and keep Tailscale URLs separate for the different-Wi-Fi gate.
- Provide a guided manual phone acceptance runner so the final physical gates produce readiness doctor artifacts, pre/post evidence, phone-side Mark Proof logs, and step-by-step pass/fail notes.
- Provide an evidence verifier that fails unless the selected-gate URL preflight passed, the manual summary is current for the latest selected-gate readiness run, every guided step passed, reports/logs exist, `acceptance.phoneMark` exists, and the phone proof URL matches the selected same-Wi-Fi or Tailscale path.
- Provide explicit firewall status/handoff/install/remove commands for inbound TCP `4317`; do not silently modify firewall state during normal host startup.
- Make Stop All Control disable real input, release held buttons, disconnect clients, and revoke sessions.
- Store trusted-device settings only after the manual approval model is proven.
- Keep updates explicit; no silent updater until signing and rollback exist.

## Packaging Direction

- Keep the Node host as the core service.
- Keep the PowerShell tray shell as the first daily-use wrapper.
- Later, package the tray wrapper into a signed Windows app or replace it with a native tray shell.
- Do not bundle a public tunnel by default.
- Keep `CAPTURE_MODE=fake` available as a troubleshooting mode.

## Files To Include

- `src/`
- `public/`
- `package.json`
- `package-lock.json`
- `docs/`
- `scripts/tray-host.ps1`
- `scripts/install-shortcut.ps1`
- `scripts/acceptance-report.ps1`
- `scripts/acceptance-ready.ps1`
- `scripts/acceptance-next.ps1`
- `scripts/install-autostart.ps1`
- `scripts/uninstall-autostart.ps1`
- `scripts/run-qa.ps1`
- `data/host-settings.json` when preserving local settings/trusted devices between runs
- `README.md`
- `MILESTONE_STATUS.md`

## Known Packaging Risks

- `@nut-tree-fork/nut-js` adds native input capability and currently brings moderate transitive npm audit advisories through `jimp`/`file-type`; `npm run dependency:audit:save` records the latest advisory status and fails on high/critical advisories.
- Windows security tools may block script-based capture approaches; the active capture path uses `screenshot-desktop`.
- Real input should remain host-gated in every packaged mode.

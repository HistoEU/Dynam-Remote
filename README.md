# Free Remote Desktop Controller

This folder is the active free local-network remote controller build. The release target is a Windows laptop host controlled from a phone on the same Wi-Fi or through a private Tailscale network.

## What Exists Now

- Native Node host server.
- Static phone PWA served by the laptop host.
- Host approval console at `/host?key=...`.
- Redacted public health endpoint plus host-key-gated host state and log export.
- Inbound HTTP/WebSocket guard for loopback, private LAN, and Tailscale by default.
- 6-digit short-lived pairing PIN.
- Pending session approval before control is allowed.
- Native WebSocket realtime channel.
- Replay-resistant client command validation with version, type, sequence, timestamp, and payload checks.
- Sequence-echo acknowledgements for critical monitor, stream, visibility, and input commands.
- HTTP and WebSocket error envelopes with recoverability and next-action guidance surfaced in phone diagnostics.
- 64 KB JSON request-body limit for phone/host API endpoints.
- Browser security headers with CSP, no-referrer, nosniff, and frame-embedding denial.
- Safe fallback selected-monitor stream frames for troubleshooting.
- Real Windows screen capture mode through `screenshot-desktop`.
- Monitor selector with fallback multi-monitor data when real capture is unavailable.
- Monitor selector with real display enumeration in screen mode.
- Testable coordinate mapper for direct touch and relative movement across side-by-side, stacked, portrait, and differently scaled monitor bounds.
- Touchpad/direct modes, dry-run pointer, wheel, keyboard, text, quality, and disconnect commands.
- Host-gated real input adapter for mouse, wheel, keyboard shortcuts, and typed text.
- Host safety controls to enable/disable real input and release held mouse buttons, modifiers, and keys.
- Session expiry and fail-closed input permission checks.
- Wrong-PIN rate limiting with visible host status.
- Functional trusted-device mode after first manual approval.
- Trusted-device management: redacted list, per-phone revoke, and clear-all revoke from the host console.
- Host console safely renders phone-supplied names, origins, trusted-device records, and logs as text.
- Persistent local host settings and trusted-device fingerprints.
- Session origin metadata and WebSocket origin checking.
- Rolling host logs for auth, monitor changes, input dry-runs, stream quality, connect, and disconnect.
- Exportable host logs and stream diagnostics with raw typed/pasted text redacted.
- Phone diagnostics for FPS, bandwidth estimate, capture time, latency, and input round trip.
- Adaptive stream cadence for responsive input and quieter idle behavior.
- Hidden-phone stream pausing with visible/hidden client diagnostics.
- Pointer-move coalescing with preserved click/key/drag ordering.
- Precision mode with reduced movement sensitivity and a visible touch halo for fine phone control.
- Zoomed viewport controls with pinch/slider zoom, two-finger pan, reset view, and direct-touch mapping through the visible crop.
- Edge-pan for zoomed touchpad mode so viewport movement stays local instead of moving the laptop cursor.
- Phone-side control preferences for scroll speed, touch halo visibility, and haptic feedback.
- Phone Mark Proof button that records authenticated physical-run viewport/PWA diagnostics in host logs.
- LAN and Tailscale IPv4/IPv6 address discovery.
- Network-risk status for LAN, Tailscale, and optional temporary public tunnel mode.
- In-app Connection Setup guidance for same-Wi-Fi, Tailscale/different-Wi-Fi, and testing-only public tunnels.
- Phone pairing diagnostics for wrong PIN, host unreachable, rate limit, expired session, and realtime disconnect cases.
- Phone reconnect recovery that stops retrying and returns to pairing when the saved session is expired or revoked.
- QR codes and copy buttons for advertised phone URLs in the host console, with recommended/secondary/Tailscale labels so same-Wi-Fi and different-Wi-Fi paths are not visually mixed together.
- PWA manifest, icon, and phone-shell-only service worker caching.
- Host settings for default quality, sensitivity, and trusted-device toggle.
- Acceptance, Tailscale, TOTP trusted-device design, and packaging notes in `docs/`.
- 15-page manual traceability audit in `docs/TRACEABILITY_AUDIT.md` plus the active 10-page finalization traceability map in `docs/FINALIZATION_TRACEABILITY.md`.
- QA runner: `npm run qa`, which uses the current tree while preserving any already-running live controller host by default and saves `qa-report-*.json` plus `.md` under `output\acceptance`, including an operator artifact snapshot for the latest dashboard, handoff, physical proof runbook, evidence bundle, refresh, firewall handoff, completion audit, and physical finalization files.
- Manual acceptance evidence reporter with auto-exported host logs: `npm run acceptance:report`.
- Physical-run readiness doctor: `npm run acceptance:doctor -- -Gate same-wifi` or `npm run acceptance:doctor -- -Gate tailscale`.
- Non-interactive physical-run host prep and stop commands: `npm run acceptance:prepare -- -Gate same-wifi` and `npm run acceptance:stop -- -Gate same-wifi`; keep the host running between gates when the next proof still needs the same prepared host.
- One-command physical-run readiness launcher: `npm run acceptance:ready -- -Gate same-wifi`, which prepares the host, opens the latest run card, saves the current readiness artifact before watcher verification, checks watcher status once, and saves a compact readiness JSON artifact.
- Guided physical phone acceptance runner with recommended/secondary URL guidance, pre/post evidence, and Mark Proof host-log capture: `npm run acceptance:phone -- -Gate same-wifi` or `npm run acceptance:phone -- -Gate tailscale`.
- Physical evidence verifier: `npm run acceptance:verify -- -Gate same-wifi` or `npm run acceptance:verify -- -Gate tailscale`; use `npm run acceptance:verify:save -- -Gate same-wifi` or `npm run acceptance:verify:save -- -Gate tailscale` to save timestamped verifier JSON under `output\acceptance`.
- Physical acceptance watcher: `npm run acceptance:watch -- -Gate same-wifi` or `npm run acceptance:watch -- -Gate tailscale`.
- Physical acceptance next-actions checklist: `npm run acceptance:next`, which reads the latest ready artifacts and writes concise operator JSON/Markdown with the next physical steps for same-Wi-Fi and Tailscale.
- Physical proof runbook: `npm run acceptance:runbook`, which writes a single terminal-friendly JSON/Markdown runbook with the first command to run, current gate statuses, phone URLs, audit blockers, and the no-refresh finalization warning.
- Physical proof launcher: `npm run acceptance:launch`, which opens the current run card/runbook and copies the selected gate phone URL when available, falls back to the current Tailscale setup URL when that gate is blocked on login, and does not run the checklist, mark proof, save verifier evidence, or change firewall/Tailscale state.
- Physical acceptance handoff page: `npm run acceptance:handoff`, which writes a scan-first HTML/Markdown/JSON launch page with the current same-Wi-Fi QR, exact checklist command, Mark Proof reminder, verifier links, and Tailscale setup blockers.
- No-refresh physical finalizer: `npm run acceptance:finalize`, which verifies both completed phone gates, writes the evidence bundle, saves the whole-manual completion audit, and records the finalization artifact without creating a newer readiness run.
- Whole-manual completion audit: `npm run completion:audit`; use `npm run completion:audit:save` to save timestamped/latest JSON and Markdown audit reports under `output\acceptance`.
- Evidence bundle manifest: `npm run evidence:bundle`.
- Tailscale bootstrap assistant for the free different-Wi-Fi path: `npm run tailscale:bootstrap` or `npm run tailscale:bootstrap:save`. It detects Tailscale, the Windows service, winget availability, and the exact next setup commands without installing software or changing firewall state.
- Tailscale setup checker for the free different-Wi-Fi path: `npm run tailscale:check` or `npm run tailscale:check:save`.
- Guided acceptance includes a selected-gate URL preflight that checks the advertised LAN/Tailscale `/api/health` URL before the phone checklist begins.
- Optional Windows Firewall rule helper and non-mutating elevated-command handoff for same-Wi-Fi/Tailscale inbound TCP `4317`.
- Windows tray launcher: `npm run tray`, with recommended phone URL copying plus an all-URLs troubleshooting option.
- Non-elevated Windows shortcut installer: `npm run shortcut:install`, which creates a Desktop shortcut to the tray host so daily launch does not require remembering a terminal command.
- Windows user-logon auto-start scripts for the tray host.

## Run

```powershell
$env:HOST_KEY='dev-host-key'
npm start
```

`npm start` is the normal release-like path: real screen capture, real input, and fast stream quality. Use `npm run start:fake` only for safe troubleshooting without showing the real laptop screen.

Open the host console URL printed by the server, then open the LAN URL on the phone.

To run the daily-use tray launcher:

```powershell
npm run tray
```

To install a normal Desktop shortcut for the tray launcher:

```powershell
npm run shortcut:install
```

To validate the shortcut target without creating one:

```powershell
npm run shortcut:selftest
```

To run automated/local QA and save the evidence artifact used by the final completion audit:

```powershell
npm run qa
```

The latest QA report is saved as `output\acceptance\qa-report-latest.json` and `.md`. It must show `node --test` passing, no failed script self-tests, host mode `milestone-2-screen-capture`, and a non-empty operator artifact snapshot.

To build and smoke-test the easy local Wi-Fi zip:

```powershell
npm run package:local-wifi
npm run package:smoke
```

The smoke test extracts the zip, starts it on a non-default port, verifies health, verifies the phone page and service worker, stops the packaged host, and confirms the port is no longer listening.

To install or remove the daily-use logon task:

```powershell
npm run autostart:install
npm run autostart:uninstall
```

To validate the auto-start command without changing Windows tasks:

```powershell
npm run autostart:selftest
```

To inspect or install the optional inbound firewall rule for phone access:

```powershell
npm run firewall:status
npm run firewall:handoff
npm run firewall:install
npm run firewall:remove
```

The rule allows TCP `4317` from `LocalSubnet`, Tailscale IPv4 `100.64.0.0/10`, and Tailscale IPv6 `fd7a:115c:a1e0::/48` on Private/Domain Windows network profiles. Install/remove require elevated PowerShell. The handoff command writes `firewall-handoff-install-*.json`, `.md`, and `.ps1` artifacts, copies the exact elevated install command, and intentionally does not install/remove a rule or mark physical phone proof complete.

To inspect the different-Wi-Fi/Tailscale path before running the phone gate:

```powershell
npm run tailscale:bootstrap
npm run tailscale:bootstrap:save
npm run tailscale:check
npm run tailscale:check:save
```

The saved bootstrap writes `tailscale-bootstrap-*.json` and `.md` under `output\acceptance` with non-mutating install/sign-in/start-service guidance, including the current Tailscale backend state and auth URL when login is pending. The saved check writes `tailscale-setup-check-*.json` and `.md` under `output\acceptance` with Tailscale CLI, tailnet IP, host-advertised Tailscale URL, auth URL, and firewall readiness details.

To snapshot host state and create a phone-test evidence checklist:

```powershell
npm run acceptance:report -- -Gate same-wifi -Phase pre
npm run acceptance:report -- -Gate same-wifi -Phase post
npm run acceptance:report -- -Gate tailscale -Phase pre
npm run acceptance:report -- -Gate tailscale -Phase post
```

When the host is reachable, each report also saves a matching `*-host-logs.json` file under `output\acceptance`. The readiness doctor also saves timestamped Markdown/JSON readiness reports in the same folder.

To run the guided physical phone acceptance flow, which starts the screen-capture host when needed, checks the selected recommended LAN/Tailscale URL from the laptop, prints the host console plus recommended and secondary phone URLs, creates pre/post reports, and saves per-step notes:

```powershell
npm run acceptance:doctor -- -Gate same-wifi
npm run acceptance:ready -- -Gate same-wifi
npm run acceptance:next
npm run acceptance:handoff
npm run acceptance:prepare -- -Gate same-wifi
npm run acceptance:watch -- -Gate same-wifi
npm run acceptance:phone -- -Gate same-wifi
# Keep the host running here if Tailscale still needs proof.
npm run acceptance:doctor -- -Gate tailscale
npm run acceptance:ready -- -Gate tailscale
npm run acceptance:next
npm run acceptance:handoff
npm run acceptance:prepare -- -Gate tailscale
npm run acceptance:watch -- -Gate tailscale
npm run acceptance:phone -- -Gate tailscale
# Stop only after the selected gate is the last remaining physical proof.
npm run acceptance:stop -- -Gate tailscale
```

The prepare command starts the screen-capture host and saves `phone-acceptance-session-*.json` plus matching Markdown and HTML run cards with the host PID, host console URL, recommended phone URLs, secondary phone URLs, inline QR codes, QR SVG files, doctor report paths, next checklist command, and stop command. Same-Wi-Fi run cards recommend non-VPN LAN adapters first; Tailscale run cards use only Tailscale URLs so the different-Wi-Fi proof cannot accidentally use a LAN path. It exits with failure for a gate that is not ready, while still saving the diagnostic session files.

The ready command is the fast path for a real phone run. It wraps prepare, opens the HTML run card unless `-NoOpen` is passed, saves the current readiness artifact before watcher verification, runs the watcher once, and saves `phone-acceptance-ready-*.json` plus `phone-acceptance-ready-*-latest.json` with the run card path, phone URLs, host health, next command, stop command, setup failures, setup warnings, ready actions, and current verifier blockers. For the Tailscale gate it preserves empty URL lists as `[]` and surfaces the exact Tailscale installation/sign-in/CLI fixes before the phone checklist starts.

The next-actions command reads the latest same-Wi-Fi and Tailscale ready artifacts and writes `phone-acceptance-next-*.json` plus `.md`. It is the concise operator checklist: open this run card, open this phone URL, run this guided checklist, tap Mark Proof, save verifier evidence, review the latest Tailscale setup-check report, fix setup items first, or handle warning actions such as running the firewall handoff before choosing any elevated firewall install.

The handoff command writes `phone-acceptance-handoff-*.html`, `.md`, and `.json`. Use it as the laptop launch surface for the real phone run: scan the same-Wi-Fi QR, run the printed checklist command, tap Mark Proof from the controller banner, keep the verifier links beside the Tailscale setup blockers, and finish with `npm run acceptance:finalize` after both gates pass.

The watch command can stay open in a second terminal while the real phone run is happening. It shows the prepared run card, phone URLs, host health, latest manual summary, and the exact verifier checks still blocking the selected gate.

Then verify the saved physical evidence bundle:

```powershell
npm run acceptance:verify -- -Gate same-wifi
npm run acceptance:verify -- -Gate tailscale
npm run acceptance:verify:save -- -Gate same-wifi
npm run acceptance:verify:save -- -Gate tailscale
npm run acceptance:finalize
```

To audit the whole manual and active finalization completion state manually:

```powershell
npm run completion:audit
npm run completion:audit:save
```

The audit commands intentionally fail until both physical evidence verifiers pass. `npm run acceptance:finalize` runs the saved verifier, bundle, and audit path in the safer order after real phone proof exists.

## Core Acceptance

- Host server starts and prints local/LAN/Tailscale IPv4 or IPv6 addresses.
- Host console shows PIN, sessions, addresses, and logs.
- Phone PWA pairs with PIN and waits for approval.
- Host approves the pending phone.
- Phone connects to WebSocket and receives screen or safe fallback stream frames.
- Phone controls send dry-run input commands and receive acknowledgements.
- Host logs every important auth/session/input/stream event.

## Not Yet Done

- Manual same-Wi-Fi phone acceptance.
- Manual Tailscale/different-Wi-Fi acceptance.
- Review/replace the real-input dependency if a no-audit-advisory option is needed.
- Optional signed/native packaging beyond the current PowerShell tray and Scheduled Task wrapper.

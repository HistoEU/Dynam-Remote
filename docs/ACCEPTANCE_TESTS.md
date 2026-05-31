# Acceptance Tests

These gates come from the 15-page build plan. Do not mark the build complete until each item has direct evidence.

## Automated Gates

- `npm run qa` saves `qa-report-*.json` and `.md` while the host is running in `CAPTURE_MODE=screen`; the report must show `node --test` passing, no failed script self-tests, host mode `milestone-2-screen-capture`, an operator artifact snapshot for the latest dashboard, handoff, physical proof launch, evidence bundle, refresh, firewall handoff, completion audit, and physical finalization files, and a generated timestamp newer than the latest implementation/test/package/acceptance-script change.
- Host health reports `app.mode = milestone-2-screen-capture`.
- Public host health reports only redacted readiness information and does not expose monitors, sessions, settings, or logs.
- Authenticated host state reports at least one monitor with bounds, scale factor, primary flag, orientation, and capture status.
- Inbound network guard allows loopback, LAN, Tailscale IPv4, and Tailscale IPv6 clients by default and rejects public remotes unless public tunnel mode is explicitly configured.
- HTTP responses include browser security headers: Content-Security-Policy, no-referrer, nosniff, and frame-embedding denial while preserving PWA, WebSocket, and data-image stream behavior.
- Protocol tests reject malformed, wrong-version, server-only, replayed, stale-timestamp, future-timestamp, and bad-payload client commands before they reach handlers.
- Protocol tests validate error envelopes include `code`, `friendly`, `detail`, `recoverable`, and `nextAction` fields where applicable.
- HTTP API failures return the same recovery-ready envelope shape: `error`, `code`, `friendly`, `detail`, `recoverable`, and `nextAction`.
- HTTP JSON request bodies are size-limited and oversized requests return `413 PAYLOAD_TOO_LARGE` with recovery guidance.
- Coordinate mapping tests cover monitor bounds, clamping, relative movement sensitivity, side-by-side monitors, stacked monitors, portrait/rotated-style bounds, different scale factors, and malformed-bound fallbacks.
- Input adapter tests prove held mouse buttons and held keyboard modifiers/keys are tracked and released by the safety reset path.
- Session tests cover approval, token expiry, and expired-session removal.
- Session tests cover wrong-PIN rate limiting and lockout reporting.
- Host console shows current network risk and pairing rate-limit status.
- Host console shows Connection Setup readiness for same-Wi-Fi, Tailscale/different-Wi-Fi, and public tunnel testing.
- Host console shows QR codes plus copy buttons for every advertised phone URL, and labels recommended same-Wi-Fi, secondary VPN-like, and Tailscale/different-Wi-Fi paths clearly.
- Host console shows Physical Proof Links with gate-aware same-Wi-Fi/Tailscale proof URLs, copy buttons, and QR codes separate from the daily-use raw address list.
- Host console shows a Latest Phone Proof panel after Mark Proof lands, including proof gate, origin, step, viewport, monitor, FPS, and checklist completion.
- Host console renders phone-supplied names, origins, trusted-device records, and logs as text instead of executable HTML.
- Phone pairing screen explains likely connection failures, including host unreachable, wrong PIN, rate limiting, expired session, and socket disconnect.
- Phone reconnect recovery checks the saved session after socket closure, keeps retrying temporary network loss, and stops with Forget-and-pair-again guidance when a saved token is expired or revoked.
- Live smoke pairs with the current PIN, waits for host approval, connects WebSocket, receives frames, changes quality, reconnects, and exercises dry-run input.
- Live smoke covers pointer move, double click, cancel drag, keyboard chord, paste text, monitor select, and kill switch.
- Live smoke proves critical command acknowledgements echo the original sequence for monitor selection, stream quality, and phone visibility updates.
- Browser input test proves rapid pointer moves are coalesced while critical click/key/drag ordering is preserved.
- Browser input test proves Precision mode lowers effective movement sensitivity, marks the Precision button active, and shows the touch halo.
- Browser input test proves a zoomed viewport maps direct-touch coordinates through the visible crop and exposes Zoom/Reset controls in Settings.
- Browser input test proves zoomed edge-pan changes the phone viewport locally without sending laptop cursor input.
- Browser settings test proves scroll speed, touch halo visibility, and haptic feedback toggles update local phone state and persist locally.
- Browser visibility test proves the phone reports visible/hidden page state to the host.
- Mobile browser visual QA confirms the Stop button remains visible, sheets fit the viewport, and keyboard controls do not overflow.
- Mobile browser visual QA confirms connection diagnostics fit the pairing screen without clipping.
- Host log export returns JSON with current state and recent logs.
- Host log export preserves command diagnostics but must not include raw typed or pasted text.
- Phone diagnostics show approximate FPS, target FPS, bandwidth estimate, frame size, capture time, latency, and input round trip.
- Phone diagnostics expose the last WebSocket error envelope and suggested next action.
- Phone Settings exposes Mark Proof, and post-run host logs include an authenticated `acceptance.phoneMark` entry with physical phone viewport, URL origin/path, PWA/touch capability flags, monitor, quality, diagnostics counters, and phone-side checklist completion counts.
- Acceptance-mode phone runs show a persistent controller-level proof banner with the selected gate, selected step, Mark Proof action, checklist progress, and saved-in-host-logs state after the host acknowledges the marker. Mark Proof must stay blocked until the gate-aware physical checklist is complete.
- Stream diagnostics show adaptive mode and preset target FPS so idle/responsive behavior can be verified.
- Host stream diagnostics show visible client count, hidden client count, hidden-frame ticks, and continuous streaming stays active for connected controller clients even if mobile Safari reports the page as hidden.
- Phone diagnostics include pointer move queued/sent/coalesced counters for input-flood debugging.
- Network validation state reports LAN/Tailscale IPv4 or IPv6/tunnel readiness and next action text.
- Monitor picker shows a layout-aware arrangement and per-monitor status details.
- Manifest, app icon, and service worker shell are available for PWA installability.
- Service worker cache scope stays phone-shell-only and does not cache host-console assets, query-string URLs, API calls, or WebSockets.
- Host settings API can update default quality and default sensitivity.
- Auto-start install self-test validates the `RemoteControllerHost` Scheduled Task command without installing it.
- Auto-start uninstall self-test validates removal targeting for the `RemoteControllerHost` Scheduled Task.
- Shortcut installer self-test validates the non-elevated Desktop/Start Menu shortcut target for the tray host without creating or changing a shortcut.
- Acceptance report self-test validates that same-Wi-Fi and Tailscale manual checklists can be generated.
- Acceptance report saves a matching sanitized host-log JSON file beside the report whenever the host is reachable.
- Acceptance report captures local Tailscale CLI IPv4/IPv6 output when the `tailscale` command is available, without failing the report when Tailscale is not installed.
- Firewall helper self-test validates the optional inbound TCP `4317` rule shape for `LocalSubnet`, Tailscale IPv4, and Tailscale IPv6 without mutating Windows Firewall.
- Firewall handoff self-test validates that the operator handoff writes JSON, Markdown, and an elevated `.ps1` command artifact without installing/removing firewall rules or marking physical proof complete.
- Guided phone acceptance records Windows Firewall readiness in the evidence summary so same-Wi-Fi failures can be separated from app failures.
- Physical-run readiness doctor checks host health, advertised LAN/Tailscale URLs, host-side URL preflight, Windows Firewall readiness, and Tailscale CLI availability before the real phone checklist starts. The doctor resolves `tailscale` from PATH and common Windows install paths such as `C:\Program Files\Tailscale\tailscale.exe`, then saves timestamped Markdown/JSON readiness reports under `output\acceptance`.
- Tailscale setup checker records installation/sign-in clues, tailnet IP output, host-advertised Tailscale URLs, and firewall readiness before the different-Wi-Fi physical gate.
- Physical-run prepare/stop commands can start a screen-capture host for the phone run, save `phone-acceptance-session-*.json` plus matching Markdown/HTML run cards with PID/recommended URLs/secondary URLs/inline QR codes/QR SVG files/doctor evidence, and stop only the host process they started by default.
- Prepared phone run-card and QR URLs include `acceptance=1`, the selected `gate`, and `step=physical-phone-proof`, so the phone controller proof banner and Settings proof panel label the gate, render the correct physical checklist, and Mark Proof records the correct same-Wi-Fi or Tailscale gate plus checklist completion in the host log payload.
- The guided phone acceptance runner also prints and saves gate-aware proof URLs, while its laptop-side preflight checks the clean origin `/api/health` URL so query-string proof context does not break readiness checks.
- The guided phone acceptance runner records pre-run blockers from the readiness doctor, missing selected-gate phone URLs, and failed selected-gate URL preflight. In `-RequireReady` mode it saves a blocked summary and exits before asking the operator to score physical steps.
- Physical-run ready command wraps prepare, opens the HTML run card by default, runs the watcher once with saved output, and saves `phone-acceptance-ready-*.json` plus latest JSON with phone URLs, host health, next command, stop command, setup failures/warnings, ready actions, and current verifier blockers.
- Physical-run ready JSON records a normalized `status`, `primaryPhoneUrl`, `setupBlockerCount`, and `physicalBlockerCount` so every dashboard, handoff, refresh, and audit consumer agrees whether the gate is complete, ready for the phone, setup-needed, or needs attention.
- Physical-run ready saves a current preliminary readiness artifact before watcher verification, then overwrites it with the final watcher snapshot, so verifier blockers shown to the operator are tied to the selected readiness run and not an older run.
- Physical-run next-actions command reads the latest ready artifacts and saves `phone-acceptance-next-*.json` plus `.md` with the exact operator steps and warning actions needed to finish same-Wi-Fi and Tailscale evidence, preserving each gate's normalized readiness status and primary phone URL from the source ready JSON.
- When the Tailscale gate is setup-needed, next-action and runbook artifacts include the latest `tailscale-setup-check-latest.md` report and the `npm run tailscale:check:save` refresh command so sign-in/IP/firewall evidence is not hidden behind bootstrap-only guidance.
- Physical proof launch command reads the current runbook and saves `physical-proof-launch-same-wifi-*.json/.md` or `physical-proof-launch-tailscale-*.json/.md`, opens/copies only operator targets when allowed, warns that PINs are short-lived and the launch command should be rerun if the card is more than about one minute old, and records that it does not replace verifier proof or mark a physical gate complete.
- Physical acceptance dashboard command reads the latest ready, next-action, evidence-bundle, and QA-report artifacts and saves `phone-acceptance-dashboard-*.html` plus `.json` so the operator has one visual launch surface for both gates, including saved verifier JSON links, QA pass status, current verifier failed checks, primary phone URLs, and normalized gate status, without replacing verifier evidence.
- Physical acceptance handoff command reads the latest ready, run-card, dashboard, next-action, evidence-bundle, and QA-report artifacts and saves `phone-acceptance-handoff-*.html`, `.md`, and `.json` so the operator has one scan-first real-phone launch page with the same-Wi-Fi QR, exact checklist command, proof reminder, QA report link, verifier links, primary phone URL, normalized gate status, warning actions such as the firewall handoff-first path, and Tailscale setup blockers.
- Physical next-action, dashboard, and handoff surfaces must point operators to `npm run acceptance:finalize` after both physical gates pass, so the final finish path verifies both gates, bundles evidence, and saves the completion audit without creating a newer stale readiness artifact.
- Prepared run cards, next-action surfaces, launch cards, and runbooks include `-RequireReady` on guided physical phone commands so a stale host, missing selected-gate URL, failed readiness doctor, or failed selected-gate preflight stops before manual checklist scoring.
- Physical acceptance refresh command runs the bootstrap, saved Tailscale setup-check, readiness, next-action, initial evidence-bundle, dashboard, handoff, final evidence-bundle, dependency-audit, completion-audit, and post-audit evidence-bundle steps in order, then saves `phone-acceptance-refresh-*.json` plus `.md`; expected physical-only failures are recorded without marking the build complete, the final pre-audit bundle indexes the handoff from the same refresh run, and the post-audit bundle indexes the completion audit generated by that same refresh run.
- Phone evidence attachment command copies operator-supplied phone screenshots/photos into `output\acceptance`, hashes them, saves `phone-evidence-*.json`, and labels them as supporting evidence that does not replace verifier proof.
- Guided phone acceptance runner self-test validates the same-Wi-Fi and Tailscale physical-run checklists, starts the host by default during real runs, captures readiness doctor artifacts, groups recommended/secondary phone URLs, writes pre/post evidence paths plus per-step notes under `output\acceptance`, exposes pre-run blockers before manual step collection, supports `-RequireReady` to stop before collecting manual answers when the selected gate is not ready, and auto-runs the selected-gate verifier with saved output after the run unless explicitly skipped.
- Guided phone acceptance step scoring requires an explicit `y`, `n`, or `s` answer for every physical step. Blank or mistyped input is rejected and re-prompted so an accidental Enter cannot silently turn a required proof step into `SKIP`.
- Guided phone acceptance summaries keep `ok=false` until all manual steps pass, post-run evidence is saved, and the selected-gate verifier succeeds. Failed verification, skipped verification, failed steps, skipped steps, or missing post logs must not produce an OK summary.
- Guided phone acceptance runner records selected-gate URL preflight results for the recommended LAN/Tailscale `/api/health` URL before the phone checklist begins.
- Phone acceptance verifier self-test validates the evidence audit rules: selected-gate URL preflight must pass, the manual summary must be current for the latest gate readiness run, readiness doctor files must exist with no failures, all manual steps must pass, pre/post reports must exist, post host logs must exist, `acceptance.phoneMark` must be present, the phone proof payload gate must match the selected verifier gate, the phone proof checklist must be complete with the expected gate-specific item count, the phone proof URL must match the selected same-Wi-Fi or Tailscale gate, and timestamped/latest verifier JSON artifacts can be saved.
- Physical acceptance watcher can monitor the prepared session, source readiness artifact, normalized readiness status, primary phone URL, host health, latest manual summary, verifier output, run-card links, phone URLs, and remaining failed checks until the selected same-Wi-Fi/Tailscale gate passes; saved watcher JSON artifacts preserve the current blocker snapshot for later audit.
- Evidence bundle manifest auto-runs and saves the same-Wi-Fi/Tailscale verifier outputs, then indexes the latest ready statuses, run cards, doctor reports, setup checks, manual summaries, host logs, saved verifier outputs, QA reports, dependency audit reports, physical proof launch reports, firewall handoff reports/scripts, physical finalization reports, acceptance dashboards, acceptance handoff pages, acceptance refresh summaries, operator-attached phone screenshots/photos, and current verifier blockers. Saved verifier output can still be failing evidence until the physical phone run passes.
- `npm run qa` preserves an already-running live controller host by default so it does not break the phone screen while the operator is testing. When port `4317` is already in use, QA starts an isolated temporary host on the next free local port, points the browser tests at that `BASE_URL`, and records the preserved live host PID plus the QA host port. Stopping the live `4317` host is only allowed through the explicit `-FreshHost` script switch.
- Physical evidence finalization command runs saved verifiers for same-Wi-Fi and Tailscale, writes the evidence bundle, saves the whole-manual completion audit, writes `physical-evidence-finalization-*.json` plus `.md`, and avoids readiness refresh commands so a freshly completed phone proof is not made stale.
- Completion audit self-test validates that the whole-manual completion audit refuses to pass when real same-Wi-Fi and Tailscale phone evidence is missing, and the real audit now also checks the latest readiness, next-action, dashboard, handoff, watcher, evidence-bundle, verifier, refresh, QA, dependency-audit, physical proof launch, firewall-handoff, physical-finalization, Tailscale bootstrap, and Tailscale setup-check artifacts are present, non-empty, and internally consistent about same-Wi-Fi readiness, Tailscale setup state, gate-aware phone URLs, normalized readiness status, primary phone URL, setup/physical blocker counts, preservation of readiness status and primary URL through next-action/dashboard/handoff/watcher artifacts, phone-side proof checklist gating, payload evidence, verifier enforcement, verifier stale-summary rejection, readiness freshness before watcher verification, operator-facing no-refresh finalizer commands, operator-facing firewall warnings that prefer non-mutating handoff before elevated install, scan-first handoff Markdown warning visibility, refresh-regenerated setup-check evidence, setup-check guidance on next-action/runbook surfaces, refresh final commands that avoid stale proof after successful verifier runs, no-refresh physical finalization command coverage, evidence-bundle and QA snapshot indexing of physical finalization artifacts, evidence-bundle and QA snapshot indexing of physical proof launch artifacts, evidence-bundle and QA snapshot indexing of firewall handoff artifacts, host-console checklist visibility, Tailscale CLI discovery from common Windows install paths in the doctor/manual report, dependency audit status with zero high/critical advisories, evidence-bundle indexing of dependency-audit JSON/Markdown, evidence-bundle indexing of physical finalization JSON/Markdown, evidence-bundle indexing of physical proof launch JSON/Markdown, evidence-bundle indexing of firewall handoff JSON/Markdown/script artifacts, verifier paths, indexed artifact links, evidence-bundle handoff artifact records, evidence-bundle indexing of the current timestamped QA report identity, saved QA pass results, named QA self-test suite coverage, QA self-test script-path mapping, QA Markdown visibility for test totals/self-test rows/artifact snapshot rows/physical gate reminder, QA freshness after implementation/test/package/acceptance-script changes, dashboard/handoff QA identity pinning to the current timestamped QA report, optional phone screenshot/photo supporting-evidence records, QA artifact snapshot records, extracted-manual source markers, all-page traceability markers, explicit non-skippable build-goal mapping, exact package-script and self-test command targets, dashboard/handoff QA visibility, and the post-audit bundle refresh step. `npm run completion:audit:save` writes timestamped plus latest JSON/Markdown audit reports before exiting, even when the only failures are the physical gates.
- Trusted-device mode requires a correct PIN and at least one manual approval before repeat auto-approval.
- Trusted-device fingerprints persist locally but are not exposed in host/health JSON.
- Host trusted-device management can list redacted trusted phones, revoke one trusted phone, clear all trusted phones, and revoke affected sessions.
- WebSocket connections with an origin must match the session's recorded origin.
- Unauthenticated `/api/host` requests are rejected.

## Manual Same-Wi-Fi Gate

- Preferred guided run:

```powershell
npm run acceptance:doctor -- -Gate same-wifi
npm run acceptance:ready -- -Gate same-wifi
npm run acceptance:next
npm run acceptance:prepare -- -Gate same-wifi
npm run acceptance:watch -- -Gate same-wifi
npm run acceptance:phone -- -Gate same-wifi
# Keep the host running here if the Tailscale gate still needs proof.
```

- Run `npm run acceptance:report -- -Gate same-wifi -Phase pre` before the test and keep the generated Markdown/JSON/log files under `output\acceptance`.
- Run `npm run acceptance:doctor -- -Gate same-wifi` and keep the generated `acceptance-doctor-same-wifi-*.md` and `.json` readiness files under `output\acceptance`.
- Use `npm run acceptance:ready -- -Gate same-wifi` as the fast path when you want the host prepared, the run card opened, and a saved readiness status before starting the guided checklist.
- Run `npm run acceptance:next` to save the current operator checklist that points at the latest same-Wi-Fi run card, phone URL, guided command, Mark Proof reminder, verifier command, and stop command.
- Run `npm run acceptance:dashboard` to save a single HTML dashboard linking the latest run card, next-action checklist, evidence bundle, readiness JSON, phone URLs, blockers, warnings, and final commands.
- Run `npm run acceptance:refresh -- -NoOpen` when you want all current acceptance artifacts regenerated in the correct order without opening extra windows.
- Optionally keep `npm run acceptance:watch -- -Gate same-wifi` open in a second terminal during the physical run; it will keep reporting the current failed verifier checks until the evidence bundle passes.
- Run `npm run firewall:status`; if the rule is not ready and the phone cannot reach the laptop, run `npm run firewall:handoff` first, then run the copied elevated install command only if you choose to allow inbound TCP `4317`, then retry.
- Start the host on the laptop with `npm start`, which forces `CAPTURE_MODE=screen`, real input, and fast quality. Use `npm run start:fake` only for safe troubleshooting outside acceptance.
- Open the host console and confirm the recommended LAN URL is visible, scannable by QR, copyable, and visually distinct from secondary VPN-like adapters.
- Use the Physical Proof Links panel when doing acceptance evidence, because those URLs include the selected proof gate expected by the verifier.
- Prefer the run card's recommended same-Wi-Fi URL. Treat VPN-like private adapter URLs as secondary candidates unless the recommended URL fails.
- Confirm the guided runner's recommended LAN URL preflight passes before opening the URL on the phone.
- Open that LAN URL from the phone on the same Wi-Fi.
- Pair with the PIN, approve on the laptop, and confirm the phone sees the live selected monitor.
- Test touchpad movement, single-tap left click, double-tap right click, press-and-hold right click, double-tap drag for tabs/windows, direct touch, two-finger scroll, keyboard shortcuts, compose text, monitor switching, reconnect, and Stop.
- Open Settings and confirm diagnostics update while the stream is active.
- Move/drag on the phone and confirm diagnostics enter a responsive state, then settle after idle.
- Lock the phone or switch away from the PWA, then confirm host diagnostics enter hidden-stream mode; reopen the PWA and confirm frames resume.
- Turn on Precision and confirm tiny movements are easier for small targets, text caret placement, window edges, and narrow scrollbars; confirm the touch halo is visible but does not cover the bottom controls.
- Use the Zoom slider and pinch zoom, then pan the zoomed stream with two fingers and confirm direct taps land on the visible desktop area rather than the unzoomed full monitor.
- While zoomed in touchpad mode, drag from a stream edge and confirm the viewport pans locally without moving the laptop cursor.
- Adjust Scroll speed and confirm two-finger scrolling can be slowed down and sped up; toggle Touch halo and Haptic feedback to confirm the phone honors both preferences.
- Complete every proof checklist item in Settings, then tap Mark Proof from the controller proof banner or Settings and confirm the post-run host logs contain `acceptance.phoneMark`.
- Confirm the host console Latest Phone Proof panel updates with the same-Wi-Fi gate, phone origin, viewport, selected monitor, diagnostics, and completed checklist counts.
- Open Monitors and confirm the selected display is visually obvious.
- Add the phone PWA to the home screen and confirm it opens back to the remembered host session after pairing.
- Enable real input only after dry-run behavior looks correct.
- Enable trusted devices, approve one phone manually, then confirm a repeat pairing from the same phone auto-approves only after the correct PIN.
- Revoke that trusted phone from the host console and confirm it must pair and receive laptop approval again.
- Confirm host Stop All Control disables real input, releases held buttons, disconnects the phone, and revokes the session.
- Run `npm run acceptance:report -- -Gate same-wifi -Phase post` again after the test and keep the auto-exported `*-host-logs.json` plus a phone screenshot/photo with the report.
- Attach the phone screenshot/photo with `npm run acceptance:attach -- -Gate same-wifi -EvidencePath "C:\path\to\phone-photo.jpg" -Label "same-wifi-proof"` so the supporting image is copied, hashed, and indexed with the evidence bundle.
- Confirm the guided run saved a selected-gate verification section in the notes and a `phone-acceptance-verification-same-wifi-*.json` artifact. Rerun `npm run acceptance:verify:save -- -Gate same-wifi` if you want a fresh verifier timestamp after attaching photos.
- If daily-use auto-start is desired, run `npm run autostart:install`, sign out and back in, confirm the tray appears, open the host console from the tray, then run `npm run autostart:uninstall` if you do not want it kept.
- If daily-use no-terminal launch is desired without auto-start, run `npm run shortcut:install`, open the created shortcut, confirm the tray appears, and use `npm run shortcut:selftest` to validate the target command without changing the system.

## Manual Tailscale Gate

- Preferred guided run:

```powershell
npm run acceptance:doctor -- -Gate tailscale
npm run tailscale:check:save
npm run acceptance:ready -- -Gate tailscale
npm run acceptance:next
npm run acceptance:prepare -- -Gate tailscale
npm run acceptance:watch -- -Gate tailscale
npm run acceptance:phone -- -Gate tailscale
# Stop only after this is the last remaining physical gate.
npm run acceptance:stop -- -Gate tailscale
```

- Run `npm run acceptance:report -- -Gate tailscale -Phase pre` before the test and keep the generated Markdown/JSON/log files under `output\acceptance`.
- Run `npm run acceptance:doctor -- -Gate tailscale` and keep the generated `acceptance-doctor-tailscale-*.md` and `.json` readiness files under `output\acceptance`.
- Run `npm run tailscale:bootstrap:save` if Tailscale is not ready yet, and keep the generated `tailscale-bootstrap-*.md` and `.json` files with the setup evidence.
- Run `npm run tailscale:check:save` and keep the generated `tailscale-setup-check-*.md` and `.json` files with the Tailscale evidence bundle.
- Use `npm run acceptance:ready -- -Gate tailscale` after Tailscale is connected so the run card opens and the readiness JSON captures the current Tailscale URL and verifier blockers. If Tailscale is not ready, the readiness JSON must keep `phoneUrls` as `[]` and surface setup fixes such as installing/signing into Tailscale or adding the CLI to `PATH`.
- Run `npm run acceptance:next` after the Tailscale ready check so the current setup fixes or phone-run actions are saved as a concise operator Markdown file.
- Optionally keep `npm run acceptance:watch -- -Gate tailscale` open in a second terminal during the different-Wi-Fi run; it will report whether the Tailscale proof has the required summary, doctor files, phone mark, and network-path match.
- Run `npm run firewall:status`; if the rule is not ready and Tailscale cannot reach the laptop, run `npm run firewall:handoff` first, then run the copied elevated install command only if you choose to allow inbound TCP `4317`, then retry.
- Connect laptop and phone to the same Tailscale tailnet.
- Confirm the host console shows a `TAILSCALE` address with QR and copy controls, or document the detected Tailscale IP manually with `tailscale ip -4` or `tailscale ip -6`.
- Use the Tailscale entry in the Physical Proof Links panel for the different-Wi-Fi proof once Tailscale is connected.
- Confirm the guided runner's Tailscale URL preflight passes before moving to the phone.
- Check the report's Tailscale CLI snapshot so the evidence bundle records the laptop tailnet IPv4 and/or IPv6 address used for the phone URL.
- If using Tailscale IPv6, confirm the URL is bracketed, for example `http://[fd7a:115c:a1e0:...]:4317`.
- Move the phone off the laptop Wi-Fi path, for example cellular data with Tailscale still connected.
- Open the Tailscale URL from the phone.
- Complete every Tailscale proof checklist item in Settings, then tap Mark Proof from the controller proof banner or Settings and confirm the post-run host logs contain `acceptance.phoneMark` for the different-Wi-Fi run.
- Confirm the host console Latest Phone Proof panel updates with the Tailscale gate, Tailscale phone origin, and completed checklist counts.
- Repeat the same pairing, approval, viewing, input, reconnect, and emergency stop checks.
- Run `npm run acceptance:report -- -Gate tailscale -Phase post` again after the test and keep the auto-exported `*-host-logs.json` plus a phone screenshot/photo with the report.
- Attach the phone screenshot/photo with `npm run acceptance:attach -- -Gate tailscale -EvidencePath "C:\path\to\tailscale-phone-photo.jpg" -Label "tailscale-proof"` so the supporting image is copied, hashed, and indexed with the evidence bundle.
- Confirm the guided run saved a selected-gate verification section in the notes and a `phone-acceptance-verification-tailscale-*.json` artifact. Rerun `npm run acceptance:verify:save -- -Gate tailscale` if you want a fresh verifier timestamp after attaching photos.
- After both physical gates pass, run `npm run acceptance:finalize`; it saves both verifier outputs, bundles evidence, runs `npm run completion:audit:save`, and writes the finalization JSON/Markdown record.

## Failure Conditions

- Any input works before laptop approval.
- Public health exposes monitor details, sessions, settings, logs, or screen data.
- Exported host logs contain raw typed text, pasted text, or captured screen frame data.
- Any real input works while Input Safety says dry-run.
- Repeated wrong PIN attempts are not rate limited.
- Public tunnel mode does not show a higher-risk warning.
- A public remote can reach HTTP or WebSocket routes while `PUBLIC_URL`/public-tunnel mode is not explicitly configured.
- HTTP responses omit CSP/no-referrer/nosniff/frame-denial headers, or the CSP blocks the phone PWA, service worker, WebSocket, or screen stream frames.
- A disconnect leaves a held mouse button, keyboard modifier, or key down.
- The phone can no longer see Stop while a drawer is open.
- Monitor switching breaks coordinate mapping.
- Reconnect creates a new unapproved session without laptop approval.
- A revoked or expired saved phone session loops forever instead of returning to pairing with clear recovery steps.
- Replayed, stale, future-dated, or server-only WebSocket messages receive an error instead of affecting monitor, stream, session, or input state.
- HTTP API failures return bare or inconsistent errors that do not tell the phone or host console the next safe recovery action.
- Oversized JSON requests can be buffered without a bounded limit or return a non-recovery error instead of `PAYLOAD_TOO_LARGE`.
- Phone-supplied names, origins, trusted-device records, or logs can inject HTML/script into the laptop host console.
- Pointer-move coalescing drops button down/up, click, wheel, key, monitor, quality, or disconnect ordering.
- Hidden phone clients keep receiving full-rate capture frames instead of pausing, or a visible phone fails to resume frames after returning to the PWA.
- Service worker caches `/host?key=...`, host-console assets, API responses, WebSockets, or other query-string requests.
- Precision mode does not visibly reduce movement sensitivity, the active Precision state is unclear, or the touch halo is hidden/confusing on the phone viewport.
- Zoomed direct touch uses unzoomed coordinates, two-finger pan sends unintended laptop input while zoomed, or Reset View does not return the stream to 100%.
- Zoomed edge-pan sends `pointer.move` input to the laptop or fails to move the visible phone viewport.
- Scroll speed does not affect phone scrolling, disabled Touch halo still appears, or disabled Haptic feedback still vibrates the phone.
- Auto-start launches the host without the tray safety menu or starts with real input already enabled.
- Same-Wi-Fi/Tailscale failures are investigated without checking Windows Firewall status for inbound TCP `4317`.
- Same-Wi-Fi/Tailscale manual runs are started without first checking `npm run acceptance:doctor -- -Gate same-wifi` or `npm run acceptance:doctor -- -Gate tailscale`.
- The Tailscale/different-Wi-Fi gate is attempted without first running `npm run tailscale:bootstrap:save`, `npm run tailscale:check:save`, or equivalent Tailscale installation/sign-in/IP evidence.
- A revoked trusted phone can still auto-approve without a new manual laptop approval.
- Acceptance reports generated while the host is reachable do not include a matching host-log JSON artifact.
- Post-run host logs do not contain an `acceptance.phoneMark` entry from the physical phone, the proof payload is missing complete gate-matched checklist evidence, or the acceptance-mode phone controller never shows the saved proof state after the host acknowledges Mark Proof.
- Guided phone acceptance runs do not save a per-step notes file with readiness doctor report, pre-report, post-report, recommended/secondary phone URLs, pre-run blockers, pass/fail/skip results, and selected-gate saved verifier output.
- Guided phone acceptance `-RequireReady` mode continues into manual step collection despite selected-gate readiness failures, no selected-gate phone URL, or failed selected-gate URL preflight.
- Physical-run prepare does not save a `phone-acceptance-session-*.json` file and matching Markdown/HTML run cards with the host PID, recommended phone URLs, secondary phone URLs, inline QR codes, QR SVG files, and doctor report paths.
- Physical-run ready does not save `phone-acceptance-ready-*.json` with run-card, host-health, URL, setup failure/warning, ready-action, next-command, stop-command, and current verifier-blocker fields.
- Physical-run next does not save `phone-acceptance-next-*.json` and `.md` with gate statuses, phone URLs, current blockers, and concrete next actions.
- Physical-run refresh does not save `phone-acceptance-refresh-*.json` and `.md` with refreshed artifact links, step results, and remaining physical blockers.
- Operator phone screenshot/photo evidence is kept only outside the project folder, has no hash, or is not indexed by `phone-evidence-*.json`.
- Guided phone acceptance runs do not include a passing selected-gate URL preflight result.
- The latest selected-gate manual summary is older than a newer selected-gate readiness run.
- Phone acceptance verifier fails, is not run, or does not save a `phone-acceptance-verification-*.json` artifact for the completed same-Wi-Fi/Tailscale evidence bundle.
- Physical acceptance watcher cannot find the prepared run card, phone URLs, latest manual summary, or verifier blockers while a same-Wi-Fi/Tailscale run is in progress.
- Evidence bundle manifest is missing, stale, does not run/save the selected-gate verifier outputs, does not list the saved verifier artifacts for both physical gates, or omits physical finalization artifacts when they exist.
- Physical finalization is skipped after both phone gates pass, or it runs readiness/refresh/prepare commands after proof instead of directly verifying, bundling, and saving the completion audit.
- Completion audit fails, or is not run, after both physical gates are claimed complete.

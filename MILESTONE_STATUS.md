# Remote Desktop Controller Build Status

Source of truth: `C:\RemoteDesktopControllerPlan\Free_Remote_Desktop_Controller_15_Page_Build_Plan.docx`.

Traceability audit: `docs\TRACEABILITY_AUDIT.md`.

## Milestone 1 - Host Shell, Phone PWA, Auth, Socket, Fake Stream, Dry-Run Input

Status: verified.

Evidence:

- Unit tests pass: `node --test`
- Live smoke passes: `node test\live-smoke.js`
- Host health endpoint responds at `http://127.0.0.1:4317/api/health`
- Host console responds at `http://127.0.0.1:4317/host?key=dev-host-key`
- Phone pairing screen screenshot: `output\playwright\phone-pairing.png`
- Host console screenshot: `output\playwright\host-console.png`
- Connected phone controller screenshot: `output\playwright\phone-controller.png`

Verified behavior:

- Host server starts and listens on port `4317`.
- Host state includes fake monitors, pairing PIN, LAN addresses, session list, and logs.
- Phone can submit PIN and create a pending session.
- Host can approve the session.
- Approved phone can open the WebSocket channel.
- Phone receives fake stream frames.
- Phone sends dry-run pointer and keyboard commands.
- Host logs dry-run input commands.
- Phone can switch selected monitor and host state updates to `display-2`.

Known limits:

- Milestone 1 evidence was originally captured against fake stream mode.
- Later milestones add real screen capture and real input behind safety gates.
- Tailscale path is displayed if a Tailscale IPv4 `100.64.0.0/10` or IPv6 `fd7a:115c:a1e0::/48` address exists, but an end-to-end remote test has not been run.

## Milestone 2 - Selected-Monitor Capture, Streaming, Quality Presets, Reconnect

Status: verified.

Completed build tasks:

- Added a replaceable capture adapter interface in `src\capture-adapter.js`.
- Added real Windows display enumeration and JPG capture through the free `screenshot-desktop` package.
- Kept fake stream as the safe fallback when screen capture is unavailable or not requested.
- Added frame payload support for `imageDataUrl` screen frames in the phone canvas renderer.
- Preserved monitor selection against the actual available monitor list.
- Added quality presets that control capture cadence.
- Added phone-side reconnect backoff after unexpected WebSocket closure.
- Updated live smoke coverage so it selects an available monitor instead of assuming a second fake display exists.
- Updated live smoke coverage for stream quality changes and reconnecting with the same approved token.

Evidence:

- Direct adapter screen capture produced a real `image/jpeg` frame for `Display 1`.
- Screen-mode health endpoint reports `app.mode = milestone-2-screen-capture`.
- Screen-mode health endpoint reports `streamStats.source = screen`.
- Full screen-mode test run passes: `node --test`.
- Screen-mode live smoke passes, receives stream frames, switches quality to `fast`, and reconnects with the same approved token.
- Visual QA screenshot captured: `output\playwright\phone-controller-screen.png`.

Notes:

- The first PowerShell prototype for capture was blocked by Windows Defender/AMSI on this machine, so the active build uses `screenshot-desktop` instead.
- The screen-mode server is currently running locally on port `4317` with `CAPTURE_MODE=screen` and `HOST_KEY=dev-host-key`.

Remaining follow-up:

- Decide whether sharp/faster image scaling is needed after real-phone performance testing.

## Milestone 3 - Real Input, Gestures, Keyboard, Safety Release, Kill Switch

Status: verified for automated/local-desktop coverage; physical phone acceptance remains in Milestone 4.

Completed build tasks:

- Added `src\input-adapter.js` with dry-run default and host-gated real input mode.
- Added real mouse move/down/up/click, wheel scrolling, keyboard shortcut, and typed-text paths through `@nut-tree-fork/nut-js`.
- Added protocol support for double click, cancel drag, key down/up, chord, and paste text commands.
- Added a separately testable coordinate mapper for direct-touch monitor bounds and relative movement, hardened against malformed numeric input.
- Expanded coordinate coverage for side-by-side monitors, stacked monitors, portrait/rotated-style bounds, different scale factors, and safe fallback bounds.
- Reworked phone touchpad gestures so movement is relative by default, taps click, quick double taps can double click, long press starts drag, drag lock cancels cleanly, and two-finger movement sends scroll.
- Expanded the keyboard command bar with F1-F12, screenshot, lock, common navigation keys, command shortcuts, latched modifiers, and compose/paste text.
- Added host API `POST /api/input-mode` to enable or disable real input with the host key.
- Added host API `POST /api/safety-release` to release held mouse buttons.
- Added host API `POST /api/kill-switch` to disable input, release held buttons, disconnect clients, and revoke sessions.
- Added session expiry metadata and fail-closed expired-session removal.
- Hardened client command validation: phone-originated WebSocket commands must use a client-allowed type, positive monotonic sequence, fresh timestamp, and object payload before monitor, stream, session, or input handlers run.
- Added sequence-echo acknowledgements for critical non-input commands including monitor selection, stream quality changes, and phone visibility updates.
- Added next-action guidance to protocol error envelopes and phone diagnostics so WebSocket failures expose `code`, `friendly`, `detail`, `recoverable`, and `nextAction`.
- Added permission checks before pointer, keyboard, or text commands reach the input adapter.
- Added wrong-PIN rate limiting with per-remote lockout and visible host status.
- Added automatic safety release on phone disconnect and socket close.
- Wired the phone Stop button through `session.disconnect`, which now releases held input before closing the session.
- Added held-key tracking in the real input adapter so `keyDown` modifiers and keys are released by `keyUp`, safety release, disconnect, real-input disable, and kill switch paths.
- Added host console Input Safety panel with real-input toggle, release button, and stop-all-control kill switch.

Evidence:

- Full screen-mode test run passes: `node --test`.
- Protocol tests reject wrong-version, server-only, missing-sequence, replayed, stale-timestamp, future-timestamp, and bad-payload client commands.
- Protocol tests validate error envelopes include recoverability and next-action guidance.
- Coordinate mapping tests cover negative monitor bounds, center mapping, edge mapping, clamping, relative sensitivity, side-by-side monitors, stacked monitors, portrait bounds, different scale factors, and malformed-bound fallbacks.
- Session tests cover expiry removal and expiration logging.
- Session tests cover wrong-PIN rate limiting and lockout status.
- Live smoke now covers double click, cancel drag, keyboard chord, paste text, quality switch, reconnect, and host kill switch.
- Live smoke validates critical acknowledgements echo the original command sequence for monitor selection, stream quality changes, and visibility updates.
- Host API enable path reports `inputSafety.mode = real`.
- Host API safety release returns `ok = true`.
- Host API disable path returns `inputSafety.mode = dry-run`.
- Real input adapter moved the local cursor by 1 pixel and returned it to the original position without clicking or typing.
- Phone UI browser QA emitted `pointer.click`, `chord`, and `pasteText` commands from actual mobile viewport interactions.
- Keyboard sheet browser QA passed: stop button visible, sheet fits viewport, 33 command buttons, no overflowing button labels.
- Host console visual QA screenshot captured: `output\playwright\host-console-input-safety.png`.
- Phone keyboard sheet visual QA screenshot captured: `output\playwright\phone-keyboard-sheet.png`.

Risk and follow-up:

- The real input dependency currently introduces 7 moderate `npm audit` advisories through `jimp`/`file-type`; npm reports no upstream fix is available.
- Real input is implemented and gated, but live clicking and typing into a real desktop app should still be manually accepted from the phone before calling the whole product complete.

## Milestone 4 - Visual Polish, Tests, Tailscale Validation, Packaging Notes

Status: in progress.

Completed build tasks:

- Added acceptance checklist in `docs\ACCEPTANCE_TESTS.md`.
- Added Tailscale validation guide in `docs\TAILSCALE_VALIDATION.md`.
- Added packaging notes in `docs\PACKAGING_NOTES.md`.
- Added `scripts\run-qa.ps1` and `npm run qa`; QA now saves timestamped/latest JSON and Markdown reports under `output\acceptance`, including an operator artifact snapshot for the latest dashboard, handoff, evidence bundle, refresh, and completion audit files.
- Added `scripts\acceptance-report.ps1`, `npm run acceptance:report`, and `npm run acceptance:selftest` to snapshot host state plus the same-Wi-Fi/Tailscale manual checklist before and after physical phone testing.
- Added `-Phase pre|post` acceptance-report tagging so same-Wi-Fi and Tailscale evidence files clearly distinguish before-test snapshots from after-test proof.
- Acceptance reports now auto-export a matching sanitized `*-host-logs.json` file beside the Markdown/JSON report whenever the host is reachable.
- Acceptance reports now include a local Tailscale CLI snapshot with `tailscale ip -4` and `tailscale ip -6` output when the CLI is available from PATH or common Windows install paths, and a non-fatal unavailable note when it is not.
- Added `scripts\manual-phone-acceptance.ps1`, `npm run acceptance:phone`, and `npm run acceptance:phone:selftest` for guided real-device same-Wi-Fi and Tailscale runs. The runner starts the screen-capture host when needed, prints phone URLs, creates pre/post reports, saves pre-run blockers plus per-step pass/fail notes under `output\acceptance`, supports `-RequireReady` to stop before manual scoring when the selected gate is not ready, and now auto-runs the selected-gate verifier with saved output after the run unless explicitly skipped.
- Added `scripts\acceptance-doctor.ps1`, `npm run acceptance:doctor`, and `npm run acceptance:doctor:selftest` to check physical-run readiness before the manual phone gate: host health, advertised LAN/Tailscale URLs, host-side URL preflight, Windows Firewall status, and Tailscale CLI availability from PATH or common Windows install paths.
- Acceptance doctor now writes timestamped readiness Markdown/JSON reports under `output\acceptance` so same-Wi-Fi and Tailscale preflight state can be kept with the physical evidence bundle.
- Added `scripts\prepare-phone-acceptance.ps1`, `scripts\stop-phone-acceptance.ps1`, `npm run acceptance:prepare`, and `npm run acceptance:stop` to start a screen-capture host non-interactively for physical testing, save `phone-acceptance-session-*.json` with PID/URLs/doctor evidence, and stop only the prepared host by default.
- Physical-run prepare now also writes a matching `phone-acceptance-session-*.md` run card with laptop URL, phone URLs, warnings/failures, checklist command, stop command, and evidence reminders.
- Physical-run prepare now generates static QR SVG files for each advertised phone URL and links them from the run card, so the real phone can scan the prepared acceptance session directly.
- Physical-run prepare now also writes an HTML run card with inline QR images, laptop host URL, phone URLs, warnings/failures, next checklist command, and stop command.
- Physical-run prepare now groups phone URLs by gate: same-Wi-Fi recommends non-VPN LAN adapters first and moves VPN-like private adapters to Secondary, while Tailscale run cards only show Tailscale URLs as phone targets.
- Physical-run prepare now makes recommended phone URLs gate-aware by adding `acceptance=1`, the selected `gate`, and `step=physical-phone-proof`; the phone Settings proof panel labels the gate and Mark Proof defaults its proof payload to that gate.
- Physical-run QR success detection now treats an existing generated SVG as success, avoiding false QR failure messages when the QR CLI writes the file but returns an unreliable exit code.
- Guided phone acceptance now also prints and stores gate-aware proof URLs while preflighting the clean origin `/api/health` URL, so terminal-driven runs preserve the same proof context as run-card and QR-driven runs.
- Added selected-gate URL preflight to the guided real-device runner so the advertised LAN/Tailscale `/api/health` URL is checked from the laptop before the phone checklist begins.
- Guided real-device runner now groups phone URLs like the run card: same-Wi-Fi preflights and prints the recommended non-VPN LAN URL first, with VPN-like private adapters listed as secondary; Tailscale runs only target Tailscale URLs.
- Added `scripts\firewall-rule.ps1`, `npm run firewall:status`, `npm run firewall:install`, `npm run firewall:remove`, and `npm run firewall:selftest` as an explicit Windows Firewall helper for inbound TCP `4317`. The rule is limited to Private/Domain profiles and remote addresses `LocalSubnet`, Tailscale IPv4 `100.64.0.0/10`, and Tailscale IPv6 `fd7a:115c:a1e0::/48`; install/remove are explicit elevated actions, not automatic host startup behavior.
- Added `scripts\firewall-handoff.ps1`, `npm run firewall:handoff`, and `npm run firewall:handoff:selftest` as a non-mutating elevated-command handoff. It writes timestamped/latest JSON, Markdown, and `.ps1` artifacts, copies the exact elevated install command, and explicitly does not install/remove firewall rules or mark physical phone proof complete.
- Guided phone acceptance now records firewall readiness in the summary JSON and notes file.
- Added `scripts\verify-phone-acceptance.ps1`, `npm run acceptance:verify`, and `npm run acceptance:verify:selftest` to audit completed physical evidence bundles. The verifier requires selected-gate URL preflight to pass, all guided steps to pass, pre/post reports and post host logs to exist, an `acceptance.phoneMark` entry to exist, the phone proof payload gate to match the selected verifier gate, the phone proof checklist to be complete with the expected gate-specific item count, and the phone proof URL to match the selected same-Wi-Fi or Tailscale network path.
- Added `npm run acceptance:verify:save` and verifier `-Save` support so same-Wi-Fi/Tailscale verifier output is saved as timestamped plus latest `phone-acceptance-verification-*.json` evidence artifacts.
- Guided phone acceptance now captures readiness doctor Markdown/JSON artifacts in the notes and summary; the physical evidence verifier now requires those doctor files to exist, match the selected gate, and report zero failures.
- Added `scripts\watch-phone-acceptance.ps1`, `npm run acceptance:watch`, and `npm run acceptance:watch:selftest` to monitor prepared physical phone sessions and report the current host health, run-card links, phone URLs, latest manual summary, and remaining verifier blockers until a gate passes.
- Added `scripts\acceptance-ready.ps1`, `npm run acceptance:ready`, and `npm run acceptance:ready:selftest` as a one-command physical-run launcher. It prepares the screen-capture host, opens the HTML run card by default, snapshots watcher status with saved watcher JSON, saves `phone-acceptance-ready-*.json`, preserves empty Tailscale URL lists as arrays, surfaces setup failures/ready actions, and avoids hanging when the prepared Node host stays running.
- Physical-run readiness now writes a current preliminary ready artifact before watcher verification and then overwrites it with the final watcher snapshot, so verifier blocker details in the operator handoff are tied to the selected readiness run instead of an older run.
- Added `scripts\acceptance-next.ps1`, `npm run acceptance:next`, and `npm run acceptance:next:selftest` as a concise operator checklist writer. It reads latest same-Wi-Fi/Tailscale ready artifacts and saves `phone-acceptance-next-*.json` plus `.md` with exact next actions and warning actions for the physical phone proof.
- Added `scripts\acceptance-dashboard.ps1`, `npm run acceptance:dashboard`, and `npm run acceptance:dashboard:selftest` to generate a single polished HTML/JSON physical acceptance dashboard from the latest ready, next-action, evidence-bundle, and QA-report artifacts, including saved verifier JSON links, QA pass status, and current verifier failed checks for each physical gate.
- Added `scripts\acceptance-handoff.ps1`, `npm run acceptance:handoff`, and `npm run acceptance:handoff:selftest` to generate a scan-first real-phone launch page from the latest ready/run-card/dashboard/next/evidence/QA artifacts, including the same-Wi-Fi QR, exact checklist command, Mark Proof reminder, QA report link, saved verifier links, and Tailscale setup blockers.
- Physical next-action, dashboard, and handoff surfaces now point to `npm run acceptance:finalize` as the final no-refresh finish path after both real phone gates pass.
- Added `scripts\acceptance-refresh.ps1`, `npm run acceptance:refresh`, and `npm run acceptance:refresh:selftest` to regenerate Tailscale bootstrap, Tailscale setup-check, same-Wi-Fi readiness, Tailscale readiness, next-action checklist, initial evidence bundle, dashboard, handoff, final evidence bundle, completion audit, and post-audit evidence bundle artifacts in the correct order while treating physical-only failures as expected incomplete evidence. The final pre-audit bundle indexes the handoff from the same refresh run, and the post-audit bundle indexes the saved completion audit.
- Acceptance refresh now also runs `scripts\dependency-audit.ps1 -Save` before the final completion audit so package-risk evidence is regenerated with the physical acceptance artifacts.
- Added `scripts\finalize-physical-evidence.ps1`, `npm run acceptance:finalize`, and `npm run acceptance:finalize:selftest` as the no-refresh final completion path after real phone runs. It saves both gate verifier outputs, writes the evidence bundle, saves the whole-manual completion audit, and records a `physical-evidence-finalization-*.json` plus `.md` report without creating a newer readiness artifact.
- Added `scripts\attach-phone-evidence.ps1`, `npm run acceptance:attach`, and `npm run acceptance:attach:selftest` to copy operator-supplied phone screenshots/photos into `output\acceptance`, hash them, save `phone-evidence-*.json`, and label them as supporting evidence that does not replace verifier proof.
- Added `scripts\tailscale-setup-check.ps1`, `npm run tailscale:check`, `npm run tailscale:check:save`, and `npm run tailscale:check:selftest` to inspect the different-Wi-Fi path before the physical Tailscale gate: Tailscale CLI/IP/status, host-advertised Tailscale URL, and firewall readiness.
- Added `scripts\tailscale-bootstrap.ps1`, `npm run tailscale:bootstrap`, `npm run tailscale:bootstrap:save`, and `npm run tailscale:bootstrap:selftest` as a non-mutating setup assistant for the free different-Wi-Fi path. It detects Tailscale CLI/service state, winget availability, and exact laptop/phone setup commands without installing software, signing in, changing firewall rules, or marking the physical gate complete.
- Added `scripts\evidence-bundle.ps1`, `npm run evidence:bundle`, and `npm run evidence:bundle:selftest` to write timestamped/latest Markdown and JSON manifests that save current same-Wi-Fi/Tailscale verifier outputs, index evidence artifacts, ready status artifacts, next-action artifacts, firewall handoff artifacts, handoff pages, and verifier blockers.
- Added `scripts\dependency-audit.ps1`, `npm run dependency:audit`, `npm run dependency:audit:save`, and `npm run dependency:audit:selftest` to save timestamped/latest package-risk JSON and Markdown reports. The policy fails on high/critical advisories and records the current moderate real-input transitive advisories as reviewed packaging risk.
- Added `scripts\completion-audit.ps1`, `npm run completion:audit`, `npm run completion:audit:save`, and `npm run completion:audit:selftest` as the final whole-manual audit. It checks the manual/docs/scripts/package hooks and intentionally fails until both same-Wi-Fi and Tailscale physical evidence verifiers pass; `:save` writes timestamped plus latest JSON/Markdown audit reports before exiting.
- Completion audit verifier failures now report concise failed-check details instead of raw verifier JSON, so physical gate blockers stay readable in the final audit output.
- Added host-console QR codes and copy buttons for each advertised phone URL.
- Host console advertised phone URLs now include guidance badges: recommended for normal same-Wi-Fi LAN adapters, secondary for VPN-like private adapters such as NordLynx, and Different Wi-Fi for Tailscale addresses.
- Added host-console Physical Proof Links panel with gate-aware same-Wi-Fi/Tailscale proof URLs, copy buttons, and QR codes separate from the daily-use raw address list.
- Added a controller-level acceptance proof banner on the phone app for gate-aware physical runs, with the selected proof gate, selected proof step, Mark Proof action, and saved-in-host-logs state after host acknowledgement.
- Added `scripts\tray-host.ps1` and `npm run tray` as the first daily-use Windows tray host shell.
- Tray host now separates daily URL copying into `Copy Recommended Phone URLs` and `Copy All Phone URLs`, so normal same-Wi-Fi use does not default to VPN-like private adapters.
- Added `scripts\install-autostart.ps1`, `scripts\uninstall-autostart.ps1`, `npm run autostart:install`, `npm run autostart:uninstall`, and `npm run autostart:selftest` for a user-logon Scheduled Task wrapper around the tray host.
- Added installable PWA metadata: manifest scope, SVG icon, and service worker shell caching.
- Narrowed service worker caching to the phone app shell only; dynamic APIs, WebSockets, query-string URLs, and host-console assets are not cached.
- Added host settings API and UI for default quality, default sensitivity, and trusted-device toggle.
- Added persistent host settings storage at `data\host-settings.json`.
- Persisted trusted-device fingerprints locally while redacting them from public host/health state.
- Made trusted-device mode functional: first contact still needs PIN plus manual laptop approval, then future correct-PIN pairings from the same trusted device fingerprint can auto-approve while trusted mode is enabled.
- Added trusted-device management in the host console: redacted device list, per-device revoke, and clear-all trusted devices. Revoking trust also revokes affected sessions and disconnects active clients for those sessions.
- Hardened host console rendering so phone-supplied device names, origins, trusted-device records, logs, and connection setup text are rendered with DOM text nodes instead of dynamic `innerHTML`.
- Added session origin metadata and WebSocket origin checking when an origin is present.
- Host session rows now show manual/trusted status, session expiry, and recorded origin.
- Added host frame diagnostics: frames sent, last frame size, capture time, dropped frame ticks, and connected client count.
- Added phone diagnostics for approximate FPS, target FPS, bandwidth estimate, frame size, host capture time, latency, and input round trip.
- Added adaptive stream cadence: input activity temporarily raises freshness, idle state lowers cadence, and diagnostics expose adaptive mode plus preset target FPS.
- Added phone-side pointer-move coalescing so rapid movement batches into fresh input updates while click, wheel, key, drag, monitor, quality, and disconnect commands flush pending movement first to preserve ordering.
- Added phone Precision mode and a visible touch halo: precision lowers movement sensitivity for fine targeting, the active button state is obvious, and the halo follows current touch location without blocking the control rail.
- Added phone viewport zoom/pan support: Settings exposes a Zoom slider and Reset View, pinch changes viewport zoom, two-finger movement pans the zoomed stream, and direct-touch coordinate mapping now respects the visible crop.
- Added zoomed edge-pan behavior: one-finger movement from the stream edge in touchpad mode pans the phone viewport locally without sending laptop cursor input, and diagnostics count local edge-pan moves.
- Added phone control preferences in Settings: scroll speed, touch halo visibility, and haptic feedback toggles persist locally, appear in diagnostics, and keep the phone controls configurable for daily use.
- Added phone-side Mark Proof in Settings: an approved phone sends an authenticated `acceptance.mark` WebSocket message and the host exports an `acceptance.phoneMark` log with viewport, URL origin/path, PWA/touch capability flags, monitor, quality, diagnostics counters, and gate-aware checklist completion for physical same-Wi-Fi/Tailscale evidence.
- Added gate-aware phone proof checklist gating: same-Wi-Fi and Tailscale acceptance URLs render the correct physical checklist in Settings, block Mark Proof until every item is checked, and include checklist counts/items in the saved proof payload.
- Added host-console Latest Phone Proof panel so the laptop visibly summarizes the newest `acceptance.phoneMark` gate, origin, step, viewport, monitor, FPS, and checklist completion during a real phone run.
- Added phone visibility reporting and host-side hidden-stream pausing: when every connected phone is hidden, the host stops sending capture frames, reports `adaptiveMode = hidden`, and exposes visible/hidden client counts plus hidden-frame ticks.
- Added host log export at `GET /api/logs?key=...` and an Export Logs button in the host console.
- Sanitized input log details so exported logs keep command diagnostics but do not store raw typed or pasted text; text commands record length only.
- Added an auto-start preference field to persistent host settings so the host UI can reflect the user's daily-use intent before installing or removing the Windows task.
- Added network-risk state for LAN, Tailscale, and public tunnel modes.
- Added in-app Connection Setup validation for same-Wi-Fi, Tailscale/different-Wi-Fi, and testing-only public tunnel paths.
- Added Tailscale IPv6 `fd7a:115c:a1e0::/48` detection, bracketed IPv6 phone URLs, and default dual-stack host binding with IPv4 fallback for different-Wi-Fi testing.
- Reduced unauthenticated `GET /api/health` to a redacted readiness payload. Monitor details, sessions, settings, and logs now require the host key through `GET /api/host` or `GET /api/logs`.
- Added inbound network guard for HTTP and WebSocket entry points: loopback, private LAN, Tailscale IPv4, and Tailscale IPv6 clients are accepted by default; public remotes are rejected unless `PUBLIC_URL` public-tunnel mode is explicitly configured.
- Added browser security headers to HTTP responses, including Content-Security-Policy, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, and frame-embedding denial while still allowing same-origin WebSockets and data-image stream frames.
- Added phone-side connection diagnostics for host unreachable, wrong PIN, PIN rate limit, expired/revoked saved session, and realtime socket disconnects.
- Standardized host HTTP API error envelopes so REST failures now match WebSocket recovery guidance with `error`, `code`, `friendly`, `detail`, `recoverable`, and `nextAction`.
- Added a 64 KB JSON body limit for phone/host API requests so oversized LAN/Tailscale requests fail closed with a `PAYLOAD_TOO_LARGE` recovery envelope instead of being buffered without bound.
- Hardened phone reconnect recovery: after a realtime socket closes, the phone verifies the saved session before retrying, keeps retrying through temporary network loss, and stops the reconnect loop with a Forget-and-pair-again prompt when the saved token is expired or revoked.
- Added optional `PUBLIC_URL` advertised address support for temporary tunnel testing with visible risk warning.
- Hardened `npm run qa` so it starts a fresh current-tree host by default instead of accidentally reusing a stale server already listening on port `4317`; `-ReuseExisting` remains available for intentional reuse.
- Upgraded the phone monitor picker with a layout-aware mini display arrangement, capture status badge, orientation, primary flag, and scale factor.
- Re-ran mobile keyboard visual QA on a 390 x 844 phone viewport; Stop remains visible, sheet fits, no key labels overflow.
- Re-ran host console visual QA with Input Safety controls.

Evidence:

- `npm run qa` passes on 2026-05-23 with 38 passing tests, 0 failures, 27 script self-tests, and saves `output\acceptance\qa-report-20260523-133223.md` plus `.json` with operator artifact snapshot records for dashboard, handoff, physical proof runbook, physical proof launch, evidence bundle, refresh, firewall handoff, completion audit, physical finalization artifacts, and the desktop shortcut installer self-test.
- Current automated tests pass: 38 tests.
- Live smoke validates exported logs and host stream diagnostics.
- Live smoke validates the phone acceptance proof marker acknowledgement and exported `acceptance.phoneMark` host-log entry.
- Live smoke validates exported logs do not contain raw pasted text while preserving text length diagnostics.
- Live smoke validates phone-hidden stream pausing: `stream.visibility` reaches the host, visible clients drop to 0, `adaptiveMode` becomes `hidden`, `fpsTarget` becomes 0, and capture frames stop advancing beyond the tolerated in-flight frame.
- Live smoke validates host network validation state for same-Wi-Fi and Tailscale setup.
- Live smoke validates public health redaction and confirms unauthenticated `/api/host` is forbidden.
- Live smoke validates the app shell returns CSP, no-referrer, and nosniff headers without breaking browser/PWA/WebSocket tests.
- Live smoke validates unauthenticated `/api/host` returns a recovery-ready `BAD_HOST_KEY` HTTP error envelope with `code`, `recoverable`, and `nextAction`.
- Live smoke validates oversized `/api/pair` JSON is rejected with `413 PAYLOAD_TOO_LARGE`, max-byte detail, and next-action guidance.
- Network unit tests validate LAN, Tailscale IPv4/IPv6, and public tunnel readiness states.
- Network unit tests validate the inbound remote-address guard for loopback, private LAN, Tailscale IPv4/IPv6, and public addresses.
- Phone browser test validates the actionable connection diagnostics card on a 390 x 844 mobile viewport.
- Phone browser test validates expired saved-session recovery stops reconnect attempts, returns to pairing, and shows the Forget-and-pair-again guidance.
- Phone browser test validates pointer-move coalescing and confirms critical click ordering is preserved.
- Phone browser test validates Precision mode lowers effective movement sensitivity and shows the touch halo/active button state on a 390 x 844 mobile viewport.
- Phone browser test validates zoomed viewport direct-touch mapping through the visible crop and captures the Zoom/Reset controls on a 390 x 844 mobile viewport.
- Phone browser test validates zoomed edge-pan changes the local viewport without sending `pointer.move` to the host.
- Phone browser test validates scroll speed, touch halo, and haptic feedback settings, including local persistence and visual fit on a 390 x 844 mobile viewport.
- Phone browser test validates Mark Proof payload generation on a mobile viewport, including gate-aware proof mode from run-card URL parameters and checklist completion in the proof payload.
- Phone browser test validates Mark Proof is blocked until the gate-aware physical checklist is complete.
- Phone browser test validates the acceptance proof banner is visible from the controller in gate-aware physical-run mode, sends `acceptance.mark`, and shows saved proof state after acknowledgement.
- Phone browser test validates page-visibility reporting so the host can pause hidden phone streams.
- Acceptance report self-test passes and verifies same-Wi-Fi plus Tailscale checklist coverage.
- Acceptance report self-test verifies default `phase = pre`; explicit `-Gate tailscale -Phase post` self-test verifies Tailscale post-run report metadata.
- Guided phone acceptance self-test passes for same-Wi-Fi and Tailscale checklist modes, including the default after-run verifier-save hook and `-RequireReady` support.
- Physical-run readiness doctor self-test passes.
- Guided phone acceptance self-test passes with doctor capture enabled, and phone evidence verifier self-test now exercises 31 checks including readiness doctor JSON/Markdown existence, gate match, zero doctor failures, stale-summary rejection, and complete gate-aware phone checklist proof.
- A non-physical same-Wi-Fi runner simulation created `output\acceptance\manual-phone-run-same-wifi-20260523-052601.json` and confirmed the stricter verifier rejects simulated/skipped evidence while accepting the doctor artifacts. Rejection reasons: manual summary older than the latest same-Wi-Fi readiness run, all 13 manual steps skipped, and no physical-phone `acceptance.phoneMark` entry.
- Tailscale `-RequireReady` smoke generated `output\acceptance\manual-phone-run-tailscale-20260523-080326.json` and `.md`; it stopped before manual step collection and saved blockers for missing Tailscale URL, missing Tailscale CLI, and no selected Tailscale phone URL.
- Current same-Wi-Fi readiness doctor passes with warnings: LAN URLs are advertised and laptop-side `/api/health` preflight passes; Windows Firewall rule is not installed or not ready.
- Current Tailscale readiness doctor and setup checker fail as expected on this machine because Tailscale is installed and the Windows service is running, but the laptop is still in `NeedsLogin`, has no tailnet IP, and therefore advertises no Tailscale IPv4/IPv6 URL.
- Current Tailscale bootstrap assistant saved `output\acceptance\tailscale-bootstrap-20260523-133237.md` and `.json`; it found `C:\Program Files\Tailscale\tailscale.exe`, confirmed the Tailscale service is running, captured backend state `NeedsLogin`, and recorded the exact auth URL `https://login.tailscale.com/a/2dfa69a0114b9`.
- Current Tailscale setup check saved sanitized reports at `output\acceptance\tailscale-setup-check-20260523-133241.md` and `.json`; the blockers are no tailnet IP and no host-advertised Tailscale URL, with host reachability passing at `http://127.0.0.1:4317`, backend state `NeedsLogin`, auth URL `https://login.tailscale.com/a/2dfa69a0114b9`, and a Windows Firewall warning that now points to `npm run firewall:handoff first`.
- Current Tailscale ready wrapper saved `output\acceptance\phone-acceptance-ready-tailscale-20260523-133256.json`; it keeps `phoneUrls` as an empty array and records the exact ready action: open the Tailscale auth URL, sign in, then run `npm run acceptance:ready -- -Gate tailscale`.
- Current readiness doctor artifacts are refreshed through the latest same-Wi-Fi and Tailscale ready wrappers, including the Tailscale `NeedsLogin` auth URL in the Tailscale doctor output.
- Same-Wi-Fi physical-run prepare/stop smoke passed: `npm run acceptance:prepare -- -Gate same-wifi` created `output\acceptance\phone-acceptance-session-same-wifi-20260523-051530.json` plus host stdout/stderr log files, and `npm run acceptance:stop -- -Gate same-wifi` stopped the prepared host PID. A follow-up port check found no listener on `4317`.
- Same-Wi-Fi physical-run card smoke passed: `npm run acceptance:prepare -- -Gate same-wifi` created `output\acceptance\phone-acceptance-session-same-wifi-20260523-051756.md` and `.json` with laptop host console URL, phone URLs, warnings, checklist command, stop command, and evidence reminders; the generated Markdown command fences render correctly.
- Same-Wi-Fi physical-run QR smoke passed: `npm run acceptance:prepare -- -Gate same-wifi` generated static QR SVGs at `output\acceptance\phone-acceptance-qr-same-wifi-20260523-052048-1.svg` and `output\acceptance\phone-acceptance-qr-same-wifi-20260523-052048-2.svg`, and linked them from `output\acceptance\phone-acceptance-session-same-wifi-20260523-052048.md`.
- Same-Wi-Fi physical-run HTML card smoke passed: `npm run acceptance:prepare -- -Gate same-wifi` generated `output\acceptance\phone-acceptance-session-same-wifi-20260523-052329.html`, with inline QR images referencing the generated SVGs, host console URL, phone URLs, warnings/failures, checklist command, and stop command. The prepared host was stopped cleanly afterward and port `4317` had no listener.
- Same-Wi-Fi physical-run watcher smoke passed: `npm run acceptance:watch -- -Gate same-wifi -Once` found the prepared run card, confirmed the screen-capture host was reachable, surfaced phone URLs, and reported the current blockers as 13 skipped manual steps plus missing `acceptance.phoneMark`.
- Same-Wi-Fi physical-run ready wrapper passed from a stopped-host state: `npm run acceptance:ready -- -Gate same-wifi -NoOpen` created `output\acceptance\phone-acceptance-ready-same-wifi-20260523-083406.json`, left the prepared host running, and reported only the expected real-phone blockers.
- Current physical-run next-actions checklist was generated at `output\acceptance\phone-acceptance-next-20260523-133257.md` and `.json`; it marks same-Wi-Fi as ready for phone testing with `http://192.168.0.7:4317?acceptance=1&gate=same-wifi&step=physical-phone-proof`, includes warning actions, links the latest Tailscale bootstrap report, and marks Tailscale as setup-needed with the exact auth URL action.
- Current same-Wi-Fi prepared run card is `output\acceptance\phone-acceptance-session-same-wifi-20260523-133242.html`; the prepared host is running on port `4317`, recommends `http://192.168.0.7:4317?acceptance=1&gate=same-wifi&step=physical-phone-proof`, and lists `http://10.5.0.2:4317 (NordLynx)` as a secondary VPN-like candidate.
- Firewall helper self-test passes and validates the intended rule shape without changing Windows Firewall.
- Firewall handoff self-test passes and validates JSON/Markdown/elevated-script artifact creation without changing Windows Firewall or marking physical proof complete. The latest handoff is `output\acceptance\firewall-handoff-install-20260523-125030.md` plus `.json` and `.ps1`; current firewall readiness is still false because no elevated rule is installed.
- Acceptance doctor, Tailscale setup check, and guided phone acceptance warnings now point to `npm run firewall:handoff` before any elevated firewall install, so the operator gets a saved/copied command without automatic firewall mutation.
- The scan-first physical handoff Markdown now includes per-gate warning sections, including the `npm run firewall:handoff first` action, so the text handoff does not hide firewall readiness warnings that were already present in the richer dashboard/next-action artifacts.
- Phone acceptance verifier self-test passes and exercises 31 evidence checks, including selected-gate URL preflight, manual-summary freshness against the latest gate readiness run, proof-gate matching, completed phone checklist proof, readiness doctor artifacts, firewall status capture, and saved verifier artifact creation.
- Physical acceptance watcher self-test passes and confirms it can call the verifier self-test, resolve the prepare/verifier scripts used during physical runs, save watcher snapshots, and expose normalized readiness status plus primary phone URL.
- Physical acceptance dashboard self-test passes and validates timestamped/latest HTML plus JSON output, same-Wi-Fi proof URL rendering, saved verifier JSON links, Tailscale setup blockers, missing-artifact visibility, and the explicit physical-evidence-required state.
- Physical acceptance refresh self-test passes and validates timestamped/latest JSON plus Markdown output, required script presence including the Tailscale setup-check step, compact step summaries, physical-only failure handling, and saved operator commands that verify phone proof, bundle evidence, and run the final audit without creating a newer stale readiness artifact after proof.
- Phone evidence attachment self-test passes and validates copying, SHA-256 hashing, timestamped/latest JSON records, safe labels, and the explicit `doesNotReplaceVerifier` marker.
- Tailscale setup checker self-test passes and validates the local firewall helper plus network module dependencies used by the different-Wi-Fi readiness check.
- Tailscale bootstrap assistant self-test passes and confirms the report is non-mutating, includes the laptop install step, and includes the final Tailscale verifier command.
- Evidence bundle self-test passes and validates the bundle writer can resolve the physical evidence verifier and produce JSON/Markdown manifests, including physical proof runbook, physical finalization, and firewall handoff indexing; real bundle runs now save current verifier JSON outputs for both gates before indexing artifacts.
- Dependency audit self-test passes and validates that moderate advisories are reported as reviewed risk while high/critical advisories remain a packaging blocker.
- Physical evidence finalization self-test passes and confirms the final no-refresh finish path writes JSON/Markdown, has its required scripts, and avoids readiness refresh commands after phone proof.
- Completion audit self-test passes and confirms the final audit reports `not-complete` when same-Wi-Fi and Tailscale physical evidence are absent while still writing saved audit reports.
- Current QA save generated `output\acceptance\qa-report-20260523-133223.md` and `.json`; it passes 38 Node/browser/live-smoke tests plus 27 script self-tests after adding launch artifact snapshot coverage, the setup-check report to Tailscale next-action/runbook guidance, refresh-regenerated Tailscale setup-check evidence, firewall handoff artifacts to QA, evidence-bundle coverage, handoff-first firewall warnings, scan-first handoff Markdown warning visibility, the physical proof launcher, physical proof runbook, physical evidence finalization artifact indexing, readiness freshness coverage, concrete Tailscale auth-URL handoff coverage, setup-URL launch fallback, no-refresh finalizer guidance, and the non-elevated no-terminal shortcut installer.
- Current dependency audit save generated `output\acceptance\dependency-audit-20260523-133304.md` and `.json`; it reports status `reviewed-known-risk`, 7 moderate advisories, and 0 high/critical advisories.
- Current physical evidence finalization report generated `output\acceptance\physical-evidence-finalization-20260523-112114.md` and `.json`; it exits incomplete as expected until real phone proof exists, but it saves both verifier outputs, evidence bundle artifacts, and completion-audit artifacts without running readiness refresh.
- Current completion audit save generated `output\acceptance\completion-audit-20260523-133326.md` and `.json`; it tracks 183 requirements and fails only the required physical evidence gates: `PHYSICAL-001` same-Wi-Fi verifier, `PHYSICAL-002` Tailscale verifier, and `PHYSICAL-003` both physical gates present. It now also proves the physical proof launcher, same-Wi-Fi/Tailscale launch artifact existence, evidence-bundle launch indexing, QA launch artifact snapshot coverage, physical proof runbook, non-mutating firewall handoff behavior, handoff-first firewall warnings, scan-first handoff Markdown warning visibility, refresh-regenerated Tailscale setup-check evidence, setup-check guidance on Tailscale next-action/runbook surfaces, latest same-Wi-Fi readiness content, Tailscale readiness/setup content including the concrete login handoff or tailnet-IP evidence, normalized readiness status plus `primaryPhoneUrl` and setup/physical blocker counts, preservation of readiness status and primary URL through next-action/dashboard/handoff artifacts, saved watcher snapshot status/primary URL/blocker proof for both physical gates, phone-side proof checklist gating, payload evidence, verifier enforcement, verifier stale-summary rejection, readiness freshness before watcher verification, no-refresh finalizer commands on the operator next-action/dashboard/handoff surfaces, refresh final commands that avoid stale proof after successful verifier runs, no-refresh physical finalization command coverage, daily-use shortcut script/package/docs coverage, host-console checklist visibility, Tailscale CLI discovery from common Windows install paths in the doctor/manual report, dependency audit evidence with no high/critical advisories, evidence-bundle dependency-audit indexing, evidence-bundle physical-finalization indexing, evidence-bundle physical-proof-runbook indexing, evidence-bundle firewall-handoff indexing, handoff gate content, dashboard gate content, dashboard/handoff QA visibility, dashboard/handoff pinning to the current timestamped QA report identity, evidence-bundle verifier paths, evidence-bundle handoff artifact records, evidence-bundle indexing of the current timestamped QA report identity, saved QA pass results, named QA self-test suite coverage, QA self-test script-path mapping, visible QA Markdown test totals/self-test rows/artifact snapshot rows/physical gate reminder, QA freshness after the newest implementation/test/package/acceptance-script change, optional phone screenshot/photo supporting-evidence validation, QA artifact snapshot records, extracted-manual source markers, all-page traceability markers, explicit non-skippable build-goal mapping, exact package-script and self-test command target checks, refresh artifact indexing, post-audit bundle refresh execution, non-empty latest operator artifacts, and the `completion:audit:save` package hook. Current concise blockers: same-Wi-Fi has a skipped manual summary from before the current readiness run plus no physical-phone `acceptance.phoneMark`; Tailscale is installed/running but in `NeedsLogin`, has no tailnet IP or selected-gate URL preflight, and is missing post report/logs plus physical-phone `acceptance.phoneMark`.
- Current acceptance refresh summary was generated at `output\acceptance\phone-acceptance-refresh-20260523-133308.md` and `.json`; it records same-Wi-Fi `ready-for-phone`, Tailscale `setup-needed`, the refreshed Tailscale setup-check artifacts, the physical proof runbook, dashboard/final-evidence/dependency-audit/handoff/audit/post-audit-bundle refresh paths, compact step summaries, saved watcher snapshots, saved completion audit artifacts, the same-refresh post-audit evidence bundle, final commands that bundle/audit after proof instead of refreshing readiness again, and the expected physical-only audit failures without marking completion.
- Current evidence bundle manifest was generated at `output\acceptance\remote-controller-evidence-bundle-20260523-133334.md` and `.json`; it saved current same-Wi-Fi and Tailscale verifier JSON outputs, indexes the latest same-Wi-Fi and Tailscale ready status, Tailscale bootstrap/setup reports, next-action checklist, physical proof launch latest/timestamped JSON and Markdown records for both gates, acceptance dashboard, acceptance handoff pages, latest QA report artifacts with artifact snapshot evidence, dependency-audit latest/timestamped JSON and Markdown records, firewall handoff latest/timestamped JSON/Markdown/script records, acceptance refresh summary, saved completion audit artifacts, physical finalization latest/timestamped JSON and Markdown records, operator-attached phone evidence records, run card, doctor, report, QR artifacts, watcher snapshots, and confirms the remaining missing physical phone evidence.
- Current physical acceptance dashboard was generated at `output\acceptance\phone-acceptance-dashboard-20260523-133259.html` and `.json`; browser QA captured `output\playwright\acceptance-dashboard.png`, verified two gate cards, no horizontal overflow at 1366 x 900, visible same-Wi-Fi proof URL, visible Tailscale setup-needed state, visible saved verifier JSON links for both gates, visible QA report links, and visible `physical evidence still required` state.
- Current physical phone handoff was generated at `output\acceptance\phone-acceptance-handoff-20260523-133259.html`, `.md`, and `.json`; browser QA captured `output\playwright\acceptance-handoff.png`, verified no horizontal overflow at 1366 x 900, rendered the latest same-Wi-Fi QR at usable size, showed the Mark Proof reminder, pointed at `http://192.168.0.7:4317?acceptance=1&gate=same-wifi&step=physical-phone-proof`, linked latest verifier JSON and QA report artifacts, and listed the current Tailscale setup blockers.
- Phone acceptance proof banner visual QA captured `output\playwright\phone-acceptance-proof-banner.png`; browser QA verified the banner is visible on a 390 x 844 mobile viewport, shows the selected same-Wi-Fi gate and physical proof step, reaches the saved proof state, keeps Stop visible, and has no horizontal overflow.
- 15-page traceability audit exists at `docs\TRACEABILITY_AUDIT.md` and maps every page goal to implemented evidence plus remaining physical proof gates.
- Acceptance report real-host smoke generated phase-tagged `output\acceptance\manual-acceptance-same-wifi-post-20260523-043028.md`, `.json`, and `manual-acceptance-same-wifi-post-20260523-043028-host-logs.json`.
- Acceptance report real-host smoke generated `output\acceptance\manual-acceptance-20260523-042803.md`, `.json`, and `manual-acceptance-20260523-042803-host-logs.json` with `hostLogsExported = true`.
- Acceptance report generated current host evidence at `output\acceptance\manual-acceptance-20260523-031602.md` and `output\acceptance\manual-acceptance-20260523-031602.json`.
- Tailscale-specific acceptance report command passes and generated `output\acceptance\manual-acceptance-20260523-031646.md` plus `.json`.
- Tray host self-test passes, resolves `http://127.0.0.1:4317/host?key=dev-host-key`, and confirms recommended phone URL selection is enabled.
- Auto-start install self-test passes and builds a `RemoteControllerHost` Scheduled Task command targeting `scripts\tray-host.ps1`.
- Auto-start uninstall self-test passes and targets unregistering the `RemoteControllerHost` Scheduled Task.
- Host console browser test validates each advertised phone URL has a QR-adjacent copy button and that clicking it writes the selected URL to the clipboard path.
- Host console browser test validates recommended/secondary/Tailscale guidance labels for phone URLs.
- Host console browser test validates gate-aware Physical Proof Links for same-Wi-Fi and Tailscale proof URLs, while excluding VPN-like LAN adapters from the recommended same-Wi-Fi proof link.
- Host console browser test validates a malicious phone-supplied device name is displayed as text, creates no injected image elements, and does not execute script.
- Host console browser test validates the Latest Phone Proof panel renders gate, origin, step, viewport, monitor, FPS, and checklist completion from the latest `acceptance.phoneMark` log.
- Host console auto-start settings visual QA screenshot captured: `output\playwright\host-console-autostart-settings.png`.
- Host console connection setup visual QA screenshot captured: `output\playwright\host-console-connection-setup.png`.
- Current acceptance report shows LAN same-Wi-Fi readiness, no detected Tailscale IPv4 `100.64.0.0/10` or IPv6 `fd7a:115c:a1e0::/48` address, dry-run input safety, screen capture source, and `Display 1` at `2560x1440` scale `1.25`.
- Host console QR visual QA screenshot captured: `output\playwright\host-console-qr-safety.png`.
- Host console address-copy visual QA screenshot captured: `output\playwright\host-console-copy-addresses.png`.
- Host console URL guidance visual QA screenshot captured: `output\playwright\host-console-url-guidance.png`.
- Host console security/risk visual QA screenshot captured: `output\playwright\host-console-security-risk.png`.
- Host console settings/PWA visual QA screenshot captured: `output\playwright\host-console-settings-pwa.png`.
- Live smoke validates manifest icons, service worker availability, phone-shell-only caching rules, query-string cache bypass rules, and settings update API.
- Live smoke validates adaptive stream state fields.
- Session tests validate trusted-device repeat approval behavior.
- Session tests validate trusted-device listing, redacted host metadata, per-device revoke, clear-all revoke, and affected session removal.
- Settings-store tests validate persistence and conservative sanitization.
- Settings-store tests validate trusted-device metadata persistence plus legacy trusted-key migration.
- Runtime settings check confirms public state exposes only `trustedDeviceCount`, while local settings file stores trusted-device keys.
- Phone adaptive diagnostics browser QA confirmed `adaptiveMode` and `presetFpsTarget` are present.
- Host trusted-session layout visual QA screenshot captured: `output\playwright\host-console-trusted-sessions.png`.
- Host trusted-device management visual QA screenshot captured: `output\playwright\host-console-trusted-device-management.png`.
- Phone monitor sheet visual QA screenshot captured: `output\playwright\phone-monitor-sheet.png`.
- Phone diagnostics visual QA screenshot captured: `output\playwright\phone-settings-diagnostics.png`.
- Phone connection-help visual QA screenshots captured:
  - `output\playwright\phone-connection-help-network.png`
  - `output\playwright\phone-connection-help-wrong-pin.png`
- Phone Precision mode visual QA screenshot captured: `output\playwright\phone-precision-halo.png`.
- Phone zoom viewport visual QA screenshot captured: `output\playwright\phone-zoom-viewport.png`.
- Phone edge-pan viewport visual QA screenshot captured: `output\playwright\phone-edge-pan-viewport.png`.
- Phone control preference visual QA screenshot captured: `output\playwright\phone-settings-control-preferences.png`.
- Visual artifacts:
  - `output\playwright\phone-controller-screen.png`
  - `output\playwright\phone-keyboard-sheet.png`
  - `output\playwright\phone-monitor-sheet.png`
  - `output\playwright\phone-settings-diagnostics.png`
  - `output\playwright\phone-connection-help-network.png`
  - `output\playwright\phone-connection-help-wrong-pin.png`
  - `output\playwright\phone-precision-halo.png`
  - `output\playwright\phone-zoom-viewport.png`
  - `output\playwright\phone-edge-pan-viewport.png`
  - `output\playwright\phone-settings-control-preferences.png`
  - `output\playwright\phone-adaptive-diagnostics.png`
  - `output\playwright\host-console-input-safety.png`
  - `output\playwright\host-console-qr-safety.png`
  - `output\playwright\host-console-copy-addresses.png`
  - `output\playwright\host-console-security-risk.png`
  - `output\playwright\host-console-settings-pwa.png`
  - `output\playwright\host-console-trusted-sessions.png`
  - `output\playwright\host-console-trusted-device-management.png`
  - `output\playwright\host-console-autostart-settings.png`
  - `output\playwright\host-console-connection-setup.png`

Remaining gates:

- Manual same-Wi-Fi phone acceptance.
- Manual Tailscale/different-Wi-Fi acceptance.
- Optional signed/native packaging beyond the current tray shell and non-elevated shortcut installer.
- Review or replace the real-input dependency if zero known audit advisories is required; current dependency audit has 0 high/critical advisories and 7 reviewed moderate advisories.

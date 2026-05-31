# 15-Page Build Manual Traceability Audit

Source of truth: `C:\RemoteDesktopControllerPlan\Free_Remote_Desktop_Controller_15_Page_Build_Plan.docx`

Audit date: 2026-05-23

This file maps every page of the build manual to the implementation, tests, evidence artifacts, and remaining proof gates. It is deliberately strict: automated browser and host tests can prove most of the product, but the manual says the build is not complete until same-Wi-Fi and Tailscale/different-Wi-Fi runs pass on a real phone.

## Current Completion Position

- Milestone 1 is verified: host shell, phone PWA, pairing/auth, WebSocket, fake stream, and dry-run input.
- Milestone 2 is verified: real selected-monitor capture, streaming, quality presets, and reconnect.
- Milestone 3 is verified by automated/local-desktop evidence: real input adapter, gestures, keyboard, safety release, and kill switch.
- Milestone 4 is functionally built and heavily tested, but remains open until physical phone acceptance passes for both same-Wi-Fi and Tailscale/different-Wi-Fi.
- The goal must stay active until the physical evidence bundles pass `npm run acceptance:verify -- -Gate same-wifi` and `npm run acceptance:verify -- -Gate tailscale`.

## Evidence Index

- Master status: `MILESTONE_STATUS.md`
- Run instructions and current limits: `README.md`
- Acceptance gates: `docs/ACCEPTANCE_TESTS.md`
- Tailscale path: `docs/TAILSCALE_VALIDATION.md`
- Packaging and daily-use notes: `docs/PACKAGING_NOTES.md`
- Automated QA: `npm run qa`, saved as `output\acceptance\qa-report-*.json` and `.md`, including an operator artifact snapshot for dashboard, handoff, physical proof launch, evidence bundle, refresh, firewall handoff, completion audit, and physical finalization artifacts.
- Physical same-Wi-Fi guided run: `npm run acceptance:phone -- -Gate same-wifi`, which now saves selected-gate verifier output after the run unless `-SkipVerifyAfter` is used.
- Physical Tailscale guided run: `npm run acceptance:phone -- -Gate tailscale`, which now saves selected-gate verifier output after the run unless `-SkipVerifyAfter` is used.
- Physical-run readiness doctor: `npm run acceptance:doctor -- -Gate same-wifi` and `npm run acceptance:doctor -- -Gate tailscale`
- Physical-run host prep/stop: `npm run acceptance:prepare -- -Gate same-wifi` and `npm run acceptance:stop -- -Gate same-wifi`; keep the host running between gates when another physical proof still needs the prepared host.
- Physical-run one-command readiness launcher: `npm run acceptance:ready -- -Gate same-wifi` and `npm run acceptance:ready -- -Gate tailscale`
- Physical-run operator next-actions checklist: `npm run acceptance:next`
- Physical-run scan-first handoff page: `npm run acceptance:handoff`
- Gate-aware phone proof links: prepared run-card and QR URLs open the phone app with `acceptance=1`, selected `gate`, and `step=physical-phone-proof`, and the phone proof payload defaults to that gate.
- Acceptance-mode phone UI now surfaces the proof gate directly in the controller through a persistent proof banner and a gate-aware proof checklist; Mark Proof remains disabled until every physical checklist item is ticked, the saved proof payload carries the checklist counts, and the physical verifier requires that checklist evidence before a gate can pass.
- Host-console Physical Proof Links expose the same gate-aware proof URLs with copy buttons and QR codes, separate from daily-use raw address links.
- Guided phone acceptance keeps those gate-aware proof URLs in notes/summary evidence and preflights the clean `/api/health` origin.
- Guided phone acceptance records pre-run blockers and supports `-RequireReady` so a Tailscale run without a Tailscale URL or CLI stops before manual step collection while still saving evidence.
- Physical-run session card evidence: `output\acceptance\phone-acceptance-session-*.md`, `.html`, and `.json`
- Physical-run ready status evidence: `output\acceptance\phone-acceptance-ready-*.json`
- Physical-run next-action evidence: `output\acceptance\phone-acceptance-next-*.md` and `.json`
- Physical-run handoff evidence: `output\acceptance\phone-acceptance-handoff-*.html`, `.md`, and `.json`
- Physical-run QR evidence: `output\acceptance\phone-acceptance-qr-*.svg`
- Physical-run readiness evidence: `output\acceptance\acceptance-doctor-*.md` and `.json`
- Host-console proof visibility: Latest Phone Proof panel renders the newest `acceptance.phoneMark` gate, origin, step, viewport, monitor, FPS, and phone checklist completion.
- Physical evidence verifier: `npm run acceptance:verify -- -Gate same-wifi`, `npm run acceptance:verify -- -Gate tailscale`, and saved verifier artifacts through `npm run acceptance:verify:save`
- Physical evidence watcher: `npm run acceptance:watch -- -Gate same-wifi` and `npm run acceptance:watch -- -Gate tailscale`; saved watcher snapshots are written as `output\acceptance\phone-acceptance-watch-*-latest.json`.
- Physical evidence finalizer: `npm run acceptance:finalize`, which verifies both physical gates with saved verifier output, writes the evidence bundle, saves the whole-manual completion audit, and does not run a new readiness refresh.
- Tailscale bootstrap assistant: `npm run tailscale:bootstrap` and `npm run tailscale:bootstrap:save`
- Tailscale setup checker: `npm run tailscale:check` and `npm run tailscale:check:save`
- Dependency audit evidence: `npm run dependency:audit:save`
- Evidence bundle manifest: `npm run evidence:bundle`, which saves current verifier JSON outputs for both gates before indexing artifacts, QA reports, physical proof launch records, firewall handoff records, physical finalization records, and blockers.
- Physical proof runbook: `npm run acceptance:runbook`, which saves a single JSON/Markdown operator artifact with the first command to run, current gate states, phone URLs, audit blockers, and the no-refresh finalizer warning.
- Physical proof launcher: `npm run acceptance:launch`, which opens the selected gate run card and runbook, copies the phone URL when available, falls back to the current Tailscale setup URL when login is blocking that gate, and explicitly does not mark physical evidence complete.
- Daily-use shortcut installer: `npm run shortcut:install`, with `npm run shortcut:selftest` to verify the target without changing the Desktop or Start Menu.
- Whole-manual completion audit: `npm run completion:audit` and saved final reports through `npm run completion:audit:save`; the latest audit currently tracks 197 requirements, including saved QA evidence, named QA self-test suite coverage, QA self-test script-path mapping, human-readable QA Markdown visibility, QA freshness after implementation/test/package/script changes, physical proof launcher behavior, physical proof launcher artifact indexing, physical proof runbook content, scan-first handoff Markdown warning visibility, firewall handoff behavior, operator warnings that prefer the non-mutating firewall handoff before elevated install, refresh-regenerated Tailscale setup-check evidence, setup-check guidance on next-action/runbook surfaces, dashboard/handoff pinning to the current QA report identity, evidence-bundle indexing of that timestamped QA identity, dependency audit evidence with no high/critical advisories plus evidence-bundle indexing of dependency-audit JSON/Markdown, evidence-bundle indexing of firewall handoff JSON/Markdown/script artifacts, verifier rejection of stale manual summaries when a newer gate readiness run exists, refresh final commands that avoid stale proof after successful verifier runs, readiness freshness before watcher verification, no-refresh finalizer commands on operator-facing physical completion surfaces, no-refresh physical finalization command coverage, evidence-bundle and QA snapshot indexing of physical finalization JSON/Markdown artifacts, evidence-bundle and QA snapshot indexing of physical proof runbook artifacts, evidence-bundle and QA snapshot indexing of physical proof launch JSON/Markdown artifacts, daily-use shortcut installer/script/package/docs coverage, readiness-artifact normalized status plus primary URL/blocker-count proof for both physical gates, next-action/dashboard/handoff preservation of readiness status and primary phone URL, saved watcher snapshot status/primary URL/blocker proof for both physical gates, phone-side proof checklist gating, payload evidence, verifier enforcement, host-console checklist visibility, Tailscale CLI discovery from common Windows install paths in the doctor and manual evidence report, concrete Tailscale login handoff or tailnet-IP setup evidence, optional phone screenshot/photo supporting-evidence validation, QA artifact snapshot evidence, extracted-manual source markers, finalization-plan source markers, active 10-page finalization traceability, all-page traceability markers, explicit non-skippable build-goal mapping, exact package-script plus self-test command target checks, package manifest cleanliness, live visual proof of the centered cursor lens, and stream wake recovery evidence.
- Firewall readiness and handoff: `npm run firewall:status`, `npm run firewall:handoff`, and elevated `npm run firewall:install` when the operator chooses to install the rule.
- Generated physical evidence folder: `output\acceptance`
- Visual QA screenshots folder: `output\playwright`

## Page 01 - Product Contract And Non-Negotiables

Status: mostly verified; blocked only by the manual's physical phone completion standard.

Implemented coverage:

- The build is a free personal Windows-first laptop host plus phone-browser PWA.
- Same-Wi-Fi is the baseline path, Tailscale is the free different-Wi-Fi path, and raw router port forwarding is not the normal plan.
- Host UI, phone UI, pairing, stream, monitor select, pointer, keyboard, drag, logs, kill switch, and Tailscale testing are tracked in `MILESTONE_STATUS.md` and `docs/ACCEPTANCE_TESTS.md`.
- Safe demo behavior exists through fake capture and dry-run input before real control is enabled.
- Real input is host-gated and can be disabled through the host console.
- Future scope such as public relay, file transfer, audio, cloud accounts, and unattended access is kept out of the MVP.

Evidence:

- `README.md` lists the current MVP boundary and excluded remaining work.
- `MILESTONE_STATUS.md` records Milestone 1 through Milestone 4 progress.
- `docs/ACCEPTANCE_TESTS.md` defines failure conditions that block weak prototypes.

Remaining proof:

- Run same-Wi-Fi physical phone acceptance and save passing `phone-acceptance-verification-same-wifi-*.json` verifier output.
- Run Tailscale/different-Wi-Fi physical phone acceptance and save passing `phone-acceptance-verification-tailscale-*.json` verifier output.

Page completion goals:

- Strict MVP boundary remains enforced.
- Every required feature is named and tracked.
- Security, latency, visual polish, and phone ergonomics remain product requirements, not optional cleanup.

## Page 02 - System Architecture

Status: verified by implementation and tests.

Implemented coverage:

- The host service serves HTTP, the static PWA, WebSocket control, health, host state, and logs.
- Capture, input, network, settings, sessions, protocol validation, coordinate mapping, and diagnostics are separated into modules.
- Phone state is controller-view state; host state remains authoritative.
- Protocol messages use version, sequence, timestamp, typed payloads, error envelopes, and acknowledgements for critical commands.
- Platform-specific behavior is behind adapters instead of being embedded in phone UI code.

Evidence:

- `src\server.js`
- `src\capture-adapter.js`
- `src\input-adapter.js`
- `src\network.js`
- `src\protocol.js`
- `src\sessions.js`
- `src\coordinate-mapper.js`
- `test\*.test.js`
- `npm run qa`
- `output\acceptance\qa-report-latest.json`

Remaining proof:

- None for architecture. Physical acceptance still indirectly confirms architecture under real phone conditions.

Page completion goals:

- Each subsystem has one job and a named interface.
- Stream implementation can be replaced later without rebuilding input or UI.
- Phone client remains lightweight and resilient.

## Page 03 - Free Remote Networking Plan

Status: implemented and automated; final completion needs physical Tailscale proof.

Implemented coverage:

- Host advertises loopback, LAN, and Tailscale IPv4/IPv6 addresses.
- Host console shows QR codes and copy buttons for advertised phone URLs.
- Inbound network guard allows loopback/private LAN/Tailscale by default and rejects public remote addresses unless public tunnel mode is explicit.
- Tailscale IPv4 `100.64.0.0/10` and Tailscale IPv6 `fd7a:115c:a1e0::/48` are detected and handled.
- IPv6 phone URLs are bracketed correctly.
- Optional public tunnel mode is labeled as higher risk.
- Windows Firewall helper can inspect, install, or remove the inbound TCP `4317` rule explicitly.
- Phone connection diagnostics explain host unreachable, wrong PIN, rate limit, expired session, and socket disconnect cases.

Evidence:

- `src\network.js`
- `scripts\firewall-rule.ps1`
- `docs\TAILSCALE_VALIDATION.md`
- `docs\ACCEPTANCE_TESTS.md`
- Network unit tests in `test\`
- Host console visual QA screenshots in `output\playwright`

Remaining proof:

- Confirm a same-Wi-Fi phone can open the LAN URL and pass guided acceptance.
- Confirm a phone off the laptop Wi-Fi path can open the Tailscale URL and pass guided acceptance.
- Current known state: no Tailscale `100.64.0.0/10` or `fd7a:115c:a1e0::/48` address has been detected in the automated checks on this machine.

Page completion goals:

- Different Wi-Fi has a real free path through Tailscale.
- Public URLs remain dangerous and temporary.
- User does not need router networking knowledge to connect.

## Page 04 - Host Capture And Streaming

Status: verified by implementation and automated tests.

Implemented coverage:

- Real screen capture mode uses the free `screenshot-desktop` dependency.
- Fake stream remains as the safe fallback.
- Host reports selected monitor metadata, capture source, frame size, capture time, stream stats, visible/hidden clients, dropped ticks, and adaptive mode.
- Phone renders image data frames and shows diagnostics.
- Quality presets alter stream cadence and target FPS.
- Hidden phone pages pause capture delivery.
- Reconnect preserves approved session state.

Evidence:

- `src\capture-adapter.js`
- `src\server.js`
- `public\app.js`
- `npm run qa`
- `output\acceptance\qa-report-latest.json`
- Visual screenshots: `output\playwright\phone-controller-screen.png`, `output\playwright\phone-adaptive-diagnostics.png`

Remaining proof:

- Real phone acceptance should verify perceived latency, readability, and hidden/resumed stream behavior outside browser emulation.

Page completion goals:

- Streaming works before advanced network features are relied on.
- Latency and freshness are measured and visible.
- Monitor-specific capture avoids coordinate confusion.

## Page 05 - Phone Control Model

Status: automated/browser verified; real phone touch acceptance pending.

Implemented coverage:

- Touchpad mode is the default relative cursor model.
- Direct-touch mode maps through monitor and zoom viewport coordinates.
- Tap, double click, right click, drag lock, cancel drag, two-finger scroll, precision mode, touch halo, zoom/pan, and edge-pan exist.
- Settings expose sensitivity, scroll speed, touch halo, haptics, zoom, and diagnostics.
- Pointer-move coalescing keeps cursor movement smooth while preserving critical command ordering.

Evidence:

- `public\app.js`
- `public\styles.css`
- Browser tests in `test\`
- Visual screenshots: `phone-precision-halo.png`, `phone-zoom-viewport.png`, `phone-edge-pan-viewport.png`, `phone-settings-control-preferences.png`

Remaining proof:

- Same-Wi-Fi physical run must prove thumb reach, touch timing, tiny target control, drag feel, scroll feel, and text caret placement on a real phone.
- Tailscale physical run must prove the control model remains usable across the free remote path.

Page completion goals:

- Default interaction is precise enough for desktop UI from a phone.
- Right click, drag, scroll, zoom, and direct touch are intentional.
- Controls are learnable through state and icons rather than walls of text.

## Page 06 - Input Injection Engine

Status: verified by automated/local-desktop evidence; physical real-input acceptance pending.

Implemented coverage:

- Protocol validation rejects malformed, stale, replayed, future-dated, wrong-version, server-only, and bad-payload client commands before handlers run.
- Dry-run input adapter records actions safely.
- Real input adapter handles cursor movement, button actions, wheel, keyboard shortcuts, text, and paste paths through `@nut-tree-fork/nut-js`.
- Held mouse buttons, modifiers, and keys are tracked and released on safety reset, disconnect, disable, and kill switch.
- Critical commands are acknowledged with sequence echoes.
- Input permission checks fail closed when session/auth/input mode is not valid.

Evidence:

- `src\input-adapter.js`
- `src\protocol.js`
- `src\server.js`
- `test\input-adapter.test.js`
- `test\protocol.test.js`
- Live smoke coverage through `npm run qa`
- Saved QA evidence in `output\acceptance\qa-report-latest.json`

Remaining proof:

- Same-Wi-Fi physical phone run must enable real input after dry-run inspection and verify movement, click, drag, wheel, keyboard, text compose, and emergency release.
- Tailscale physical run must repeat the critical control and stop checks from a different network path.
- Known risk: `npm run dependency:audit:save` currently reports moderate advisories through real-input dependency transitive packages and zero high/critical advisories; replace/review if a zero-advisory requirement is imposed.

Page completion goals:

- Phone intent is normalized before OS injection.
- Real input fails closed.
- Held input state cannot survive disconnects or kill switch.

## Page 07 - Monitor Selection And Coordinate Mapping

Status: verified by implementation and tests.

Implemented coverage:

- Host enumerates monitors in screen capture mode and fake monitors in safe demo mode.
- Host console and phone UI expose selected monitor state.
- Phone monitor picker shows layout-aware display arrangement, capture status, orientation, primary flag, scale factor, and resolution.
- Coordinate mapper covers side-by-side, stacked, portrait/rotated-style, different scale factors, negative bounds, clamping, malformed fallback, relative movement, and zoomed visible crop.
- Monitor selection receives protocol acknowledgement.

Evidence:

- `src\coordinate-mapper.js`
- `src\capture-adapter.js`
- `public\app.js`
- Coordinate mapper tests in `test\`
- Visual screenshot: `output\playwright\phone-monitor-sheet.png`

Remaining proof:

- Physical phone acceptance must confirm monitor switching feels obvious and direct-touch coordinates stay correct on the actual selected laptop display.

Page completion goals:

- Monitor select is visible, reliable, and coordinate-safe.
- Mixed monitor layouts do not break mapping.
- The selected display is unmistakable in the phone UI.

## Page 08 - Keyboard, Shortcuts, And Command Bar

Status: automated/browser verified; real phone typing acceptance pending.

Implemented coverage:

- Phone keyboard sheet includes command buttons for hidden desktop keys and common shortcuts.
- Keyboard drawer exposes modifiers, arrows, system keys, shortcuts, text compose, and custom command actions.
- Modifier latch state is tracked and released safely by the host input adapter.
- Text and paste commands are supported while exported logs record text length only, not raw typed/pasted content.
- Browser QA verifies the keyboard sheet fits a phone viewport, keeps Stop visible, and has no overflowing button labels.
- Protocol and input tests verify key/chord/text command ordering and safe release behavior.

Evidence:

- `public\app.js`
- `public\styles.css`
- `src\input-adapter.js`
- `src\protocol.js`
- `test\input-adapter.test.js`
- `test\protocol.test.js`
- Phone keyboard screenshot: `output\playwright\phone-keyboard-sheet.png`
- Saved QA evidence in `output\acceptance\qa-report-latest.json`

Remaining proof:

- Same-Wi-Fi physical acceptance must verify normal text entry, paste text, shortcut chords, modifier latch/release, arrows, Esc/Tab/Enter, and emergency stop while typing.
- Tailscale physical acceptance must repeat the critical keyboard, shortcut, and text compose checks from a different network path.

Page completion goals:

- Phone keyboard controls are faster than hunting through menus.
- Common desktop keys and shortcuts are one tap away.
- Modifier latch, text compose, and safety release are obvious and reliable.

## Page 09 - Security, Pairing, And Session Control

Status: verified by implementation and tests; final security proof includes physical gates.

Implemented coverage:

- Six-digit short-lived PIN pairing exists.
- Laptop approval is required before a first control session.
- Session tokens expire and are revoked by kill switch or trusted-device revocation.
- Wrong PIN attempts are rate limited and visible.
- Trusted devices require first manual approval and correct PIN before repeat auto-approval.
- Host API and logs require host key where appropriate.
- WebSocket origin is checked when present.
- No unauthenticated screen, monitor details, settings, sessions, or logs are exposed.
- HTTP API failures use recovery-ready error envelopes.
- Browser security headers include CSP, no-referrer, nosniff, and frame denial.
- JSON body size is limited to 64 KB.
- Public remotes are blocked unless public tunnel mode is explicitly configured.
- Host console renders phone-provided names, origins, logs, and trusted-device records as text.
- Raw typed/pasted text and screen frame contents are not stored in exported logs.
- Kill switch disables input, disconnects clients, revokes sessions, and releases held state.

Evidence:

- `src\sessions.js`
- `src\server.js`
- `src\settings-store.js`
- `public\host.js`
- `docs\ACCEPTANCE_TESTS.md`
- Session and settings tests in `test\`
- Security-related live smoke and unit tests through `npm run qa`
- Saved QA evidence in `output\acceptance\qa-report-latest.json`
- Host screenshots: `host-console-trusted-sessions.png`, `host-console-trusted-device-management.png`

Remaining proof:

- Physical acceptance must verify first approval, trusted repeat approval, revoke behavior, control cannot start before laptop approval, and Stop All Control works during a real session.

Page completion goals:

- The host starts locked and every phone session is authenticated.
- Laptop owner can approve, observe, revoke, and stop sessions instantly.
- Different-Wi-Fi access uses private networking or hardened temporary public tunnel only.

## Page 10 - Performance And Clean Optimization

Status: verified by instrumentation and tests; physical feel pending.

Implemented coverage:

- Stream diagnostics track frame counts, capture time, frame size, dropped ticks, connected client count, hidden clients, adaptive mode, and FPS target.
- Phone diagnostics show approximate FPS, target FPS, bandwidth estimate, latency, frame size, capture time, and input round trip.
- Adaptive cadence raises responsiveness after activity and lowers work when idle.
- Hidden clients pause stream delivery.
- Pointer movement is coalesced while click/key/drag ordering is preserved.
- Latest-frame behavior is favored over stale queue buildup.

Evidence:

- `src\server.js`
- `public\app.js`
- `test\live-smoke.js`
- Visual screenshot: `output\playwright\phone-adaptive-diagnostics.png`

Remaining proof:

- Same-Wi-Fi and Tailscale physical runs must record whether pointer movement feels fresh enough for daily admin tasks.
- If real-phone latency is poor, next optimization candidates are lower default resolution, WebRTC streaming, or dirty-region capture.

Page completion goals:

- Optimization is measured.
- Stale frames are not allowed to create delayed control.
- CPU and battery behavior quiet down during idle or hidden states.

## Page 11 - Visual Design System

Status: browser visually verified; physical phone visual acceptance pending.

Implemented coverage:

- Phone opens into the control surface, not a landing page.
- The stream is the main surface.
- Top status, bottom control rail, and slide-up sheets are implemented.
- Monitor, keyboard, settings, and diagnostics sheets exist.
- Controls use strong active, disabled, danger, and pressed states.
- Keyboard and settings screens have mobile viewport screenshots.
- Host console has QR, address copy, input safety, connection setup, security/risk, settings/PWA, sessions, and trusted-device screenshots.

Evidence:

- `public\index.html`
- `public\styles.css`
- Visual artifacts in `output\playwright`
- Browser viewport tests in `test\`

Remaining proof:

- Real phone acceptance must confirm no control overlap, clipped labels, unreachable Stop action, unreadable monitor state, or thumb-reach problem remains.

Page completion goals:

- Phone UI is a true control surface.
- Controls are polished, consistent, and thumb-friendly.
- Live desktop remains visible and unobstructed whenever possible.

## Page 12 - Testing, QA, And Safety Checks

Status: automated testing implemented; mandatory physical gates pending.

Implemented coverage:

- Unit tests cover protocol, mapping, input adapter state, sessions, settings, trusted devices, network classification, and safety behavior.
- Live smoke covers pairing, approval, WebSocket, frames, quality, reconnect, input commands, logs, Mark Proof, stream diagnostics, visibility, API redaction, headers, and payload limits.
- Browser tests cover mobile UI modes, settings, diagnostics, gesture commands, connection recovery, and visual fit.
- Acceptance report, guided phone runner, firewall helper, and evidence verifier all have self-tests.
- Physical evidence verifier rejects incomplete bundles.

Evidence:

- `npm run qa` currently saves `qa-report-latest.json` with 76 passing tests, 0 failures, 27 passing script self-tests, host mode `milestone-2-screen-capture`, and current operator artifact snapshot records including physical finalization artifacts.
- `npm run acceptance:selftest`
- `npm run acceptance:phone:selftest`
- `npm run acceptance:doctor:selftest`
- `npm run acceptance:prepare:selftest`
- `npm run acceptance:ready:selftest`
- `npm run acceptance:next:selftest`
- `npm run acceptance:dashboard:selftest`
- `npm run acceptance:refresh:selftest`
- `npm run acceptance:attach:selftest`
- `npm run acceptance:stop:selftest`
- `npm run acceptance:verify:selftest`
- `npm run acceptance:verify:save -- -Gate same-wifi` after the physical same-Wi-Fi run
- `npm run acceptance:verify:save -- -Gate tailscale` after the physical Tailscale run
- `npm run acceptance:watch:selftest`
- `npm run tailscale:bootstrap:selftest`
- `npm run tailscale:check:selftest`
- `npm run evidence:bundle:selftest`
- `npm run firewall:selftest`

Remaining proof:

- `npm run acceptance:phone -- -Gate same-wifi`
- `npm run acceptance:ready -- -Gate same-wifi`
- `npm run acceptance:next`
- `npm run acceptance:watch -- -Gate same-wifi`
- `npm run acceptance:verify -- -Gate same-wifi`
- `npm run acceptance:phone -- -Gate tailscale`
- `npm run acceptance:ready -- -Gate tailscale`
- `npm run acceptance:next`
- `npm run acceptance:watch -- -Gate tailscale`
- `npm run acceptance:verify -- -Gate tailscale`

Page completion goals:

- Testing covers safety, correctness, mobile layout, and real phone behavior.
- Dry-run mode exists for safe debugging.
- Acceptance criteria can block a bad build.

## Page 13 - Packaging, Install, And Daily Use

Status: developer/daily-use wrapper implemented; signed native packaging remains optional.

Implemented coverage:

- Host can run from source with screen capture.
- PowerShell tray launcher exists.
- User-logon Scheduled Task install/uninstall scripts exist.
- PWA manifest, icon, service worker, viewport rules, and installable shell exist.
- Settings persist locally.
- Trusted-device management and log export exist.
- Packaging notes document developer release behavior, known limits, firewall, acceptance evidence, and future signed packaging.

Evidence:

- `scripts\tray-host.ps1`
- `scripts\install-autostart.ps1`
- `scripts\uninstall-autostart.ps1`
- `public\manifest.webmanifest`
- `public\sw.js`
- `docs\PACKAGING_NOTES.md`
- `npm run autostart:selftest`

Remaining proof:

- Physical same-Wi-Fi acceptance should add the PWA to the phone home screen and confirm remembered host/session behavior.
- Optional future: package the tray shell as a signed native Windows app.

Page completion goals:

- Controller can be launched without remembering deep developer commands.
- Phone installation stays free through PWA behavior.
- Settings and logs are understandable for debugging.

## Page 14 - Build Execution Roadmap

Status: roadmap followed; final milestone remains open for physical proof.

Implemented coverage:

- Milestone 1 skeleton was completed and verified.
- Milestone 2 capture/stream was completed and verified.
- Milestone 3 input/gesture/safety was completed and verified by automated/local evidence.
- Milestone 4 polish/testing/Tailscale/packaging docs is implemented, with physical acceptance gates ready but not passed.
- Public tunnel and relay convenience stayed behind safety boundaries.

Evidence:

- `MILESTONE_STATUS.md`
- `README.md`
- `docs\ACCEPTANCE_TESTS.md`
- `docs\TAILSCALE_VALIDATION.md`
- `docs\PACKAGING_NOTES.md`
- `npm run qa`
- `output\acceptance\qa-report-latest.json`

Remaining proof:

- Do not call the MVP complete until same-Wi-Fi and Tailscale physical paths both pass.

Page completion goals:

- Every milestone produces runnable behavior.
- Risky network exposure is delayed until safety exists.
- Roadmap remains detailed enough to drive execution.

## Page 15 - Master Goal List For The Whole Build

Status: not complete by the manual's own definition until physical phone gates pass.

Implemented coverage:

- Host scaffold with served PWA, WebSocket, health, local/LAN/Tailscale address display, and local/private guard exists.
- Pairing PIN, session token, laptop approval, expiry, rate limits, trusted devices, host key, and kill switch exist.
- Monitor enumeration, selected-monitor capture, frame metadata, quality presets, and diagnostics exist.
- Pointer, click, right click, drag lock, wheel, keyboard shortcuts, text compose, modifier latch, and safety release exist.
- Full-screen phone stream, top status strip, bottom rail, monitor sheet, keyboard drawer, settings drawer, diagnostics, zoom, precision, and control preferences exist.
- Coordinate mapping tests cover the required monitor layouts and zoomed viewport path.
- Tailscale usage path is documented and implemented with IPv4/IPv6 support.
- Visual QA, performance logs, reconnect behavior, idle throttling, and emergency disconnect are covered by automated/browser tests.

Evidence:

- Code in `src\`, `public\`, and `scripts\`
- Tests in `test\`
- Docs in `docs\`
- Screenshots in `output\playwright`
- Acceptance tooling in `scripts\acceptance-report.ps1`, `scripts\manual-phone-acceptance.ps1`, `scripts\verify-phone-acceptance.ps1`, and `scripts\watch-phone-acceptance.ps1`
- One-command physical-run readiness tooling in `scripts\acceptance-ready.ps1`
- Operator next-action tooling in `scripts\acceptance-next.ps1`
- Scan-first operator handoff tooling in `scripts\acceptance-handoff.ps1`

Remaining proof:

- Same-Wi-Fi physical phone run must pass and be verified.
- Tailscale/different-Wi-Fi physical phone run must pass and be verified.
- Evidence must include readiness doctor artifacts, pre/post reports, host logs, selected-gate URL preflight, per-step notes, `acceptance.phoneMark`, completed phone-side proof checklist payload, firewall status, and saved verifier output.

Page completion goals:

- All page goals are merged into this actionable execution standard.
- Build completion requires functionality, security, networking, visuals, performance, and testing.
- Codex execution follows the manual in depth and does not mark the goal complete early.

## Non-Skippable Final Gate Checklist

- Same-Wi-Fi run: `npm run acceptance:phone -- -Gate same-wifi`
- Same-Wi-Fi ready wrapper: `npm run acceptance:ready -- -Gate same-wifi`
- Same-Wi-Fi next-action checklist: `npm run acceptance:next`
- Physical acceptance dashboard: `npm run acceptance:dashboard`
- Physical acceptance handoff page: `npm run acceptance:handoff`
- Physical acceptance refresh: `npm run acceptance:refresh -- -NoOpen`
- Optional phone screenshot/photo attachment: `npm run acceptance:attach -- -Gate same-wifi -EvidencePath <path>`
- Same-Wi-Fi watcher: `npm run acceptance:watch -- -Gate same-wifi`
- Same-Wi-Fi verifier: `npm run acceptance:verify -- -Gate same-wifi`
- Same-Wi-Fi saved verifier: `npm run acceptance:verify:save -- -Gate same-wifi`
- Tailscale run: `npm run acceptance:phone -- -Gate tailscale`
- Tailscale setup check: `npm run tailscale:check:save`
- Tailscale ready wrapper: `npm run acceptance:ready -- -Gate tailscale`
- Tailscale next-action checklist: `npm run acceptance:next`
- Tailscale watcher: `npm run acceptance:watch -- -Gate tailscale`
- Tailscale verifier: `npm run acceptance:verify -- -Gate tailscale`
- Tailscale saved verifier: `npm run acceptance:verify:save -- -Gate tailscale`
- No-refresh physical finalizer: `npm run acceptance:finalize`
- Evidence bundle: `npm run evidence:bundle` to save current verifier outputs and index the full artifact set
- QA report: `npm run qa` to save current automated/local test evidence before the final audit
- Whole-manual final audit: `npm run completion:audit:save`
- Each verifier must pass against real phone evidence, not self-test fixtures.
- The post-run host logs must contain `acceptance.phoneMark` from the physical phone.
- The proof URL origin must match the selected network gate.
- The per-step guided notes must show all required steps passed.
- The final status file must be updated only after both physical gates pass.

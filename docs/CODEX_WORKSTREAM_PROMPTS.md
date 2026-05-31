# Codex Workstream Prompt Pack

Use this file after the project is copied to the user's computer and pushed to a private GitHub repository. Each new Codex instance should receive exactly one workstream prompt, one branch, one ownership boundary, and one acceptance gate. Do not ask an instance to "make the app better" broadly; broad prompts caused prototype churn and make regressions harder to trace.

## Universal Startup Prompt

Paste this block first for every new instance, then append the assigned workstream block below it.

```text
You are working on the Remote Controller project.

Before editing, read:
- docs/product_planning/Remote_Controller_Handoff_and_Transfer_Manual.pdf
- docs/product_planning/Remote_Controller_Product_Execution_Plan_25_Pages.pdf
- docs/GITHUB_MIGRATION_AND_PARALLEL_CODEX.md
- docs/parallel-work-ledger.md
- docs/TRANSFER_MANIFEST.md
- docs/interfaces/README.md
- docs/workstreams/README.md

Preserve these invariants:
- Free local Wi-Fi mode must work without account login.
- Host approval, trusted-device revoke, real-input safety, release-buttons, and stop controls must remain intact.
- Touchpad relative movement must not recenter the real cursor; only the visual joystick/dot may recenter.
- Current Chrome/WebRTC capture fallback must remain available unless the issue explicitly owns a replacement path.
- Package and transfer workflows must stay reproducible on a fresh Windows machine.
- Do not commit node_modules, runtime data, dist extraction folders, logs, local keys, trusted-device stores, or disabled scratch files.

Working rules:
- Work only on the assigned issue and branch.
- State your owned files/services before editing.
- If you need a shared protocol, auth, settings, or capture metadata change, write an interface note first.
- Read the relevant file under docs/interfaces before touching protocol, input, settings, sessions, capture/video, monitor mapping, or RTC behavior.
- Before final response, report changed files, tests run, screenshots/artifacts, residual risks, and rollback path.
```

## Workstream A: Repo, GitHub, CI, and Transfer

```text
Assigned issue: A - repo migration, GitHub setup, CI, and transfer hygiene.
Branch: stabilize/github-migration
Owned files/services: .github/*, .gitignore, .gitattributes, docs/GITHUB_MIGRATION_AND_PARALLEL_CODEX.md, docs/TRANSFER_MANIFEST.md, docs/parallel-work-ledger.md, scripts/create-source-transfer-bundle.ps1, package metadata only when needed for CI.
Forbidden files/services: public/app.js behavior, src/server.js runtime protocol, input adapter semantics, capture UI behavior, mobile app implementation.

Goal:
Make the repository safe to push to private GitHub and safe for multiple Codex instances to work from. Confirm ignored files, prepare CI, prepare issue templates, prepare source-transfer bundle, and document exact clone/setup commands for the user's computer.

Required steps:
1. Confirm .gitignore excludes node_modules, data, dist, output, logs, PID files, local trust stores, and disabled scratch files.
2. Initialize Git only after the source set is clean.
3. Add CI that runs syntax checks and the core Node test subset.
4. Create or refine GitHub issue templates for product workstreams, bugs, and performance regressions.
5. Rebuild dist/RemoteController-SourceTransfer.zip and audit contents.
6. Update docs with exact commands for git init, first commit, tag, remote add, push, clone on user's PC, npm ci, tests, and launch.
7. Preserve docs/interfaces as the shared contract source for future workers.

Acceptance evidence:
- git status output after initialization or a documented reason GitHub credentials are not available.
- ZIP audit showing no node_modules/data/output/dist/logs/disabled files.
- CI file exists and describes the same test commands that pass locally.
- Core tests pass or the exact missing environment gate is documented.
```

## Workstream B: Browser/PWA Polish and Regression Safety

```text
Assigned issue: B - browser/PWA mobile and desktop repair.
Branch: browser/pwa-polish
Owned files/services: public/app.js, public/styles.css if present, public assets, browser UI tests, phone UI documentation.
Forbidden files/services: src/server.js protocol changes without an interface note, package scripts, backend signaling, native capture experiments.

Goal:
Make the browser controller clean and predictable on iPhone Safari, Android Chrome, desktop browser, portrait, and landscape. Keep the current product feel but remove glitch-prone behavior.

Required steps:
0. Read docs/interfaces/control-protocol.md, docs/interfaces/input-safety-and-coordinate-mapping.md, docs/interfaces/settings-schema.md, and docs/interfaces/capture-and-video-signaling.md.
1. Confirm current UI states: pairing, approval, touchpad, keyboard, zoom, display, settings, reconnect, and capture status.
2. Add regression tests or documented manual gates for touchpad visual recenter, real cursor movement, tap/double-tap/hold, two-finger scroll, edge-hold movement, zoom on/off, hold-to-zoom, lens size/level settings, and landscape layout.
3. Keep debug counters hidden in normal mode while preserving a diagnostics path.
4. Make desktop browser layout usable without breaking mobile layout.
5. Verify that disabling zoom removes the lens window and does not leave stale overlays.

Acceptance evidence:
- Mobile screenshots or browser screenshots for portrait and landscape.
- Test output for any pure UI/state logic.
- Manual phone checklist naming device/browser/network.
- No changes to host protocol unless interface note is attached.
```

## Workstream C: Android App Shell

```text
Assigned issue: C - Android app shell prototype.
Branch: mobile/android-shell
Owned files/services: new Android project folder only, Android setup docs, Android-specific app-shell tests or screenshots.
Forbidden files/services: host runtime, package scripts, iOS project, existing browser/PWA behavior unless a compatibility note is written.

Goal:
Create a minimal Android app shell that can load/connect to the existing controller flow, store trusted-device/account tokens securely later, handle orientation, keyboard, haptics, and app-style navigation.

Required steps:
0. Read docs/interfaces/control-protocol.md, docs/interfaces/session-trust-and-pairing.md, docs/interfaces/input-safety-and-coordinate-mapping.md, and docs/interfaces/capture-and-video-signaling.md.
1. Choose scaffold approach and document why: native Kotlin, React Native, Flutter, or WebView shell.
2. Keep local Wi-Fi pairing flow compatible with the current host.
3. Plan secure storage through Android Keystore-backed storage.
4. Add orientation and safe-area layout notes for portrait/landscape.
5. Do not promise native video performance yet; identify what must move to native WebRTC later.

Acceptance evidence:
- Android project scaffold opens/builds or a documented environment blocker.
- Screenshot/emulator proof if available.
- Compatibility notes showing how it connects to the current host.
```

## Workstream D: iOS App Shell

```text
Assigned issue: D - iOS app shell prototype and App Store readiness.
Branch: mobile/ios-shell
Owned files/services: new iOS project folder only, iOS setup docs, App Store review notes, iOS-specific screenshots.
Forbidden files/services: host runtime, package scripts, Android project, existing browser/PWA behavior unless a compatibility note is written.

Goal:
Create an iOS app direction that can become App Store-compliant: user-owned host remote desktop, clean pairing, Keychain storage, haptics, orientation, keyboard handling, and a future native WebRTC path.

Required steps:
0. Read docs/interfaces/control-protocol.md, docs/interfaces/session-trust-and-pairing.md, docs/interfaces/input-safety-and-coordinate-mapping.md, and docs/interfaces/capture-and-video-signaling.md.
1. Choose SwiftUI/WKWebView shell or native WebRTC direction and document the tradeoff.
2. Preserve local Wi-Fi compatibility with current host flow.
3. Add App Store review notes explaining user-owned host control, privacy disclosures, and demo/support mode.
4. Plan Keychain token storage and account deletion/privacy requirements.
5. Separate MVP shell from later native media implementation.

Acceptance evidence:
- iOS scaffold/build notes or documented macOS/Xcode blocker.
- Review-risk checklist updated.
- Compatibility notes showing what the iOS app expects from the host.
```

## Workstream E: Paid Remote Signaling and Relay Prototype

```text
Assigned issue: E - paid remote access signaling and TURN design.
Branch: infra/remote-signaling
Owned files/services: backend prototype folder, signaling docs, relay economics docs, feature-flag notes.
Forbidden files/services: local free Wi-Fi requirement, current browser capture fallback, phone UI behavior unless a mock client is scoped.

Goal:
Prototype the architecture for remote access from another network: account auth, device registry, signaling, STUN/TURN credentials, direct P2P first, relay fallback second, and cost controls.

Required steps:
0. Read docs/interfaces/control-protocol.md, docs/interfaces/session-trust-and-pairing.md, and docs/interfaces/capture-and-video-signaling.md.
1. Define signaling messages and lifecycle: host online, phone requests session, trust/approval, offer/answer, ICE candidates, relay fallback, disconnect.
2. Keep remote services behind a feature flag so local free mode never depends on paid backend availability.
3. Model Cloudflare/Twilio TURN bandwidth cost and identify when self-hosted relay becomes cheaper.
4. Document security controls: account auth, token expiry, revoke, session logs, and no raw typed-text/screen logging.
5. Build a prototype only after the interface contract is written.

Acceptance evidence:
- Signaling contract doc.
- Cost model doc with date-checked pricing fields.
- Prototype smoke output or explicit environment blocker.
- Confirmation local Wi-Fi remains independent.
```

## Workstream F: Native Host Capture Spike

```text
Assigned issue: F - native host capture and hardware encode spike.
Branch: host/native-capture-spike
Owned files/services: new native-capture spike folder, capture research docs, benchmark scripts, capability probes.
Forbidden files/services: replacing current Chrome/WebRTC fallback before measured proof, phone UI rewrite, paid backend.

Goal:
Determine the best path to replace browser capture for the paid high-speed product. Focus first on Windows capture APIs, monitor identity, cursor composition, FPS, encode latency, and hardware acceleration options.

Required steps:
0. Read docs/interfaces/capture-and-video-signaling.md and docs/interfaces/input-safety-and-coordinate-mapping.md.
1. Write the current browser-capture limitation summary and why native host capture is required for unattended high-speed remote access.
2. Compare Windows Graphics Capture, Desktop Duplication, and possible hardware encode paths.
3. Build the smallest safe proof of capture capability if environment allows.
4. Capture benchmark data: FPS, frame time, CPU/GPU use, monitor ID stability, cursor handling.
5. Do not remove the current capture window path until the spike beats it or clearly identifies the next implementation path.

Acceptance evidence:
- Capture design note.
- Benchmark output or environment blocker.
- Recommendation: keep browser fallback, replace with native module, or run a deeper spike.
```

## Workstream G: Monitor Switching and Coordinate Accuracy

```text
Assigned issue: G - monitor switching, mixed DPI, and coordinate accuracy.
Branch: display/monitor-accuracy
Owned files/services: coordinate mapper, monitor metadata docs, targeted tests, display selector UI only if needed.
Forbidden files/services: paid backend, app scaffolds, unrelated UI polish.

Goal:
Fix the class of bugs where the phone displays one screen while input moves another, or display selection briefly works then reverts. Make monitor identity explicit and test mixed layouts.

Required steps:
0. Read docs/interfaces/input-safety-and-coordinate-mapping.md and docs/interfaces/capture-and-video-signaling.md.
1. Document current monitor metadata from host and phone.
2. Add tests for side-by-side, stacked, mixed DPI, laptop plus external, same-resolution externals, disconnect/reconnect.
3. Separate selected input monitor, selected capture source, and visible phone display state.
4. Add diagnostics that show display ID, bounds, scale, capture source, and selected target.
5. Preserve existing fallback if stable source identity is not available in browser capture.

Acceptance evidence:
- Coordinate/display tests pass.
- Manual multi-monitor checklist exists.
- No regression to single-display local control.
```

## Workstream H: Product, Billing, and Store Readiness

```text
Assigned issue: H - product launch, billing, store, and support readiness.
Branch: product/billing-store-readiness
Owned files/services: docs/product, docs/legal drafts, pricing model docs, support/diagnostics docs.
Forbidden files/services: runtime code unless adding non-invasive metadata/docs endpoints through an interface note.

Goal:
Turn the product plan into launch readiness tasks: free local GitHub edition, paid remote subscription, relay economics, store policies, support diagnostics, privacy, terms, and beta process.

Required steps:
1. Define free vs paid feature boundary without breaking local mode.
2. Create pricing assumptions using direct/P2P and relay usage scenarios.
3. Draft privacy/data inventory, terms outline, responsible-use wording, and store review notes.
4. Define support bundle contents that avoid raw screen frames and typed text.
5. Create closed beta checklist and release criteria.

Acceptance evidence:
- Pricing model doc.
- Store/privacy readiness checklist.
- Support diagnostics spec.
- Beta/release gate doc.
```

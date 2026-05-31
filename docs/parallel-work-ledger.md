# Parallel Work Ledger

Use this file before launching extra Codex instances. Each instance gets one row, one branch, and one ownership boundary.

| Status | Instance | Branch | Plan chapter/page | Owned files/services | Forbidden files/services | Acceptance evidence | Notes |
|---|---|---|---|---|---|---|---|
| active | Worker 1 | `stabilize/github-migration` | Handoff + GitHub migration | `.github/*`, `.gitignore`, `.gitattributes`, repo/transfer/CI/package/acceptance scripts and docs, `packaging/local-wifi/*` | Runtime protocol, phone UI behavior, mobile/native/paid backend work | Source manifest, CI validation, package smoke, handoff audit output | Six-worker launch plan current release runway |
| planned | Worker 2 | `browser/pwa-polish` | Browser/PWA repair | `public/app.js`, `public/styles.css`, browser UI tests, phone UI manual evidence | `src/server.js` protocol changes without interface note, package scripts, backend/native/mobile work | Mobile/desktop screenshots and phone/browser tests | Consolidates original browser issues 03 and 04 |
| planned | Worker 3 | `capture/monitor-performance` | Capture, monitor accuracy, and performance | Capture/monitor docs, coordinate/display tests, monitor metadata and performance evidence | Paid backend, app scaffolds, unrelated UI polish | Capture/monitor logic tests, performance notes, physical multi-monitor checklist | Consolidates original display and native-capture lanes |
| planned | Worker 4 | `mobile/android-shell` | Android app plan | Android app scaffold/docs only | Host runtime, package scripts, iOS, paid backend | Android build/emulator/device proof or environment blocker | Consumes stable browser/host contracts |
| planned | Worker 5 | `mobile/ios-shell` | iOS app plan | iOS app scaffold/docs only | Host runtime, package scripts, Android, paid backend | iOS build/simulator/device proof or macOS/Xcode blocker | Consumes stable browser/host contracts |
| planned | Worker 6 | `infra/product-remote-readiness` | Paid remote, product, billing, store, support | Remote architecture docs/prototype, pricing/store/support docs, feature-flag notes | Free local Wi-Fi requirement, unflagged paid backend dependency, native/mobile implementation | Signaling/cost model, product readiness docs, local-mode independence proof | Consolidates original remote and product lanes |

Note: older planning docs describe eight Codex lanes. The active launch packet uses six workers by combining display with capture/performance and combining remote infrastructure with product readiness. The ownership boundaries above override the older eight-row split for this parallel run.

Rules:
- Update this ledger before editing.
- Do not share write ownership unless the PR explicitly coordinates it.
- Do not mark a row done unless the acceptance evidence is attached in the PR.
- If a worker discovers a shared-interface change is needed, create an interface note before editing both sides.
- Start each worker from `docs/CODEX_WORKSTREAM_PROMPTS.md`; do not invent a looser prompt in chat.
- Create GitHub issues from `docs/GITHUB_ISSUE_BREAKDOWN.md` and paste the issue URL into this ledger when available.

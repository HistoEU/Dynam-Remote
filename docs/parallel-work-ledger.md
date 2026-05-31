# Parallel Work Ledger

Use this file before launching extra Codex instances. Each instance gets one row, one branch, and one ownership boundary.

| Status | Instance | Branch | Plan chapter/page | Owned files/services | Forbidden files/services | Acceptance evidence | Notes |
|---|---|---|---|---|---|---|---|
| planned | Codex A | `stabilize/github-migration` | Handoff + GitHub migration | `.github/*`, `.gitignore`, `docs/*migration*`, transfer docs | Runtime protocol, phone UI behavior | Source manifest, templates, validation output | Current workstream |
| planned | Codex B | `browser/pwa-polish` | Browser/PWA repair | `public/app.js`, `public/styles.css`, browser UI tests | `src/server.js` protocol changes without RFC | Mobile/desktop screenshots and phone tests | Use Workstream B prompt |
| planned | Codex C | `mobile/android-shell` | Android app plan | Android app scaffold only | Host, package scripts, iOS | Android emulator/device proof | Start after repo migration |
| planned | Codex D | `mobile/ios-shell` | iOS app plan | iOS app scaffold only | Host, package scripts, Android | iPhone/simulator proof | Start after repo migration |
| planned | Codex E | `infra/remote-signaling` | Paid remote networking | Backend prototype docs/code | Free local Wi-Fi path | Direct vs TURN test notes | Feature flag required |
| planned | Codex F | `host/native-capture-spike` | Host capture/video pipeline | Native capture spike folder | Current Chrome capture fallback | Latency/FPS comparison | Do not replace current stream until proven |
| planned | Codex G | `display/monitor-accuracy` | Monitor switching + coordinate accuracy | Coordinate mapper, monitor metadata docs, display tests | Paid backend, app scaffolds, unrelated UI polish | Multi-monitor logic tests and manual checklist | Use Workstream G prompt |
| planned | Codex H | `product/billing-store-readiness` | Product, billing, store, support readiness | Product/legal/support docs | Runtime code unless interface note exists | Pricing model, store/privacy checklist, beta gates | Use Workstream H prompt |

Rules:
- Update this ledger before editing.
- Do not share write ownership unless the PR explicitly coordinates it.
- Do not mark a row done unless the acceptance evidence is attached in the PR.
- If a worker discovers a shared-interface change is needed, create an interface note before editing both sides.
- Start each worker from `docs/CODEX_WORKSTREAM_PROMPTS.md`; do not invent a looser prompt in chat.
- Create GitHub issues from `docs/GITHUB_ISSUE_BREAKDOWN.md` and paste the issue URL into this ledger when available.

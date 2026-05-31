# Orchestrator Command Center

This file is the live coordination point for the six-worker Dynam Remote push. It exists so the main orchestrator can review branches, merge safely, and keep launch claims tied to evidence.

## Repository Baseline

- Repository: `https://github.com/HistoEU/Dynam-Remote`
- Baseline commit: `d11ac38`
- Baseline tag: `v0.1-local-wifi-baseline-v76`
- Baseline status: pushed to `origin/main`
- Core baseline validation already run by orchestrator:
  - `npm ci`
  - `node --check src\server.js`
  - `node --check public\app.js`
  - `node --check public\host.js`
  - `node --check public\capture.js`
  - `node --test test\protocol.test.js test\settings-store.test.js test\session-store.test.js test\coordinate-mapper.test.js test\input-adapter.test.js test\rtc-room.test.js test\capture-adapter.test.js`
- Result: 35 core tests passed.

## Current GitHub Setup

- Labels: created.
- Milestones: created.
- Live issue creation: not complete from this shell. GitHub issue markdown files remain the source of truth under `docs/github_issues/`.
- GitHub connector status: read-only for this repository in this Codex session.
- Local Git push status: works through stored Git credentials.

## Worker Map

| Worker | Branch | Primary Scope | Prepped Prompt Source | Review Priority |
| --- | --- | --- | --- | --- |
| Worker 1 | `stabilize/github-migration` | Release, CI, packaging, setup, acceptance, repo hygiene | `docs/codex_workers/stabilize-github-migration.txt` | 1 |
| Worker 2 | `browser/pwa-polish` | Phone controller black-stage display, two-finger pan, deep zoom, PWA polish | `docs/codex_workers/browser-pwa-polish.txt` | 2 |
| Worker 3 | `capture/monitor-performance` | Capture, monitor accuracy, native capture spike, performance proof | `docs/codex_workers/display-monitor-accuracy.txt`; `docs/codex_workers/host-native-capture-spike.txt` | 3 |
| Worker 4 | `mobile/android-shell` | Android app shell and compatibility path | `docs/codex_workers/mobile-android-shell.txt` | 4 |
| Worker 5 | `mobile/ios-shell` | iOS app shell and App Store readiness path | `docs/codex_workers/mobile-ios-shell.txt` | 5 |
| Worker 6 | `infra/product-remote-readiness` | Paid remote architecture, relay economics, product/store/support readiness | `docs/codex_workers/infra-remote-signaling.txt`; `docs/codex_workers/product-billing-store-readiness.txt` | 6 |

## Worker Branch Rules

Each worker must:

- Work on only its assigned branch.
- Push its branch to origin when done.
- Report commit hash, changed files, tests run, artifacts, blockers, and risks.
- Avoid merging to `main`.
- Avoid broad rewrites outside owned scope.
- Update `docs/interfaces/` before changing shared protocol, settings, capture metadata, session trust, input mapping, or coordinate behavior.
- Preserve free local Wi-Fi without account login.
- Preserve host approval, Stop controls, revoke controls, trusted-device boundaries, and real-input safety.
- Avoid committing `node_modules`, `data`, generated `dist`, `output`, logs, PID files, host keys, trusted-device stores, local env files, or private proof artifacts.

## Orchestrator Review Order

1. Review Worker 1 first. Its CI/package/acceptance changes affect every later branch.
2. Review Worker 2 second. It changes the primary user surface.
3. Review Worker 3 third. Capture and monitor contracts can affect Worker 2 and future native apps.
4. Review Worker 4 fourth. Android should consume stable host/browser contracts.
5. Review Worker 5 fifth. iOS should consume stable host/browser contracts.
6. Review Worker 6 sixth. Paid remote/product readiness must remain feature-flagged away from free local mode.

## Standard Review Flow

For each worker branch:

1. Fetch latest refs:

```powershell
git fetch origin --prune
```

2. Inspect branch diff:

```powershell
git diff --stat origin/main...origin/<worker-branch>
git diff --name-only origin/main...origin/<worker-branch>
```

3. Confirm ownership:
   - Did the worker only touch owned files?
   - If not, did it update the relevant interface contract first?
   - Are runtime safety controls preserved?

4. Read the actual patch:

```powershell
git diff origin/main...origin/<worker-branch>
```

5. Run worker-specific validation from the worker final report.

6. Run protected baseline:

```powershell
npm ci
node --check src\server.js
node --check public\app.js
node --check public\host.js
node --check public\capture.js
node --test test\protocol.test.js test\settings-store.test.js test\session-store.test.js test\coordinate-mapper.test.js test\input-adapter.test.js test\rtc-room.test.js test\capture-adapter.test.js
```

7. If browser UI changed, start the host and run browser/manual checks.

```powershell
$env:HOST_KEY='dev-host-key'
npm start
```

8. If packaging changed, run package build and smoke where feasible:

```powershell
npm run package:local-wifi
npm run package:smoke
```

9. If remote/product pricing or policy changed, verify date-stamped primary sources before accepting claims.

10. Decide:
    - merge
    - request changes
    - split branch
    - reject as out of scope

## Non-Negotiable Acceptance Gates

Do not mark the full product launch-ready until there is evidence for:

- Same-Wi-Fi physical phone acceptance.
- Tailscale/different-Wi-Fi physical phone acceptance.
- Multi-monitor physical acceptance.
- Browser/PWA portrait and landscape checks.
- Android build or explicit environment blocker plus compatibility proof.
- iOS build or explicit environment blocker plus App Store posture.
- Paid remote architecture that does not break free local mode.
- Native capture/performance recommendation with measured evidence or a precise blocker.
- Package smoke for the distributable local Wi-Fi edition.
- Support/privacy bundle rules that avoid raw screen frames and typed text.

## Immediate Orchestrator Tasks

- Keep this command center current.
- Watch for worker branches appearing on origin.
- Worker 3 reviewed: `docs/coordination/reviews/worker-3-capture-monitor-performance.md`.
- Worker 5 reviewed: `docs/coordination/reviews/worker-5-ios-shell.md`.
- Worker 2 reviewed and patched: `docs/coordination/reviews/worker-2-browser-pwa-polish.md`.
- Worker 4 reviewed and patched: `docs/coordination/reviews/worker-4-android-shell.md`.
- Review Worker 1 as soon as it commits/pushes because its CI/package/acceptance changes affect every later merge.
- Watch for Worker 6 / `infra/product-remote-readiness`; no local worktree or remote branch was visible during the latest sweep.
- Keep a separate review note for each worker under `docs/coordination/reviews/`.
- Do not implement worker-owned features while workers are active unless a branch stalls and the user redirects ownership.

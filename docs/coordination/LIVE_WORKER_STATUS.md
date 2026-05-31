# Live Worker Status

Last updated by orchestrator: 2026-05-31.

This file tracks what the local machine currently shows. It is not a substitute for each worker's final branch report, but it helps the orchestrator avoid reviewing stale or misplaced work.

## Active Worktrees Seen Locally

| Worker | Expected Branch | Local Path | Current Local Status |
| --- | --- | --- | --- |
| Worker 1 | `stabilize/github-migration` | `C:\tmp\stabilize-github-migration` | Active changes in CI, packaging, setup/audit scripts, package smoke tests |
| Worker 2 | `browser/pwa-polish` | `C:\tmp\dynam-worker-2-browser-pwa-polish` | Active changes in `public/app.js` and `test/phone-connection-help.test.js` |
| Worker 3 | `capture/monitor-performance` | `C:\tmp\dynam-worker-3-capture-monitor-performance` | Active changes in capture, monitor, server, RTC, app/host/capture UI, tests, benchmark/spike folders |
| Worker 4 | `mobile/android-shell` | `C:\tmp\dynam-worker-4-android-shell` | Clean as of this check |
| Worker 5 | `mobile/ios-shell` | `C:\Users\Administrator\Documents\Remote desktop app\extracted\RemoteController-MoveToMyComputer\source\RemoteController-SourceTransfer` | Active untracked `clients/ios` work in the shared source folder |
| Worker 6 | `infra/product-remote-readiness` | not visible yet | No local worktree visible as of this check |
| Orchestrator | `codex/orchestrator-coordination` | `C:\tmp\dynam-orchestrator` | Owns coordination docs only |

## Immediate Coordination Notes

- Worker 5 appears to be using the original source folder rather than a `C:\tmp` worktree. Do not switch or clean that folder while Worker 5 is active.
- Worker 2 and Worker 3 both touch `public/app.js`. Review order matters. Worker 2 owns the display-stage/control surface; Worker 3 should avoid unrelated phone UI changes unless they are required for capture/monitor diagnostics.
- Worker 3 touches shared server and interface contracts. Its branch needs close review before merge.
- Worker 1 touches packaging and scripts that may affect every other branch's validation assumptions.
- Worker 6 may need a worktree if it has not started locally. Expected branch is `infra/product-remote-readiness`.

## Next Checks

Run periodically:

```powershell
git fetch origin --prune
git worktree list --porcelain
git -C C:\tmp\stabilize-github-migration status --short --branch
git -C C:\tmp\dynam-worker-2-browser-pwa-polish status --short --branch
git -C C:\tmp\dynam-worker-3-capture-monitor-performance status --short --branch
git -C C:\tmp\dynam-worker-4-android-shell status --short --branch
git -C "C:\Users\Administrator\Documents\Remote desktop app\extracted\RemoteController-MoveToMyComputer\source\RemoteController-SourceTransfer" status --short --branch
```

When a worker reports completion, fetch origin, inspect its branch, and create a review note under `docs/coordination/reviews/`.


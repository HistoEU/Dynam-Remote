# Multi-Codex Launch Kit

This file is for the Codex instance that creates the GitHub project and then needs to split the next work across several Codex sessions. The purpose is simple: make every worker start from the same baseline, on a separate branch, with one clear ownership boundary. Do not launch parallel workers from the same folder. Use Git worktrees or separate clones so each Codex can run commands, edit files, and test without overwriting another worker's state.

## Required Starting State

Before using this launch kit, the GitHub creator Codex must finish the baseline repo setup:

1. The private GitHub repository exists.
2. `main` has a clean baseline commit.
3. The baseline tag exists:

```text
v0.1-local-wifi-baseline-v76
```

4. The current source has been pushed to the private GitHub repository.
5. The issue files in `docs/github_issues/` have either been created as GitHub issues or are ready to be copied.
6. The worker contracts in `docs/interfaces/` and `docs/workstreams/` are tracked in Git.

If the repository has no commits yet, stop here and complete `docs/GITHUB_CREATOR_HANDOFF.md` first. Worktrees need a real commit to branch from.

## Why Worktrees

Use one Git worktree per Codex instance. A worktree is a separate folder connected to the same repository. Each folder can be opened by a different Codex instance and checked out to a different branch. This avoids the common failure mode where one Codex edits the browser app while another Codex is editing packaging or Android files in the same working tree.

Recommended local layout:

```text
C:\RemoteDesktopControllerPlan\remote-control-mvp
C:\RemoteDesktopControllerPlan\codex-worktrees\stabilize-github-migration
C:\RemoteDesktopControllerPlan\codex-worktrees\browser-pwa-polish
C:\RemoteDesktopControllerPlan\codex-worktrees\mobile-android-shell
C:\RemoteDesktopControllerPlan\codex-worktrees\mobile-ios-shell
C:\RemoteDesktopControllerPlan\codex-worktrees\infra-remote-signaling
C:\RemoteDesktopControllerPlan\codex-worktrees\host-native-capture-spike
C:\RemoteDesktopControllerPlan\codex-worktrees\display-monitor-accuracy
C:\RemoteDesktopControllerPlan\codex-worktrees\product-billing-store-readiness
```

Keep the original folder as the coordination folder. Use the worktree folders for implementation.

## Dry Run First

From the repo root:

```powershell
cd C:\RemoteDesktopControllerPlan\remote-control-mvp
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\create-codex-worktrees.ps1
```

That prints the branch plan and the exact `git worktree add` commands. It does not change files.

After checking the output:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\create-codex-worktrees.ps1 -Apply
```

Optional parameters:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\create-codex-worktrees.ps1 -BaseDir C:\RemoteDesktopControllerPlan\codex-worktrees -StartPoint main -Apply
```

Use `-StartPoint v0.1-local-wifi-baseline-v76` if you want every worker branched exactly from the tagged baseline instead of the current `main`.

## Branches and Worker Ownership

Use these workstreams exactly unless the user changes the plan:

| Branch | Folder | Worker brief | Primary issue |
| --- | --- | --- | --- |
| `stabilize/github-migration` | `stabilize-github-migration` | `docs/codex_workers/stabilize-github-migration.txt` | `docs/github_issues/01-baseline-repo-and-tag.md` and `02-ci-local-validation.md` |
| `browser/pwa-polish` | `browser-pwa-polish` | `docs/codex_workers/browser-pwa-polish.txt` | `docs/github_issues/03-browser-pwa-regression-lock.md` and `04-zoom-lens-settings.md` |
| `display/monitor-accuracy` | `display-monitor-accuracy` | `docs/codex_workers/display-monitor-accuracy.txt` | `docs/github_issues/05-monitor-coordinate-accuracy.md` |
| `mobile/android-shell` | `mobile-android-shell` | `docs/codex_workers/mobile-android-shell.txt` | `docs/github_issues/06-android-shell.md` |
| `mobile/ios-shell` | `mobile-ios-shell` | `docs/codex_workers/mobile-ios-shell.txt` | `docs/github_issues/07-ios-shell.md` |
| `infra/remote-signaling` | `infra-remote-signaling` | `docs/codex_workers/infra-remote-signaling.txt` | `docs/github_issues/08-remote-signaling-turn.md` |
| `host/native-capture-spike` | `host-native-capture-spike` | `docs/codex_workers/host-native-capture-spike.txt` | `docs/github_issues/09-native-capture-spike.md` |
| `product/billing-store-readiness` | `product-billing-store-readiness` | `docs/codex_workers/product-billing-store-readiness.txt` | `docs/github_issues/10-product-billing-store-support.md` |

## Prompt to Paste Into Each Worker

After creating a worktree, open that worktree folder in a new Codex instance and paste the worker's prompt from `CODEX_START_HERE.txt`. The worktree script copies that file from the matching source prompt under `docs/codex_workers/`.

If worktrees are not being used, paste the matching file from `docs/codex_workers/` manually.

Fallback generic prompt:

```text
You are working on the Remote Controller project in a dedicated Git worktree.

Before editing, read:
- docs/GOAL_STATUS_LEDGER.md
- docs/interfaces/README.md
- docs/workstreams/README.md
- docs/CODEX_WORKSTREAM_PROMPTS.md
- docs/parallel-work-ledger.md
- <YOUR_ASSIGNED_WORKSTREAM_BRIEF>
- <YOUR_ASSIGNED_GITHUB_ISSUE_FILE>

Your branch is: <BRANCH>.
Your owned scope is: <SCOPE>.

Preserve the free local Wi-Fi path. Do not make it require account login, paid backend services, or remote relay availability. Do not loosen host approval, stop controls, revoke controls, real-input safety, or trusted-device boundaries. If you must change a shared interface, update docs/interfaces first, explain the contract change, and keep compatibility where possible.

Implement only the assigned workstream. Run the validation checks that fit the change. Before final response, report changed files, tests run, manual checks, known risks, and exact next handoff step.
```

Replace:

- `<YOUR_ASSIGNED_WORKSTREAM_BRIEF>` with one file from `docs/workstreams/`.
- `<YOUR_ASSIGNED_GITHUB_ISSUE_FILE>` with one file from `docs/github_issues/`.
- `<BRANCH>` with the exact branch name.
- `<SCOPE>` with the branch ownership from the table above.

## Merge Order

Use this order to reduce conflict and regression risk:

1. `stabilize/github-migration`
2. `browser/pwa-polish`
3. `display/monitor-accuracy`
4. `host/native-capture-spike`
5. `infra/remote-signaling`
6. `mobile/android-shell`
7. `mobile/ios-shell`
8. `product/billing-store-readiness`

The browser branch should land before native apps rely on its behavior. Monitor mapping should land before mobile apps assume final coordinate behavior. Remote signaling should stay behind flags until local Wi-Fi is proven unaffected.

## Collision Rules

If two workers need the same file, pause one worker and update `docs/parallel-work-ledger.md` before continuing. The file most likely to collide is `public/app.js`; do not let browser polish, monitor mapping, and capture experiments all edit it independently without an explicit contract note.

Shared contracts live in:

```text
docs/interfaces/
```

Worker-specific plans live in:

```text
docs/workstreams/
```

When behavior changes, update the interface doc first, then code, then tests. The docs are not decoration here; they are how separate Codex sessions avoid guessing.

## Validation Expectations

Every worker should run the smallest meaningful checks before handoff. The common protected baseline is:

```powershell
node --check src\server.js
node --check public\app.js
node --check public\host.js
node --check public\capture.js
node --test test\protocol.test.js test\settings-store.test.js test\session-store.test.js test\coordinate-mapper.test.js test\input-adapter.test.js
```

If the worker changes package installation or CI:

```powershell
npm ci
```

If the worker changes browser behavior, it must include manual or browser evidence for the actual controller page. If the worker changes Android, iOS, paid relay, or native capture, it must say what was actually run and what remains theoretical.

## What the Other Codex Must Not Claim

The other Codex should not mark the full product complete after creating GitHub. At that point, it has only created the collaboration base. The still-open work includes native mobile apps, paid remote access, native capture, monitor switching finalization, store readiness, packaging polish, and physical-device acceptance across multiple computers.

The correct status after GitHub creation is:

```text
GitHub baseline is complete.
Parallel workstreams are ready.
Productization goal remains active.
```

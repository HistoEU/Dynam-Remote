# GitHub Creator Handoff

This is the first file the Codex instance creating the GitHub project should read. Its job is not to redesign the product. Its job is to move the current project into a clean private GitHub repository, preserve the verified planning packet, create the first issues, and prepare the repo so other Codex instances can work safely.

## Current Workspace

Source root:

```powershell
C:\RemoteDesktopControllerPlan\remote-control-mvp
```

Important transfer artifacts:

```powershell
dist\RemoteController-SourceTransfer.zip
dist\RemoteController-SourceTransfer.zip.sha256
dist\Remote_Controller_Product_Planning_Packet_DENSE_VERIFIED.zip
```

The source-transfer ZIP is the clean source package. It intentionally excludes:

- `node_modules/`
- `data/`
- `dist/`
- `output/`
- logs and PID files
- disabled incident-response scratch files
- local host keys, trusted-device data, or private proof artifacts

The dense planning packet contains the DOCX/PDF planning files and verified page previews. It is a reference/release artifact, not normal tracked source.

## Read These Before Doing Anything

Read these files in this order:

1. `docs/TRANSFER_MANIFEST.md`
2. `docs/GITHUB_MIGRATION_AND_PARALLEL_CODEX.md`
3. `docs/GITHUB_ISSUE_BREAKDOWN.md`
4. `docs/CODEX_WORKSTREAM_PROMPTS.md`
5. `docs/parallel-work-ledger.md`
6. `docs/FIRST_CODEX_GITHUB_PROMPT.txt`
7. `docs/USER_COMPUTER_SETUP.md`
8. `docs/CODEX_MULTI_INSTANCE_LAUNCH.md`
9. `docs/GITHUB_READY_CHECKLIST.md`
10. `docs/codex_workers/*.txt`
11. `docs/interfaces/README.md`
12. `docs/workstreams/README.md`
13. `docs/GOAL_STATUS_LEDGER.md`
14. `docs/github_issues/*.md`
15. `docs/product_planning/Remote_Controller_Handoff_and_Transfer_Manual.pdf`
16. `docs/product_planning/Remote_Controller_Product_Execution_Plan_25_Pages.pdf`

Do not infer the plan from chat history. The files above are the handoff source of truth.

## GitHub Repo Setup

Create a private GitHub repository first. Suggested name:

```text
remote-controller
```

Keep it private until security, packaging, pricing, and store-readiness work are cleaner.

If starting from the source-transfer ZIP on the user's computer:

```powershell
Expand-Archive -LiteralPath .\RemoteController-SourceTransfer.zip -DestinationPath .\remote-controller
cd .\remote-controller\RemoteController-SourceTransfer
```

If starting from the current workspace:

```powershell
cd C:\RemoteDesktopControllerPlan\remote-control-mvp
```

Then run:

```powershell
git init
git status --ignored
```

Confirm ignored output shows generated/private folders ignored, especially:

- `node_modules/`
- `data/`
- `dist/`
- `output/`
- `*.disabled`
- `*.disabled-by-incident-response`
- `*.log`
- `*.pid`

Before pushing, run the explicit readiness checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\list-github-handoff-assets.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\audit-source-transfer-bundle.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\audit-github-handoff.ps1
```

The full pre-push checklist is in `docs/GITHUB_READY_CHECKLIST.md`.

## First Commit Commands

Preferred safe path: preview the Git commands first.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\bootstrap-github-baseline.ps1
```

If the preview is correct, run it for real:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\bootstrap-github-baseline.ps1 -Apply
```

If the private repo URL is already known, the script can also add/push the remote:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\bootstrap-github-baseline.ps1 -RemoteUrl "<PRIVATE_GITHUB_REPO_URL>" -Apply
```

Manual path:

Stage only the intended source set:

```powershell
git add .gitignore .gitattributes .github docs packaging public scripts src test README.md MILESTONE_STATUS.md package.json package-lock.json
git status --short
```

Before committing, make sure no ignored/private files are staged:

```powershell
git diff --cached --name-only
```

Commit and tag:

```powershell
git commit -m "baseline: local wifi controller v76 planning handoff"
git tag v0.1-local-wifi-baseline-v76
```

Add the private remote and push:

```powershell
git remote add origin <PRIVATE_GITHUB_REPO_URL>
git branch -M main
git push -u origin main
git push origin v0.1-local-wifi-baseline-v76
```

## If Git Identity Is Missing

If Git refuses to commit because `user.name` or `user.email` is missing, set it locally for this repo:

```powershell
git config user.name "<USER_NAME>"
git config user.email "<USER_EMAIL>"
```

Do not invent the user's email. Ask if you do not know what identity to use.

## If `.git` Already Exists

This workspace may already have a partially initialized `.git` folder from an earlier attempt. If so:

```powershell
git status --ignored
git log --oneline --decorate -5
git tag --list
```

If there are no commits, proceed with the first commit commands above. Do not run destructive cleanup such as `git reset --hard` or deleting `.git` unless the user explicitly approves it.

## Validation Before Push

Run these checks before pushing if dependencies are available:

Preferred runbook path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-user-computer-setup.ps1
```

That command is a dry run. To run `npm ci`, syntax checks, and protected tests:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-user-computer-setup.ps1 -Apply
```

Manual path:

```powershell
node --check src\server.js
node --check public\app.js
node --check public\host.js
node --check public\capture.js
node --test test\protocol.test.js test\settings-store.test.js test\session-store.test.js test\coordinate-mapper.test.js test\input-adapter.test.js
```

If `npm ci` is needed on a fresh computer:

```powershell
npm ci
```

Do not claim physical-device coverage from these tests. Phone, browser capture, multi-monitor, Android, and iOS checks remain separate gates.

## GitHub Labels and Issues

After the baseline push, create labels from `docs/GITHUB_ISSUE_BREAKDOWN.md`.

Then create the first ten issues from `docs/github_issues/*.md`:

1. Initialize Private GitHub Repo and Baseline Tag
2. Make CI Match Local Validation
3. Browser/PWA Regression Lock
4. Zoom and Lens Settings Finalization
5. Monitor Switching and Coordinate Accuracy
6. Android App Shell Prototype
7. iOS App Shell Prototype
8. Remote Signaling and TURN Cost Model
9. Native Windows Capture Spike
10. Product, Pricing, Store, and Support Readiness

Each issue should include:

- labels
- milestone
- plan pages
- scope
- forbidden files/services
- acceptance evidence
- branch name
- assigned Codex prompt from `docs/CODEX_WORKSTREAM_PROMPTS.md`
- relevant interface contracts from `docs/interfaces/`
- relevant starter brief from `docs/workstreams/`
- current status/gap mapping from `docs/GOAL_STATUS_LEDGER.md`

Quick issue file list:

```powershell
Get-ChildItem docs\github_issues\*.md | Sort-Object Name | Select-Object Name
```

Preferred script path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\github-create-labels-milestones-issues.ps1 -Repo "<OWNER>/<REPO>"
```

That command is a dry run and prints the `gh` commands. After reviewing the output and confirming GitHub CLI is authenticated, apply it:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\github-create-labels-milestones-issues.ps1 -Repo "<OWNER>/<REPO>" -Apply
```

If the current folder already has `origin` set and `gh repo view` works, `-Repo` can be omitted when using `-Apply`.

The helper script creates:

- all labels from the issue breakdown
- all milestones from the issue breakdown
- ten issues from `docs/github_issues/*.md`

If any labels or milestones already exist, review the `gh` output and continue with the missing items only.

## Branches for Other Codex Instances

Use these branch names:

```text
stabilize/github-migration
browser/pwa-polish
mobile/android-shell
mobile/ios-shell
infra/remote-signaling
host/native-capture-spike
display/monitor-accuracy
product/billing-store-readiness
```

Preferred worktree launch path after the baseline commit/tag exists:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\create-codex-worktrees.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\create-codex-worktrees.ps1 -Apply
```

The first command is a dry run. The second command creates one folder per Codex worker. Full launch instructions are in `docs/CODEX_MULTI_INSTANCE_LAUNCH.md`.

When `-Apply` succeeds, each worktree receives a `CODEX_START_HERE.txt` file copied from the matching prompt in `docs/codex_workers/`.

Update `docs/parallel-work-ledger.md` with issue URLs after creating the GitHub issues.

## Release Artifacts

Do not commit release ZIPs into normal source. Attach these as GitHub Release assets or keep them outside Git:

```powershell
dist\OpenHostLink.zip
dist\Remote_Controller_Product_Planning_Packet_DENSE_VERIFIED.zip
dist\RemoteController-SourceTransfer.zip
dist\RemoteController-SourceTransfer.zip.sha256
```

Recommended GitHub release after push:

```text
v0.1-local-wifi-baseline-v76
```

Release notes should say:

- Current local Wi-Fi controller baseline.
- Includes verified dense planning packet.
- Includes clean source-transfer bundle.
- Browser/Chrome capture remains a fallback path, not final paid remote architecture.
- Multi-monitor switching remains a known future workstream.

## Hard Rules

- Do not make local Wi-Fi depend on an account.
- Do not remove the current Chrome/WebRTC fallback during repo migration.
- Do not commit logs, host keys, local trust stores, screenshots with private screen contents, or package extraction folders.
- Do not mark Android, iOS, paid remote access, native capture, or monitor switching as complete. They are planned workstreams.
- Do not loosen input safety, host approval, revoke, release-buttons, or stop controls.

## Final Report Format

When finished, report:

```text
GitHub repo URL:
Baseline commit hash:
Baseline tag:
Created labels:
Created issues:
Release assets attached:
Transfer ZIP audited:
Tests run:
Handoff audit:
Files changed:
Known remaining blockers:
Next Codex instance to launch:
```

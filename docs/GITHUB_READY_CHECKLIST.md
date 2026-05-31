# GitHub Ready Checklist

Use this checklist immediately before the other Codex creates or pushes the private GitHub repository. The point is to avoid a messy first commit, avoid leaking local runtime files, and make sure the next Codex workers can start from one clean baseline.

## 1. Confirm the Source Root

Expected source root:

```powershell
C:\RemoteDesktopControllerPlan\remote-control-mvp
```

If working from the source-transfer ZIP, the expected folder after extraction is:

```powershell
<extract-folder>\RemoteController-SourceTransfer
```

Required root files:

```text
.gitattributes
.gitignore
README.md
MILESTONE_STATUS.md
package.json
package-lock.json
```

Required source folders:

```text
.github/
docs/
packaging/
public/
scripts/
src/
test/
```

If any of these are missing, do not create the baseline commit yet.

## 2. Run the Asset List

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\list-github-handoff-assets.ps1
```

This should show the handoff files, issue files, planning PDFs, multi-Codex launch doc, and worktree script.

## 2A. Run the One-Command Handoff Audit

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\audit-github-handoff.ps1
```

Expected result:

```text
status: pass
failedCount: 0
```

This checks the required handoff files, ten issue files, seven workstream briefs, eight ready-to-paste Codex worker prompts, interface contracts, verified plan previews, per-page density audit, key PowerShell script syntax, and transfer ZIP cleanliness. It is read-only. Use `-RunTests` only when Node dependency/test execution is available:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\audit-github-handoff.ps1 -RunTests
```

## 3. Audit the Transfer ZIP

If using the transfer ZIP:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\audit-source-transfer-bundle.ps1
```

Expected result:

```text
forbiddenCount: 0
missingRequiredCount: 0
```

The audit must confirm that the ZIP contains:

```text
docs/CODEX_MULTI_INSTANCE_LAUNCH.md
docs/codex_workers/*.txt
scripts/create-codex-worktrees.ps1
docs/GITHUB_CREATOR_HANDOFF.md
docs/FIRST_CODEX_GITHUB_PROMPT.txt
docs/TRANSFER_MANIFEST.md
.github/workflows/ci.yml
```

The audit must also confirm that the ZIP does not contain:

```text
node_modules/
data/
dist/
output/
*.log
*.pid
*.disabled
*.disabled-by-incident-response
__pycache__/
*.pyc
local host keys
trusted-device stores
private proof artifacts
```

## 4. Verify Local Setup

Dry-run first:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-user-computer-setup.ps1
```

Then run the full check when dependencies and network are available:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-user-computer-setup.ps1 -Apply
```

Manual fallback:

```powershell
npm ci
node --check src\server.js
node --check public\app.js
node --check public\host.js
node --check public\capture.js
node --test test\protocol.test.js test\settings-store.test.js test\session-store.test.js test\coordinate-mapper.test.js test\input-adapter.test.js
```

These checks prove syntax and core protocol/input/session behavior. They do not prove iPhone/Android, Chrome capture, multi-monitor switching, paid remote access, or native capture.

## 5. Preview the Git Baseline

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\bootstrap-github-baseline.ps1
```

Review the printed commands. Confirm the first commit stages only:

```text
.github/
.gitattributes
.gitignore
docs/
packaging/
public/
scripts/
src/
test/
README.md
MILESTONE_STATUS.md
package.json
package-lock.json
```

Confirm it does not stage:

```text
node_modules/
data/
dist/
output/
logs
PID files
host keys
trusted-device stores
disabled scratch files
```

## 6. Create the Private GitHub Repo

Recommended repo name:

```text
remote-controller
```

Keep it private until security, packaging, pricing, and store-readiness work are clean.

Minimum repo settings:

```text
Visibility: Private
Default branch: main
Issues: Enabled
Actions: Enabled
Wiki: Off unless needed later
Discussions: Off unless needed later
```

Do not make the repo public until the security, licensing, and product-support workstreams approve it.

## 7. Apply the Baseline

If the remote URL is known:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\bootstrap-github-baseline.ps1 -RemoteUrl "<PRIVATE_GITHUB_REPO_URL>" -Apply
```

If the script cannot be used, run the manual commands in `docs/GITHUB_CREATOR_HANDOFF.md`.

Expected baseline tag:

```text
v0.1-local-wifi-baseline-v76
```

## 8. Create GitHub Issues

Preview:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\github-create-labels-milestones-issues.ps1 -Repo "<OWNER>/<REPO>"
```

Apply:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\github-create-labels-milestones-issues.ps1 -Repo "<OWNER>/<REPO>" -Apply
```

The script should create labels, milestones, and ten initial issues from `docs/github_issues/*.md`.

## 9. Prepare Parallel Codex Work

Preview:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\create-codex-worktrees.ps1
```

Apply only after the baseline commit exists:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\create-codex-worktrees.ps1 -Apply
```

Open each worktree in a separate Codex instance and paste the matching prompt from:

```text
docs/CODEX_MULTI_INSTANCE_LAUNCH.md
```

## 10. Required Final Report

The GitHub-creating Codex must report:

```text
GitHub repo URL:
Baseline commit hash:
Baseline tag:
Transfer ZIP audited:
Created labels:
Created milestones:
Created issues:
Release/reference assets preserved:
Tests/checks run:
Worktrees prepared:
Files changed:
Known blockers:
Next Codex worker to launch:
```

Correct status after this checklist:

```text
GitHub baseline is complete.
Parallel workstreams are ready.
The full productization goal is still active.
```

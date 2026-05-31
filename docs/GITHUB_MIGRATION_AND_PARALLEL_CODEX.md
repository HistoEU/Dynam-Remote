# GitHub Migration and Parallel Codex Setup

## Goal

Move the current remote controller project into a private GitHub repository, tag the working local Wi-Fi baseline, then let multiple Codex instances work on separate chapters without damaging the free local mode or each other's branches.

## Current Source Root

`C:\RemoteDesktopControllerPlan\remote-control-mvp`

The canonical source files are:
- `src/`
- `public/`
- `packaging/`
- `scripts/`
- `test/`
- `docs/`
- `README.md`
- `MILESTONE_STATUS.md`
- `package.json`
- `package-lock.json`
- `.gitignore`
- `.gitattributes`
- `.github/`

Do not commit:
- `node_modules/`
- `data/`
- `dist/`
- `output/`
- logs or PID files
- local host keys, trust stores, or proof artifacts
- `*.disabled` or `*.disabled-by-incident-response` scratch copies

## Migration Steps

1. Create a private GitHub repo.
2. From the source root, initialize Git only after reviewing `.gitignore`.
3. Run `git status --ignored` and confirm generated folders are ignored.
4. Add source and docs.
5. Commit as `baseline: local wifi controller v76 planning handoff`.
6. Tag as `v0.1-local-wifi-baseline-v76`.
7. Push `main`.
8. Create labels and milestones from `docs/GITHUB_ISSUE_BREAKDOWN.md`.
9. Create issues from `docs/GITHUB_ISSUE_BREAKDOWN.md`, using the 25-page plan as the detailed source of truth.
10. Assign each Codex instance one issue, one branch, and one ownership boundary from `docs/CODEX_WORKSTREAM_PROMPTS.md`.
11. Update `docs/parallel-work-ledger.md` before each worker starts.
12. Use `docs/CODEX_MULTI_INSTANCE_LAUNCH.md` and `scripts/create-codex-worktrees.ps1` to create one folder/branch per worker.
13. Use `docs/GITHUB_READY_CHECKLIST.md`, `scripts/audit-source-transfer-bundle.ps1`, and `scripts/audit-github-handoff.ps1` as the final pre-push/readiness gate.

## Suggested Commands

```powershell
cd C:\RemoteDesktopControllerPlan\remote-control-mvp
git init
git status --ignored
git add .gitignore .gitattributes .github docs packaging public scripts src test README.md MILESTONE_STATUS.md package.json package-lock.json
git commit -m "baseline: local wifi controller v76 planning handoff"
git tag v0.1-local-wifi-baseline-v76
git remote add origin <YOUR_PRIVATE_REPO_URL>
git push -u origin main
git push origin v0.1-local-wifi-baseline-v76
```

## Files to Hand to New Codex Instances

Give every instance these files or links after the repo exists:

- `docs/GITHUB_CREATOR_HANDOFF.md` for the first Codex instance creating the private GitHub repo.
- `docs/FIRST_CODEX_GITHUB_PROMPT.txt` as the exact opening prompt for that instance.
- `docs/CODEX_MULTI_INSTANCE_LAUNCH.md` for the branch/worktree launch commands and worker prompts.
- `docs/GITHUB_READY_CHECKLIST.md` for the final pre-push checklist.
- `docs/GOAL_STATUS_LEDGER.md` so the worker can tell proved work from prepared or missing work.
- `docs/CODEX_WORKSTREAM_PROMPTS.md`
- `docs/GITHUB_ISSUE_BREAKDOWN.md`
- `docs/github_issues/*.md` for copy-paste issue bodies.
- `docs/interfaces/README.md` for shared contract boundaries.
- `docs/workstreams/README.md` for focused worker starter briefs.
- `docs/parallel-work-ledger.md`
- `docs/TRANSFER_MANIFEST.md`
- `docs/product_planning/Remote_Controller_Handoff_and_Transfer_Manual.pdf`
- `docs/product_planning/Remote_Controller_Product_Execution_Plan_25_Pages.pdf`

The latest verified planning packet is:

`dist/Remote_Controller_Product_Planning_Packet_DENSE_VERIFIED.zip`

The latest clean source-transfer bundle is:

`dist/RemoteController-SourceTransfer.zip`

## Codex Instance Launch Prompt

Paste this into each new Codex instance after cloning:

```text
You are working on the Remote Controller project. Read these first:
- docs/product_planning/Remote_Controller_Handoff_and_Transfer_Manual.pdf
- docs/product_planning/Remote_Controller_Product_Execution_Plan_25_Pages.pdf
- docs/CODEX_WORKSTREAM_PROMPTS.md
- docs/GITHUB_ISSUE_BREAKDOWN.md
- docs/parallel-work-ledger.md

Your assigned issue is: <ISSUE>.
Your branch is: <BRANCH>.
Your owned files/services are: <OWNERSHIP>.
Do not edit outside your ownership boundary unless you first write an interface note and report the risk.

Preserve:
- free local Wi-Fi mode without account login
- host approval and real-input safety
- v76 touchpad relative movement behavior
- package reproducibility
- current Chrome/WebRTC fallback unless your issue explicitly replaces it

Before final response, report changed files, tests run, screenshots/artifacts, residual risks, and rollback path.
```

## Merge Discipline

Merge order:
1. Repository hygiene and CI.
2. Browser/PWA regression and polish.
3. Packaging/install cleanup.
4. Android/iOS shell prototypes.
5. Remote signaling/TURN prototype behind flags.
6. Native capture spike behind flags.

No paid remote/backend work may make local Wi-Fi depend on an account.

## Worktree Launch

After the baseline commit and tag are pushed, preview the worktree plan:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\create-codex-worktrees.ps1
```

Then create the folders:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\create-codex-worktrees.ps1 -Apply
```

Open each created folder in a separate Codex instance and paste the matching prompt from `docs/CODEX_MULTI_INSTANCE_LAUNCH.md`.

## What Is Still Not Done

- The private GitHub repository has not been created from this machine.
- No remote URL has been added.
- No baseline commit or tag exists in this folder yet.
- The project has not actually been copied to the user's computer.
- Android and iOS app folders have not been scaffolded.
- Paid remote signaling, relay provider setup, and native capture implementation are still future workstreams.

Do not mark the productization goal complete until those items are either completed or explicitly handed off with evidence.

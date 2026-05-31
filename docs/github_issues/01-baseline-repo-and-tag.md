# Issue 1: Initialize Private GitHub Repo and Baseline Tag

Labels: `workstream:repo`, `release-gate`

Milestone: `M0 - Baseline Transfer`

Branch: `stabilize/github-migration`

Plan pages: Page 2, Page 3, Page 4, Page 25.

## Purpose

Move the current Remote Controller source into a private GitHub repository without leaking runtime data, generated artifacts, logs, local trust stores, package extraction folders, or disabled scratch files. This issue is the foundation for every other Codex workstream.

## Scope

- Initialize Git in the clean source folder.
- Commit only source, docs, tests, packaging scripts, and GitHub scaffolding.
- Tag the working baseline as `v0.1-local-wifi-baseline-v76`.
- Push `main` and the tag to the private GitHub repository.
- Keep release ZIPs outside normal source control.

## Owned Files

- `.gitignore`
- `.gitattributes`
- `.github/*`
- `docs/GITHUB_CREATOR_HANDOFF.md`
- `docs/GITHUB_MIGRATION_AND_PARALLEL_CODEX.md`
- `docs/TRANSFER_MANIFEST.md`
- `docs/parallel-work-ledger.md`
- `scripts/create-source-transfer-bundle.ps1`

## Forbidden Changes

- Do not alter phone UI behavior.
- Do not alter host protocol or real-input behavior.
- Do not remove Chrome/WebRTC capture fallback.
- Do not commit `node_modules`, `data`, `dist`, `output`, logs, PID files, disabled files, host keys, or trusted-device stores.

## Required Interface Contracts

- `docs/interfaces/README.md`

## Implementation Steps

1. Read `docs/GITHUB_CREATOR_HANDOFF.md`.
2. Run `git status --ignored` and confirm excluded folders are ignored.
3. Stage only the intended source set:

```powershell
git add .gitignore .gitattributes .github docs packaging public scripts src test README.md MILESTONE_STATUS.md package.json package-lock.json
```

4. Check the staged file list:

```powershell
git diff --cached --name-only
```

5. Commit:

```powershell
git commit -m "baseline: local wifi controller v76 planning handoff"
```

6. Tag:

```powershell
git tag v0.1-local-wifi-baseline-v76
```

7. Push:

```powershell
git remote add origin <PRIVATE_GITHUB_REPO_URL>
git branch -M main
git push -u origin main
git push origin v0.1-local-wifi-baseline-v76
```

## Acceptance Evidence

- `git status --ignored` proves generated/private folders are ignored.
- `git log --oneline --decorate -1` shows the baseline commit.
- `git tag --list` shows `v0.1-local-wifi-baseline-v76`.
- `git remote -v` points to the private GitHub repository.
- Release artifacts are not part of normal tracked source.

# Issue 2: Make CI Match Local Validation

Labels: `workstream:repo`

Milestone: `M0 - Baseline Transfer`

Branch: `stabilize/github-migration`

Plan pages: Page 18, Page 23, Page 25.

## Purpose

Make GitHub Actions verify the same lightweight checks that pass locally, without pretending CI can cover phone hardware, browser capture prompts, multi-monitor behavior, or native app work.

## Scope

- Keep `.github/workflows/ci.yml` aligned with local validation.
- Run syntax checks for host and public scripts.
- Run the core Node test subset.
- Document physical-device gates separately.

## Owned Files

- `.github/workflows/ci.yml`
- `docs/GITHUB_MIGRATION_AND_PARALLEL_CODEX.md`
- `docs/TRANSFER_MANIFEST.md`

## Forbidden Changes

- Do not remove tests to make CI pass.
- Do not add phone/capture/multi-monitor claims to CI unless the workflow truly tests them.
- Do not change runtime behavior unless a test reveals a real baseline break.

## Required Interface Contracts

- `docs/interfaces/README.md`

## Required CI Commands

```powershell
node --check src\server.js
node --check public\app.js
node --check public\host.js
node --check public\capture.js
node --test test\protocol.test.js test\settings-store.test.js test\session-store.test.js test\coordinate-mapper.test.js test\input-adapter.test.js
```

## Acceptance Evidence

- CI workflow exists under `.github/workflows/ci.yml`.
- Workflow installs dependencies with `npm ci`.
- Workflow runs the syntax checks and core test subset.
- PR or local run output shows the same checks passing or names the exact environment blocker.

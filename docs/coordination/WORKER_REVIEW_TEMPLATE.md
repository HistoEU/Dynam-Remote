# Worker Review Template

Copy this template into `docs/coordination/reviews/worker-N-<branch>.md` for each completed worker branch.

## Review Target

- Worker:
- Branch:
- Local path or remote ref:
- Base reviewed against:
- Worker final commit:
- Review date:

## Worker Claim

Summarize what the worker says it completed.

## Changed Files

Paste:

```powershell
git diff --name-only origin/main...origin/<branch>
```

Group files by:

- Runtime
- UI
- Tests
- Docs
- Packaging
- Generated or suspicious artifacts

## Scope Check

- Owned scope followed:
- Forbidden scope touched:
- Interface note required:
- Interface note present:
- Shared safety behavior affected:

## Product Safety Check

Confirm:

- Free local Wi-Fi remains accountless:
- Host approval remains intact:
- Stop control remains intact:
- Revoke controls remain intact:
- Trusted-device boundaries remain intact:
- Real-input safety remains intact:
- No raw screen frames or typed text added to logs/support exports:
- No secrets or local state committed:

## Validation Run By Worker

Paste worker-reported commands and results.

## Validation Run By Orchestrator

Run and record relevant checks:

```powershell
npm ci
node --check src\server.js
node --check public\app.js
node --check public\host.js
node --check public\capture.js
node --test test\protocol.test.js test\settings-store.test.js test\session-store.test.js test\coordinate-mapper.test.js test\input-adapter.test.js test\rtc-room.test.js test\capture-adapter.test.js
```

Add worker-specific checks here.

## Manual / Browser / Device Evidence

- Screenshots:
- Browser checks:
- Physical phone checks:
- Android/iOS build or blocker:
- Performance benchmark or blocker:

## Findings

List issues in severity order:

- P0:
- P1:
- P2:
- P3:

## Merge Decision

Choose one:

- Merge approved
- Request changes
- Split branch
- Reject out of scope
- Hold for another worker branch

## Follow-Up

- Required before merge:
- Required after merge:
- Assigned owner:


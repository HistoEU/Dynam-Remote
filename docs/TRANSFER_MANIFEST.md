# Transfer Manifest

This manifest describes what to move to the user's computer before GitHub is fully active.

## Copy These

- `.github/`
- `.gitattributes`
- `.gitignore`
- `docs/`
- `packaging/`
- `public/`
- `scripts/`
- `src/`
- `test/`
- `README.md`
- `MILESTONE_STATUS.md`
- `package.json`
- `package-lock.json`

## Optional Release Artifacts

- `dist/OpenHostLink.zip`
- `dist/Remote_Controller_Product_Planning_Packet_DENSE_VERIFIED.zip`
- `dist/RemoteController-SourceTransfer.zip`
- `output/checkpoints/checkpoint-one-v67-current.zip`
- `output/checkpoints/checkpoint-two-v68-webrtc-current.zip`

Keep release artifacts separate from source control. They are useful for rollback and family testing, but they should be GitHub release assets, not normal tracked source.

## Verified Bundles Created on This Machine

Use these two bundles for transfer if GitHub is not ready yet:

| Bundle | Purpose | SHA256 |
|---|---|---|
| `dist/RemoteController-SourceTransfer.zip` | Clean source-only project transfer. Excludes `node_modules`, runtime data, generated dist contents, smoke output, logs, PID files, and disabled scratch files. | See `dist/RemoteController-SourceTransfer.zip.sha256`, generated after the ZIP is built. |
| `dist/Remote_Controller_Product_Planning_Packet_DENSE_VERIFIED.zip` | Dense verified planning packet containing DOCX, PDF, density audit, and preview PNGs. | `EFDE8EA8755681AF30297FF080917FF5B23ADCEDFDD1AE727A00A13EB33C97D2` |

If either bundle is rebuilt, update the hash before transferring it.

## Do Not Copy Into Git

- `node_modules/`
- `data/`
- `dist/OpenHostLink/`
- `dist/RemoteController-LocalWiFi/`
- `output/package-smoke*/`
- `output/acceptance/package-smoke*/`
- `server.pid`
- `server.out.log`
- `server.err.log`
- any local host key, trusted-device file, or private proof log

## Fresh Computer Verification

Read the full runbook first:

```text
docs/USER_COMPUTER_SETUP.md
```

After transfer:

```powershell
cd <new-project-folder>
npm ci
node --check src\server.js
node --check public\app.js
node --check public\host.js
node --check public\capture.js
node --test test\protocol.test.js test\rtc-room.test.js test\settings-store.test.js test\session-store.test.js test\coordinate-mapper.test.js test\input-adapter.test.js test\host-console.test.js test\phone-connection-help.test.js
$env:HOST_KEY='dev-host-key'
npm start
```

Then open:

`http://127.0.0.1:4317/host?key=dev-host-key`

## Acceptance

The transfer is accepted when:
- dependencies install or the packaged zip launches
- the host console opens
- the phone URL/QR appears
- tests pass or a missing physical-device gate is explicitly documented
- the new Codex instance can identify its issue, branch, owned files, and acceptance evidence

## First Codex Instance on User Computer

After cloning or unpacking, paste this into the first Codex instance on the user's computer:

```text
You are taking over the Remote Controller project on the user's computer. First read docs/FIRST_CODEX_GITHUB_PROMPT.txt, docs/GITHUB_CREATOR_HANDOFF.md, docs/TRANSFER_MANIFEST.md, docs/GITHUB_MIGRATION_AND_PARALLEL_CODEX.md, docs/CODEX_MULTI_INSTANCE_LAUNCH.md, docs/GITHUB_READY_CHECKLIST.md, docs/CODEX_WORKSTREAM_PROMPTS.md, docs/GITHUB_ISSUE_BREAKDOWN.md, docs/parallel-work-ledger.md, docs/GOAL_STATUS_LEDGER.md, and the two PDFs in docs/product_planning. Do not redesign the product yet. Create or verify the private GitHub repo, run the listed checks, create the baseline commit/tag, create the first issues, prepare the multi-Codex branch/worktree plan, and report the final repo URL, commit hash, tag, issue list, transfer ZIP audit, tests run, worktree plan, and remaining blockers.
```

Updated first-read list:

```text
docs/FIRST_CODEX_GITHUB_PROMPT.txt
docs/GITHUB_CREATOR_HANDOFF.md
docs/GOAL_STATUS_LEDGER.md
docs/TRANSFER_MANIFEST.md
docs/GITHUB_MIGRATION_AND_PARALLEL_CODEX.md
docs/CODEX_MULTI_INSTANCE_LAUNCH.md
docs/GITHUB_READY_CHECKLIST.md
docs/codex_workers/README.md
docs/CODEX_WORKSTREAM_PROMPTS.md
docs/GITHUB_ISSUE_BREAKDOWN.md
docs/parallel-work-ledger.md
docs/interfaces/README.md
docs/workstreams/README.md
```

Helpful scripts for that instance:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\list-github-handoff-assets.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\audit-source-transfer-bundle.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\audit-github-handoff.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-user-computer-setup.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\bootstrap-github-baseline.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\github-create-labels-milestones-issues.ps1 -Repo "<OWNER>/<REPO>"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\create-codex-worktrees.ps1
```

The verification, bootstrap, GitHub issue, and worktree commands are dry runs unless `-Apply` is added. The audit commands are read-only and should exit cleanly before transfer.

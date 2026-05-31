# User Computer Setup Runbook

Use this when moving the Remote Controller project from this workspace to the user's actual computer. This file is for the human/user-computer Codex. It is intentionally command-level and does not assume the reader remembers this chat.

## What to Move

Preferred source package:

```text
dist\RemoteController-SourceTransfer.zip
dist\RemoteController-SourceTransfer.zip.sha256
```

Optional reference package:

```text
dist\Remote_Controller_Product_Planning_Packet_DENSE_VERIFIED.zip
```

Optional current family-test local Wi-Fi package:

```text
dist\OpenHostLink.zip
```

Do not copy raw `node_modules`, runtime `data`, smoke output, logs, PID files, or disabled scratch files into GitHub.

## Fresh Windows Computer Prerequisites

Install or confirm:

- Windows 10/11
- Node.js 20 or newer
- Git
- GitHub CLI (`gh`) if the same machine will create labels/issues/releases
- Chrome or Edge for browser capture fallback
- Same Wi-Fi or Tailscale/local network path for phone tests

Useful checks:

```powershell
node --version
npm --version
git --version
gh --version
```

If `gh` is not installed, GitHub labels/issues can be created manually from `docs/github_issues/*.md`.

## Unpack Source Bundle

Example:

```powershell
mkdir C:\RemoteController
Copy-Item .\RemoteController-SourceTransfer.zip C:\RemoteController\
Copy-Item .\RemoteController-SourceTransfer.zip.sha256 C:\RemoteController\
cd C:\RemoteController
Get-FileHash -Algorithm SHA256 .\RemoteController-SourceTransfer.zip
Get-Content .\RemoteController-SourceTransfer.zip.sha256
Expand-Archive -LiteralPath .\RemoteController-SourceTransfer.zip -DestinationPath .\source -Force
cd .\source\RemoteController-SourceTransfer
```

If the hash from `Get-FileHash` does not match the `.sha256` file, stop and re-copy the bundle.

## First Verification

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-user-computer-setup.ps1
```

That command is safe and does not install dependencies. It checks for required files and tool availability.

If prerequisites are installed and you are ready to actually run `npm ci` and tests:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-user-computer-setup.ps1 -Apply
```

The script writes a timestamped report under:

```text
output\user-computer-setup\
```

## Manual Verification Commands

If running manually:

```powershell
npm ci
node --check src\server.js
node --check public\app.js
node --check public\host.js
node --check public\capture.js
node --test test\protocol.test.js test\settings-store.test.js test\session-store.test.js test\coordinate-mapper.test.js test\input-adapter.test.js
```

Then start:

```powershell
$env:HOST_KEY='dev-host-key'
npm start
```

Open:

```text
http://127.0.0.1:4317/host?key=dev-host-key
```

## GitHub Setup on User Computer

Read first:

```text
docs/FIRST_CODEX_GITHUB_PROMPT.txt
docs/GITHUB_CREATOR_HANDOFF.md
docs/GOAL_STATUS_LEDGER.md
```

Preview baseline Git commands:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\bootstrap-github-baseline.ps1
```

Apply after reviewing:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\bootstrap-github-baseline.ps1 -RemoteUrl "<PRIVATE_GITHUB_REPO_URL>" -Apply
```

Preview labels/milestones/issues:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\github-create-labels-milestones-issues.ps1 -Repo "<OWNER>/<REPO>"
```

Apply after reviewing:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\github-create-labels-milestones-issues.ps1 -Repo "<OWNER>/<REPO>" -Apply
```

## Acceptance Criteria

The move is accepted when:

- source bundle hash matches
- source folder unpacks cleanly
- `node`, `npm`, and `git` are available
- `npm ci` succeeds
- syntax checks pass
- protected tests pass
- host starts
- host console opens at local URL
- phone URL/QR appears
- GitHub repo exists or the blocker is documented
- first Codex worker can identify issue, branch, owned files, contracts, and acceptance evidence

## Known Not-Complete Items

Do not mark the whole product complete after this setup. These are still future work:

- Android app implementation
- iOS app implementation
- browser/PWA physical-device polish
- multi-monitor physical validation
- paid remote backend/signaling/relay
- native capture/high-speed video path
- store/legal/billing/support readiness


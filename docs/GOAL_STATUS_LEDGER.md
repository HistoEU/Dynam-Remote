# Goal Status Ledger

This ledger maps the user's full productization goal to current evidence, remaining gaps, and owning workstreams. It prevents future Codex instances from mistaking planning artifacts for completed product work.

## Status Key

- `proved`: current files or command output prove the requirement is done.
- `prepared`: the handoff, plan, issue, or script exists, but the product work itself is not complete.
- `missing`: no implementation/evidence yet.
- `external`: requires the user's computer, GitHub credentials, app-store tooling, accounts, or physical devices.

## Current Evidence Snapshot

| Area | Status | Evidence | Notes |
|---|---|---|---|
| Dense 25-page execution plan | proved | `docs/product_planning/Remote_Controller_Product_Execution_Plan_25_Pages.pdf`; `preview_density_audit.txt`; verified preview folders | Current audit shows 25 rendered plan previews with per-page non-background density readings. |
| Handoff and transfer manual | proved | `docs/product_planning/Remote_Controller_Handoff_and_Transfer_Manual.pdf`; `docs/TRANSFER_MANIFEST.md` | Manual exists and transfer manifest gives command-level steps. |
| Clean source-transfer ZIP | proved | `dist/RemoteController-SourceTransfer.zip`; `dist/RemoteController-SourceTransfer.zip.sha256`; `scripts/audit-source-transfer-bundle.ps1` | Current bundle audit excludes `node_modules`, `data`, `output`, `dist`, logs, PID files, and disabled scratch files, and confirms required handoff files. |
| GitHub creator handoff | proved | `docs/GITHUB_CREATOR_HANDOFF.md`; `docs/FIRST_CODEX_GITHUB_PROMPT.txt`; `docs/GITHUB_READY_CHECKLIST.md` | Other Codex has exact setup, readiness checks, and final report instructions. |
| Copy-paste GitHub issues | proved | `docs/github_issues/*.md` | Ten issue files exist for the first product workstreams. |
| Parallel Codex prompts | proved | `docs/CODEX_WORKSTREAM_PROMPTS.md`; `docs/CODEX_MULTI_INSTANCE_LAUNCH.md`; `docs/codex_workers/*.txt`; `docs/parallel-work-ledger.md` | Branches, ownership, forbidden files, worktree launch commands, ready-to-paste worker prompts, and acceptance evidence are defined. |
| Interface contracts | proved | `docs/interfaces/*.md` | Shared protocol/input/session/settings/capture contracts exist and are linked from issues. |
| Workstream starter briefs | proved | `docs/workstreams/*.md` | Browser, Android, iOS, remote networking, native capture, display, and product briefs exist. |
| GitHub automation helpers | prepared | `scripts/bootstrap-github-baseline.ps1`; `scripts/github-create-labels-milestones-issues.ps1`; `scripts/create-codex-worktrees.ps1`; `scripts/audit-source-transfer-bundle.ps1`; `scripts/audit-github-handoff.ps1` | Dry-run by default where mutating; actual GitHub application requires the other Codex/user machine. Worktree creation requires a baseline commit/tag first. |
| GitHub Actions CI | prepared | `.github/workflows/ci.yml` | Will run once pushed to GitHub. Local syntax checks passed. |
| Current code validation | proved | Latest local command output: syntax checks passed; protected tests `27/27` passed | This proves the core source state, not physical-device behavior. |

## Requirement-by-Requirement Ledger

| Requirement | Status | Evidence | Owner / Next Action |
|---|---|---|---|
| Make an Android app | prepared | `docs/workstreams/android-app-shell.md`; `docs/github_issues/06-android-shell.md`; 25-page plan Page 9 | Workstream C: `mobile/android-shell`. Actual Android scaffold still missing. |
| Make an iOS app | prepared | `docs/workstreams/ios-app-shell.md`; `docs/github_issues/07-ios-shell.md`; 25-page plan Page 10 | Workstream D: `mobile/ios-shell`. Actual iOS scaffold still missing and likely needs macOS/Xcode. |
| Fix browser version on mobile | prepared | `docs/workstreams/browser-pwa-stabilization.md`; issues 03 and 04; interface contracts | Workstream B. Needs real iPhone/Android evidence after changes. |
| Fix browser version on desktop | prepared | same browser/PWA workstream docs | Workstream B. Needs desktop browser screenshots/tests after repo baseline. |
| Leave desktop app for later | proved as planning decision | 25-page plan Page 24; workstream docs omit desktop-app implementation | Do not start desktop app until later milestone. |
| Free GitHub local Wi-Fi edition | prepared | transfer bundle, packaging docs, GitHub creator handoff, issue 01 | GitHub Codex must create private repo, baseline tag, then later public/free release decision. |
| Paid remote subscription plan | prepared | 25-page plan Pages 5, 7, 14, 15; `remote-networking-and-relay.md`; issue 08 | Workstream E. No backend/subscription implemented yet. |
| Very fast remote speeds | prepared | native capture and remote networking briefs; capture/video interface contract | Workstreams E and F. Needs native capture/encode and relay/P2P evidence. |
| Move project to user's computer | prepared | `dist/RemoteController-SourceTransfer.zip`; `docs/TRANSFER_MANIFEST.md` | External: user/other Codex must move/unpack/verify on target machine. |
| Move project to GitHub | prepared | `GITHUB_CREATOR_HANDOFF.md`; scripts; issue 01 | External: GitHub repo/credentials needed. No remote URL is currently configured here. |
| Multiple Codex instances can work safely | prepared | prompt pack, issues, ledger, interface contracts, workstream briefs, `docs/codex_workers/*.txt`, `docs/CODEX_MULTI_INSTANCE_LAUNCH.md`, `scripts/create-codex-worktrees.ps1` | Needs GitHub baseline commit/tag, then worktrees/branches created by GitHub Codex. |
| 25-page detailed plan filled with details | proved | PDF/DOCX plus verified previews and density audit | Existing planning deliverable complete. |
| Verify pages with screenshots/previews | proved | `page_previews_plan_verified`, `page_previews_handoff_verified`, `preview_density_audit.txt` | Direct DOCX render via LibreOffice was unavailable earlier; generated previews are from structured source content. |
| Research on speed/other software/pricing/policy | prepared | source appendix in handoff manual and 25-page plan; sources listed | Must be rechecked before final launch because pricing/platform rules can change. |
| Android/iOS/store/legal readiness | prepared | iOS/Android/product workstream briefs; issues 06, 07, 10 | Actual app submissions/legal review missing. |
| Publish and start making money | missing | Product/billing/store brief and issue 10 only | Requires implementation, beta, store/release, billing, and support work. |

## Current Bundle Status

Latest source bundle:

```text
dist/RemoteController-SourceTransfer.zip
```

Latest source bundle hash:

```text
See dist/RemoteController-SourceTransfer.zip.sha256.
```

The sidecar file is the authority because embedding the ZIP hash inside a file that is itself included in the ZIP would change the ZIP hash on every rebuild.

Latest dense planning packet:

```text
dist/Remote_Controller_Product_Planning_Packet_DENSE_VERIFIED.zip
```

Planning packet hash:

```text
EFDE8EA8755681AF30297FF080917FF5B23ADCEDFDD1AE727A00A13EB33C97D2
```

## Remaining External Actions

The following cannot be honestly marked complete from this workspace alone:

1. Create the private GitHub repository.
2. Push the baseline commit and tag.
3. Create GitHub labels, milestones, and issues in the real repo.
4. Move/unpack the project on the user's computer.
5. Verify `npm ci`, tests, and host launch on the user's computer.
6. Launch additional Codex instances on separate branches/issues.
7. Scaffold Android and iOS apps.
8. Build paid remote signaling/relay/backend.
9. Build native capture/video performance path.
10. Fix/verify browser/PWA with real physical phones and desktop browser.
11. Run multi-monitor physical acceptance.
12. Prepare billing/store/legal/support and closed beta.

## Next Best Action

Give the other Codex this prompt:

```text
Read docs/FIRST_CODEX_GITHUB_PROMPT.txt first, then follow docs/GITHUB_CREATOR_HANDOFF.md and docs/CODEX_MULTI_INSTANCE_LAUNCH.md. Your first job is to create or verify the private GitHub repo, push the baseline, create labels/milestones/issues from docs/github_issues, prepare one worktree/branch per future Codex worker after the baseline commit exists, and report the repo URL, baseline commit hash, tag, created issues, tests run, worktree plan, and blockers. Do not redesign the product yet.
```

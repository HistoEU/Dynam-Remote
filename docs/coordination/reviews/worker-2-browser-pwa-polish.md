# Worker 2 Review - Browser PWA Polish

## Review Target

- Worker: Worker 2
- Branch: `browser/pwa-polish`
- Local path: `C:\tmp\dynam-worker-2-browser-pwa-polish`
- Base reviewed against: `origin/main`
- Worker commit reviewed: `493b2a3` (`Polish phone black-stage display`)
- Orchestrator follow-up commit: `d9dca12` (`Fix PWA reload guard for v77 shell`)
- Review date: 2026-05-31

## Worker Claim

Implements the black display stage requested by the user: deep zoom up to 5x, two-finger free pan that can push the remote screen partly off the phone viewport into black background, transformed direct-touch mapping, RTC video viewport alignment, and regression tests for stage pan, focal zoom, and existing touchpad/zoom behavior.

## Changed Files

Runtime/UI:

- `public/app.js`
- `public/index.html`
- `public/styles.css`
- `public/sw.js`

Tests:

- `test/host-console.test.js`
- `test/phone-connection-help.test.js`

Docs:

- `docs/ACCEPTANCE_TESTS.md`
- `docs/interfaces/input-safety-and-coordinate-mapping.md`
- `docs/workstreams/browser-pwa-stabilization.md`

Generated or suspicious artifacts: none committed.

## Scope Check

- Owned scope followed: yes.
- Forbidden scope touched: no backend protocol, native app, paid relay, or account requirement changes.
- Interface note required: yes, display-stage coordinate mapping changed.
- Interface note present: yes, `docs/interfaces/input-safety-and-coordinate-mapping.md` now documents local stage transforms and protected no-host-input behavior.
- Shared safety behavior affected: no weakening observed. Two-finger stage gestures remain local and tested not to emit host pointer moves.

## Product Safety Check

- Free local Wi-Fi remains accountless: yes.
- Host approval remains intact: yes.
- Stop control remains intact: yes.
- Revoke controls remain intact: yes.
- Trusted-device boundaries remain intact: yes.
- Real-input safety remains intact: yes.
- No raw screen frames or typed text added to logs/support exports: yes.
- No secrets or local state committed: yes.

## Review Finding Fixed By Orchestrator

- P2 fixed: Worker 2 bumped the shell/cache/register version to `v77`, but left the one-time service-worker reload guard as `remote-controller-shell-v68-reloaded`. That could let an already-open phone tab skip the post-update reload. Fixed in `public/app.js` at line 4277 with commit `d9dca12`.

## Validation Run By Orchestrator

Commands run from `C:\tmp\dynam-worker-2-browser-pwa-polish`:

```powershell
node --check public\app.js
node --check public\host.js
node --check src\server.js
node --test test\phone-connection-help.test.js test\host-console.test.js test\coordinate-mapper.test.js test\input-adapter.test.js test\protocol.test.js
```

Results:

- Syntax checks passed.
- Focused Node/Playwright tests passed: 75/75 before the reload-key fix.

Post-fix checks:

```powershell
node --check public\app.js
node --test test\host-console.test.js test\phone-connection-help.test.js
rg -n 'remote-controller-shell-v(68|77)-reloaded|sw\.js\?v=77' public\app.js public\sw.js
```

Results:

- `public/app.js` syntax passed.
- Host console plus phone PWA tests passed: 56/56.
- `rg` confirms `/sw.js?v=77` and `remote-controller-shell-v77-reloaded`; no stale `v68` reload key remains.

Full suite:

```powershell
# Started an isolated host on port 47645 with HOST_KEY=dev-host-key, CAPTURE_MODE=screen, REAL_INPUT=0.
npm test
```

Result:

- Passed with exit code 0.

Browser/visual evidence:

- Opened `http://127.0.0.1:47643/` in the in-app Playwright browser at a 390x844 viewport.
- Generated visual proof at `C:\tmp\dynam-worker-2-browser-pwa-polish\output\orchestrator-test\worker2-black-stage-390x844.png`.
- Pixel check at canvas point `(6, 6)` returned `[0, 0, 0, 255]`.
- Stage snapshot after 4.5x zoom and positive pan showed `stageRect.left=125`, `stageRect.top=85`, `stageRect.width=1755`, proving the screen can sit partially off viewport over black.

## Findings

No remaining blocking findings.

## Merge Decision

Merge approved after orchestrator fix `d9dca12`.

## Follow-Up

- Required before merge: none from this review.
- Required after merge: physical phone same-Wi-Fi/touch evidence for the actual two-finger feel, especially iPhone Safari and Android Chrome.
- Assigned owner: physical acceptance worker plus orchestrator.

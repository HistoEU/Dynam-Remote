# Pull Request

## Workstream
- Issue:
- Branch:
- Owner/Codex instance:
- Files intentionally owned by this PR:

## What Changed
- 

## What Must Not Break
- Free local Wi-Fi mode still works without an account.
- Host approval and real-input safety remain intact.
- Touchpad movement remains relative; the visual touchpad dot must not move the real cursor.
- Existing package flow remains reproducible.

## Verification
- [ ] `node --test test\protocol.test.js test\rtc-room.test.js test\settings-store.test.js test\session-store.test.js test\coordinate-mapper.test.js test\input-adapter.test.js test\host-console.test.js test\phone-connection-help.test.js`
- [ ] Package/smoke test, if packaging changed.
- [ ] Phone/browser screenshot or physical-device result, if UI/control behavior changed.
- [ ] Performance numbers, if video/network/input smoothness changed.
- [ ] Docs updated, if behavior changed.

## Known Risks
- 

## Rollback
- Previous branch/tag/zip/flag to return to:


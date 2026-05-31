# Settings Schema Contract

Source of truth:

- `src/settings-store.js`
- `test/settings-store.test.js`
- host console settings UI
- phone settings UI

## Current Settings

Current persisted settings:

- `qualityDefault`
- `inputSensitivityDefault`
- `trustedDevicesEnabled`
- `autoStart`
- `trustedDeviceKeys`
- `trustedDevices`

## Defaults

Default values:

- `qualityDefault: "fast"`
- `inputSensitivityDefault: 1.55`
- `trustedDevicesEnabled: false`
- `autoStart: true`
- `trustedDeviceKeys: []`
- `trustedDevices: []`

## Sanitization Rules

Protected behavior:

- `qualityDefault` must be one of `fast`, `balanced`, `sharp`, or `battery`
- invalid quality falls back to `fast`
- `inputSensitivityDefault` clamps from `0.35` to `2.5`
- non-boolean `trustedDevicesEnabled` falls back to `false`
- `autoStart` must be boolean or defaults to `true`
- trusted-device keys shorter than or equal to 16 characters are rejected
- trusted-device records are sanitized before persistence

## Adding Settings

Before adding a setting:

1. define the default
2. define sanitization
3. define UI owner
4. define persistence behavior
5. define whether old clients ignore it safely
6. add/update tests
7. update this contract

Examples of likely future settings:

- zoom hold-to-show
- zoom lens size
- zoom level
- scroll edge-hold speed
- touchpad sensitivity profile
- remote quality cap
- relay usage preference

## Protected Tests

Run after settings changes:

```powershell
node --test test\settings-store.test.js
```

If a setting affects phone UI, also attach a browser/phone screenshot or physical-device note.


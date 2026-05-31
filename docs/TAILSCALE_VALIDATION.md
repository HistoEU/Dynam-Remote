# Tailscale Validation

Tailscale is the free different-Wi-Fi method for this build. Raw router port forwarding is out of scope because this app controls the whole laptop.

## Preflight

- From the project folder, generate a starting evidence report:

```powershell
npm run tailscale:bootstrap:save
npm run tailscale:check:save
npm run acceptance:report -- -Gate tailscale -Phase pre
```

- Preferred guided run:

```powershell
npm run acceptance:doctor -- -Gate tailscale
npm run acceptance:ready -- -Gate tailscale
npm run acceptance:next
npm run acceptance:prepare -- -Gate tailscale
npm run acceptance:phone -- -Gate tailscale
# Stop only after this is the last remaining physical gate.
npm run acceptance:stop -- -Gate tailscale
```

The bootstrap assistant records whether Tailscale, the Windows service, and winget are available, then saves `tailscale-bootstrap-*.json` and `.md` with exact install, service-start, sign-in, phone setup, readiness, and verifier commands. It is intentionally non-mutating: it does not install software, sign in, change firewall rules, or satisfy the physical gate. The setup checker inspects Tailscale installation/sign-in clues, tailnet IPs, host-advertised Tailscale URLs, current backend state, auth URL, and firewall readiness, then saves `tailscale-setup-check-*.json` and `.md` under `output\acceptance`. The doctor checks host health, advertised Tailscale URLs, local Tailscale CLI output, host-side Tailscale `/api/health` preflight, and Windows Firewall readiness. It saves timestamped readiness Markdown/JSON files under `output\acceptance`, including the exact auth URL when the laptop is installed but still needs login. The ready command prepares the screen-capture host, opens the HTML run card by default, snapshots watcher/verifier blockers, preserves empty Tailscale phone URLs as `[]`, and saves `phone-acceptance-ready-tailscale-*.json` with setup failures and ready actions. The next-actions command saves `phone-acceptance-next-*.md` and `.json` so the current Tailscale setup fixes, phone-run actions, and warning actions are visible without reading the full evidence bundle. The guided runner then preflights the selected Tailscale `/api/health` URL from the laptop, prints the Tailscale/LAN URL candidates, creates pre/post reports, and writes a per-step notes file under `output\acceptance`.
- During the phone run, tap Mark Proof from the controller proof banner or Settings so the exported host logs include `acceptance.phoneMark` with the phone viewport, URL origin/path, PWA mode, and diagnostics marker for the Tailscale path.
- After the run, verify the saved evidence bundle:

```powershell
npm run acceptance:verify -- -Gate tailscale
npm run acceptance:verify:save -- -Gate tailscale
```

- Keep the report's Tailscale CLI snapshot with the evidence. If `tailscale` is on PATH, the report records `tailscale ip -4` and `tailscale ip -6`; if not, it records that the CLI was unavailable instead of failing.
- Keep the saved setup-check report with the evidence so missing Tailscale CLI, sign-in, advertised URL, or firewall readiness is recorded before the physical run.
- Install Tailscale on the laptop and phone.
- Sign both devices into the same tailnet.
- Keep the host bound to local interfaces only; do not expose the app through router port forwarding.
- Keep default inbound protection active: only loopback, private LAN, and Tailscale-style clients should reach HTTP/WebSocket routes unless public tunnel mode is intentionally configured.
- Check Windows Firewall readiness:

```powershell
npm run firewall:status
npm run firewall:handoff
```

- If the phone cannot reach the laptop over Tailscale and the rule is not ready, run `npm run firewall:handoff` first to save/copy the exact elevated command and handoff artifacts without mutating firewall state. Then run `npm run firewall:install` from elevated PowerShell if you choose to install the rule. The rule allows TCP `4317` from Tailscale IPv4/IPv6 ranges and same-Wi-Fi local subnet on Private/Domain profiles.
- Confirm the host Network Risk panel says `tailscale` when using a Tailscale address, or `lan` for same-Wi-Fi.
- Confirm the host Connection Setup panel shows Same Wi-Fi as `ready` for the LAN path and Different Wi-Fi as `ready` when either a Tailscale IPv4 `100.64.0.0/10` address or Tailscale IPv6 `fd7a:115c:a1e0::/48` address is detected.
- Start the host with screen capture enabled:

```powershell
$env:CAPTURE_MODE='screen'
$env:HOST_KEY='dev-host-key'
$env:HOST='::'
node src/server.js
```

## Host Checks

- Open `http://127.0.0.1:4317/host?key=dev-host-key`.
- Confirm the Addresses panel includes a Tailscale address when Tailscale is connected.
- Confirm the Connection Setup panel switches Different Wi-Fi from `missing` to `ready`.
- If no Tailscale address appears, run:

```powershell
npm run tailscale:check:save
tailscale ip -4
tailscale ip -6
```

- Use `http://<tailscale-ipv4>:4317` from the phone, or `http://[<tailscale-ipv6>]:4317` when testing the IPv6 tailnet path. The square brackets are required for IPv6 URLs.
- If the IPv6 address appears but the phone cannot connect, confirm the host was started with `HOST='::'` so the Node server listens on IPv6 as well as IPv4.

## Phone Checks

- Pair using the visible PIN.
- Approve the phone on the laptop.
- Verify live screen frames appear.
- Test Stop before enabling real input.
- Enable real input from the host only after dry-run input is verified.
- Switch the phone away from Wi-Fi if needed and keep Tailscale active, then reconnect to the Tailscale URL.

## Pass Criteria

- Pairing still requires the current PIN and laptop approval.
- The guided runner records a passing Tailscale URL preflight before the phone checklist starts.
- Repeated wrong PIN attempts are rate limited.
- The same phone can reconnect with its approved token.
- The host console shows the connected device and input safety state.
- Stop and Stop All Control both disconnect the phone and release held input.
- Latency is acceptable enough for pointer movement and text entry.
- A second acceptance report from `npm run acceptance:report -- -Gate tailscale -Phase post` plus its auto-exported `*-host-logs.json` are saved after the physical phone run.
- `npm run acceptance:verify:save -- -Gate tailscale` passes against the saved guided-run summary and saves `phone-acceptance-verification-tailscale-*.json`.

## Current Machine Note

The current host state shows LAN-style addresses and a VPN-style `10.x` address. I have not seen a Tailscale IPv4 `100.64.0.0/10` or IPv6 `fd7a:115c:a1e0::/48` address in the automated checks on this machine, so the physical Tailscale gate still needs a real phone/tailnet run.

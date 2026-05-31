# Remote Networking and Relay Brief

Branch: `infra/remote-signaling`

Issue:

- `08-remote-signaling-turn.md`

Plan pages:

- Page 5: Architecture Split
- Page 7: Remote Networking, NAT Traversal, and Relay
- Page 14: Account, Billing, and Subscription Design
- Page 15: Infrastructure and Backend Services

## Mission

Design and prototype the paid remote access path without making free local Wi-Fi depend on paid infrastructure. The target architecture is account-backed signaling, device registry, P2P-first WebRTC, and TURN relay fallback only when direct connection fails.

## Owns

- backend prototype folder if created
- signaling contract docs
- relay economics docs
- feature flag docs
- account/device registry design docs

## Does Not Own

- browser/PWA controls
- native capture implementation
- local free mode dependency chain
- package launchers

## Must Read First

- `docs/interfaces/control-protocol.md`
- `docs/interfaces/session-trust-and-pairing.md`
- `docs/interfaces/capture-and-video-signaling.md`

## Required Architecture

Remote paid flow should eventually include:

1. user account login
2. host device registry
3. phone requests connection to a registered host
4. host verifies account/session/trust
5. signaling service exchanges offer/answer/ICE
6. direct P2P path attempted first
7. TURN relay fallback when direct fails
8. host keeps local stop/revoke controls
9. relay usage is measured for billing/fair-use

## Hard Invariants

- local Wi-Fi must still work without account login
- paid remote backend outage must not break local mode
- relay traffic must be measured
- typed text and screen frames must not be logged by default
- host must be able to revoke/stop remote sessions

## Cost Model

Create or update a cost model with:

- 720p30 estimated GB/hour
- 1080p30 estimated GB/hour
- 1080p60 estimated GB/hour
- idle/control-only usage
- direct vs relay percentage assumptions
- Cloudflare TURN price checked date
- Twilio TURN price checked date
- self-hosted relay break-even assumptions

## Validation

Minimum evidence:

- signaling contract exists
- local free mode independence is explicitly stated
- provider pricing date fields exist
- prototype smoke output or external blocker is documented

## Done Means

The product has a realistic paid remote architecture and cost story, not just "use a tunnel" or "make it faster somehow."


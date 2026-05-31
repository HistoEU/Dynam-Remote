# Issue 8: Remote Signaling and TURN Cost Model

Labels: `workstream:remote`, `needs-performance-proof`

Milestone: `M3 - Paid Remote Architecture`

Branch: `infra/remote-signaling`

Plan pages: Page 5, Page 7, Page 14, Page 15.

## Purpose

Design the paid remote path for controlling a computer from another network. This must be P2P-first, relay fallback second, and priced around real bandwidth economics.

## Scope

- Define account-backed remote signaling.
- Define device registry.
- Define WebRTC offer/answer/ICE lifecycle.
- Define STUN/TURN credential strategy.
- Model Cloudflare, Twilio, and possible self-hosted relay costs.
- Keep local Wi-Fi independent from paid backend services.

## Owned Files

- Backend prototype folder if created.
- Signaling contract docs.
- Relay economics docs.
- Feature flag notes.

## Forbidden Changes

- Do not make local free mode require account login.
- Do not replace current local WebRTC/capture fallback.
- Do not log typed text or screen frames.

## Required Interface Contracts

- `docs/interfaces/control-protocol.md`
- `docs/interfaces/session-trust-and-pairing.md`
- `docs/interfaces/capture-and-video-signaling.md`

## Starter Brief

- `docs/workstreams/remote-networking-and-relay.md`

## Acceptance Evidence

- Signaling contract exists.
- TURN pricing date-checked fields exist.
- Cost model includes direct/P2P and relayed scenarios.
- Local free mode remains independent.

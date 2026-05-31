# Product, Billing, Store, and Support Brief

Branch: `product/billing-store-readiness`

Issue:

- `10-product-billing-store-support.md`

Plan pages:

- Page 13: Security, Trust, and Abuse Prevention
- Page 14: Account, Billing, and Subscription Design
- Page 20: Store, Legal, and Policy Readiness
- Page 21: Parallel Workstream Map
- Page 24: Later Desktop App and Platform Expansion

## Mission

Turn the technical plan into launch readiness. This workstream defines free vs paid boundaries, pricing assumptions, store-review posture, support diagnostics, privacy/data inventory, responsible-use language, and closed beta gates.

## Owns

- product docs
- pricing model docs
- legal/privacy/support draft docs
- beta/release gate docs

## Does Not Own

- runtime behavior unless adding a non-invasive metadata endpoint through an interface note
- final legal advice
- paid backend implementation
- native capture implementation

## Must Read First

- `docs/interfaces/session-trust-and-pairing.md`
- `docs/interfaces/capture-and-video-signaling.md`

## Free vs Paid Boundary

Free local GitHub edition:

- local Wi-Fi control
- PIN pairing
- host approval
- real-input safety
- browser/PWA fallback
- manual/technical Tailscale guidance where appropriate

Paid remote edition:

- account login
- device registry
- remote signaling
- relay fallback
- trusted device recovery
- better onboarding/support
- relay usage management
- eventually native high-speed capture path

## Support Bundle Rules

Support exports may include:

- app version
- OS/browser version
- network path classification
- direct vs relay status
- capture stats
- error codes
- session IDs or redacted IDs

Support exports must not include by default:

- raw screen frames
- raw typed text
- full tokens
- raw trusted-device keys
- private screenshots

## Validation

Minimum evidence:

- free/paid feature matrix
- pricing model with relay assumptions
- store/privacy checklist
- support diagnostics spec
- closed beta gate checklist

## Done Means

The product has a credible path to money without weakening the free local product or making unsupported store/legal claims.


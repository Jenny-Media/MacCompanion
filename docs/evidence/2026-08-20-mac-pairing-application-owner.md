# Mac pairing application owner evidence

Date: 2026-08-20

## Claim

`CompanionMacApp` now owns the bundle-independent application composition
between the pure Mac pairing reducer and a future authenticated local IPC
adapter. `MacPairingApplicationOwnerV0` publishes every creating, presenting,
dismissing, failure, expiry, and invalidation transition without giving SwiftUI
transport or pairing authority.

Create and dismiss response loss retain and resend the exact original command.
Every newly issued command ID is unique for the owner lifetime. Correlated
receipts alone can advance presentation state; an invalid dismissal receipt
keeps the code visible and re-arms its remaining lifetime. The expiry delay is
never extended past the receipt's five-minute lifetime when the local wall
clock regresses. Expiry immediately erases the secret-bearing receipt and sends
a best-effort dismissal for Agent cleanup.

Each asynchronous operation is fenced by an owner revision. Agent, listener,
logout, or app invalidation clears the QR, cancels expiry, and invalidates the
in-flight revision before publishing idle. A delayed create response therefore
cannot resurrect a code after the trusted local context is gone.

## Verification

Ten focused tests cover the published create/dismiss lifecycle, exact create
and dismiss retry, delayed-response fencing, mismatched create and dismiss
receipts, expiry erasure and cleanup, failed-dismiss expiry re-arming,
owner-lifetime command-ID reuse denial, and regressed-clock bounding. The
hardened unsigned gate passes 816 Swift tests and inventories this target
through the repository, dependency, privacy, SBOM, and release-evidence checks.

## Boundary

The local client is an injected protocol, not an XPC implementation or a peer
authentication claim. The permanent menu-app target must bind it only to the
Agent service admitted by the final designated-requirement policy, map
connection invalidation into `agentInvalidated()`, retain one application-wide
owner, and drive the value-only sheet from published snapshots. Signed process
lifecycle, rendered sheet behavior, localization, physical scan, and live
expiry behavior remain release evidence.

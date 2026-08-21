# Local pairing approval construction evidence

Date: 2026-08-20

## Claim

The bundle-independent pairing boundary now carries a complete Agent-issued
local review after the remote secret proof and transcript signature verify.
The review binds the pairing and client IDs, SHA-256 fingerprints of both
validated client public keys, the transcript digest, derived authentication
string, exact expiry, and current policy revision. It contains no QR secret,
public-key bytes, endpoint, remote-supplied name, or mutable authority.

The remote protocol carries no device display name. An approval command must
bind the complete review and a Mac-user-entered `DeviceDisplayName`; a decline
must carry explicit JSON `null` for the name. The Agent decision actor rechecks
the complete review, wall/monotonic validity, and current policy revision,
drives the boot-scoped pairing authority, retains a bounded exact-command
replay receipt, and exposes a one-use outcome for the future remote pairing
pump. Mismatch, expiry, policy drift, and altered review data fail closed.
Transient clock, policy-source, or durable-authority failure cannot publish a
false receipt; retryable failures restore the exact pending review.

Approval writes pairing consumption, both client keys, Monitor Only state,
authorization epoch 1, grant revision 1, policy revision, the locally chosen
name, and the minimal security event in one SQLite transaction. Decline
consumes the boot-scoped authority while persisting no device or name.

## Verification

Strict local-IPC tests cover exact-key decoding, complete review binding,
approval/name and decline/null invariants, explicit-null encoding, receipt
correlation, unknown fields, and partial outcomes. Pairing tests cover the
golden proof-to-decision path, public-key/fingerprint consistency, nameless
decline, and injected rollback after device/name mutation. Agent tests cover
approval, decline, exact replay, one-use outcomes, altered transcript,
expiry, policy drift, transient clock failure, and durable retry.

The normative cryptographic fixture independently fixes both client public-key
fingerprints. Current focused results are 38 `CompanionIPC` tests, 13
`CompanionPairing` tests, 26 `CompanionSecurity` tests, 50
`CompanionPersistence` tests, and 132 `CompanionAgent` tests.

## Boundary

This is package construction evidence. A later bundle-independent
[host pairing wire owner](2026-08-20-host-pairing-wire-owner.md) now waits for
and consumes the one-use outcome, and a subsequent
[listener-ingress construction](2026-08-20-host-listener-ingress-construction.md)
adds the pairing-specific Network.framework pump. A subsequent
[local review delivery construction](2026-08-20-local-pairing-review-delivery.md)
adds an already-authorized delivery capability, Mac owner/reducer, and
compile-checked SAS/name sheet. Authenticated XPC publication, live pinned TLS,
final Keychain custody, signed identities, accessibility review, and physical
QR/SAS exchange remain unproven. No release or end-to-end pairing claim follows
from these tests.

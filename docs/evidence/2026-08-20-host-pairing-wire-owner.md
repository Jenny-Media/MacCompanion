# Host pairing wire-owner construction evidence

Date: 2026-08-20

## Claim

`AgentHostPairingWireSessionV0` now owns one already-verified host TLS pairing
connection from `pairing.begin` through a server-initiated terminal result. It
binds its host ID and fingerprint at construction, accepts only begin followed
by a proof correlated to the exact challenge, and shares one bounded replay
window across every inbound and outbound message ID. It cannot accept a host
identity, policy revision, review, name, or local decision from wire JSON.

The owner drives the boot-scoped `PairingSessionAuthority` for challenge and
proof verification. After proof succeeds, it asks the Agent decision actor to
create a current-policy review, then requires an injected trusted-local
publisher to acknowledge that exact secret-free review before emitting
`pairing.pendingApproval`. Publication failure or cancellation consumes the
review/authority and returns no false pending state.

The local decision actor now resolves pending, in-flight, durable outcome, and
expiry as one serialized operation. A deadline poll cancels an untouched
pending review, but defers while a local decision is already inside its durable
commit. Approval constructs `pairing.complete` only from the exact
`CompletedPairing`, constructor-bound host facts, and initial Monitor Only
revisions. Decline and expiry return closed registered errors correlated to the
original proof. A poll with no outcome consumes no response message ID.

## Verification

Nine focused tests use real P-256 client keys, real transcript/proof/signature
construction, the real pairing authority, and the real local decision actor.
They cover successful review-before-pending and durable completion, nameless
decline, invalid-proof retry on the exact challenge, deadline expiry, publisher
failure, cancellation during suspended publication, durable commit crossing
the deadline, wrong proof correlation, and shared inbound/outbound replay.

The complete `CompanionAgent` target passes 141 tests. The exact hardened
repository gate passes 60 indexed protocol/product fixtures, 636 repository
files, all package/platform builds and three no-prompt/no-network probes, and
exactly 853 Swift tests under the provisional Xcode 27 beta toolchain.

## Boundary

This wire owner remains socket-independent. A later
[role-safe listener ingress and pairing pump](2026-08-20-host-listener-ingress-construction.md)
now supplies the one-use classifier, framed Network.framework construction,
silent completion/deadline scheduling, and independent primary/pairing
handoff. The trusted-local publisher is still an abstraction, not authenticated
XPC or rendered SAS/name UI evidence.

v0.1 also does not recover a completion frame lost after the Mac durable
commit. That failure can leave a locally visible Monitor Only orphan which the
Mac user must remove before re-pairing; it never grants Act or Control and is
not silently merged. Signed identities, real key custody, live pinned TLS, XPC,
physical QR exchange, and lost-completion UX remain release work.

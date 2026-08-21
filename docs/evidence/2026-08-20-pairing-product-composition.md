# Pairing product composition evidence

Date: 2026-08-20

## Claim

The release-shaped bundle-independent pairing path now has one sealed product
composition instead of independently injectable authorities. One
`PairingSessionAuthority` is constructed from the exact required
`SQLiteSecurityStore` and `BoundedPairingAuditWriterV0`, then shared by the
local QR session handler, host transcript-proof owner, local decision handler,
and connection-scoped review service. The review service is issued by the
already bootstrapped local-service root for one already authenticated and
authorized visible menu-app surface.

`AgentNetworkPairingProductCompositionFactoryV0` consumes one sealed TLS
listener configuration and constructs the listener, its pairing-context
authority, and that complete pairing service graph in one operation. The same
context supplies the identity and endpoints encoded in the QR and receives the
listener and Bonjour readiness transitions. The public production listener
factory accepts only the resulting aggregate. Split listener, context,
authority, decision, and review-publisher initializers are package-only test
seams, so an external app target cannot cross-wire them.

Its only service-root input is the complete startup-reconciled
`AgentPrimaryServicesV1`. That aggregate retains its originating required-audit
composition and issues pairing services from its exact local-service root. The
pairing product derives host ID, primary-session authority, local network and
route publishers, durable security store, and audit writer from that one
bootstrap; none is separately injectable through the public listener factory.

The aggregate is an actor that issues its listener service exactly once. Loss
of the authorized menu endpoint terminally invalidates review delivery before
cancelling the exact listener service, which then retires primary/pairing
handoff, pairing context, and active QR authority. Repeated loss is idempotent,
and neither listener construction nor QR creation can resume on that instance.

The aggregate exposes only the two local capabilities needed after menu-app
authorization: secret-bearing pairing-session create/dismiss and secret-free
review delivery/resolution. It does not expose the durable pairing authority to
an application target.

## Verification

One end-to-end bundle-independent composition test drives local QR creation,
decodes the exact secret and listener facts, performs transcript proof through
the aggregate's authority, registers and visibly publishes the resulting
review, approves it through the connection-scoped service, and verifies the
same SQLite store received the device while the required detailed-audit store
received one `pairing.approved` event. A second test proves QR creation is
unavailable before both listener and Bonjour readiness, then verifies the QR
contains the exact fingerprint, service, and port derived from the consumed TLS
listener configuration. A third test creates an active QR and listener service,
then proves endpoint loss is idempotent and terminal across review publication,
listener state, context availability, QR creation, consumed pairing authority,
and attempted listener-service reuse.

Both focused tests pass. All 157 `CompanionAgentTests` pass. The exact hardened
validation command passes 60 indexed protocol/product fixtures, 657 repository
files, every package/platform build, all three no-prompt/no-network probes, and
exactly 890 Swift tests under the provisional Xcode 27 beta toolchain.

## Boundary

This is construction, access-control, persistence, audit, and deterministic
test evidence. It does not authenticate an XPC audit token or designated code
requirement, create final bundle endpoints, prove a signed menu-app crash and
reconnection lifecycle, open a physical listener, or complete a physical
QR/TLS/SAS exchange. The production factory's `alreadyAuthorizedSurface`
parameter is a capability issued after platform peer verification; it is not
itself identity evidence. Final identities, stable Xcode 26.6, signing custody,
signed targets, and physical-device evidence remain external gates.

# Host listener ingress and pairing-pump construction evidence

Date: 2026-08-20

## Claim

The shared host listener now has a role-safe bundle-independent construction
path. `NetworkHostIngressClassifierV0` consumes the exact one-use
verified-ready TLS connection, reads exactly one bounded frame without
over-reading a second frame, and accepts only authoritative `auth.hello` or
`pairing.begin` as the initial kind. It returns an opaque one-use authority
containing the same socket owner, TLS binding, and preserved first frame.
Classification grants nothing; the selected semantic owner strictly decodes
the frame again.

`NetworkHostPairingFramePumpV0` consumes only a pairing-classified authority.
It replays the preserved begin frame, serializes prove and response framing,
keeps receiving while local approval is pending, and uses a byte-independent
monotonic task to send durable completion/decline/expiry without requiring
another client byte. Send, receive, framing, deadline, remote-close, and local
cancellation paths close the exact semantic pairing owner.

`AgentNetworkListenerIngressHandoffV2` retains only one unclassified candidate
but owns primary and pairing generations independently. A pairing candidate
cannot replace the authenticated primary, a second pairing candidate cannot
interrupt the visible SAS owner, and a primary challenger does not replace the
current phone until its real application-authentication session reaches
`ready`. A superseded in-flight classifier or authentication candidate is
cancelled without touching either active role. The outer listener service has
a role-safe public construction path that wires the classifier, both exact
factories, content-free status, route evidence, and pairing-availability loss.

## Verification

The `CompanionNetworkPlatform` target passes 24 tests. Eleven new tests cover
the two authoritative first frames, fragmented prefix/payload reads, no
second-frame over-read, one-use/mismatched roles, wrong kind, invalid length,
truncation, deadline and clock regression, preserved begin/prove ordering,
silent durable completion, silent expiry, malformed framing, send failure, and
a real P-256 application-authentication exchange that does not publish primary
activation until valid proof and session-description send both succeed.

The `CompanionAgent` target passes 147 tests. Six new handoff tests cover
independent primary/pairing activation, rejection of a second pairing owner,
valid primary replacement, suspended-classifier cancellation, role-local
terminal cleanup, global teardown, and the unproven-primary non-eviction fence.

The exact hardened repository gate passes 60 indexed protocol/product
fixtures, 646 repository files, all package/platform builds and three
no-prompt/no-network probes, and exactly 870 Swift tests under the provisional
Xcode 27 beta toolchain.

## Boundary

This is package construction, not physical-network or release evidence. The
trusted-local pairing review publisher remains an abstraction until final
identities enable designated-requirement-authenticated XPC. The public
role-safe service constructor is not yet installed in a permanent signed
LaunchAgent target. Live Network.framework callback ordering, Local Network
privacy attribution, real Keychain/Secure Enclave custody, physical QR/pinned
TLS exchange, lock-session behavior, and loss/reconnect UX remain external or
later integration gates. The older primary-only service constructor remains
only for existing construction tests and must not be selected by the release
composition.

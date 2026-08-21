# Client Secondary Role Network Evidence

Date: 2026-08-21

Environment: concrete Network.framework construction plus injected pair-owner
fault tests and macOS/iOS package cross-compiles on Xcode 27 beta. This is
unsigned socket-construction and generation-fencing evidence. It is not a live
host exchange, decoded frame, posted input event, physical-device,
stable-toolchain, or release claim.

## One-shot TLS handoff

The client TLS attempt context now retains a role-neutral verified handoff after
the live callback accepts TLS 1.3, rejects early data, validates the strict leaf
profile, and matches the immutable paired-host fingerprint. This handoff grants
no traffic. The application-primary consumer still rebuilds and admits the
existing application role authority, while a secondary connector may consume
only the raw peer evidence for replay through its input or media authority.
The exact `NWConnection` identity and one-consumption rule are unchanged.

## Exact-endpoint connector

`NetworkClientInteractiveRoleConnectorV0` accepts an endpoint only from the
selected-primary role composition. It constructs one unstarted
Network.framework TLS connection on that endpoint, bounds readiness by the
unused-channel lifetime, consumes evidence only for that same ready connection,
creates the requested role authority, and transfers all reads and sends through
the exact-read handshake pump. Cancellation closes the connection at every
phase. A ready handoff retains the authenticated socket and rechecks role
traffic admission before later byte reads or sends.

## All-or-none role generation

`NetworkClientInteractiveRolePairOwnerV0` starts input and media against one
identical endpoint and accepted session. It samples the selected-primary fence
before dialing and again after both server proofs. It publishes a pair only when
roles, channel IDs, endpoint, and current primary all match. Any role failure,
channel swap, endpoint mismatch, or primary replacement closes every sibling
that reached ready. Exact primary termination closes both; a stale termination
cannot affect the pair. The application-state factory supplies the fence from
the still-current authenticated session, endpoint, and accepted Control value.

## Verification

Three new pair tests prove one endpoint for both roles, closed input/media
membership, exact termination, sibling cleanup after a media failure, and
post-proof primary revalidation with both sockets closed on replacement. The
existing TLS-context tests still prove one unstarted connection, one handoff,
wrong-connection rejection, and pin-shape rejection after the role-neutral
refactor. The prior exact-read pump tests remain green.

The hardened unsigned gate passes with 60 indexed protocol/product fixtures,
734 repository files before this evidence record plus 34 historical blob paths
and 14 repository-material fixtures, four Swift package manifests and 12
dependency-policy fixtures, three privacy manifests with 12 fixtures and six
required-reason API source records, 10 source-SBOM fixtures, 16 release-evidence
fixtures, and 1,008 Swift tests. All macOS/iOS package cross-compiles and all
three no-prompt/no-network construction probes pass. Only the expected
read-only user SwiftPM cache warnings appear.

## Remaining gates

- Bind automatic pair startup/cancellation to the configured-route application
  product and retain the ready sockets for Desktop activation.
- Read the initial media records through the existing decoder/render authority,
  acknowledge the first clean Desktop frame, then enable the input sender.
- Prove live private-route TLS, media, input, backgrounding, replacement, and
  lock fallback on signed physical devices.
- Re-run on stable Xcode 26.6 and preserve signed release evidence separately.

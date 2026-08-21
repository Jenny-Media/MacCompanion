# Configured-route Primary Product Selection Evidence

Date: 2026-08-21

Environment: bundle-independent Swift composition and injected primary-frame
I/O on macOS with Xcode 27 beta. This is state-machine, custody-composition,
injected-transport, cross-compile, and repository-policy evidence. It is not a
permanent target, signed identity, live socket, physical-device, latency,
stable-toolchain, or release claim.

## Boundary

`client-primary-router.md` now requires every parallel authenticated dial to
own a separate inactive product candidate. Authentication may construct that
candidate's concrete Observe and Act owners, but it cannot publish their events
or handles. Only the reconnect owner may select a candidate, and only after its
state machine accepts the exact round and endpoint as the current primary.
Late, stale, losing, cancelled, and pre-selection-terminated candidates close
without product publication.

Selection publishes the authenticated session and both concrete lane owners as
one bounded synchronous handoff. Every later Observe or Act event, and the
single selected-route termination, carries the immutable host ID and
connection ID. A product consumer therefore has exact replacement fences and
never treats endpoint text, DNS, interface, or reachability as connection
identity.

## Composition

`NetworkClientReconnectRuntimeV1` now accepts product event handoffs instead of
raw authenticated-byte callbacks. Each configured route attempt derives both
the session signer and the separately protected approval signer from the
durable paired host. It constructs one `NetworkClientPrimaryProductCandidateV0`
before authentication begins, binds it to that attempt's exact pump, and routes
authenticated command frames only through its connection-scoped router.

`AuthenticatedDialRouteV0` carries a package-only selection action. The
`ReconnectControllerV0` calls it only after the exact authenticated result has
been accepted by the reconnect state machine. The dial executor still closes
every non-winning authenticated route, and none of those routes receives the
selection action.

Candidate termination invalidates Observe and Act together. Termination is
idempotent, is published at most once, and remains silent for a candidate that
was never selected. The relay has no crash-on-remote-input precondition and
withholds all lane publications until selection.

## Verification

Focused tests prove:

- a two-route authenticated race selects exactly one winner and closes the
  other route without selecting it;
- configured composition binds the durable session identity and constructs the
  product candidate with the separate approval authority;
- a real injected pump completes application authentication while the product
  remains unpublished;
- selecting that exact candidate exposes its authenticated Observe and Act
  owners once;
- a correlated status response publishes only after selection and carries the
  exact authenticated host and connection IDs;
- selected termination invalidates the lane and publishes exactly once; and
- a candidate terminated before selection cannot later publish selection or
  termination.

The first complete gate run detected Swift 27 beta's failure footer for the
unrelated `CompanionInteractiveRuntimeTests` target and correctly rejected the
run even though Swift returned zero. The isolated 22-test target passed, and an
immediate complete hardened rerun passed cleanly.

The clean hardened unsigned gate validates 60 indexed protocol/product
fixtures, 721 current repository files plus 34 historical blob paths and 14
repository-material fixtures, four Swift package manifests and 12 dependency
policy fixtures, three privacy manifests with 12 fixtures and six
required-reason API source records, 10 source-SBOM fixtures, 16 release-evidence
fixtures, and 994 Swift tests. All macOS/iOS package cross-compiles and all
three no-prompt/no-network construction probes pass. Only the expected
read-only user SwiftPM cache warnings appear.

## Remaining gates

- Bind the selected connection-tagged events into one application state owner
  and project the real Observe and Act streams into the first-party workspace.
- Add the future Control lane to the same selected-primary composition without
  weakening its independent session/channel authorization.
- Prove replacement, backgrounding, approval-key presence, and complete
  Observe/Act exchanges over physical pinned private routes.
- Re-run on stable Xcode 26.6 and preserve signed release evidence separately.

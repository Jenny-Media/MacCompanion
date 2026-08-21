# Client Primary Router Evidence

Date: 2026-08-21

Environment: bundle-independent Swift packages and an injected
Network.framework primary-frame I/O seam on macOS with Xcode 27 beta. This is
construction, protocol-state, and cross-compile evidence. It is not a permanent
target, signed identity, live socket, physical-device, latency, or release
claim.

## Boundary

`spec/capability-protocol/v0/client-primary-router.md` defines one immutable
connection-scoped owner between the authenticated primary pump and the Observe,
Act, and Control path owners. It parses only the closed generic envelope
metadata, then requires exact pending correlation, registered reply kind,
exclusive monotonic deadline, and receive-message replay admission before one
path receiver may decode the exact body.

The outbound lane registry is closed. Observe owns status and self-audit
requests; Act owns registry and operation requests; Control owns only the
Interactive Control primary-channel request family. A shared `error` response
is routed by its correlation ID rather than guessed from UI state or body. The
router retains the protocol-wide 32-request bound and a 4,096-entry replay
window in each direction.

Receivers prepare a typed publication but cannot commit it themselves. The
router checks its generation after asynchronous decoding and commits the
publication synchronously only while the exact connection remains current.
Replacement, backgrounding, disconnect, authentication loss, or termination
invalidates every installed receiver exactly once. An old lane sender cannot be
reactivated by a new connection.

Transport-send failure removes only that pending correlation and returns to the
path owner before connection invalidation. This is required so Act can retain
the same durable operation ID and enter `deliveryUnknown`; the router never
fabricates a reply or silently retries an effect.

## Network composition

`NetworkClientPrimaryRouterBridgeV0` closes the construction cycle between the
real `NetworkClientPrimaryFramePumpV0` sender and the router. The pump is bound
before authentication begins. Its authentication callback is now awaited, so
the bridge constructs and activates the identity-matched router, concrete
Observe owner, Act channel, and lane receivers before the pump announces
authenticated product traffic.
Incoming command frames enter only the router. Pump termination invalidates the
bridge and all path state; explicit cancellation invalidates path state before
cancelling I/O.

The Observe and Act owners use only their respective lane-bound senders. They
publish only typed `ClientObserveChannelEventV0` and
`ClientActChannelEventV1` values after the router's generation check.

## Verification

Twelve new tests prove:

- strict generic metadata parsing for original requests, replies, closed fields,
  object bodies, and correlation direction;
- self-audit request/reply registration and exact failed-send cancellation;
- shared-error delivery only to the correlation-owning Observe or Act lane;
- rejection of cross-lane sends before transport;
- whole-router invalidation on wrong reply kind or duplicate reply message ID;
- send failure returning before receiver invalidation;
- invalidation suppressing publication from a suspended receiver;
- replacement permanently fencing the old lane sender; and
- a real injected primary pump completing pinned authentication, constructing
  the bridge, sending both an Act registry request and an Observe status request
  through the router, routing both correlated responses back into their exact
  owners, publishing typed events, and invalidating both owners on pump
  cancellation.

The focused Wire, Transport, Client, and Client Network-platform suites pass
with 54, 37, 89, and 34 tests respectively. The repository-wide hardened gate
then passes with 987 Swift tests, all macOS/iOS package cross-compiles, and all
three construction probes. Only the expected read-only user SwiftPM cache
warnings appear.

## Remaining gates

- Instantiate the bridge from the configured-route application product and the
  future permanent iOS target, with a concrete Control receiver.
- Prove live same-socket callback ordering and response deadlines on a physical
  iPhone-to-Mac private route.
- Execute approval-key presence, signed Core Audio mutation/read-back, and
  Interactive Control channel establishment on signed physical devices.
- Re-run on stable Xcode 26.6 and preserve signed release evidence separately.

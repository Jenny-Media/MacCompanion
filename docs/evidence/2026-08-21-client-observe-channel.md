# Authenticated Client Observe Channel Evidence

Date: 2026-08-21

Environment: bundle-independent Swift packages and an injected
Network.framework primary-frame I/O seam on macOS with Xcode 27 beta. This is
construction, state-machine, cross-compile, and injected-transport evidence. It
is not a permanent target, signed identity, live socket, physical-device,
latency, stable-toolchain, or release claim.

## Boundary

`spec/capability-protocol/v0/client-observe.md` defines one Observe owner for
one authenticated client, host, device, and primary connection. It receives
only the primary router's Observe-bound sender and has no Act or Control send
authority. Status and self-audit may each have one pending read, so the two
read-only products remain independently usable without opening screen capture.

The first accepted status response fixes the host status generation for the
connection. Later responses require the same generation and a strictly greater
revision. Exact host identity and request correlation are mandatory. Freshness
subtracts host-reported age plus the entire measured request round trip, anchors
the remaining validity to the client monotonic clock, and becomes stale at the
exclusive deadline. Disconnect may retain the last validated snapshot, but its
assessment is always unreachable and preserves the original observation time.
A failed send publishes no synthetic status and does not replace an earlier
validated snapshot.

Self-audit delegates exclusive cursor continuity and descending sequence checks
to `ClientAuditPagerV1`. Each bounded page is published separately with its
retention boundary, pruned-through marker, and dropped-event count. The owner
does not accumulate unbounded history. A correlated remote error or send
failure invalidates that traversal until an explicit reset.

All reply decoding produces a prepared typed event. Only
`ClientPrimaryCommandRouterV0` commits it after checking that the exact primary
connection generation remains current. Wrong correlation, host, kind,
generation, revision, freshness clocks, or audit cursor invalidates the router
and every installed product lane.

## Network composition

`NetworkClientPrimaryRouterBridgeV0` now always constructs the concrete Observe
owner alongside the Act owner during the awaited authentication callback and
before authenticated product traffic is announced ready. The bridge exposes
the connection-scoped owner to the application composition, routes incoming
frames through the shared primary router, and invalidates Observe and Act
together on pump termination, cancellation, or replacement.

An injected full-pump test completes pinned application authentication, obtains
both concrete owners, sends an Act catalog request and an Observe status request
on the same authenticated pump, routes both correlated responses through their
closed lanes, publishes both typed events, and invalidates both owners when the
pump is cancelled.

## Focused verification

Six Observe-owner tests prove:

- conservative status freshness is live only before its exclusive deadline,
  stale at the deadline, and unreachable after disconnect;
- the last validated snapshot and original observation facts survive
  disconnect without being relabelled live;
- status generation changes and revision replay/regression fail the whole
  primary connection without a second publication;
- a transport-send failure preserves prior status, clears only the failed read,
  publishes nothing, and permits a later retry;
- two self-audit pages use the exclusive continuation cursor and preserve each
  page's explicit dropped-event evidence;
- shared error replies are assigned only by exact status or audit correlation;
  and
- invalidation during a suspended send wins, publishes nothing, and leaves no
  live Observe work.

The focused `CompanionClient` and `CompanionClientNetworkPlatform` suites pass
with 89 and 34 tests respectively.

The final hardened unsigned repository gate also passes with 60 indexed JSON
fixtures, 715 current repository files plus 34 historical blob paths and 14
repository-material fixtures, four package manifests and 12 dependency-policy
fixtures, three privacy manifests with 12 fixtures and six required-reason API
source records, 10 source-SBOM fixtures, 16 release-evidence fixtures, and 987
Swift tests. All macOS/iOS package cross-compiles and all three construction
probes pass. Only the expected read-only user SwiftPM cache warnings appear.

## Remaining gates

- Bind the bridge into the configured-route application product and future
  permanent iOS target, then project these typed events into the first-party
  Observe UI without inventing route or authorization state.
- Prove the complete Agent status and privacy-limited self-audit exchange over a
  physical pinned iPhone-to-Mac private route, including timeout, reconnect, and
  locked-session behavior.
- Re-run on stable Xcode 26.6 and preserve signed release evidence separately.

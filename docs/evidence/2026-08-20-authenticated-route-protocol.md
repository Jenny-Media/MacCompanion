# Authenticated configured-route protocol evidence — 2026-08-20

Status: normative fixture plus bundle-independent wire, host state-machine,
primary-session, and Agent local-status construction evidence under Xcode 27
beta. The [client configured-route model and authenticated-session request/ack
state](2026-08-20-client-configured-route-construction.md), atomic catalog
persistence, [durable edit/reconciliation and package UI](2026-08-20-client-configured-reconnect-composition.md),
exact reconnect binding, and post-auth pump dispatch are also constructed.
App-lifecycle orchestration, a live socket, and physical
private-DNS/Tailscale evidence remain open.

The v0.1 protocol now separates configured route provenance from endpoint
syntax. A client configuration assigns one opaque 16-byte route ID and one
explicit class to the exact canonical candidate. DNS suffixes, resolved
addresses, interfaces, processes, installed apps, and system routes cannot
create or change the class.

After pinned TLS and application authentication, `route.observation` carries
only the exact connection ID, opaque configured-route ID, `privateDNS` or
`privateNetwork`, and a strictly increasing connection-local sequence. Its closed
acknowledgement echoes those fields plus the fixed 30-second lifetime. It
contains no endpoint, hostname, address, interface, DNS result, Tailscale
identity, tailnet, peer, relay, traffic, credential, or platform error. The
fact is routing presentation metadata and grants no authority.

The indexed fixtures fix canonical request/ack bytes, reject an unknown class
and zero sequence, and define initial acceptance, heartbeat, replay, changed
provenance, primary replacement, disconnect, and exact inclusive expiry. The
wire values round-trip those authoritative bytes and reject both invalid
fixtures.

`AuthenticatedRouteObservationSessionV1` owns one exact connection. It requires
sequence one first, exact +1 thereafter, immutable route ID/class, a
non-regressing host monotonic clock, and freshness through the inclusive
30-second deadline. Expiry withdraws presentation while retaining the sequence
binding so a valid heartbeat can recover it; close is terminal and rejects
delayed traffic. It produces the exact correlated acknowledgement only for the
latest admitted request.

The authenticated primary session now admits this request only in `ready`,
after durable-principal revalidation and replay admission. It updates liveness,
uses the connection-owned route authority, returns the exact correlated
acknowledgement, integrates the inclusive route deadline into its byte-independent
timer, and withdraws the route on expiry or close without closing an otherwise
healthy authenticated session.

Agent bootstrap injects one narrow publisher facet for each primary-session
generation. The local authority accepts only that generation and exact 16-byte
connection ID, maps only `privateDNS` or `privateNetwork`, and absorbs diagnostic
projection failures so they cannot alter authentication or command authority.
A replacement publisher fences delayed publication and withdrawal from the old
session. Configured-route replacement and expiry preserve independently owned
LAN evidence; LAN events cannot extend configured-route freshness and
configured-route heartbeats cannot extend LAN evidence.

The public validation gate passed 60 indexed fixtures, all 744 Swift tests
including 90 `CompanionAgent` tests, Network and Mac UI builds, iOS Simulator
client-platform and client-UI builds, all three no-network probe builds, and
`git diff --check`. SwiftPM user-cache warnings are expected in the restricted
environment. Native scene/reachability binding, stable Xcode 26.6, final
signing, rendered UI, and physical route evidence remain required.

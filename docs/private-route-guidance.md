# Private access setup and diagnostics

Status: Stage 3 product contract. This guidance helps a person configure and
troubleshoot reachability without giving the client authority over a VPN,
network account, route table, Mac Companion grant, or Remote Control session.

## Product boundary

Mac Companion operates no network relay, VPN account, rendezvous service, or
public port-forwarding service. It supports:

- the same trusted local network through Bonjour or an explicitly saved private
  address; and
- a private network the user already manages, such as Tailscale, ZeroTier, or
  WireGuard, through an explicitly saved DNS name or address.

The app may explain how to prepare those routes. It does not install, sign in
to, configure, inspect, or administer the private-network provider. Provider
identity, peers, account data, traffic, relays, and credentials never enter the
Mac Companion route protocol, local status, audit history, diagnostics, or
evidence.

## Provider-neutral route model

The v0.1 persisted and wire value is `privateNetwork`, not a provider name.
Tailscale is a product-guidance example rather than a trust primitive. A saved
route has explicit local provenance and is not inferred from DNS suffixes,
resolved addresses, interfaces, processes, installed apps, or a satisfied
`NWPath`.

Only the exact winning configured route may be presented as authenticated, and
only after that same connection completes the pinned host check and Mac
Companion application authentication. The label never grants Observe, Act, or
Control authority.

## Guidance states

The client guidance projection accepts only closed, explicit facts:

- not yet evaluated;
- waiting for foreground or a coarse usable network path;
- ready, connecting, or bounded-backoff retrying;
- authenticated on an endpoint from the exact saved catalog revision;
- authentication or authorization requiring user action;
- manually disconnected; or
- lifecycle closed; or
- status withheld because the application binding, route lifecycle, reconnect
  owner, and controller snapshots contradict one another or are changing.

Route exhaustion is presented as a route problem. Authentication or current
authorization denial is presented as a Mac Companion pairing/access problem.
Coarse reachability is described only as a scheduling signal and never as proof
that a LAN, VPN, overlay, DNS name, or host is available.

## Setup guidance

For the same local network, the app directs the user to join the same trusted
LAN, start pairing/discovery, grant Local Network access when iOS asks, and use
Bonjour or an explicitly saved private address.

For a user-managed private network, the app directs the user to configure the
provider outside Mac Companion on both devices, verify provider membership with
the provider's own tools, save the Mac's private DNS name or address as
`Private Network`, and then let Mac Companion independently authenticate it.

## Lifecycle binding

The application-binding snapshot now carries the exact validated route
lifecycle composition from the same owner. The guidance verifies host,
revision, candidate ordering, fingerprint, foreground, reachability,
transition, close, and shutdown coherence before mapping a reconnect phase. It
withholds a contradictory or transitional snapshot instead of guessing a
route or authorization cause.

The disposable iOS harness consumes that binding snapshot directly, so its
initial no-network message is a real lifecycle projection rather than static
sample copy. Controller-internal authentication, denial, backoff, and shutdown
transitions publish a content-free, latest-one wakeup through the reconnect
owner. The existing serialized application bridge then re-reads the complete
snapshot, so the UI remains live without polling or accepting facts from the
wakeup itself.

## Remaining signed-product work

The permanent iOS target must instantiate this composed owner and provide
exact Settings/deep-link affordances only after final identifiers and privacy
strings exist. Signed physical-device tests must cover Local Network
grant/deny/recovery, at least one LAN route, and at least one user-managed
private-network route. Those tests remain product evidence, not authorization
evidence.

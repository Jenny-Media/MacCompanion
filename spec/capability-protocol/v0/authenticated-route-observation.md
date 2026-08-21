# Authenticated configured-route observation v0.1

Status: normative for `route.observation`. This message supplies only bounded
routing presentation metadata after application authentication. It never
creates identity, trust, a grant, a capability, an operation, or Interactive
Control authority.

## Client provenance

Endpoint syntax and network interfaces do not determine route class. A client
configuration stores a random 16-byte `configuredRouteID` alongside exactly
one canonical endpoint and one closed provenance:

- `localDiscovery` for a Bonjour candidate;
- `directPrivateAddress` for a user-configured RFC 1918 IPv4 or IPv6 ULA
  candidate;
- `privateDNS` for an ordinary user-configured private DNS candidate; or
- `privateNetwork` for a DNS or address candidate reached through a
  user-managed private network such as Tailscale, ZeroTier, or WireGuard.

The provenance is explicit user configuration. DNS suffix, resolved address,
interface name/type, process presence, installed application, or system route
never creates or changes it. The client storage adapter rejects a reused
`configuredRouteID`, a provenance/endpoint-kind mismatch, and a route winner
whose endpoint differs from the exact configured record used for that attempt.
`directPrivateAddress` accepts only `10/8`, `172.16/12`, `192.168/16`, or
`fc00::/7`; public, loopback, link-local, documentation, and other address
ranges require another explicit provenance or are rejected.

On first pairing, a Bonjour endpoint may initialize `localDiscovery`, and an
already-canonical RFC 1918/ULA literal may initialize
`directPrivateAddress`. DNS and every other address remain unresolved until a
local client surface explicitly selects a valid provenance. Bootstrap preserves
the paired endpoint order, assigns a fresh opaque ID per endpoint, and publishes
revision one only after every unresolved endpoint has a choice. It never
classifies DNS by suffix or a resolved address.

Only `privateDNS` and `privateNetwork` produce `route.observation` in v0.1. LAN is
derived on the Mac solely from exact listener plus Bonjour-registration
readiness. `directPrivateAddress` remains client presentation metadata and is
not published in the current Mac local-status route-kind registry.

## Wire and admission

After `session.describe.response` completes on a candidate primary connection,
the client may send `route.observation` on that same command channel. Its body
is the closed schema in `message-schemas.md`; its `correlationID` is null. An
accepted observation receives `route.observation.ack` correlated to the request
and echoing only the exact opaque route ID, class, sequence, and fixed lifetime.

The session description authenticates the connection independently of route
metadata. When an observation is required, the route-attempt owner publishes
the connection as a usable reconnect winner only after the initial observation
write succeeds; it does not wait for the acknowledgement. A failed write or an
acknowledgement absent for 30 seconds closes that candidate connection, but the
observation and acknowledgement never grant command authority. Unrelated
authenticated command traffic remains admissible while the acknowledgement is
pending.

The host accepts an observation only when all of these facts match in one
primary-session actor turn:

1. the channel is the current authenticated primary connection for the paired
   client;
2. `connectionID` equals the connection ID issued in that connection's
   `auth.challenge`;
3. the message ID has not appeared in the connection replay window;
4. `observationSequence` is exactly one for the first accepted observation and
   exactly the previous accepted value plus one afterward;
5. `configuredRouteID` and `routeClass` equal the first accepted values for
   the connection; and
6. the route class is exactly `privateDNS` or `privateNetwork`.

Failure closes no other connection, grants nothing, and does not refresh or
replace the last accepted route fact. A duplicate/lower sequence is
`protocol.duplicateMessage`; a gap, changed route ID/class, wrong connection,
wrong phase, unknown class, or invalid bound is `protocol.invalidFrame` and
closes the offending connection under the primary-session protocol policy.

No endpoint, hostname, address, interface, DNS result, VPN or overlay-provider
identity, peer, traffic count, relay, credential, or raw platform error appears
in the message, local status, audit event, diagnostic export, or evidence.

## Freshness and ownership

The host samples its own monotonic clock only after admission. An accepted
observation is fresh through the inclusive deadline 30,000 milliseconds after
that sample. A later snapshot withdraws it exactly once. Clients send a new
strictly sequential observation after at most 15 seconds while the same route
and primary connection remain active.

Primary replacement, connection close, logout, disable, suspension,
revocation, Agent stop, or boot change withdraws the connection-owned fact
immediately. A delayed observation from an old connection cannot refresh the
new owner. A new primary connection begins again at sequence one and may use a
different configured route ID/class.

The resulting local route label is informational. Every command continues to
require the current authenticated principal plus the existing durable grant,
policy, epoch/revision, provider, host-state, approval, and execution fences.

## Fixture authority

`spec/fixtures/valid/route-observation-private-dns.json` and
`route-observation-ack-private-dns.json` fix the wire exchange.
`spec/fixtures/authenticated-route-observation-v0.1.json` fixes initial
acceptance, heartbeat, replay, mismatch, replacement, disconnect, and exact
inclusive expiry behavior. Invalid class and zero-sequence fixtures fail
closed. Implementations may not add a wire/status adapter until these fixtures
are indexed and verified.

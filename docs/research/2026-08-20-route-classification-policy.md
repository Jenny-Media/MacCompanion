# Route-classification policy research — 2026-08-20

Status: design finding and implementation boundary. Automatic private-DNS or
private-network-provider classification from a generic Network.framework path
is **no-go**.
The bundle-independent closed route authority remains valid, but concrete
sources must provide stronger product-owned evidence.

## Primary-source findings

Apple defines [`NWPath`](https://developer.apple.com/documentation/network/nwpath)
as the properties of a path available to the process. `status == .satisfied`
means connections can use a path; `supportsDNS` means a DNS server is
configured; neither proves that a Mac Companion hostname resolves to this Mac
or that the phone can reach the Agent listener.

Apple's discussion of
[`nw_path_uses_interface_type`](https://developer.apple.com/documentation/network/nw_path_uses_interface_type%28_%3A_%3A%29)
states that a path may report an interface type because it routes directly,
routes through a tunnel over a physical interface, or is eligible for multiple
interfaces. Therefore Wi-Fi/Ethernet does not prove LAN routing, and `.other`
does not prove a particular VPN.

Tailscale documents
[three macOS variants](https://tailscale.com/docs/concepts/macos-variants): a
Mac App Store Network Extension, a standalone System Extension, and open-source
`tailscaled` using `utun`. A process/interface-name probe would therefore be
variant-specific and brittle. The supported
[`tailscale status --json`](https://tailscale.com/docs/reference/tailscale-cli#status)
surface is machine-readable but explicitly has a format subject to change and
contains peer, user, machine, address, traffic, and relay metadata that local
Mac Companion status must not ingest or retain.

The open-source Tailscale
[`safesocket`](https://github.com/tailscale/tailscale/blob/main/safesocket/safesocket.go)
code also shows distinct Unix-socket versus sandboxed-macOS local TCP/token
mechanisms. Mac Companion must not couple its release Agent to those internal
transport details merely to display a route badge.

## Policy

- A default satisfied path, Wi-Fi/Ethernet use, `.other`, configured DNS,
  interface name, process presence, or installed Tailscale app is insufficient
  to publish any Mac Companion route kind.
- `lan` may be published only from product-owned listener plus local-discovery
  readiness evidence, and must still mean “locally advertised candidate,” not
  guaranteed phone reachability.
- `privateDNS` and provider-neutral `privateNetwork` may be published only
  after a locally configured candidate of that class completes Mac Companion's
  pinned TLS and application authentication. The label remains
  routing/presentation metadata and never becomes authorization. Tailscale,
  ZeroTier, WireGuard, and later providers do not become protocol identities.
- Until that authenticated-route fact exists in a fixture-backed protocol,
  local status leaves those classes absent. The UI may still offer setup
  guidance without claiming availability.
- No route diagnostic or evidence artifact records addresses, DNS or machine
  names, interface identifiers, peers, tailnet identity, traffic counters,
  relay locations, credentials, or raw platform errors.

## Consequence

There is no value in a generic `NWPathMonitor` classifier probe at this stage:
it cannot establish the product facts required by the policy. The listener and
Bonjour registration callbacks are now composed for the narrow `lan` fact.
The useful next route work is to specify a fixture-backed authenticated
route-class fact after the primary client connection path is ready. It can
proceed without a Tailscale SDK or Mac-side integration.

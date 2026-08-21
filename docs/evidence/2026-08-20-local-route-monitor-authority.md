# Local route-monitor authority evidence — 2026-08-20

Status: bundle-independent ordering and freshness evidence under Xcode 27
beta. This is not a concrete `NWPathMonitor`, a live LAN/private-DNS/Tailscale
classification, a signed process, or physical route evidence.

`AgentLocalRouteMonitorAuthorityV1` is a content-free projection seam for
source-specific route authorities. Its public state can contain only `stopped`,
`observing`, or `unavailable`; a generation; the closed `lan`, `privateDNS`, and
`privateNetwork` set; and monotonic observation/freshness times. Address, hostname,
interface, peer, credential, Bonjour text, tailnet identity, and raw error
values are unrepresentable.

Every accepted source event advances one safe-integer generation. Times cannot
regress behind either a source event or a freshness read. Exact listener plus
Bonjour LAN evidence is event-owned. The current authenticated configured-route
contribution remains fresh through its inclusive 30-second deadline; the first
later read removes only that contribution and later reads are idempotent. A LAN
event cannot extend configured-route freshness, and a configured-route
heartbeat cannot extend or expire LAN evidence. An empty aggregate route set
and explicit monitor failure publish `routeUnavailable`. Intentional stop
clears the route-source warning so a disabled monitor is not reported as a path
failure.

Route fields now have their own status update rather than sharing the paired
device/provider inventory update. The status actor independently fences route
generations. This matters across actor reentrancy: if generation two reaches
the status sink before a suspended generation one callback completes,
generation one is rejected and cannot roll status backward. Listener-owned
network state and warnings, paired/provider counts, security posture,
lifecycle, and audit health remain untouched by route publication.

Nine focused projection/authenticated-source tests prove path appearance,
disappearance, recovery, explicit monitor failure, intentional stop, inclusive
source-scoped freshness and one-time expiry, LAN preservation, primary-owner
replacement fencing, invalid/unsafe/regressed time isolation, and delayed
generation rejection. The public repository gate passed 60 indexed fixtures,
all 717 Swift tests including 90 `CompanionAgent` tests, macOS and
iOS Simulator compile lanes, all three no-network probe builds, and diff
hygiene.

Acceptance still requires a separately reviewed classification policy and
physical evidence for each published route kind. In particular, the authority
does not assume that an arbitrary `.other` interface proves Tailscale, that a
DNS server proves private-DNS reachability, or that an available default path
proves LAN listener reachability.

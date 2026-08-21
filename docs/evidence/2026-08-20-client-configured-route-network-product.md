# Client configured-route Network product evidence — 2026-08-20

## Claim

The release client now has a product construction path above its sealed
session-key reconnect runtime.

`NetworkClientConfiguredRouteApplicationProductFactoryV1` accepts one selected
host ID, durable paired-host inventory, durable route persistence, and the
public reconnect runtime. It reads and reconciles the exact host/route state,
constructs the reconnect controller only through
`NetworkClientConfiguredReconnectCompositionV1`, fixes initial scheduling to
background and unreachable, and binds system route/round identifiers plus the
same runtime monotonic clock. Failure returns no binding or product.

On iOS, `UIKitClientConfiguredRouteNetworkProductFactoryV1` consumes that
complete product and constructs the default Boolean-only coarse-reachability
application owner. The returned product exposes the owned route lifecycle for
local settings edits and the one UIKit owner for start/stop. It has no route,
DNS, interface, VPN, installed-app, or provenance inference API.

Pairing is deliberately not a prerequisite. The separate sealed pairing owner
can scan and commit a first host before any configured-route product exists.

## Automated evidence

Two focused tests prove that:

- exact durable paired identity and route revision produce a reconciled
  background/unreachable product with the expected immutable pin/candidate and
  no signer or network work; binding start remains ineligible until later local
  scheduling facts arrive, and close tears down the lifecycle;
- missing paired identity or route state fails before a product is returned.

The concrete UIKit factory cross-compiles for the arm64 iOS Simulator through
the public `CompanionClientPlatform` target. The complete unsigned gate validates
60 indexed fixtures, 678 repository files, dependency/privacy/SBOM/release
policies, 920 Swift tests, both platform cross-compiles, and three no-network/
no-prompt probes.

## Deliberate limits

This is not permanent-target or physical evidence. Final container/file
protection, Keychain access group, UIKit lifecycle, real Network.framework
reachability, Wi-Fi/airplane/background behavior, route editing, and live pinned
reconnect still require the signed iOS target and physical devices.

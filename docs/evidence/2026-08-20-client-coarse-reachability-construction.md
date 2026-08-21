# Client Coarse Reachability Construction Evidence

Date: 2026-08-20

Environment: bundle-independent Swift tests and an iOS Simulator cross-compile
with Xcode 27 beta. This is source construction and compile evidence. It is not
signed-target, physical-device, live-route, Local Network permission, or
release evidence.

## Boundary

`NetworkClientCoarseReachabilitySourceV1` is an application-global,
main-actor-owned `NWPathMonitor` adapter. Its public data plane is exactly one
`AsyncStream<Bool>`:

- `true` only when `NWPath.Status` is `satisfied`;
- `false` for `requiresConnection`, `unsatisfied`, and unknown future values;
- no value before the first real monitor callback.

The source accepts no endpoint. It exposes no interface type, address, DNS,
VPN, installed-app, expensive/constrained-path, or route-provenance metadata.
It therefore can suppress futile scheduling but cannot select, classify, rank,
or authorize a route. Product composition must pass initial reachability as
`false` and let the first event unlock eligibility.

The source starts once, rejects restart, cancels idempotently, finishes its
stream on stop, and drops callbacks outside the running phase. The stream keeps
only the newest unconsumed Boolean, while the serial application binding
deduplicates repeated values and owns dial eligibility.

## Verification

Two injected-monitor tests prove:

1. there is no optimistic initial event; satisfied maps to `true`; both
   requires-connection and unsatisfied map to `false`; stop finishes the
   consumer and cancels exactly once; and
2. duplicate start and restart-after-stop are rejected, stop is idempotent, and
   a callback after stop cannot publish an event.

`CompanionClientPlatform` also cross-compiles for the iOS 17 Simulator triple
with the concrete Network.framework owner and status switch. The hardened
repository gate passes 60 indexed fixtures and 751 Swift tests, both iOS
compile targets, the macOS UI compile, and all three no-prompt construction
probes.

## Remaining gates

- Instantiate the [composed application-global owner](2026-08-20-client-network-application-owner-construction.md)
  in the future permanent signed iOS target; do not create one owner or source
  per SwiftUI scene.
- Physically prove airplane-mode, Wi-Fi loss/recovery, foreground/background,
  and private-route-unavailable behavior. A globally satisfied path must never
  be presented as proof that a configured host route is reachable.
- Measure reconnect suppression and recovery latency without logging endpoint
  or interface metadata.
- Stable Xcode 26.6 and final identity/signing evidence remain separate release
  gates.

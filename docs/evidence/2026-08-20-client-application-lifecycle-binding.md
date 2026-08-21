# Client Application Lifecycle Binding Evidence

Date: 2026-08-20

Environment: bundle-independent Swift package tests plus an unsigned iOS
Simulator harness on iOS 27.0 with Xcode 27 beta. This is construction,
ordering, and Simulator lifecycle evidence. It is not signed-product,
physical-device, live-network, or release evidence.

## Construction

`ClientConfiguredRouteApplicationBindingV1` is the single serial boundary
between application scheduling facts and one
`ClientConfiguredRouteLifecycleV1`. It accepts only:

- one explicit start event;
- foreground/background state;
- one injected reachable/not-reachable fact; and
- close.

It cannot discover, classify, add, replace, or infer a route. Pending events
may synchronize the lifecycle but cannot dial. A round starts only after the
binding is running, foreground, and reachable. The lifecycle then revalidates
the durable paired identity and reconciles the durable configured-route
revision before it hands any candidate to the reconnect owner.

The binding serializes events across actor suspension, starts at most one round
per eligible interval, re-arms only after foreground or reachability becomes
false, and closes the complete lifecycle on invalid time, invalid round
identity, or a lifecycle transition failure.

`UIKitClientConfiguredRouteApplicationBridgeV1` is a main-actor adapter. It
uses application-active notifications rather than one arbitrary SwiftUI scene
because the reconnect owner is application-global. Reachability remains an
injected `AsyncStream<Bool>`; the adapter has no DNS, interface, VPN,
installed-app, or route-provenance authority. Applied state is projected back
through a main-actor callback for UI observation. That snapshot now includes
the exact validated lifecycle composition from the same owner; consumers no
longer need to combine binding booleans with a separate route read. A
content-free latest-one wakeup also carries controller-internal completion to
the bridge's serialized event tail; the callback itself carries no route or
trust facts and merely causes a complete snapshot re-read.

## Verification

Four package tests prove:

1. pending and background states never dial, duplicate eligible facts do not
   start duplicate rounds, background closes the authenticated route, and a
   later foreground transition re-arms one round;
2. a durable route revision replaced after lifecycle construction but before
   application start is reconciled, and only the replacement route reaches the
   dial boundary; and
3. an invalid local monotonic time closes both binding and lifecycle without a
   dial.
4. an invalid injected round identifier closes both binding and lifecycle
   without a dial; and
5. binding snapshots carry coherent initial background ownership and complete
   closed lifecycle/reconnect/controller state.

The disposable `ClientUIHarness` composes the real binding and UIKit bridge
with a temporary durable route store and synthetic authenticated dial results.
Its lifecycle UI test begins unreachable with zero rounds, renders the real
provider-neutral private-access state, injects reachability and observes round
one, presses Home, reactivates the app, and observes exactly round two. No
socket, private key, Keychain item, or permanent identity is present. The
complete current harness run passed 6 tests with 0 failures.

The hardened repository gate also passed with 60 indexed fixtures, 751 Swift
tests, both iOS compile targets, the macOS UI compile, and all three no-prompt
platform construction probes.

## Remaining gates

- Bind the [constructed coarse Network.framework source](2026-08-20-client-coarse-reachability-construction.md)
  in the future permanent signed target. It may suppress futile scheduling,
  but must not classify routes or authorize transport.
- Prove the same ordering on signed physical iOS builds with real durable
  custody and live private routes.
- Measure foreground reconnect and route-fallback latency on the supported
  physical device matrix.
- Stable Xcode 26.6 and final identity/signing evidence remain separate release
  gates.

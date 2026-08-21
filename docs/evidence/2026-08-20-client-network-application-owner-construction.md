# Client Network Application Owner Construction Evidence

Date: 2026-08-20

Environment: bundle-independent Swift package construction plus an unsigned
iOS Simulator harness on iOS 27.0 with Xcode 27 beta. This is lifecycle,
failure-containment, and Simulator evidence. It is not permanent-target,
signed-product, physical-device, live-network, or release evidence.

## Construction

`UIKitClientConfiguredRouteNetworkApplicationOwnerV1` is the single intended
application-global owner of:

- one Boolean-only `ClientCoarseReachabilitySourceV1`;
- one `UIKitClientConfiguredRouteApplicationBridgeV1`; and
- one already-constructed `ClientConfiguredRouteApplicationBindingV1`.

The owner has no endpoint, route-catalog, interface, DNS, VPN, installed-app,
or provenance API. Its default source is the concrete scheduling-only
Network.framework adapter, while the protocol permits deterministic disposable
and test sources without broadening the data plane.

Startup is fixed:

1. start the one-owned coarse source;
2. mark the owner running;
3. start the UIKit bridge with initial reachability forced to `false`;
4. synchronize application activity and lifecycle startup; and
5. consume the newest buffered source event.

This guarantees that no optimistic path value can bypass durable identity and
route reconciliation. The owner rejects reuse. Normal stop first stops and
finishes reachability, then asks the bridge to close the binding and lifecycle.

The bridge now treats its first binding error as terminal: it removes UIKit
observers, cancels reachability consumption, stops accepting queued events, and
reports one failure. The application owner then stops the source and closes its
own phase. A failed source start follows the same owner-level terminal path.

## Verification

The disposable `ClientUIHarness` now uses the composed owner with a manual
Boolean source and synthetic authenticated dial outcomes. Four UI tests pass:

1. every closed product surface remains accessible;
2. the host projection changes from Ready to No Network;
3. reachable starts round one, Home/reactivation starts exactly round two, and
   no terminal failure is reported; and
4. an injected zero round ID makes the first reachable event terminal, reports
   exactly one failure, starts zero rounds, and ignores a later reachability
   attempt.

The final result bundle is under
`/private/tmp/maccompanion-client-ui-owner-final-derived/Logs/Test/` and reports
4 passed, 0 failed, 0 skipped, and no runtime warnings.

The package-level binding tests separately prove pending/background suppression,
durable revision reconciliation, invalid-clock closure, and invalid-round-ID
closure. Coarse-source tests prove closed status mapping and source lifecycle.
The concrete owner and bridge cross-compile for the iOS 17 Simulator triple.

## Remaining gates

- The package now supplies a [store-bound configured-route Network product](2026-08-20-client-configured-route-network-product.md) and iOS factory that
  construct exactly one default owner from durable identity/routes and the
  sealed reconnect runtime. Instantiate that product in the future permanent
  signed iOS app target after final identity decisions.
- Prove real Network.framework callbacks, airplane mode, Wi-Fi loss/recovery,
  foreground/background, and configured private-route failure on physical
  devices.
- Prove app termination/relaunch with durable identity and route state; normal
  lifecycle shutdown must call `stop()` explicitly.
- Stable Xcode 26.6 and final signing evidence remain separate release gates.

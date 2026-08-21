# Client configured reconnect composition — 2026-08-20

Status: bundle-independent revision owner, durable edit-to-runtime service,
first-pairing bootstrap authority, client lifecycle composition, serialized UI
adapter, package-level local configuration UI, and compile-checked concrete
Network.framework composition under Xcode 27 beta. Native scene/reachability
event binding, rendered/signed UI evidence, and physical routes remain open.

`ClientReconnectConfigurationV1` joins one immutable durable paired-host
identity to exactly one configured-route snapshot. It rejects a mismatched host
ID and derives both the ordered reconnect candidates and provenance catalog
from that same revision. Its reconnect-state factory carries only the paired
host fingerprint as identity evidence; route text and provenance remain
routing and presentation inputs.

`ClientConfiguredReconnectOwnerV1` owns the complete controller for one such
revision. Replacement requires the same exact paired identity and a strictly
newer catalog revision, constructs and validates the replacement controller,
then idempotently shuts down the old controller before publishing the new one.
The owner rejects overlapping transitions, so foreground/reachability updates,
dial starts, revision changes, and close cannot interleave across an `await`.
`ReconnectControllerV0.shutdown()` cancels its exact round, clears its round
generation, closes its authenticated route, rejects reuse, and closes any late
authenticated result through the existing stale-round fence.

`NetworkClientConfiguredReconnectCompositionV1` is the concrete construction
path. It creates every `NetworkClientRouteAttemptV0` from the same
configuration's client, host, device, pin, ordered candidates, and immutable
catalog. Runtime clock, randomness, queues, signer, callbacks, and retry policy
remain injected; none can substitute a route catalog or paired identity.

Local edits use the closed `ClientConfiguredRouteEditIntentV1` add, replace,
and remove cases. Add and replace require an explicit provenance and reuse the
catalog's exact endpoint-kind validation. The editor has no API for DNS suffix,
resolved-address, interface, process, installed-app, or route inference. Each
successful edit advances exactly one bounded revision, preserves route order,
and retains an opaque ID across replacement. An exact no-op replacement is
rejected instead of consuming a revision.

`ClientConfiguredRouteUpdateServiceV1` is the sole edit-to-runtime boundary.
It verifies that durable storage and the live reconnect owner begin at the
same host, identity pin, ordered candidates, and revision. It applies one
closed intent, commits that revision atomically, and only then replaces the
runtime controller. A failure before rename preserves the exact prior runtime;
if publication may have advanced, or activation after commit fails, the old
runtime is closed rather than permitted to dial stale routes. Its explicit
startup reconciliation advances a durably newer revision before reuse and
fails closed on regression or mismatch.

`ClientConfiguredRouteBootstrapPlanV1` automatically classifies only a
Bonjour service as local discovery and an RFC 1918 IPv4 or IPv6 ULA literal as
a direct private address. DNS and public literals require one explicit local
choice. `ClientRouteConfigurationProjectionV1` and the iOS SwiftUI
`ClientRouteConfigurationViewV1` expose only endpoint-compatible alternatives
and emit the same closed intents without starting discovery, resolution, or
network activity.

`ClientConfiguredRouteLifecycleV1` loads one exact validated paired identity
and route snapshot, constructs the reconnect/update authorities, and reconciles
storage before exposing any dial method. Every round revalidates the durable
identity and reconciles the route revision first. Backgrounding closes the
connected route and denies new rounds while retaining a restartable
composition; missing, changed, or unreadable identity state closes the whole
authority. The atomic paired-host store implements the narrow exact-host
inventory lookup without exposing private-key bytes.

`ClientRouteConfigurationIntentAdapterV1` serializes app edits and publishes a
UI snapshot only after durable commit and live activation both succeed. It
rejects a reentrant edit while publication is pending. The one-shot bootstrap
authority has only an injected catalog-commit effect and no reconnect/network
capability, so cancellation cannot publish a catalog or start a connection.
Both SwiftUI route surfaces are value-driven and emit state changes or closed
domain intents; they require no `@State` macro and pass the ordinary sandboxed
iOS Simulator compile gate.

Focused tests prove exact old-route retirement, new-revision candidate
publication, stale-revision and mixed-identity rejection, invalid factory
shutdown, idempotent controller shutdown/reuse denial, explicit edit ordering,
no-op and provenance mismatch/unknown/final-route denial, both sides of the
rename boundary, post-commit activation failure, externally published revision
reconciliation, conservative first-pairing classification, cancellation with
zero publication, lifecycle reconciliation/background/identity-loss behavior,
serialized post-activation UI publication, and closed UI projection/draft
behavior. The hardened public gate passes 60 indexed fixtures and 744 Swift
tests, iOS Simulator client-platform and client-UI compiles, the
macOS UI compile, all three no-network probe builds, and `git diff --check`.
SwiftPM user-cache warnings are expected in the restricted environment.

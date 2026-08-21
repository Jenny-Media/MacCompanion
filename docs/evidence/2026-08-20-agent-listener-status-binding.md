# Agent listener-to-status binding evidence — 2026-08-20

Status: bundle-independent construction and injected test evidence under Xcode
27 beta. This is not a live listener, authenticated XPC, final signing, Local
Network permission, or physical-device evidence.

The sealed `AgentNetworkListenerServiceV1` production initializer now requires
the `AgentLocalServiceRootV1` network-only status facet. It cannot receive the
raw coherent status authority. Exact listener transitions publish only the
closed network state, zero-or-one active-primary count, and the existing
`routeUnavailable` warning; no endpoint, peer identity, TLS metadata, address,
or error text enters local diagnostics.

The service installs a revision callback on its owned handoff before starting.
Every pending, binding, active, replacement, terminal, and cancellation
mutation advances that callback. The service ignores delayed older handoff
revisions and projects the current combined listener/handoff snapshot, so the
active count is not sampled only at acceptance time.

Before sampling a possibly suspending snapshot, each publication reserves a
monotonic generation from the root publisher. The coherent status authority
accepts only a strictly newer generation. A publication that finishes after a
newer fact therefore fails closed instead of rolling status backward. This
same ordering covers ready, listener loss, intentional cancellation, and
accepted-connection start-failure warning removal.

Status publication errors are caught and reduced to one closed local failure
class. They do not enter listener admission decisions, create authority, retain
a connection, skip listener/handoff cancellation, or replace a transport
terminal reason. Injected tests prove starting/listening/active/stopped
projection, handoff-originated active-count change, unique increasing
publication generations, operation with an always-failing status sink, and
complete teardown after that failure. A separate authority test publishes a
newer generation first and proves the delayed older generation cannot restore
degraded/zero-session facts.

The public validation gate passed 54 indexed fixtures, all 690 Swift tests
including 77 `CompanionAgent` tests, Network and Mac UI builds, iOS Simulator
client-platform and client-UI builds, all three no-network probe builds, and
`git diff --check`. SwiftPM user-cache warnings are expected in the restricted
environment. Stable Xcode 26.6, final identities, signed listener execution,
and physical LAN evidence remain required for acceptance.

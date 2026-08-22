# Authenticated menu product composition evidence

Date: 2026-08-21

## Outcome

The completed Agent sender, generation router, menu receiver, dashboard owner,
and prepared Agent root now meet at package-owned product seams without making
either permanent executable active. The construction preserves the independent
Observe path: losing or replacing the menu generation removes visible review
delivery, but it does not itself terminate an already composed primary Agent
root or infer a Control grant.

## Agent ordering

`MacLocalXPCAgentProductV1.composeWithMenuPresentation` selects the explicit
readiness/status/presentation profile only inside package construction. Its
ordered lifecycle pump first requires an accepted menu-ready lifecycle receipt,
then asks the exact current server generation for its cached opaque sender
endpoint. The endpoint is bound through
`MacLocalXPCAuthenticatedMenuSurfaceRouterV1`; an absent endpoint, router
failure, or surface-consumer failure cancels only that exact peer. Failed
lifecycle admission requests transport cancellation before any secondary
disposition observer may suspend. An authenticated replacement revokes the
previous ready generation immediately, before the replacement can publish
readiness. Endpoint-originated terminal fencing likewise removes the exact
downstream authority and cancels the exact peer without waiting for a later
transport event.

`MacAgentAuthenticatedMenuSurfaceAuthorityV1` is the stable narrow authority
retained by the one-use prepared primary root. It exposes only pairing-review
and host-recovery presentation protocols. Strict increasing generations,
exact invalidation, terminal waiter completion, and post-suspension stale
checks prevent rollback or late presentation across a menu replacement. A
menu restart can install a later generation without rebuilding the durable
Agent identity or silently converting the loss into whole-product shutdown.
Cancellation wins over a racing availability install, and overlapping network
composition calls reserve the one-use preparation before their first actor
suspension.

The public real-custody bootstrap now prepares this presentation-aware local
XPC product, but the returned `MacAgentPreparedProductV1` remains inert. Its
package activation seam starts local authorization, waits for an exact ready
menu generation, and only then consumes the sealed TLS/primary preparation into
an unstarted network pairing product. No listener or QR context is constructed
before that authorization. Reuse, pre-authorization consumption, and terminal
restart fail closed. The composed network authority cannot escape its prepared
lifecycle owner. Product finish converges any in-flight composition,
retires the network aggregate if it exists, finishes local XPC, terminates
surface waiters, and consumes the preparation once.

Menu loss has a distinct nonterminal convergence path. It withdraws and
cancels a publishing or visible pairing review, permits an in-flight durable
decision to converge, and permits a later authenticated generation to publish
a fresh review while listener, primary ingress, QR context, and Observe
ownership remain intact.

## Menu ordering

`MacLocalXPCDashboardProductV1` has a release-shaped constructor accepting only
the menu-owned pairing-review and host-recovery presenters. It constructs the
production `MacLocalXPCClientV1` with those surfaces while remaining inert
until `start()`. Dashboard finish now calls the client's awaitable receiver
retirement witness, so exact retained review withdrawal completes before the
dashboard owner is retired. Test doubles must implement the same barrier; no
cancel-only fallback can accidentally satisfy the product protocol.

## Verification

Focused Xcode 27 beta package runs pass 94 `CompanionAgentPlatform` tests, 10
`CompanionAgentProductPlatform` tests, and 200 `CompanionAgent` tests. New cases prove accepted-readiness-only
endpoint binding, the exact presentation profile, missing-endpoint peer
cancellation, endpoint-terminal propagation, replacement-before-readiness
revocation, awaited dashboard receiver retirement, unavailable/rollback/
terminal stable-authority behavior, stale suspended-presentation compensation,
availability waiter completion and cancellation, authorization-before-one-use
primary consumption, deterministic concurrent composition, nonescaping
unstarted network construction, nonterminal visible-review cancellation and
replacement, in-flight decision convergence, reuse rejection, and terminal
network cleanup.

The complete repository gate passes across 914 repository files, 1,073
historical blob paths, 299 Swift source files, 64 indexed fixtures, 14 privacy
source records, 1,298 unique package tests, every supported cross-build, and
all platform probes. A fresh unsigned Xcode 27 beta application build also
succeeds and contains the Mac Companion executable, embedded Agent executable,
and expected LaunchAgent property list. Signed runtime acceptance remains an
external gate.

## Explicit non-claims

No permanent target imports or invokes `CompanionAgentProductPlatform`; the
Agent main remains `.authenticationOnly` and the menu app remains the truthful
unavailable shell. This checkpoint does not start the network listener, create
a pairing QR, resolve menu-to-Agent approval or recovery commands, activate
Control, register login items, change signing or entitlements, or prove a live
signed two-process exchange. Stable-Xcode, final-identity, managed-entitlement,
notarization, and physical-device evidence remain separate gates.

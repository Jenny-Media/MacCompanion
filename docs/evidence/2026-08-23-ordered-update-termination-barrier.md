# Ordered update termination barrier

Date: 2026-08-23

Status: package behavior and permanent-app source composition pass on Xcode 27
beta. No app, Agent, listener, local-XPC service, login role, TCC surface,
network connection, Sparkle download, or installer was started.

## Outcome

The foreground update-installation owner now treats application termination as
a barrier. Before runtime shutdown, termination is an ordinary cancellation:
the prepared reply resolves skip and the authority closes. During shutdown,
termination reports foreground loss to the coordinator and waits for handed-
off, cancelled, or failed terminal state. It cannot return while network or
Agent recovery is still in flight.

The permanent AppKit delegate now returns `terminateLater` for ordinary
termination. Its ordered task cancels and joins any Sparkle validation
lifecycle, cancels the exact correlation, waits for launch convergence,
finishes the product dashboard, and only then calls
`reply(toApplicationShouldTerminate: true)`. `applicationWillTerminate` is a
fallback into the same idempotent task rather than the cleanup authority.

The Sparkle adapter does not yet retain an installation application, so its
termination preparation currently covers informational and validation state.
The eventual ready-callback binding must join the already proven installation
barrier before installation is enabled.

## Verification

Five focused application-owner tests pass. The termination race suspends the
second gate observation after confirmation, requests application termination,
verifies no install/skip reply races early, then releases the observation. The
authority fails closed, emits skip, reaches a sanitized terminal failure, and
the termination waiter returns with no network or Agent effect. The permanent-
target validator requires the terminate-later order and explicit reply.
The complete repository gate passes 73 authoritative fixtures, 35 update-
policy fixtures, every supply-chain, privacy, SBOM, signing, packaging,
release-evidence, permanent-target, and cross-platform validator, 1,603
MacCompanionKit tests, and 8 platform-probe tests on Xcode 27 beta.

## Deliberate non-claims

This is orderly AppKit termination, not SIGKILL, crash, power-loss, or kernel
failure evidence. The ready callback and confirmation presentation remain
unbound. Signed two-version execution, forced process loss at each shutdown
phase, stable Xcode 26.6 repetition, and physical confirmation UX remain
release gates.

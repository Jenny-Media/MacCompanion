# Coordinated Agent network-listener activation evidence

Date: 2026-08-21

## Outcome

The prepared Agent product now retains construction, start, and teardown of
the shared network listener behind the same nonescaping lifecycle owner as the
authenticated local-XPC product and one-use primary preparation. This closes
the package-level activation and rollback seam without activating either
permanent executable.

## Ownership and ordering

Network composition is still admitted only after local XPC has started and an
exact authenticated menu generation is available. The resulting listener-free
network product never escapes `MacAgentPreparedProductV1`. A package-owned
preparation operation constructs the exact sealed listener service from that
retained product and retains only its narrow lifecycle interface. A separate
one-use activation operation starts that exact retained service.

The concrete construction overload requires explicit primary and pairing
request-context factories, one monotonic clock, one queue, and closed terminal
and admission callbacks. It delegates listener/Bonjour readiness exclusively
to `AgentNetworkListenerServiceV1`; successful return from `start()` does not
invent listening or advertisement evidence.

Listener construction and start are single-flight. Concurrent or repeated
activation is rejected before another listener can be constructed. Product
finish cancels an admitted activation task, converges any service it produced,
cancels that listener before terminal network teardown, then finishes local
XPC, the stable menu authority, and the prepared primary root. A listener-start
failure runs the same whole-product rollback and cannot leave the one-use
network root reusable.

Menu-generation loss remains deliberately nonterminal after listener
preparation or start:
it cancels only local review delivery and pending decisions. The shared
listener and primary/Observe path stay owned and active; pairing review cannot
complete again until a later authenticated menu generation is installed.

## Verification

The focused Xcode 27 beta ProductPlatform suite passes 11 tests. New coverage
proves that listener preparation is unavailable before network composition,
constructs the exact sealed service after composition, rejects reuse, retains
that idle service across menu-generation replacement, and cancels it during
whole-product finish. Narrow runtime-owner coverage separately proves that an
injected start failure and caller cancellation while start is suspended both
converge to one terminal listener cancellation, that runtime cancellation is
issued before finish waits for the admitted start barrier, and that duplicate
or concurrent start attempts do not cancel the incumbent. The product test
invokes the exact production terminal-handler wrapper and proves it converges
with a later explicit finish.

The concrete listener-service suite passes 15 tests. Its new deterministic
start-versus-cancel regression suspends handoff installation, cancels the
service, and proves terminal state plus zero native listener starts both before
and after the suspended installation resumes.

The complete repository gate covers 915 repository files, 1,092 historical
blob paths, 299 Swift source files, 64 indexed fixtures, 14 privacy source
records, 1,300 unique package tests, every supported cross-build, and all
platform probes. A clean code-signing-disabled Xcode 27 beta build of the
permanent Mac application and embedded Agent also succeeds from the checked-in
project after the repository gate.

## Explicit non-claims

No permanent target imports or invokes `CompanionAgentProductPlatform`; the
Agent main remains `.authenticationOnly` and the menu app remains the truthful
unavailable shell. This checkpoint does not supply the final live console-
session request-context source, activate the permanent listener, create a
pairing QR, register login items, change signing or entitlements, or prove a
signed two-process exchange. Stable-Xcode, final-identity, managed-entitlement,
notarization, and physical-device evidence remain separate gates.

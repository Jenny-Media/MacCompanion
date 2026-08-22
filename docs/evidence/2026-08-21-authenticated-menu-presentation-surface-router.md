# Authenticated menu presentation-surface router evidence

Date: 2026-08-21

## Scope

MacLocalXPCAuthenticatedMenuSurfaceRouterV1 converts one already-authenticated
menu transport generation into exactly two package-only capabilities:
pairing-review presentation and host-identity-recovery presentation. It does
not expose a caller role, authentication flag, transport endpoint, grant
decision, recovery executor, Control authority, or any raw XPC payload.

The router authorizes only the three existing Agent-to-menu presentation
methods: publishPairingReview, publishHostIdentityRecoveryReview, and
publishHostIdentityRecoveryResume. It does not add those messages to the XPC
profile or claim that a concrete endpoint exists.

## Generation and retirement fences

- generations are positive, strictly increasing high-water values;
- an exact endpoint/generation retry shares its activation barrier and may
  receive new facets with the same private issuance token;
- weak accepted-endpoint identity history prevents active or retained retired
  endpoint objects from representing another transport generation without
  keeping retired transports alive;
- conflicting duplicates invalidate their candidate, while rollback,
  retired-generation reuse, terminal state, and invalid numeric generations
  fail before endpoint construction;
- every facet call carries both the transport generation and private issuance
  token, then revalidates after any endpoint acknowledgement;
- a late presentation acknowledgement is compensated by exact withdrawal;
- replacement retires the prior endpoint before the new facets return;
- invalidation and external finish share serialized retirement barriers; and
- completed nonterminal cleanup barriers are released instead of retaining an
  unbounded task chain.

Endpoint invalidation receives a distinct terminal-fence capability exposing
only a non-waiting request. Numeric generation and method policy are checked
before candidate construction; duplicate endpoint identity is resolved before
a newly accepted endpoint receives its exact fence. Exact retries therefore
retain the original live fence, while rejected candidates receive none. The
fence's weak request closure does not retain the router and is bound to the
accepted generation and private token, so retired endpoints cannot terminally
fence replacement authority. External product lifecycle owners retain the
router's separate awaitable finish barrier. This type-level split avoids a
self-await even when the callback originates in a detached task, while
preserving complete-retirement semantics for the owner.

## Verification

Twenty focused tests pass under Xcode 27 beta. They cover the closed surface
set, exact duplicate replay, conflicting duplicates, high-water rollback
rejection, old-facet rejection, replacement and activation barriers, delayed
pairing/recovery acknowledgements, exact invalidation, concurrent finish,
invalidation/finish convergence, finish during replacement, re-entrant
same-generation invalidation, inline and detached finish requests, stale
accepted-endpoint and rejected-candidate terminal requests, exact-retry fence
preservation, active and retired cross-generation endpoint reuse rejection,
and active-fence request versus owner-retirement ordering.

The complete repository gate passes across 898 repository files, 293 Swift
source files, 1,243 unique package tests with zero duplicate names, all 8
platform-probe tests, 14 privacy source records, every policy validator, and
the supported iOS and macOS cross-builds. A fresh unsigned Xcode 27 beta build
of the Mac app and embedded Agent also completed with BUILD SUCCEEDED. The
build includes the already-linked CompanionLocalXPCPlatform product but adds no
new permanent-target dependency or router construction.

## Product boundary and next gate

The existing CompanionLocalXPCPlatform product already contains this source,
but no permanent application target constructs the package-only router. This
slice changes no project target, application source, product dependency, XPC
kind, parser, request/reply shape, Keychain path, listener, login item, network
authority, pairing decision, recovery execution, or runtime activation.

The next safe lane is to add strict bounded pairing/recovery presentation XPC
messages and a concrete generation-owned endpoint, then compose that endpoint
with the prepared Agent product under coordinated activation and rollback.
Signed runtime proof remains gated by final identities and signing.

# Local XPC menu-readiness binding

Date: 2026-08-21

Status: package construction and unsigned beta-toolchain evidence; permanent
Agent bootstrap instantiation and signed runtime remain open

## Constructed capability

The production local XPC profile now contains one explicit post-authentication
menu lifecycle request:

- request: exact `{"kind":"lifecycle.menu-ready","version":1}`;
- acknowledgement: exact
  `{"kind":"lifecycle.menu-ready.ack","version":1}`; and
- local authorization: `publishMenuReady`, permitted only from the
  authenticated menu app to the Agent.

The hello remains non-authorizing. The Agent creates an authenticated lifecycle
observation only after the exact hello acknowledgement is sent. It publishes
menu readiness only after the separate exact readiness acknowledgement is sent.
A premature, malformed, duplicate, late, or rejected readiness exchange cancels
the peer and cannot manufacture readiness.

`MacLocalXPCLifecycleBindingV1` adapts those generation-bound transport events
to the existing `MacAgentLifecycleObservationRootV1`. Its ordered event pump
uses one bounded `AsyncStream` consumer. Actor operation tokens fence every
suspending factory, readiness, invalidation, replacement, and shutdown path, so
a late continuation cannot restore retired authority. Queue overflow, delivery
after termination, and explicit shutdown stop transport input and invalidate
residual lifecycle authority instead of buffering without limit.

## Replacement and fail-closed behavior

A merely accepted transport candidate does not displace the current
authenticated peer. Only a candidate whose exact hello has been acknowledged
becomes current. At that boundary the Agent fences and cancels the old peer,
then emits the new authentication event. It does not emit an intermediate old
lifecycle invalidation, so a legitimate replacement cannot create a false
recovery transition.

Client callbacks carry an independent monotonic session generation. A delayed
cancel, hello reply, or readiness reply from a cancelled session is ignored
after restart. The server likewise assigns every listener start a monotonic run
generation and requires exact active-run plus retained-peer membership before
accepting any callback. It retains accepted peers explicitly, rejects an
incoming peer if its owner or listener run is gone, caps pre-hello candidates at
eight, and cancels each candidate after a generation-bound ten-second deadline.
Server and client public lifecycle methods detect re-entry on their own serial
XPC queue instead of synchronously redispatching to that queue. Shutdown fences
the run, initiates cancellation of every accepted peer and the listener, and
releases the peer requirement before publishing any invalidation callback.

Old cancellation and post-authentication messages are rejected by the exact
current-generation gate. They cannot clear or restore the replacement. The
existing lifecycle root atomically replaces the old menu observation when it
constructs the new one, and hello still leaves the replacement in `starting`
until its distinct readiness exchange succeeds.

If lifecycle connection creation or readiness publication fails, the binding
invalidates any retained lifecycle connection and returns `failedClosed` with
the exact transport generation. The event pump requires an explicit failure
handler. The permanent composition must wire that handler to
`MacLocalXPCServerV1.cancelPeer(generation:)`, which asynchronously cancels only
the still-current matching peer and cannot cancel a later replacement.

## Focused evidence

- All 20 `CompanionLocalXPCPlatformTests` pass. They cover closed hello and
  readiness gates, exact XPC scalar types and dictionary shape, publication
  only after acknowledgement, invalidation, candidate non-displacement,
  authenticated replacement, stale client/session callbacks, old-listener
  callbacks after restart, bounded pre-hello admission, and generation-bound
  deadline expiry.
- All 15 `MacLocalXPCLifecycleBindingV1Tests` pass. They cover hello without
  readiness, exact readiness/invalidation, replacement, rejected lifecycle
  receipts, failed replacement construction, suspended-readiness invalidation
  and replacement races, stale old invalidation during suspended replacement,
  suspended authentication invalidation, ordered event delivery, bounded-queue
  overflow, suspended-readiness shutdown fencing, transport-before-serialized-retirement liveness, shutdown cleanup, and
  fail-closed transport escalation.
- The exact local IPC role matrix and version-mismatch tests pass with
  `publishMenuReady` admitted only on `menuApp -> agent`.
- Existing lifecycle tests still prove that an authenticated menu connection
  does not claim readiness until explicit publication and that replacement
  fences old callbacks.
- The C bridge passes `clang -fsyntax-only -Wall -Wextra -Werror` against the
  Xcode 27 beta macOS SDK with a macOS 26 deployment floor.
- The public unsigned validation gate passes with 878 repository files, 17
  release-evidence fixtures, 284 Swift source files, and all 1,182
  `MacCompanionKit` tests, cross-compiles (including the Mac-only local-XPC
  product as an empty iOS module), platform probes, strict C bridge compilation,
  and permanent-target validation.
  It performs no signing, service registration, network access, or privacy
  prompt.
- A separate code-signing-disabled Xcode Debug build succeeds for the permanent
  Mac app and embedded Agent with the updated package graph. This is build
  evidence, not signed runtime or service-registration evidence.

## Deliberately open

The permanent Agent target starts the authenticated XPC server but does not yet
construct the complete startup-reconciled `AgentPrimaryServicesV1`, lifecycle
root, binding, or event pump. Instantiating this adapter without that complete
root would manufacture a partial readiness source. Its source therefore selects
the explicit `authenticationOnly` server profile, which rejects every
post-authentication request. The permanent-target validator requires that
profile and forbids the readiness profile until full Agent bootstrap
composition is available.

No status payload, pairing method, diagnostic method, action, lease, media,
input, surface, remote listener, service registration, or privacy authority is
issued by this checkpoint. The next local method is the existing content-free
`readAgentStatus` capability, bound to the same authenticated generation and
full Agent root. Signed permanent-target runtime, stable-toolchain repetition,
and live `SMAppService` registration remain separate gates.

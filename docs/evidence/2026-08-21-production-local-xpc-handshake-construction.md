# Production local XPC handshake construction

Date: 2026-08-21

Status: production target construction and unsigned build evidence on Xcode 27 beta;
signed permanent-target runtime, status, and broader method evidence remain open

## Constructed boundary

The permanent Mac Companion Agent now owns the Mach service
`media.jenny.maccompanion.agent`. Its embedded LaunchAgent property list
publishes that service, and the Agent starts a narrow local XPC server before
entering its process run loop.

`CompanionLocalXPCPlatformC` wraps the macOS 26 C-only XPC listener, session,
peer-requirement, message, reply, cancellation, and rich-error APIs behind
opaque references. `CompanionLocalXPCPlatform` provides the Swift ownership
and one-use handshake state machines used by the permanent targets.

Both endpoints are created inactive. Before activation:

- the Agent listener requires the same Apple team and exact menu signing
  identifier `media.jenny.maccompanion`;
- the Agent repeats that requirement on every incoming peer session; and
- the menu client requires the same Apple team and exact Agent signing
  identifier `media.jenny.maccompanion.agent`.

The only accepted pre-authentication request remains the exact closed
`{"kind":"hello","version":1}` dictionary. The Agent sends only the exact
`hello.ack` response. Malformed, repeated, late, or otherwise unsupported
messages cancel the peer.

## Publication and invalidation fence

Transport authentication and observable authenticated lifetime are separate
states. The Agent publishes `authenticatedMenu(generation:)` only after the
exact hello is accepted and its exact acknowledgement is sent successfully.
A cancellation publishes `invalidatedMenu(generation:)` only if that
authentication event was previously published, and it can do so only once.
Every event carries the connection generation so a later capability owner can
reject stale replacement callbacks.

The menu client similarly publishes authentication only after an exact
acknowledgement received through the Agent-bound session. Error, malformed
reply, cancellation, or explicit shutdown invalidates and releases the owned
session.

## Evidence executed

- Twenty focused `CompanionLocalXPCPlatformTests` pass, including cancellation
  before hello, reply failure before publication, exact one-use publication,
  repeated invalidation, malformed hello, client and listener generation
  fencing, bounded pre-hello admission, and generation-bound deadline expiry.
- The production C bridge compiles with `-Wall -Wextra -Werror` against the
  macOS 27 beta SDK at a macOS 26 deployment floor.
- The permanent-target validator proves the exact Mach service, both package
  dependencies, the narrow Agent startup, and the absence of remote listener,
  persistence, Keychain, or readiness construction.
- An unsigned Debug `MacCompanion` Xcode build succeeds and embeds the Agent
  executable plus LaunchAgent property list.

The public validation script now compile-checks both disposable signed-probe
sources and the production C bridge without signing, launchd mutation,
network access, or privacy prompts.

## Authority deliberately absent

An authenticated hello grants no status read, lifecycle readiness, pairing,
diagnostic, action, lease, media, input, or remote-listener authority. The Mac
application does not yet instantiate the client. The Agent creates no remote
listener, keys, stores, provider graph, or readiness state from this handshake.

The subsequent
[menu-readiness checkpoint](2026-08-21-local-xpc-menu-readiness-binding.md)
binds the first explicit lifecycle capability to the authenticated connection
generation and proves replacement, ordering, and fail-closed cancellation
seams. Content-free status transport and permanent Agent bootstrap instantiation
remain next. Persistent service registration remains an explicit user action
and was not performed by either construction.

Stable Xcode 26.6 and signed permanent-target runtime evidence remain release
gates; this beta-toolchain result is provisional.

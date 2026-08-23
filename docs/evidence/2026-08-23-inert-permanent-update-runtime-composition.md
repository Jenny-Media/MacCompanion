# Inert permanent update-runtime composition

Date: 2026-08-23

Status: focused package behavior and permanent-app source composition pass on
Xcode 27 beta. No app, Agent, listener, local-XPC service, login role, TCC
surface, network connection, Sparkle download, or installer was started.

## Outcome

The single-use install admission now exposes its already validated numeric
candidate build. `MacCompanionUpdateRuntimeCompositionV0` consumes that exact
value to construct the durable Agent-stop owner; it never reparses a build from
display version, archive URL, bundle metadata, or mutable Sparkle state.

The permanent composition requires the product's current dashboard route and
dashboard instance, passes that object as the typed close/drain command channel,
and obtains the bounded reopen/rebuild closure from the product router. Runtime
observations use `NSApp.isActive`, fail-closed monotonic uptime milliseconds,
and the menu-visible Control indicator. Indicator inactive maps to update
inactive, active maps to active, and stopping maps to cleanup-uncertain.

The application delegate retains this composition only when the durable Agent
reactivation composition exists. Construction opens no XPC session and starts
no listener, Agent, login role, update check, or installer. The Sparkle ready
callback has no reference to this composition and still cancels its prepared
reply.

## Verification

Focused tests prove candidate build 11 survives the exact validation admission
and all three visible indicator phases project to the closed update Control
states. The permanent-target validator requires the composition, exact
candidate-build use, and indicator-derived gate while continuing to reject a
direct prepared-installer start, full/background checks, or a second install
reply. The complete repository gate passes 73 authoritative fixtures, 35
update-policy fixtures, every supply-chain, privacy, SBOM, signing, packaging,
release-evidence, permanent-target, and cross-platform validator, 1,602
MacCompanionKit tests, and 8 platform-probe tests on Xcode 27 beta.

## Deliberate non-claims

The permanent adapter does not construct the foreground installation owner or
present confirmation. Application termination is not yet deferred around an
in-flight shutdown. Signed two-version execution, forced process loss, stable
Xcode 26.6 repetition, and physical confirmation UX remain release gates.

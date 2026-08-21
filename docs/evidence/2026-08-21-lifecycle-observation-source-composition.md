# Lifecycle observation source composition evidence — 2026-08-21

## Claim

Mac Companion now binds its generation-fenced process observation owner to the
two legitimate bundle-independent product sources without allowing a caller to
assert its own role.

`MacAgentLifecycleObservationRootV1.afterAgentBootstrap(services:)` accepts the
complete `AgentPrimaryServicesV1` aggregate returned only after identity,
provider publication, durable operation reconciliation, local status, required
audit, and primary-session construction succeed. Root creation activates and
publishes one fresh Agent generation. A disabled/ineligible lifecycle cannot
construct it, and an incorrectly pre-ready Agent is retired before fresh
bootstrap readiness is accepted.

After the final platform adapter authenticates an exact menu connection, it may
request one `MacAuthenticatedMenuLifecycleConnectionV1`. Issuance activates a
generation but does not claim ready. The capability owns ready and invalidation,
serializes them through suspension, rejects duplicate generation ownership,
replays exact terminal invalidation, and fences every callback from a replaced
connection. It accepts no caller role, PID, bundle path, label, or signing
claim.

## Automated evidence

Eight new tests prove:

- complete Agent bootstrap as the sole Agent-ready source;
- menu connection issuance remaining `starting` until explicit ready;
- exact menu invalidation, recovery request, and terminal receipt replay;
- ready-after-invalidation rejection;
- replacement fencing of old ready and invalidation callbacks;
- rejection of two owners for one menu generation;
- serialized concurrent invalidation with one recovery request;
- disabled Agent-bootstrap rejection; and
- retirement of an incorrectly pre-ready Agent before fresh readiness.

The focused `CompanionAgentPlatformTests` target passes all 45 tests. The
repository-wide hardened gate passes with 63 indexed protocol/product fixtures,
14 repository-material fixtures, 12 dependency-policy fixtures, 12 privacy
fixtures, 10 source-SBOM fixtures, 16 release-evidence fixtures, and 1,117 Swift
tests across 790 validated repository files. Both required client cross-compiles
and all three no-prompt/no-network platform probes also pass. The only emitted
warnings are the expected read-only user-level SwiftPM cache warnings.

## Deliberate limits

This composition starts after authentication; it does not implement or weaken
the audit-token/designated-requirement check. The final target must bind root
issuance to the authenticated menu XPC connection, define complete menu runtime
readiness, deliver every interruption/invalidation/process-loss callback, and
deliver every interruption/invalidation/process-loss callback. The subsequent
[bounded process recovery evidence](2026-08-21-bounded-process-recovery-scheduling.md)
implements the fixed bundle-independent retry policy. Final service identities,
signed XPC, and physical crash/login/update evidence remain release gates.

# Bounded process recovery scheduling evidence — 2026-08-21

## Claim

An authenticated menu connection whose exact-generation invalidation advances
the lifecycle but cannot confirm its first process-start request now enters one
closed recovery loop. The observation owner retains only the exact post-exit
lifecycle revision, menu observation epoch, and fixed menu recovery effect. The
scheduler makes at most three further attempts after 250 milliseconds, 1
second, and 4 seconds.

This policy applies only to the idempotent request to start an already-
registered login role. It is not available to capability operations or other
external effects. `outcomeUnknown` may therefore be retried within the same
fence, but it never means the process exists or is ready. Only a later
authenticated observation can publish readiness.

Every attempt serializes with observation activation and rechecks the exact
revision, role epoch, `starting` state, enabled/logged-in eligibility, and
absence of a replacement observation. Success, cancellation, replacement,
disable/logout, any revision or epoch change, or exhaustion stops the loop. The
connection continues to replay its original exact terminal receipt, so later
background recovery cannot rewrite history.

## Automated evidence

Four focused tests prove:

- failed and ambiguous outcomes retry only until the first completed request;
- three failed retries exhaust without an unbounded fourth retry;
- an authenticated replacement connection fences a sleeping retry before it
  can invoke the platform starter; and
- an intervening lifecycle revision change likewise fences the retry.

The focused `CompanionAgentPlatformTests` target passes all 49 tests. The
repository-wide hardened gate passes with 63 indexed protocol/product fixtures,
14 repository-material fixtures, 12 dependency-policy fixtures, 12 privacy
fixtures, 10 source-SBOM fixtures, 16 release-evidence fixtures, and 1,121 Swift
tests across 792 validated repository files. Both required client cross-compiles
and all three no-prompt/no-network platform probes also pass. The only emitted
warnings are the expected read-only user-level SwiftPM cache warnings.

## Deliberate limits

This scheduler requests starts; it does not observe processes, invent readiness,
or authenticate XPC. The final target still must prove the concrete start
adapter's idempotence and postcondition behavior plus interruption,
invalidation, crash, login/logout, update, and uninstall callbacks with signed
identities on physical systems.

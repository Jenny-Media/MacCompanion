# Native bounded keep-awake provider evidence — 2026-08-21

## Claim

Mac Companion now has a second reviewed native-action candidate without
expanding the advertised MVP registry. The provider exposes separate
`startKeepAwake` and `stopKeepAwake` capability descriptors. Start accepts an
absolute `untilUnixMilliseconds`, rejects expired operations, and requires an
execution-time duration between 60 seconds and four hours. Stop accepts only an
empty object and is idempotent.

The controller owns at most one opaque assertion ID. An exact active deadline
is idempotent; changing it releases the old assertion before creating a new one;
release ambiguity creates no replacement and becomes `outcomeUnknown`; and a
known-expired system-timed assertion is never treated as live state. Provider
results are canonical closed JSON and raw IOKit facts never cross the boundary.

The macOS backend compiles against Apple's public IOPM API using
`kIOPMAssertionTypePreventUserIdleSystemSleep`, a fixed content-free name, and
the system timeout-release action. Construction and descriptor inspection are
inert. No validation command activates an assertion.

## Product decision

This capability remains candidate-only. The market MVP still advertises only
the already-composed `setAudioMuted` action because keep-awake needs signed
physical timeout/crash/logout evidence and a dedicated time-selection UI. The
dynamic generic integer editor is not an acceptable product surface for an
absolute deadline.

## Automated evidence

Eight new tests prove:

- closed start/stop descriptors and conservative effect facts;
- canonical start and stop results with exact timeout/release calls;
- rejection of expired, malformed, too-short, and over-four-hour requests;
- exact idempotency and release-before-replacement ordering;
- safe expiration without releasing an already system-timed-out handle;
- no replacement after ambiguous release;
- closed provider mapping of release ambiguity and creation failure; and
- idempotent stop when no assertion is owned.

The focused `CompanionNativeProvidersTests` target passes all 12 tests. The
repository-wide hardened gate passes with 63 indexed protocol/product fixtures,
14 repository-material fixtures, 12 dependency-policy fixtures, 12 privacy
fixtures, 10 source-SBOM fixtures, 16 release-evidence fixtures, and 1,129 Swift
tests across 800 validated repository files. Both required client cross-compiles
and all three no-prompt/no-network platform probes also pass. The only emitted
warnings are the expected read-only user-level SwiftPM cache warnings.

## Deliberate limits

Compile and injected evidence do not prove that a signed Agent receives the
expected assertion attribution or that timeout, crash, logout, lid-close,
explicit sleep, battery, and thermal behavior matches the product copy. Those
are explicit promotion gates. The separately reviewed three-state
[system-appearance action is now a Stage 0 no-go](2026-08-21-native-system-appearance-no-go.md),
not an unimplemented native-provider promise.

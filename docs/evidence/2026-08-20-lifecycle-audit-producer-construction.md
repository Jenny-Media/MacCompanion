# Lifecycle audit producer construction evidence

Date: 2026-08-20

## Claim

The bundle-independent Agent layer now accepts only completed lifecycle
transitions that exactly reproduce the pure reducer's before state, event,
after state, and ordered effects. It emits stable, privacy-safe global audit
rows for explicit enabled-intent and Observe-availability changes without
placing audit storage on the lifecycle recovery or safety path.

## Construction boundary

- `CompletedLifecycleTransitionV0` rejects a forged or mismatched completion.
- `BoundedLifecycleAuditWriterV0` observes a transition only after the caller
  has obtained its authoritative new state and effects.
- Explicit enabled-intent changes map to `host.securityStateChanged`.
- Observe-availability changes map to `host.availabilityChanged`.
- Global records use only the `system` actor, closed outcomes, and
  `allPairedDevices`; they carry no device, correlation, capability,
  operation, session, authority-revision, route, or surface fields.
- Event IDs are deterministic over a durable transition ID and event code.
- Duplicate observation is harmless. A failed, throttled, or quota-dropped
  best-effort append degrades writer health but cannot modify the completed
  state or ordered teardown/recovery effects.
- The shared audit model now rejects global rows from actors other than
  `agent` or `system`, matching the wire privacy contract.

## Tests

Focused commands passed:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --package-path Packages/MacCompanionKit --disable-sandbox \
  --scratch-path /private/tmp/maccompanion-swift-build \
  --filter LifecycleAuditWriterV0Tests

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --package-path Packages/MacCompanionKit --disable-sandbox \
  --scratch-path /private/tmp/maccompanion-swift-build \
  --filter auditModelRejectsIdentityAndGlobalPrivacyContradictions
```

The current public validation gate also passed with 54 authoritative fixtures and 637
Swift tests, iOS Simulator client-platform and client-UI compilation, macOS UI
compilation, three no-prompt/no-network platform probes, and `git diff --check`.

## Boundary not claimed

This does not claim a signed `SMAppService` composition, authenticated XPC,
actual process recovery, lock/logout behavior on a clean user, or a physical
device. The release composition must make lifecycle observation mandatory,
while still executing teardown and recovery before any best-effort history
write.

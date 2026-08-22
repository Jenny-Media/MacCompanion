# Permanent menu application launch

Date: 2026-08-22

## Claim

The permanent containing app now starts its existing dashboard product exactly
once from the real AppKit application-launch lifecycle. The package-owned
`MacCompanionDashboardApplicationDelegateV1` is retained through SwiftUI's
`NSApplicationDelegateAdaptor`; the executable receives only its typed
dashboard and cannot invoke the package-scoped transport start directly.

## Construction

- `applicationDidFinishLaunching` reserves one launch task before starting the
  existing `MacCompanionDashboardApplicationV1`.
- A duplicate launch callback cannot start a second dashboard or local-XPC
  client.
- Launch failure is swallowed only after the dashboard's complete terminal
  cleanup finishes, leaving the UI truthfully unavailable.
- Explicit package-owned finish cancels and awaits an admitted launch before
  joining the dashboard's shared terminal barrier. App termination and delegate
  deinitialization begin best-effort cleanup through that same operation.
- The permanent SwiftUI target no longer constructs dashboard transport state.
  It retains the package delegate, presents `applicationDelegate.dashboard`,
  and forwards only typed status retry.
- The delegate does not construct a local-XPC client or product, select a server
  profile, install pairing/recovery presentation surfaces, mutate login roles,
  or start network ingress.

The Agent's separately sealed selector remains authoritative for the other side
of the Mach service: enabled canonical startup provides readiness/status;
disabled or durable recovery remains authentication-only; first-unlock retry
provides no server. An incompatible or unavailable server makes the menu
dashboard unavailable without profile fallback.

## Deterministic verification

The ten focused menu application-platform tests cover construction without
transport, explicit dashboard start, launch-driven exactly-once start, duplicate
launch callbacks, launch failure, cancellation during suspended start, finish
versus suspended launch, shared repeated finish, retry admission, source
terminalization, and deinitialization cleanup.

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --package-path Packages/MacCompanionKit --filter \
CompanionMacApplicationPlatformTests
```

Result: all 10 tests passed on Xcode 27 beta.

The permanent-target validator requires the exact package-owned delegate and
typed dashboard access in the executable, requires one launch-owned dashboard
start in the package layer, and continues to reject raw dashboard products,
clients, profile choice, presentation surfaces, storage/bootstrap authority,
login mutation, direct executable start, and semantic project-graph drift.

The complete repository gate passed with 64 indexed protocol/product fixtures,
934 repository files, 1,168 historical blob paths, 304 production Swift source
files, 1,348 package tests, every supported cross-build, and all 8 platform
probe tests. A code-signing-disabled Debug build of the generated
`MacCompanion` scheme also passed and embedded the Agent and LaunchAgent
property list.

## Non-claims and next gate

This checkpoint does not claim that the app or Agent was launched, that an
unsigned/ad-hoc process authenticated, or that a readiness acknowledgement or
status reply crossed the real Mach service. It does not prove launchd, login
registration, Keychain/Secure Enclave access, TCC attribution, managed
entitlements, presentation, pairing, networking, Observe, Act, or Control.

Subsequent [signing revalidation](2026-08-22-signing-identity-revalidation.md)
proved that the login Keychain contains valid Jenny Media LLC development and
Developer ID identities and that the permanent Debug app and embedded Agent
sign correctly. The next runtime gate is a durable explicit enablement path,
followed by one reciprocal same-team Agent/menu readiness-and-status round trip
without enabling the presentation profile or network ingress.

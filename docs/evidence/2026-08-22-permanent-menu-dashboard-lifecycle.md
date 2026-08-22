# Permanent menu dashboard lifecycle bridge

Date: 2026-08-22

## Claim

The permanent Mac containing app now constructs and retains the real typed
dashboard application lifecycle through a dedicated package product. It no
longer hardcodes an unavailable source or simulates a retry with a timer.
Construction starts no local XPC session, and the permanent target does not
invoke the explicit transport-start transition.

## Construction

- `CompanionMacApplicationPlatform` owns the generation-fenced
  `MacAgentDashboardApplicationOwnerV0` and the existing
  `MacLocalXPCDashboardProductV1` behind one main-actor observable source.
- The public surface is limited to typed source, bounded status retry, and
  awaitable terminal `finish`. The explicit `start` transition is
  package-scoped, so the permanent Xcode target cannot invoke it at this
  checkpoint.
- Source begins unavailable. Loading and status can arrive only through the
  dashboard owner's callback after explicit start; the bridge never invents
  them.
- Retry is `notCompleted` before start, after finish, or across a concurrent
  terminal transition.
- Start is one-use. Failure awaits product retirement before escaping.
  Concurrent and repeated finish calls join the same barrier, and
  deinitialization begins best-effort cleanup only when no barrier exists.
- The permanent app constructs the bridge in SwiftUI state and forwards retry
  to it. It does not call `start`, register either login role, or choose an XPC
  profile.
- The permanent-target validator compares the exact ordered semantic Swift
  package products in both `project.yml` and the generated PBX dependency and
  Frameworks graphs. Adversarial removal and comment-preserving product-ID
  substitution must fail.

## Verification

The seven focused tests cover zero-start construction, owner-produced loading,
retry forwarding only while active, start-failure convergence, suspended
start versus repeated finish, cancellation-triggered terminal cleanup,
repeated-start rejection, and deinitialization cleanup:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --package-path Packages/MacCompanionKit --filter \
CompanionMacApplicationPlatformTests
```

Result: all 7 tests passed on Xcode 27 beta.

The complete repository gate passed with 64 indexed JSON fixtures, 932
repository files, 1,145 historical blob-paths, 304 production Swift source
files, 1,342 package tests, every supported cross-build, and all 8 platform
probe tests. The code-signing-disabled Xcode Debug build also passed and
embedded the permanent Agent and LaunchAgent property list.

## Non-claims and next gate

Current command-line Keychain inspection reports zero valid code-signing
identities. The permanent Agent also intentionally exposes only its
authentication-only local XPC profile. Therefore this checkpoint does not
claim a reciprocal signed connection, menu readiness, status delivery,
pairing/recovery presentation, login-role registration, launchd behavior,
Keychain/Secure Enclave custody, TCC, entitlements, network ingress, Observe,
Act, or Control.

The next source checkpoint is a narrow Agent application owner that selects
exactly one Mach-service owner and activates only authenticated readiness and
status for an enabled canonical lifecycle. It must not start both the
authentication-only and status products, and it must not silently inherit the
broader pairing/recovery presentation profile.

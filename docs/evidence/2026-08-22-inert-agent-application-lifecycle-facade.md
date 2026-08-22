# Inert Agent application lifecycle facade

Date: 2026-08-22

## Claim

`MacAgentApplicationLifecycleFacadeV1` gives a future permanent Agent target one
package-owned lifecycle and request-context owner that is safe-disabled,
session-ambiguous, and activation-inert at construction.

## Construction

- The facade fixes its initial lifecycle to disabled, both managed processes
  stopped, and `otherConsoleUserActive`. Observe, new Interactive Control, and
  local administration are therefore unavailable.
- It retains exactly one `MacAgentConservativeRequestContextProductV1`.
  Package-scoped primary and pairing closures come from that same owner and
  still issue fresh message identifiers and clock samples per request.
- Construction installs no observer and reads no console facts. `start()` only
  starts the conservative public-workspace observer and rejects a second start.
- `finish()` is terminal and idempotent. It removes the observer, moves primary
  request context to `serviceStoppingForLogout`, and prevents a later start or
  notification from reviving state.
- Deinitialization also performs synchronous terminal finish. Context closures
  may retain the inner context owner after the facade is released, but primary
  contexts are already stopping and cannot revive. The pairing closure contains
  only clocks and a fresh message identifier; it owns no listener, pairing
  session, or admission authority. A future listener owner must still retire
  its listener before finishing this lifecycle owner.
- The facade has no bootstrap, storage, Keychain, XPC, process-start, listener,
  Bonjour, login-registration, readiness, pairing-session, or runtime-activation
  dependency or method.
- `CompanionLifecycle` is an explicit product-target dependency rather than an
  undeclared transitive import.

## Deterministic verification

The focused facade suite proves:

1. Construction performs zero public-fact reads and publishes only the exact
   safe-disabled ambiguous lifecycle.
2. Start samples once, duplicate start fails, and active-screen/session
   notifications never promote the state to active or locked.
3. Primary and pairing closures use one retained owner and produce distinct
   request identifiers.
4. Repeated finish, finish-before-start, post-finish wake delivery, and later
   start attempts remain terminal and fail closed.
5. Both context closures may escape while the facade is released; a weak owner
   becomes nil, the primary closure is terminal immediately, later workspace
   events cannot revive it, and the surviving pairing closure remains
   content-free.

Focused command:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --package-path Packages/MacCompanionKit --filter \
'MacAgent(ConservativeRequestContextProduct|ApplicationLifecycleFacade)V1Tests'
```

Result: 10 tests passed, including 6 facade tests and the 4 underlying
request-context tests.

`swift test list` reports 1,315 unique package tests with no duplicate names.

The complete repository gate passed:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
/bin/bash scripts/validate.sh
```

Result: 64 indexed JSON fixtures, 923 repository files, 1,118 historical
blob-paths, 14 repository-material fixtures, four Swift package manifests, 12
dependency-policy fixtures, permanent Apple-target policy, 301 production
Swift source files, 1,315 package tests, every supported cross-build, and all
8 platform-probe tests passed on Xcode 27 beta.

The checked-in Xcode project also built the code-signing-disabled Debug
containing app and embedded Agent:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project MacCompanion.xcodeproj -scheme MacCompanion \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

The first attempt exhausted the volume while writing generated compiler
intermediates. Only the exact rebuildable
`Packages/MacCompanionKit/.build` cache was removed; the retry completed with
`** BUILD SUCCEEDED **`. This is unsigned construction evidence, not signed or
physical runtime evidence.

## Non-claims

This checkpoint does not load durable enablement intent, create release
storage or host identity, prepare or start local XPC, construct or start a
network listener, register login roles, change either permanent target, or
prove signed or physical runtime behavior. It cannot identify a positively
active or locked configured-user session and enables no Observe, Act, pairing,
or Interactive Control path.

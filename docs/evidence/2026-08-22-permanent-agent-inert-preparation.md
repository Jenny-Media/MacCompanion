# Permanent Agent inert preparation

Date: 2026-08-22

## Claim

The permanent `MacCompanionAgent` executable now performs release-shaped
storage, durable-intent, and host-identity preparation before opening its
existing authentication-only local XPC service. The executable links a narrow
application product that exposes preparation and authentication-start
coordination; its retained prepared owner exposes only terminal finish, and the
executable does not receive the broader product activation API.

## Construction

- `CompanionAgentApplicationPlatform` is the permanent-target boundary. It
  constructs production storage and identity inputs internally, then maps the
  broader preparation result to `ready(owner)` or one of three explicit
  fail-closed deferrals.
- Host identity uses the fixed application-tag prefix
  `media.jenny.maccompanion.agent.identity.v1`, requires the Secure Enclave,
  and preserves the existing prompt-free after-first-unlock custody profile.
- Interactive admission, approval/bootstrap material generation, and runtime
  installation all fail with an explicit unavailable error. No surface-control
  dispatcher exists.
- The injected lifecycle process starter performs no registration, launch,
  lookup, or mutation and always reports `notCompleted`.
- The public prepared owner exposes only awaited terminal `finish()`. It does
  not expose storage paths, host identity, lifecycle snapshots, local-XPC or
  network construction, listener start, pairing, process start, login roles,
  providers, or runtime activation.
- The executable begins its existing reciprocal-identity authentication-only
  XPC service after preparation returns ready. Durable local-recovery and
  recovery-fenced states also retain that non-authorizing handshake for future
  menu recovery work instead of entering an unconditional launchd retry loop.
  First-unlock wait alone exits so the configured launchd policy may retry.
  Preparation errors exit closed.
- If authentication-only XPC startup fails, the executable awaits prepared-root
  retirement before exiting. A live process retains both owners for its entire
  lifetime.
- `project.yml`, the generated Xcode project, and the permanent-target policy
  link exactly the narrow application and local-XPC products into the Agent.
  The policy rejects
  direct broad-product, network-platform, lifecycle-platform, and activation
  imports from the executable.

This checkpoint is activation-inert, not persistence-inert. On a real launch it
may create or reconcile the private Application Support hierarchy, SQLite
stores, deny latch, durable remote-access intent, and host Keychain identity.
Those are deliberate durable preparation effects. It does not start an
observer, readiness-producing product XPC, network listener, Bonjour, pairing,
process launch, login-role mutation, provider effect, or remote route.

## Deterministic verification

The focused application-platform tests independently pin the exact stable tag,
Secure Enclave requirement, injected registry generation and wall time,
absence of a surface-control authority, fail-closed Interactive admission/
materials, and the inert process-start outcome. They also prove every
preparation mapping, first-unlock-only retry, durable recovery idle policy,
preparation-before-authentication ordering, ready-owner retention, XPC-start
compensation, preparation-failure isolation, idempotent finish, and narrow-owner
deinitialization retirement. A focused Agent test drives the real inert runtime
`install` and repeated `terminate` seams.

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --package-path Packages/MacCompanionKit --filter \
CompanionAgentApplicationPlatformTests
```

Result: all 6 application-platform tests passed; the focused inert Interactive
runtime test also passed.

The complete repository gate passed:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
/bin/bash scripts/validate.sh
```

Result: 64 indexed JSON fixtures, 929 repository files, 1,131 historical
blob-paths, 14 repository-material fixtures, four Swift package manifests, 12
dependency-policy fixtures, permanent Apple-target policy, 303 production
Swift source files, 1,335 package tests, every supported cross-build, and all
8 platform-probe tests passed on Xcode 27 beta.

The checked-in Xcode project also built the code-signing-disabled Debug app and
embedded Agent:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project MacCompanion.xcodeproj -scheme MacCompanion \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Result: `** BUILD SUCCEEDED **`; the output contains the outer app executable,
embedded `MacCompanionAgent`, and LaunchAgent plist. This is unsigned
construction evidence, not signed execution or physical Keychain proof.

## Non-claims

This checkpoint does not implement the local host-identity recovery method or
UI; durable recovery wait exposes authentication only. It does not activate the Agent product, its conservative session
observer, readiness/status XPC product, network listener, Bonjour, pairing,
Observe, Act, or Interactive Control. It does not prove first-unlock retry,
recovery UX, reciprocal signed XPC authentication, Keychain/Secure Enclave
custody from the final code identity, launchd behavior, entitlements, TCC,
networking, or physical two-process behavior. Those remain independently gated.

# Permanent Agent single-service selection

Date: 2026-08-22

## Claim

The permanent per-user Agent now delegates local-service startup to one sealed
application-platform owner. The executable cannot import LocalXPC, select a
server profile, inject a status reader, supply a start closure, or construct a
second owner for the permanent Mach service.

The application owner prepares durable state first and then applies one closed
selection table:

| Prepared outcome | Selected service |
| --- | --- |
| Exact revision-zero enabled/starting lifecycle | Authenticated menu readiness and content-free status |
| Exact revision-zero disabled/stopped lifecycle | Authentication only, with the prepared root retained |
| Local recovery required or recovery fenced | Authentication only |
| First unlock required | No service; exit for launchd retry |

Any other ready lifecycle is rejected before service construction. Selected
construction, start, or caller cancellation retires the chosen service and any
prepared root before the error escapes. Failure never tries the other profile
as fallback.

## Authority boundary

- The status-capable deferred factory is fixed below the application boundary
  to `MacLocalXPCAgentProductV1.afterAgentBootstrap`. It cannot select the
  pairing/recovery presentation profile.
- The public running owner exposes only awaitable, idempotent `finish()`; its
  selected mode is private.
- The permanent Agent Xcode target links only
  `CompanionAgentApplicationPlatform`. LocalXPC is an internal Swift-package
  dependency of that boundary.
- The menu app remains transport-inert. This checkpoint starts only the Agent
  side selected service and does not activate the menu dashboard client.
- Network listener, Bonjour, pairing, diagnostic export, presentation surfaces,
  Observe, Act, and Control remain unstarted.

## Deterministic verification

The nine focused Agent application-platform tests cover preparation mapping,
the exact enabled/disabled/recovery/first-unlock selection matrix, zero calls to
the unselected factory, status and authentication start failures without
fallback, rejection of a nonzero prepared revision before construction, caller
cancellation during suspended status start and immediately after ready
preparation, complete prepared-root retirement, and concurrent/repeated finish
through one terminal barrier.

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --package-path Packages/MacCompanionKit --filter \
CompanionAgentApplicationPlatformTests
```

Result: all 9 tests passed on Xcode 27 beta.

The permanent-target validator checks the exact one-product Agent dependency
and Frameworks graphs in `project.yml` and the generated PBX project, forbids
raw LocalXPC imports, servers, profile literals, readers, products, injected
factories, and duplicate startup from the executable, and rejects adversarial
profile broadening, presentation-surface injection, extra product links, and
comment-preserving PBX product substitution.

The complete repository gate passed with 64 indexed protocol/product fixtures,
933 repository files, 1,155 historical blob paths, 304 production Swift source
files, 1,345 package tests, every supported cross-build, and all 8 platform
probe tests. A code-signing-disabled Debug build of the generated
`MacCompanion` Xcode scheme also passed and embedded the Agent and LaunchAgent
property list.

## Non-claims and next gate

This is source ownership, injected-test, full-validator, and unsigned-build
evidence. The Agent was not launched. It does not prove a reciprocal signed XPC
connection, live readiness acknowledgement or status delivery, launchd
behavior, Keychain/Secure Enclave access, TCC attribution, managed entitlements,
login-role registration, networking, or physical-device behavior.

Current command-line Keychain inspection reports zero valid code-signing
identities. The next runtime gate is to provision or restore the Jenny Media LLC
development identity, connect the already-owned menu dashboard start through an
explicit product lifecycle transition, and prove one reciprocal signed
Agent/menu readiness-and-status round trip without enabling presentation or
network ingress.

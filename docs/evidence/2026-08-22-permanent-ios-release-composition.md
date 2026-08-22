# Permanent iOS pairing, route, and workspace composition

Date: 2026-08-22

## Claim

The permanent `MacCompanionIOS` target now composes the package-owned no-relay
pairing flow, explicit first-route publication, configured reconnect product,
and the first-party Observe, Approved Actions, and separately authorized Remote
Control workspace. This supersedes the bootstrap-only application composition
recorded in the earlier permanent-target checkpoint; it does not supersede that
checkpoint's identity, privacy, storage, or unsigned-build evidence.

## Release ownership

`IOSClientReleaseApplicationV1` is the sole target-facing application owner. It
retains protected bootstrap storage internally and exposes only value phases,
the verified pairing presentation, an explicit route plan, or a selected
workspace product. The application source imports `CompanionClientPlatform`
and `CompanionClientUI`; it has no raw Network, Security, Keychain, camera,
route-store, or paired-host-store API.

The owner:

- starts one verified QR pairing attempt through the exact package network
  composition and Security-backed separated session/approval keys;
- publishes no reconnect route until every ambiguous DNS or public-address
  candidate receives an explicit user provenance choice;
- resumes a crash between durable pairing and route publication as
  `routeSetupDeferred`, rather than dialing or declaring the paired identity
  corrupt;
- builds the configured reconnect product only after exact route publication;
- starts UIKit activity and Boolean reachability scheduling through the
  existing application owner without treating either as route authority; and
- retires configured lifecycle and Interactive role products together after a
  terminal network-composition failure.

Pairing does not request Observe, Act, or Control authority. Approved Actions
remain available from their own granted catalog and operation session. Remote
Control remains a separate workspace intent with its own fresh approval,
secondary roles, clean-media gate, and stop path.

## First-party UI composition

The permanent app now renders the real one-shot scanner, pairing identity/SAS
states, recoverable route setup, and selected-primary workspace. Two reusable
package views keep application state narrow:

- `ClientRouteBootstrapApplicationViewV1` owns only the bounded selection map
  admitted by the route projection; it cannot persist or infer a route.
- `ClientPrimaryWorkspaceApplicationViewV1` owns selected-item Approved Action
  presentation and typed parameter drafts while reusing the existing
  revision-fenced workspace model. It does not duplicate Control commands.

The root service is owned once with Swift Observation and async start follows
the SwiftUI task lifecycle. Mutually exclusive scanner presentation uses an
item sheet. Errors are sanitized and preserve the last verified product state.

## Verification

The package's 1,389 Swift tests pass unchanged. The permanent target generator
and generated project bind exactly `CompanionClientPlatform` and
`CompanionClientUI`. The focused validator now also checks recoverable partial
pairing, exact first-route insertion, package-owned pairing/network factories,
Observe/Act/Control workspace reuse, selected-item action presentation, and
route deselection. Its adversarial self-tests reject a substituted product,
raw network use, background mode, missing backup protection, non-initial route
replacement, Boolean action-sheet replacement, and lost route deselection.

An unsigned Xcode 27 beta iOS Simulator build succeeds:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -quiet -project MacCompanion.xcodeproj \
  -scheme MacCompanionIOS -sdk iphonesimulator \
  -configuration Debug \
  -derivedDataPath /private/tmp/MacCompanionIOSCompositionDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

The complete validation entry point also passes. It inspects 963 current
repository files and 1,249 historical blob paths, all fixture/policy suites,
316 Swift source files, the 1,389-test package suite, eight platform-probe
tests, both client compile surfaces, and all no-prompt/no-network probes.

## Non-claims and next gate

No Simulator was booted and no physical device, camera, Local Network prompt,
Keychain user-presence operation, live socket, paired Mac, Observe response,
Core Audio mutation, captured pixel, decoded frame, or posted input event was
exercised. The iOS App ID, provisioning, signed launch, Data Protection runtime
inspection, and TestFlight record remain open.

The next product proof is reciprocal signed Agent activation followed by one
physical same-LAN pairing. That run must verify the exact QR/SAS transcript,
route publication and reconnect, one fresh Observe response, and one explicit
`setAudioMuted` operation before Interactive Control is attempted.

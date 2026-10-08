# Normal Simulator Keychain and live pairing verification

Date: 2026-09-27

## Failure and fix

The first live test used the normal app, a fresh code from the disposable signed
Agent, and the production pairing owners. The app failed during local identity
preparation, before sending a pairing request. The UI reported local storage
failure. A hosted Security.framework diagnostic reproduced OSStatus **-34018**
(`errSecMissingEntitlement`) for both the ordinary session key and the approval
key; removing the approval private-usage flag did not resolve the failure.

The generated normal Simulator project had disabled signing and supplied no
Simulator Keychain entitlement. The corrected Debug Simulator builder supplies
one isolated development application identifier/access group and lets Xcode
package simulated entitlements and sign the app ad hoc. Manually adding those
entitlements to the host code signature failed to launch; that approach is not
used. The working Xcode build embeds the simulated entitlement section in the
executable. The builder verifies the supplied file, Xcode's packaged file,
actual executable section, Simulator SDK metadata and signature. Native framework
copy signing is disabled so their admitted binary hashes remain unchanged.

The normative Simulator contract and sole manifest-indexed fixture were updated
first. No permanent identity/group is allocated. Device and Release targets do
not select this development entitlement. Session/approval protection, approval
user presence, pairing/signature/certificate validation and existing golden
cryptographic vectors are unchanged.

The hosted diagnostic passes one test with zero failures: both original session
and approval key settings create keys successfully. It also probes the
presence-only variant without selecting it in the app. No approval is signed.
Diagnostic deletion is attempted, but its status is not asserted; this is not a
Keychain cleanup acceptance claim. Its local report is
`/private/tmp/maccompanion-normal-custody-diagnostics-20260927-v1/diagnostic-report.json`
(SHA-256 `a563b38b81f95d00b192b35981fcfd590644d8e73cd3d1c870b2c9a8221b7c91`).

## Normal app live test

`scripts/verify_normal_native_live_pairing.py` builds a separate UI test around
the normal app. The disposable signed Agent uses its existing first-party
pairing/TLS/XPC composition and test-only host custody. The consent bridge creates
a real fresh pairing code and explicitly withholds Mac approval. The test types
the code into the normal app, selects Connect Securely, reaches **Compare this
code on your Mac**, and cancels back to normal code entry. No saved paired success
is displayed. The host still reports zero paired devices and no approval marker.
Client key custody is the normal Security.framework implementation.

One XCTest passed, zero failed/skipped/expected failures, in 25.753 seconds.
Actual xcresult counts, Simulator platform, source readback, embedded framework
hashes and entitlement packaging are checked. Disposable Agent job/private state
and owned child cleanup are verified. This is loopback pairing proof and
cancellation, not completed pairing, client approval presence or native Control.

Report: `/private/tmp/maccompanion-normal-live-pairing-20260927-v2/report.json`.

Report SHA-256: `a904adac8721aac7dd921b96cba991619a6619515e81a4ca0dcb4283aebfe8f7`.

Native source inputs: `aab1110bf2ca88c8cec4a3679d6e661c0c40c0b99d325ef7e8bd686fb9c954bc`.

Normal tested executable: `d64c9eb3095b05080ff129630dc67fb6c6d77560330baa6e562bb0f2ee90c8d4`.

The runner reuses the disposable normal build project/cache. It records that
the baseline artifact may be rebuilt; this run's tested executable equals the
baseline hash. Transient QR/test diagnostics remain private local files, never
repository content. The app was relaunched after cleanup and is at normal
scanning/code entry in Simulator `8FF65ABB-572E-4EE4-9A9F-F61AA302A586`.

## Device exclusion and stable validation

Normal SDK builds pass at:

- `/private/tmp/maccompanion-normal-simulator-keychain-build-20260927-v6`.
- `/private/tmp/maccompanion-normal-device-keychain-build-20260927-v6`.

The device executable hash is
`e9dd018bc66831a19528d43005b877a1c3838f325b4ec84f935aff4227ceef31`.
Compiled inspection finds the Simulator constructor and development group in
the Simulator executable and neither in the device executable. Guard report:
`/private/tmp/maccompanion-normal-keychain-compiled-guards-20260927.json`.
The device app is not installed or launched.

Stable Xcode 27.0 `bash scripts/validate.sh` passes with 110 indexed fixtures,
package tests and required platform builds. Log:
`/private/tmp/maccompanion-simulator-keychain-validation-20260927.log`.

## Next acceptance

Follow-up: [completed normal pairing, workspace and restart](2026-09-27-normal-paired-workspace-and-restart.md)
now verifies completed pairing and the normal saved-route primary journey. Its
explicit test-consent and cleanup boundaries are recorded separately.

Complete pairing against the disposable host with explicit test consent, then
exercise normal route setup/primary reconnect and Control while retaining client
approval presence. Normal installed Mac GUI/TCC continuity, full paired LAN,
physical custody/install/acceptance and actual input remain open. Native
App/Window capture, visible-area bitrate and current corresponding-source
assembly remain open. The earlier harness video/control results are separate
evidence; this normal-app checkpoint makes no video playback claim.

# Exact-HEAD Apple Development construction

Date: 2026-08-23
Source revision: `7c9968298b80cac437a8654b816d90ad05a9cdf0`
Runtime effects: build and read-only signature/service inspection only

## Outcome

The exact clean source revision above built successfully with the installed
Xcode 27 beta and the already-installed Apple Development identity. Signing
authority was supplied only to the local `xcodebuild` invocation. No team,
identity selector, profile, credential, or private account value entered the
project or repository.

The ephemeral build outputs are:

- Derived data:
  `/private/tmp/maccompanion-head-signed-7c99682-derived`
- App:
  `/private/tmp/maccompanion-head-signed-7c99682-derived/Build/Products/Debug/Mac Companion.app`
- Private build log:
  `/private/tmp/maccompanion-head-signed-7c99682-build.log`
- Build-log SHA-256:
  `045e9d2d37d45c37cc3a28187a0ff814a1a6a93df17f502bd1c4957e42ecd110`

The private temporary log is not a repository or release artifact because
Xcode prints local certificate presentation details into build output.

Independent inspection proved:

- `codesign --verify --deep --strict` accepts the containing application;
- strict direct verification accepts the embedded Agent;
- the containing application identifier is exactly
  `media.jenny.maccompanion`;
- the Agent identifier is exactly `media.jenny.maccompanion.agent`;
- both signatures carry the same nonempty development-team identity;
- both executables carry the hardened runtime; and
- the persistent `media.jenny.maccompanion.agent` launch service remains
  absent after the build and inspection.

This supersedes the signing-identity conclusion in the earlier
[external-gate recheck](2026-08-23-external-release-gate-recheck.md). That zero
result was produced under restricted Keychain visibility. It remains an
accurate record of that failed inspection context, not the current signing
state.

## Non-claims

This is an Apple Development Debug construction, not a Developer ID,
notarized, stapled, packaged, TestFlight, App Store, or promotion-ready
candidate. Xcode 27 beta is still the only installed Xcode application; stable
Xcode 26.6 remains required for final release evidence. Final Developer ID and
App Store distribution custody remain controlled release-environment gates.

The app was not launched for this checkpoint. No Remote Access enablement,
`SMAppService` registration, Agent process launch, persistent product-data or
Keychain mutation, privacy prompt, network listener, pairing, Observe, Act,
Control, input posting, screen capture, notarization request, upload,
publication, or external side effect occurred.

## Next gate

The exact signed build is ready for the separately confirmed physical sequence:

1. launch this exact app and explicitly enable Remote Access;
2. prove reciprocal signed local-XPC identity and readiness;
3. pair the physical iPhone over same-LAN QR/SAS;
4. prove one fresh Observe response and one separately consented
   `setAudioMuted` action; and
5. only then test Desktop pixels/input and Smart Zoom with the relevant privacy
   consent.

The first step registers and launches a persistent Agent and therefore still
requires action-time user confirmation. Privacy permission changes and
`setAudioMuted` remain separate confirmations.

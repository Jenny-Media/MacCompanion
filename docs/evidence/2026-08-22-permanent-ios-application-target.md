# Permanent iOS application target and protected restart bootstrap

Date: 2026-08-22

## Claim

The repository now contains the permanent iPhone and iPad application target
for `media.jenny.maccompanion.ios`. Its first release composition is deliberately
transport-inert: it opens only protected app-container state, validates an exact
one-Mac restart boundary, and publishes a sanitized unpaired, paired, or
unavailable phase to a small SwiftUI shell. It does not browse, dial, scan a
camera, request a permission, or start Observe, Act, or Control.

## Target and permission boundary

- `MacCompanionIOS` is a checked-in XcodeGen application target with the iOS
  26.0 floor, iPhone/iPad device family, fixed product identity, static
  `Info.plist`, and no tracked team, profile, signing identity, entitlement
  file, background mode, Mac Catalyst, or Designed-for-iPhone-on-visionOS mode.
- The target links only `CompanionClientPlatform`. Raw pairing, networking,
  camera, and UI packages cannot be selected independently by the application
  source at this checkpoint.
- The static property list declares exactly `_maccompanion._tcp`, truthful
  Local Network and one-shot pairing-camera descriptions, and no background
  execution or arbitrary transport-security exception.
- The indexed iOS privacy manifest is copied to the bundle root and declares no
  tracking, tracking domains, collected data, or required-reason API category.
  Final-candidate inspection and submission answers remain separate gates.

## Protected restart construction

`IOSClientReleaseBootstrapV1` creates or resumes one canonical per-install
client UUID beneath the app's Application Support container. Initial
publication uses a synchronized temporary file and Darwin's exclusive rename,
so a concurrent first writer cannot replace an already published identity.
Directories are mode `0700`, regular files are mode `0600`, the tree uses
`completeUntilFirstUserAuthentication`, and its root and descendants are
excluded from backup. Symlinks and non-directory/non-regular entries fail
closed.

Restart accepts no more than one durable paired-host record, requires its
client UUID to equal the installation UUID, requires exactly that host's one
saved route catalog, and re-registers the exact published Security-framework
key references before reporting `paired`. Missing keys, missing routes,
orphaned routes, multiple hosts/routes, corrupt canonical data, unsafe storage,
or protection failures publish only a closed unavailable reason. The public
application API exposes none of the stores, key custody, route text, or host
identifier.

## Deterministic verification

`scripts/validate_permanent_ios_target.py` checks both the generator input and
generated project, exact package-product authority, identity and deployment
settings, the closed property-list schema, inert application source, and the
protected bootstrap invariants. Its self-tests mutate the package dependency,
add background fetch, inject raw network authority, remove backup exclusion,
and substitute the generated dependency reference; every mutation is rejected.

An unsigned Xcode 27 beta Simulator build succeeds for both `arm64` and
`x86_64`:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -quiet -project MacCompanion.xcodeproj \
  -scheme MacCompanionIOS -sdk iphonesimulator \
  -configuration Debug \
  -derivedDataPath /private/tmp/MacCompanionIOSDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Bundle inspection confirms `media.jenny.maccompanion.ios`, minimum iOS 26.0,
the two declared device families, exact permission strings and Bonjour service,
no background mode, a universal Simulator executable, and the indexed
`PrivacyInfo.xcprivacy` at the application root.

The complete public validation entry point also passes. It covers 959 current
repository files and 1,236 historical blob paths, all fixture and policy suites,
1,389 `MacCompanionKit` Swift tests, eight platform-probe tests, both iOS client
compile targets, the macOS UI compile, and all three no-prompt/no-network
platform probes.

## Non-claims and next gate

This is not a signed iOS build, registered iOS App ID, provisioning or
TestFlight proof. No Simulator was booted during this checkpoint, so the app was
not cold-launched and no runtime claim is made about the first unpaired screen,
Data Protection attributes, backup exclusion, absence of permission prompts,
or restart behavior. It is not physical-device, Secure Enclave, Keychain,
camera, Local Network, Bonjour, pairing, reconnect, Observe, Act, or Control
evidence.

The next iOS gate is a clean Simulator cold launch with no permission prompt or
network activity, followed by registered-identity physical-device signing and
the real package-owned pairing composition. The independent Mac gate remains
the already prepared signed disabled-to-ready Agent acceptance run.

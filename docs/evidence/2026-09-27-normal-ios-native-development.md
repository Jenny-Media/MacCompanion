# Normal iOS native development composition — 2026-09-27

The first-party Moonlight video driver, native video/TLS bridge and launch adapter
now live under `Native/Client`. The experiment builders and signed Simulator lane
consume those sources. The default SDK excludes `ReferenceNativeSurfaceProbe`;
reference comparisons require the explicit `--reference-probe` option. Normal
candidate inventory and the normal app builder reject the reference profile.

The normal iOS application root selects the promoted launch adapter only under
`DEBUG`, `MACCOMPANION_ADMITTED_NATIVE_DEVELOPMENT` and engine module availability.
Its default permanent project does not provide these native sources or that
condition. Release does not select the development adapter. Existing paired-host
signer/current-primary route, presentation, background retirement and input
permissions remain authoritative. No wire, pairing, approval, credential or
operation-signature semantics changed. The normative client-launch document and
sole indexed admission fixture describe this composition.

`scripts/build_native_ios_development.py` generates a Debug-only project from the
normal application specification. It verifies current native source provenance
and engine binaries, compiles the three promoted Swift adapters with the normal
app, and embeds the engine and OpenSSL. It does not link the standalone adapter
framework, which would duplicate the shared client type graph, or any experimental
implementation. The builder requires a fresh output directory and records native
input, builder and resulting application binary digests. Native input provenance
covers the candidate and shared package sources; the normal target root is also
reviewed as source and its compiled result is recorded separately.

## Build and validation evidence

- Both native SDK builds passed. Source input SHA256:
  `ad8ef45eb4af2325468f87a7b300e1f97e380767929af0ae1c7c1220bb34c1dc`.
  Logs: `/private/tmp/maccompanion-production-ios-adapter-iphone-sdk-final.log`
  and `/private/tmp/maccompanion-production-ios-adapter-simulator-components.log`.
  The first device-SDK build exposed a non-public readiness accessor; the promoted
  driver's accessor is now public and the final build passes.
- Twelve native component tests passed on the dedicated Simulator. Six framework
  inventory checks passed with reference inclusion false:
  `/private/tmp/maccompanion-production-ios-adapter-inventory.log`.
- Normal iPhone-SDK application build passed:
  `/private/tmp/maccompanion-normal-native-ios-device-build-20260927-v3/build-report.json`.
  Application binary SHA256:
  `f4770c919e0864437d072861efbb9492026a3ae99ea451e8fd82e017c79e077a`.
  No physical device was accessed or installed.
- Normal Simulator application build passed:
  `/private/tmp/maccompanion-normal-native-ios-simulator-build-20260927-v1/build-report.json`.
  Application binary SHA256:
  `4464cca9f4a3b2c617bdc1d78fa9ff07b6dffc2258757efe8d292a33671c296f`.
- The first project generator looped while creating intermediate groups across
  external paths. Its sampled stack established the path traversal; only that
  owned generator was stopped. Disabling intermediate group generation fixed it.
  A subsequent generator crash tried to select Release in a Debug-only project;
  explicit Debug action configurations fixed it. Both failed outputs are retained.
- Stable Xcode 27.0 repository validation passed:
  `/private/tmp/maccompanion-normal-ios-native-handoff-validation.log`.
  The permanent iOS source-shape validator now checks the explicit development
  branch and default construction after the root's helper extraction.

## Normal Simulator launch and its limit

XcodeBuildMCP installed and launched the actual normal app, bundle ID
`media.jenny.maccompanion.ios`, in dedicated Simulator
`8FF65ABB-572E-4EE4-9A9F-F61AA302A586` (iPhone 17, iOS 27.0). The normal app was
previously absent. The installed executable matches the build digest. No Simulator
was erased and no unrelated app or physical phone was touched.

The UI reports protected local storage unavailable before pairing. The app created
only its first private application directory (mode 0700). A debugger attached to
this app read only the folder's protection/backup metadata: the required
`FileProtectionType.completeUntilFirstUserAuthentication` attribute is absent
(`nil`), while backup exclusion is true. `IOSClientReleaseStorageV1.applyProtection`
requires that attribute and therefore rejects the folder. The debugger detached
without modifying storage or authentication behavior. The normal app retains its
protected-storage and Secure Enclave requirements.

Normalized report:
`/private/tmp/maccompanion-normal-native-ios-simulator-launch-20260927.json`, SHA256
`8fdd25f8776f0cdd87b5926919563b781459d27cf1fbe3920f42198c631fd10e`.
Launch is verified; pairing and a native Control session in this normal app are not.
This Simulator result does not establish a physical-device storage failure.

## Live native regression acceptance

The signed isolated Simulator lane passed after the source promotion, using the
same native input digest and the production-supervisor portable host. One XCTest
completed four visible native sessions in 241.111 seconds with zero failures.
Typing, modifiers, shortcuts, pointer, background retirement, reachability-loss
teardown, explicit restart, Stop and fresh Observe passed; cleanup was verified.
Capture geometry remained physical 5120 by 2134, logical 2560 by 1067 and encoded
1920 by 800. Final input effects remain synthetic.

Report: `/private/tmp/maccompanion-agent-xpc-evidence.gsbfjvml/signed-simulator-report.json`.
Report SHA256: `bbaf2d71e07a0e6e14fb65f95d432abc1053fcd76a1faadc813bde54a7e2a28e`.
Combined runner/source SHA256:
`177ef024696236a4f22e717d27bf8f3c6e8e4bd82335ecdd0f75b78f37fb78ab`.
Host manifest SHA256:
`ea719c8ec6830a838eb97f66c6b0b661031e4f79ff18ae4a9720a73c952a3e2e`.
This test consumes the promoted adapters and shared normal UIKit owners in the
harness. It does not pair or stream through the installed normal iOS application.

## Remaining

Normal paired Control, signed normal Mac GUI/session/TCC continuity, physical
installation, LAN and real final system input remain open. The isolated signed
Simulator lane uses substituted custody/consent and a synthetic final input sink;
its video tests remain separate from normal application acceptance. Native
App/Window capture, visible-area bitrate and complete corresponding-source delivery
remain open. No release admission, commit, publication or physical acceptance is
claimed.

## Subsequent normal Simulator acceptance

The historical file-protection failure above is followed by the explicit
[normal Simulator development bootstrap and code-entry checkpoint](2026-09-27-normal-simulator-bootstrap-and-code-entry.md). The physical/default protected bootstrap remains unchanged; the new mode is Debug Simulator-only and clearly identified.

# Sunshine / Moonlight engine integration experiment

This is the source and lifecycle foundation for the approved integration of both
normal MacCompanion apps. It is not linked into release targets. The implementation
plan is [here](../../docs/sunshine-moonlight-integration-plan.md); measured evidence
and remaining work are [here](../../docs/evidence/2026-09-26-sunshine-moonlight-foundation.md).
The [Simulator embedded-engine checkpoint](../../docs/evidence/2026-09-26-simulator-embedded-moonlight.md)
records live playback through the extracted component, Stop, and a fresh start.
The [normal-client Simulator checkpoint](../../docs/evidence/2026-09-27-normal-client-native-simulator.md)
records authenticated pairing/Control, actual native frames and two Stop/restart
cycles through the normal UIKit owners in a generated experimental app.
The [continuous Stop checkpoint](../../docs/evidence/2026-09-27-continuous-native-stop.md)
repairs the measured shutdown race and repeats both cycles with continuous
bootstrap production.
The [Desktop geometry checkpoint](../../docs/evidence/2026-09-27-native-desktop-geometry.md)
uses the normal Mac preparer and actual selected display bounds for both streams.
The [host input checkpoint](../../docs/evidence/2026-09-27-native-host-input-pause.md)
adds an independent Mac input pause before native preparation. Presentation
acknowledgement and native input enablement remain unfinished.
The [content mapping checkpoint](../../docs/evidence/2026-09-27-native-content-mapping.md)
adds shared geometry and direct-touch/trackpad padding rejection. The source
inventory binds its normative document and authoritative fixture; it does not
yet connect that mapping to native input.

Run that lane only against a dedicated booted Simulator:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer MACCOMPANION_SIMULATOR_ID=YOUR_DEDICATED_SIMULATOR_UDID python3 scripts/verify_signed_simulator.py --native-root /private/tmp/maccompanion-engine --continuous-bootstrap
```

A portable host development candidate can be constructed and explicitly selected:

```sh
python3 scripts/package_native_host.py --root /private/tmp/maccompanion-engine --output /private/tmp/maccompanion-portable-host --smoke
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer MACCOMPANION_SIMULATOR_ID=YOUR_DEDICATED_SIMULATOR_UDID python3 scripts/verify_signed_simulator.py --native-root /private/tmp/maccompanion-engine --native-host-package /private/tmp/maccompanion-portable-host --continuous-bootstrap
```

The package includes the six runtime dylibs, OpenSSL CLI and supervisor, with
loader-relative references and verified ad-hoc signatures/file hashes. Installed
formula/license provenance is retained; complete transitive source/build and
permanent identity/TCC admission remain open. This is a development candidate.

The lane uses continuous generated bootstrap, software test custody/consent and an
isolated signed Mac helper. Conditional native input admission now passes through
the normal controls to a synthetic host sink, including background and reconnect
recovery. Run signed host lanes sequentially; this does not package or install
either normal app or prove actual system input.

## Components

- `source-lock.json`: exact upstream commits, selected build submodules, upstream
  license hashes, vendored library hashes, download checksums, and patch hashes.
  The extra recorded Sunshine submodules describe this checkout; only the listed
  macOS build dependencies in `reference_build.py` are fetched and verified.
- `reference_build.py`: fetch, verify, and build the reference host/client outside
  the repository. Existing source changes outside admitted patches are rejected.
- `engine_build.py`: generate a disposable Xcode project for a video-only Moonlight
  framework from pinned native sources. Pairing, discovery, launch, and input are
  excluded. The H.264/HEVC candidate excludes the upstream AV1 parser and FFmpeg
  libraries. OpenSSL is built from the checksum-pinned official source release
  for both SDKs. Complete host/transitive corresponding source and release
  dependency admission remain pending.
- `openssl_build.py`: reproducible arm64 iOS/Simulator source build, framework
  assembly and file-bound provenance. The source archive and license are retained;
  only disposable compiler objects are reclaimed after producing each framework.
- `../../Native/Client/CompanionMoonlightVideo.*`: bounded native video session, singleton ownership,
  asynchronous Stop, callback retirement, renderer blanking, and transport-key
  erasure. Lifecycle tests exercise the actual native connection failure and Stop.
- `../../Native/Client/MoonlightNativeVideoDriverV0.swift`: injects the extracted engine into the
  normal `UIKitClientNativeVideoOwnerV0` and `UIKitClientLiveSurfaceViewV0`.
  The normal Desktop product has a composition hook; authenticated enrollment,
  presentation and conditional input admission pass in the isolated signed lane.
  Permanent installed-app composition remains pending.
- `candidate_inventory.py`: content-binds both SDK framework binaries to their
  build inputs, checks architectures/dynamic dependencies and absence of native
  FFmpeg parser references, and explicitly reports remaining release admission.
- `SunshineProcessOwner.swift`: experimental Control revalidation and process
  ownership adapter. The production authenticated owner must supply the admission
  predicate and original monotonic deadline. This adapter does not issue grants.
  `test_process_owner.py` checks denied/expired admission, live revocation, terminal
  ownership, and concurrent Stop against a real disposable process.
- `../../Native/Host/companion-supervisor.c`: finite deadline, exact parent-exit monitoring, child
  process group, termination escalation, and reaping. `test_supervisor.py` tests
  real process behavior rather than mocked process calls.
- `mac_probe.py`: loopback-only, finite host probe with isolated private state;
  optional normal upstream PIN pairing through stdin. All remote input is disabled.

## Normal iOS development app

The first-party video, TLS and launch adapters now live under `Native/Client`.
The SDK builder excludes `ReferenceNativeSurfaceProbe` by default. The explicit
`--reference-probe` option is reserved for reference comparisons; candidate
inventory and the normal app builder reject that profile.

After building both SDKs without that reference option, build the normal app:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 scripts/build_native_ios_development.py --root /private/tmp/maccompanion-engine --sdk iphonesimulator --output /private/tmp/maccompanion-normal-ios-native
```

Use a fresh output directory. This generates a Debug-only project from the normal
app specification, compiles the promoted Swift adapters with the normal app, and
embeds only the verified engine and OpenSSL. It does not link the standalone
adapter framework, which would duplicate the shared client type graph. The normal
root selects native video only with the explicit development build condition.
No reference authority or experimental implementation is linked. The permanent
release project remains subject to its separate dependency gates.

The normal app retains its protected storage and hardware key requirements.
Simulator launch alone does not prove pairing or a native Control session; use
the isolated harness for live Simulator coverage when those platform requirements
cannot be met. Never weaken normal storage or key custody to make that test pass.

## Build

Prerequisites: Apple Silicon Mac, Xcode, Homebrew CMake, miniupnpc, OpenSSL 3,
Opus, ICU, Python 3.14, and XcodeGen. SDK/dependency installations are not pinned by
these commands; exact shipping builds require the later inventory/admission work.
The reference iOS patch adopts scenes for the Xcode 27 Simulator runtime.

```sh
python3 Experiments/SunshineMoonlightIntegration/reference_build.py fetch --root /private/tmp/maccompanion-engine
python3 Experiments/SunshineMoonlightIntegration/reference_build.py verify --root /private/tmp/maccompanion-engine
python3 Experiments/SunshineMoonlightIntegration/reference_build.py mac --root /private/tmp/maccompanion-engine
python3 Experiments/SunshineMoonlightIntegration/reference_build.py ios --root /private/tmp/maccompanion-engine
python3 Experiments/SunshineMoonlightIntegration/engine_build.py --root /private/tmp/maccompanion-engine --sdk iphoneos
python3 Experiments/SunshineMoonlightIntegration/engine_build.py --root /private/tmp/maccompanion-engine --sdk iphonesimulator --test-simulator YOUR_DEDICATED_SIMULATOR_UDID
python3 Experiments/SunshineMoonlightIntegration/reference_build.py ios-embedded --root /private/tmp/maccompanion-engine
python3 Experiments/SunshineMoonlightIntegration/candidate_inventory.py --root /private/tmp/maccompanion-engine
python3 Experiments/SunshineMoonlightIntegration/test_supervisor.py
python3 Experiments/SunshineMoonlightIntegration/test_process_owner.py
python3 Experiments/SunshineMoonlightIntegration/mac_probe.py --root /private/tmp/maccompanion-engine --seconds 12
```

The PIN probe uses `--pin-stdin --seconds 600`. Reuse only its own private directory
with `--data-directory`; never point it at an installed Sunshine configuration.
Launch the reference Simulator app with `MACCOMPANION_REFERENCE_SILENT_AUDIO=1`
only when intentionally testing video without audio. The default audio path is
unchanged. This flag is not used by a normal MacCompanion target.

After building the Simulator framework, `ios-embedded` links and embeds it in the
disposable reference client. Launch that app with
`MACCOMPANION_REFERENCE_EMBEDDED_ENGINE=1` to replace its native video connection
with `CompanionMoonlightVideoSession`. Existing upstream pairing and launch supply
the configuration, including required `serverCodecModeSupport`; this does not
implement MacCompanion credential enrollment. The extracted component is silent
and excludes input. Generated renderer and callback symbols are namespaced so
the framework can coexist with the reference client's original classes.

For an automated teardown check, also set
`MACCOMPANION_REFERENCE_AUTO_STOP=1`. Two seconds after a decoded frame, the
reference controller invokes its existing return-to-app-list path. Fixed logs
report the frame, requested Stop, and completed native drain. This seam does not
prove touchscreen gesture acceptance. Omit the flag for interactive playback.

Set `MACCOMPANION_REFERENCE_NORMAL_SURFACE=1` with the embedded-engine flag to
exercise the normal MacCompanion UIKit video surface and native owner against
the paired reference transport. This test uses synthetic local authority and
never enables input. It is not normal MacCompanion pairing/approval acceptance.
The owner keeps an opaque black cover while connecting or failed, checks actual
decoded dimensions, and retires on authoritative binding/deadline loss.

## Patch scope

The patch set adopts iOS scenes, decouples the renderer from upstream StreamView,
blanks it on Stop, adds a fixed first-frame diagnostic, permits explicit silent
reference audio, adds an explicitly enabled embedded-engine/automated-Stop test
route, removes stream keys from launch logging, and permits a validated
isolated Sunshine state directory. Invalid state overrides fail closed.

No application authentication, pairing protocol, capability grant, signature,
permanent target identity, or shipping TCC ownership was changed. The reference
uses upstream pairing; it does not prove MacCompanion enrollment or approval.

Keep generated apps, keys, certificates, pairing state, raw logs, captured pixels,
and input content outside Git. The probe stores them under a mode-0700 directory.
An upstream session can contain private launch data even when its own logging has
been narrowed. Do not copy raw diagnostics into repository evidence.

## Isolated managed enrollment probe

`test_managed_host.py --root <owned-reference-root>` builds a disposable Swift
probe outside the repository, against the production host enrollment coordinator
and client attestation owner. The backend generates isolated native credentials,
registers only the signed client certificate, checks the prepared server identity,
and reaps its finite helper before deleting private state. The probe checks
certificate admission, malformed enrollment, invalid proof, port conflict, and
revocation. It does not read or stop the user's installed Sunshine service.

The client uses temporary session custody and synthetic Control authority in this
probe. Normal primary messages, client TLS/launch, and release-target composition
remain unfinished. The backend is loopback-only with input and audio disabled.
The report hashes source inputs and executables and explicitly denies normal
primary-flow, physical-device, and release acceptance claims.

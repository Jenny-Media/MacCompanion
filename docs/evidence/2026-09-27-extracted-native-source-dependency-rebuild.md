# Extracted native dependency rebuild and offline Web UI

Date: 2026-09-27. Development source-delivery evidence; no release admission.

## Extracted dependency rebuild

`scripts/rebuild_native_source_dependencies.py` requires an explicit source-manifest SHA-256, checks the archive against its closed file map, and extracts into a new output directory. The frozen workspace builders rebuilt OpenSSL, miniupnpc, Opus and ICU for Mac, plus OpenSSL for iPhone and Simulator. All six configurations passed final installed-file/provenance checks; the retained source payload stayed unchanged. An incorrect manifest pin was rejected before output creation.

- Source packet: `/private/tmp/maccompanion-native-source-inputs-20260927-v2`.
- Source manifest SHA-256: `146be6eecba35e73aa7ff5d585cabfb4343fa6d2442fea6ae74a012424ee8216`.
- Archive SHA-256: `d62017a4a67553e0dd01d87dcd722ebee5ef3d987319246bc595cf54406a2d10`.
- Rebuild report: `/private/tmp/maccompanion-source-dependency-rebuild-20260927-v1/rebuild-report.json`.
- Report SHA-256: `ad949c6d1b2d4809a3469f811580710694cc76b23f9de971fa0748ee9747c9c9`.

These are fresh dependency artifacts. Their hashes differ from the tested original candidate; this does not claim bit-for-bit reproduction or fresh video acceptance for the rebuilt artifacts. No tested candidate was replaced.

## Sunshine Web UI package closure

`scripts/cache_native_web_dependencies.py` retained all 193 public npm archives from the frozen Sunshine root lockfile, verified each SHA-512 integrity and package identity, and recorded package license metadata and notice hashes. An isolated npm cache then imported the archives, installed with `npm ci --offline --ignore-scripts`, and built 81 Web UI assets with `npm run build`. Required index and PIN pages were present. The package lock and archives stayed unchanged.

The initial prototype rejected EJS's unusual archive root. The repaired parser accepts exactly one safe top-level package manifest and still verifies package name, version and integrity. The fresh second run passed.

- Web report: `/private/tmp/maccompanion-web-source-inputs-20260927-v2/web-source-inputs.json`.
- Report SHA-256: `e6d8ca8b16b9be2775232260ceacfb662b9f4a50f2c51299b3108b92add6e00c`.
- Lock SHA-256: `341acf09cb1f3176ac5d7e38c9c6b34835c61cef5084b4c181dc2c391bca97d2`.

Blank npm configurations and an isolated cache exclude developer credentials. Codecov/GitHub environment overrides are cleared; the upstream plugin runs without upload or telemetry. npm installation used offline mode; this is not an operating-system network-denial assertion for every subprocess. Some optional platform packages retain general-purpose build-tool binaries. Package metadata is not a legal compatibility or complete source assertion.

## Validation and remaining scope

Stable Xcode repository validation exited zero after both lanes: `/private/tmp/maccompanion-source-rebuild-handoff-validation.log` (109 indexed fixtures).

The source archive and npm inputs are separate artifacts. Full native codec, Sunshine, client engine and adapter reconstruction/rebuild from a delivered packet remains open, including Git metadata and source-only handling of unused vendored artifacts. Corresponding-source completion and release admission remain false.

Development normal-app composition can proceed in the lanes allowed by the dependency/process/TCC gates. Source-delivery progress alone does not admit an experimental component into a permanent target, and release source completion is not a blanket prerequisite for every development-only build.

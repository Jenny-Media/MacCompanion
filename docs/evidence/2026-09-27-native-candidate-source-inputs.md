# Native candidate source-input archive

## Purpose and scope

`scripts/package_native_sources.py` retains the development candidate's source
inputs before permanent dependency admission. It binds the source-built portable
Mac host package and both iPhone/Simulator client framework inventories. It does
not claim complete GPL corresponding source, an offline rebuild, or release
admission.

The archive includes selected first-party application/package/test/build/spec
sources, build documentation, upstream source trees with their admitted patches,
all initialized pinned submodules, six checksum-verified source archives, and
Mac/client source-build records. The six archives cover OpenSSL, miniupnpc, Opus,
ICU, Boost and nlohmann-json; the Mac and iOS clients share the pinned OpenSSL
source. Both SDK inventories contain engine, adapter and source-built OpenSSL
framework bindings.

Collection checks upstream revisions and modifications, rejects untracked
upstream files, verifies the actual host link inputs and installed dependency
prefixes, and rechecks source/build bindings after collecting. It also records
excluded prebuilt binaries and certificate/credential-shaped files from expanded
Git trees. No developer signing state, user data, private runtime state, audit
database or raw logs are selected. Unmodified official source archives retain
their upstream public test fixtures.

The source audit additionally covers the compiled NanoRS submodule at
`b1e3c22ca0cdc0bb83e3cd6ed1a2fc77869ed99a`, beyond the narrower historical Mac
reference source check. Its revision and tracked files match the pinned lock.
This adds source-delivery evidence; it does not silently change the old reference
builder's admission rules.

## Verified artifact

Output: `/private/tmp/maccompanion-native-source-inputs-20260927-v2`.
Archive: `native-source-inputs.tar.gz`, approximately 330 MiB.
There are 42 pinned Git source components and 17,355 retained files/symlinks.
The manifest records 20 excluded files in the expanded upstream trees.

Archive SHA-256:
`d62017a4a67553e0dd01d87dcd722ebee5ef3d987319246bc595cf54406a2d10`.
Source manifest SHA-256:
`146be6eecba35e73aa7ff5d585cabfb4343fa6d2442fea6ae74a012424ee8216`.
Bound host-package manifest SHA-256:
`57c2da8f82672ff585f2c541a5f21414c9e7c618ccd32632ee311bb633ed0056`.
Bound client inventory SHA-256:
`2537b3753249d002258316f88c371662bcf0c213fb1665498227a1f7316b353d`.
Native client source-input SHA-256:
`3d88c40f461e57dbbe2ac2daae5aa92b15aa396639a3cff2c7e003d76ba1a0e7`.

Archive creation normalizes ownership and timestamps. Verification reads every
archive entry, rejects invalid/duplicate paths and unexpected entry types, and
compares its complete file map against the retained source payload. An isolated
safe extraction passed full readback of all 17,355 entries. Modifying its copied
README was rejected as `Source payload changed`. The temporary extracted copy
was removed, leaving the original archive unchanged.

The initial v1 construction was superseded by v2, which adds build documentation,
both SDK artifact records and post-collection component reinspection. Artifacts
are retained outside the repository; no source archive or generated state was
committed.

## Validation and remaining requirements

The required stable-Xcode `bash scripts/validate.sh` lane completed with exit
zero, including 109 indexed fixtures, at
`/private/tmp/maccompanion-native-source-inputs-validation.log`. Product code and
wire/security behavior were unchanged. The [four-session live native package
checkpoint](2026-09-27-source-built-portable-native-host.md) remains the applicable
functional evidence; no new playback acceptance is inferred from this archive.

Offline reconstruction/rebuild proof remains open. The existing builders require
Git metadata and validate unused vendored binaries intentionally omitted here.
Sunshine's Web UI also needs its pinned transitive npm source closure. These
requirements must be addressed before setting `correspondingSourceComplete` or
source/build admission to true. Permanent process/TCC ownership, normal-app
composition, installation, actual system input and physical acceptance remain
open, as do native App/Window capture and visible-area bitrate.

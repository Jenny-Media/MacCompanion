# Source-built Mac host dependencies

## Completed source builds

The development host dependency lane now builds OpenSSL 3.5.8, miniupnpc
2.3.3, Opus 1.6.1 and ICU 78.3 from checksum-pinned upstream archives.
`scripts/native_host_dependency_sources.json` records the build inputs; it is
not a protocol fixture index. Archive hashes are checked before extraction and
the extracted regular files are compared against the archive before building.
Each installed prefix retains its license and file-bound build provenance.
The stable Xcode 27.0 toolchain targets arm64 macOS 26.0.

Build output: `/private/tmp/maccompanion-native-host-sources-20260927`.
All four builds completed successfully. Their provenance records cover 156,
24, 14 and 268 installed files respectively.

`scripts/build_native_host_codecs.py` builds the pinned Sunshine build-deps
FFmpeg, SVT-AV1, x264 and x265 sources. All seven required libraries are present:
avcodec, avutil, swscale, CBS, SVT-AV1, x264 and x265. The installed prefix and
its 183 files are recorded under
`/private/tmp/maccompanion-native-host-codecs-20260927/provenance.json`.
Hardware VideoToolbox and the upstream software encoders remain enabled.

## Repairs during the build

OpenSSL and miniupnpc completed on the first attempt. The GitHub Opus archive
address returned HTTP 404; the Xiph distribution mirror supplied the archive
with the same locked SHA-256. The complete runtime dependency lane then passed.

FFmpeg initially failed to link its compiler check because its separate link
command lacked the Apple SDK path. Supplying explicit linker flags exposed a
second missing SDK path in its build-time host compiler checks. The final build
supplies the same SDK through `SDKROOT` and linker flags, records both, and
completed successfully without modifying upstream sources.

The first host link exposed an x265 API mismatch: FFmpeg had selected Homebrew
API 216 while the pinned source-built x265 exports API 215. The upstream copied
source cannot resolve Git version metadata and omits its package descriptor.
The builder now supplies a descriptor for its own prefix, records the pinned
source tag and descriptor hash, and restricts package discovery to that prefix.
It also cleans FFmpeg's generated compiler outputs before rebuilding, because
changing discovery flags alone retained the stale API-216 object. The final
archive requests API 215, matching the source-built encoder. No upstream source
file was edited for this repair.

The host dependency audit additionally rejected Sunshine's default Homebrew
miniupnpc search result. The builder now puts the verified miniupnpc prefix
first in the executable's linker search. Source-built miniupnpc uses an
`@rpath` install name and ICU uses bare library install names; the development
audit resolves those only when exactly one verified source prefix contains the
named library. Packaging must rewrite those names before relocation.

The linker reports that some x265 assembly objects target macOS 27.2 despite
the requested 26.0 deployment target. The development build is for the current
macOS 27.2 machine; compatibility with macOS 26.0 is unverified and this warning
must be resolved before a permanent deployment-target claim.

## Verified host checkpoint

`scripts/build_source_native_host.py` builds Sunshine to consume these
verified prefixes and source-built codecs, with a descriptor for Apple's SDK
system libcurl. It records static and dynamic link inputs and rejects unexpected
Homebrew libraries. The final build completed successfully, with 25 actual
static link inputs and seven non-system runtime library inputs recorded under
`/private/tmp/maccompanion-source-built-host-20260927/provenance.json`.
The checksum-verified Boost 1.89.0 archive and its license hash are retained in
that record. The build runs from Sunshine's source directory so its version
metadata identifies the pinned `63d35f7` revision and the reviewed development
patches.

Host SHA-256:
`f73ab88612d2aa1502c10d40133ada08eb38f3c9d3118a32e149f468405a65c2`.

The host help/startup check passed with `DYLD_LIBRARY_PATH` explicitly restricted
to the four development source prefixes. This is a source-prefix startup check,
not proof of a relocated package. All four runtime dependency prefixes passed
a subsequent archive/source/installed-file recheck, and their OpenSSL executable
reports version 3.5.8. The required stable-Xcode `bash scripts/validate.sh` lane
completed with exit zero at
`/private/tmp/maccompanion-source-host-handoff-validation.log`, including all
109 indexed fixtures.

## Remaining evidence

The replacement portable package and its live Simulator journey remain separate
checkpoints. The previously passing portable package and Simulator evidence used
the older host/dependency artifact; those results are not transferred to this
new host. Retain complete transitive source notices and build records, fix the
assembly deployment-target warning, and verify the new packaged artifact before
repeating live playback/input/recovery acceptance.

These are development artifacts. Permanent process/TCC admission, normal-app
composition, installation and physical/system-input acceptance remain pending.
Native App/Window capture and visible-area bitrate work also remain pending.
No release admission or complete corresponding-source claim is made here.

## Later checkpoint

The [source-built portable native host](2026-09-27-source-built-portable-native-host.md)
supersedes the open deployment warning and package/Simulator checks above. The
assembly target is fixed and inspected, the new portable package passes integrity,
relocation and credential checks, and four live Simulator sessions pass through
that exact package. Permanent admission and normal-app/physical acceptance remain
open.

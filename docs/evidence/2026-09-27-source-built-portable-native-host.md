# Source-built portable native host

## Deployment repair

The x265 custom ARM assembly commands bypassed CMake's normal macOS deployment
settings. The codec builder now supplies explicit deployment and SDK arguments
to those commands and regenerates their owned assembly objects. It also passes
the deployment target in the build environment. After building, it inspects load
commands from every object in each of the seven required static archives and
rejects missing or newer deployment versions.

The final inspected versions are `26.0` for FFmpeg avcodec/avutil/swscale, CBS,
SVT-AV1, x264 and x265. Sunshine rebuilt successfully without the previous newer
deployment-target warnings. This repairs the artifact-level warning; runtime
compatibility on a physical macOS 26 machine has not been tested.

## Package construction and checks

`scripts/package_source_native_host.py` consumes the audited development host
record, verifies every source dependency prefix and actual static/dynamic link
input, and packages the host with its source-built runtime libraries and OpenSSL
executable. The supervisor is retained as a development helper. No Homebrew
runtime library is selected.

The collector resolves absolute, loader-relative, rpath and bare library names
only within the verified source library set. It rewrites library references to
package-local loader-relative paths, removes inherited search paths, and rejects
unresolved references. Nested binaries and the outer app receive development
signatures. Verification checks the closed package file map, construction
provenance, every nested signature and the package-local library graph.

The package retains source build records and OpenSSL, miniupnpc, Opus, ICU,
Sunshine, FFmpeg, x264, x265, SVT-AV1, Boost and nlohmann-json notices. Complete
transitive corresponding-source distribution and permanent admission remain
open; the development profile explicitly reports `correspondingSourceComplete`
and `releaseAdmitted` as false.

Package: `/private/tmp/maccompanion-source-portable-host-20260927-v1`.
Ten Mach-O files: Sunshine, supervisor, OpenSSL CLI and seven runtime dylibs.
Manifest SHA-256:
`57c2da8f82672ff585f2c541a5f21414c9e7c618ccd32632ee311bb633ed0056`.
Source host SHA-256:
`f73ab88612d2aa1502c10d40133ada08eb38f3c9d3118a32e149f468405a65c2`.
Packaged/signed host SHA-256:
`6affffcac3feffcb9009dfb3cbe2a90d285c7b0966a495b8855badace55cce2b`.

Strict package verification, host startup and credential generation/self-signature
verification pass without external loader or OpenSSL configuration. An isolated
copy relocated into a path containing spaces passes the same checks. A controlled
change to its copied network library is rejected as `Packaged files changed`.
The temporary relocation copy and credential material are removed afterward.

## Simulator evidence

The native Simulator lane selects the verified package explicitly and builds its
Mac TLS helper against the hash-verified source-built OpenSSL prefix. The existing
baseline path remains available for historical experiments. The new live journey
is a separate result from the previous package's acceptance.

The new journey passed on the dedicated iOS 27 Simulator
`8FF65ABB-572E-4EE4-9A9F-F61AA302A586`. One XCTest completed with zero failures
and four visible native sessions. It verified decoded video, correlated
presentation/input admission, direct iOS typing, visible keyboard dismissal,
Shift+Tab, Copy and pointer delivery, background revocation, reachability-loss
teardown, explicit fresh restart, Stop queue drainage and fresh Observe. The
exact package manifest was verified before and after the journey. Owned fixture,
Simulator lock and Agent state cleanup passed.

Evidence: `/private/tmp/maccompanion-agent-xpc-evidence.r17pzgp8`.
Report: `signed-simulator-report.json`; elapsed time: 495.459 seconds including
build/setup, with a 190.789-second XCTest session.
Combined source SHA-256:
`f12381c67507bc6eb034308e7f3f88afd28200c32738ee75a964abff3845829b`.
Native SDK source-input SHA-256:
`3d88c40f461e57dbbe2ac2daae5aa92b15aa396639a3cff2c7e003d76ba1a0e7`.
Probe support SHA-256:
`269304ba0925b83aa514034f05650fb7131ec0362ed0b8490f96fb6f93f93090`.

Each session verified an approved display sample of 5120x2134 physical pixels,
2560x1067 logical points and a 1920x800 encoded frame. Native input effects still
reach a synthetic host sink behind the real permit. This is loopback Simulator
acceptance through normal UIKit owners, not installed normal-app, real system
input, LAN or physical-device acceptance.

## Validation and remaining work

The required stable-Xcode `bash scripts/validate.sh` lane completed with exit
zero, including 109 indexed fixtures, at
`/private/tmp/maccompanion-source-package-validation.log`.

Permanent source/build admission and process/TCC ownership, normal-app
composition, signed installation, actual system input, physical acceptance,
native App/Window capture and visible-area bitrate remain open.

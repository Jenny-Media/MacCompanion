# WebRTC package feasibility checkpoint

The isolated B1 package probe passes on Xcode 27 beta. Native WebRTC is a
buildable candidate for Mac Companion's next streaming experiment. This
checkpoint is not a streaming benchmark or production integration approval.

## Verified result

| Check | Result |
|---|---|
| Pinned WebRTC 153.0.0 archive | Published SHA-256 matched before extraction |
| Swift 6 compile and link | Passed for arm64 macOS, iOS device and iOS Simulator |
| Output platform inspection | Mach-O platforms MACOS, IOS and IOSSIMULATOR; minimum OS 26.0; SDK 27.0 |
| Mac execution | Factory and screencast source created; H.264 encoder/decoder factories available |
| Synthetic frame | A 1280×720 buffer reached the local track's renderer callback with matching dimensions |
| Diagnostics | All three compiler logs and final Mac runtime stderr empty |
| Substituted archive | Rejected before extraction, compilation or execution |
| Required repository validation | `scripts/validate.sh` exited 0; 1,837 Swift Testing tests across 42 runs passed, along with the script validators and platform build checks |

The [machine-readable record](2026-09-12-webrtc-package-probe.json) includes the
exact package/artifact revisions, source hashes, target triples, compiler
version and observed callback result. It contains no screen, input, credential
or real session content.

## Corrections made during execution

The initial Mac execution could not allocate an IOSurface pixel buffer under
the restricted command sandbox (`CVReturn -6662`). The same executable passed
with ordinary macOS access. Screen Recording permission and a physical client
are not required for this synthetic check.

The compiler invocation now selects each SDK through both `xcrun --sdk` and
Swift's SDK argument. This removes the initial iOS sysroot warnings; output
load commands independently confirm the target platforms. Failed runs retain
partial results and diagnostic logs. The runtime check now fails if H.264 is
missing or the synthetic frame does not reach its local callback within five
seconds; calling a submission API alone is not treated as verified delivery.

## Boundaries and next work

- The iOS outputs are linked libraries. No Simulator or physical iOS app was
  installed or executed.
- The local renderer callback observes a raw local video track. No encode,
  decode, peer negotiation, network delivery or on-screen presentation was
  exercised. Codec availability is not proof of hardware codec use.
- The production app, grants, pairing state and media path are unchanged.
  Sunshine/RustDesk comparisons remain paused.
- Stable Xcode validation remains outstanding because only Xcode beta is
  installed. This does not block the disposable experiment.
- Next is a separate B2 experiment with two peers, a real video track and
  ScreenCaptureKit capture. Real capture needs its own macOS consent; physical
  iOS acceptance needs a signed runnable client and an available device.

Reproduction is documented in the
[probe README](../../Experiments/WebRTCProbe/README.md). The exact temporary
build, logs and linked outputs for this checkpoint are retained at
`/private/tmp/maccompanion-webrtc-probe-zrt4_5vd/`.
The full repository validation log is
`/private/tmp/maccompanion-webrtc-repository-validation.log`.

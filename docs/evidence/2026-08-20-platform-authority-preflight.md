# Platform authority preflight — 2026-08-20

## Scope

This is a negative baseline for the disposable `Experiments/PlatformAuthorityProbe` command-line identity. It is not evidence about the eventual signed Mac Companion menu app, TCC attribution, Persistent Content Capture entitlement, input posting, lock behavior, or release lifecycle.

## Toolchain

- macOS: 27.0, build 26A5416b
- Xcode: 27.0 beta, build 27A5218g
- Swift: Apple Swift 6.4 (`swiftlang-6.4.0.25.4`)

The planned release baseline remains stable Xcode 26.6. This beta result is provisional.

## Commands

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
MACCOMPANION_DISABLE_SWIFTPM_SANDBOX=1 \
bash scripts/validate.sh

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift run --disable-sandbox \
  --scratch-path /private/tmp/maccompanion-platform-probe-build \
  --package-path Experiments/PlatformAuthorityProbe \
  platform-authority-probe --preflight
```

## Result

- Package compile: pass, including availability-gated production-module ScreenCaptureKit configuration/filter construction, a concrete but uninstantiated stream-session adapter, unstarted VideoToolbox H.264 compression-session construction, and unposted Core Graphics event construction
- Four no-enumeration package tests bind the capture configuration to the frozen 1,920 by 1,200 and 2,304,000-pixel ceilings, 30 fps ceiling, queue-depth bound, video-range 4:2:0 pixel format, cursor-on policy, and audio-off policy
- Four injected VideoToolbox policy tests bind adaptive profiles to the 8 Mbit/s and two-second ceilings and prove fail-fast ordered application of realtime mode, H.264 High 4.1, disabled frame reordering, bitrate, frame rate, and keyframe frame-count/duration properties; the concrete `VTCompressionSession` property driver is compile-checked but never invoked by validation
- Five AVCC output tests construct exact bounded decoder configuration, including the approved High-profile 4:2:0 8-bit extension form; reject wrong, inconsistent, and oversized parameter sets before output allocation; round-trip parameter sets through a real in-memory CoreMedia H.264 format description; and copy a real in-memory `CMBlockBuffer` only through strict access-unit/keyframe validation
- Three encoded-sample tests normalize real in-memory `CMSampleBuffer` keyframe/delta attachments, bounded dimensions, AVCC bytes, and nonnegative nanosecond presentation time; seven injected encoder-owner tests prove initial/explicit clean-keyframe enforcement, strictly increasing source sequence and presentation time, one-in-flight/one-latest-waiting replacement, clean recovery after a stale-frame drop, awaited runtime publication backpressure, output rejection, submission failure, stop, and late-callback suppression
- The concrete `VTCompressionSession` adapter compile-checks requested hardware acceleration, exact profile application, per-frame clean-keyframe properties, correlated callback tokens, validated sample normalization, pending-frame completion, and idempotent invalidation, but validation never constructs it
- Eight injected publisher tests prove configuration-before-clean-frame ordering, AVCC validation through the runtime action boundary, unchanged-configuration elision, clean-only configuration replacement, same-fence discontinuity recovery, sequence-preserving new-fence transitions, monotonic timeline, exact end state, and fail-closed runtime rejection
- Seven ScreenCaptureKit tests use in-memory pixel/sample buffers and injected sessions/encoders to prove complete-frame/status/pixel-profile admission, one-newest callback buffering, serialized source sequencing, start/stop/system-stop/sample/encoder failure teardown, immediate encoder-terminal propagation, and exactly-once terminal reporting; the concrete `SCStream` adapter is compile-checked but validation never constructs or starts it
- Existing Screen Recording access for this CLI identity: false
- Existing Accessibility access for this CLI identity: false
- `SMAppService.mainApp` status from this non-containing executable: `notFound`
- Permission prompts requested: none
- Input events posted: none

## Interpretation

The selected Apple frameworks and API surfaces compile under the available beta SDK, and the probe's default mode remains non-authoritative. The package capture factory neither enumerates content nor creates or starts `SCStream`; the concrete stream adapter compiles but is not instantiated. VideoToolbox policy and owner tests inject their platform seams and never create a compression session. CoreMedia output tests allocate only caller-supplied in-memory format descriptions, block buffers, pixel buffers, and sample buffers. The concrete compression session is compiled but not instantiated. The experiment's remaining construction helpers are deliberately unreachable from CLI arguments during validation. This is not capture, hardware encoding, physical callback ordering, input, latency, or cleanup evidence. The negative permission/service values are expected for an identity-neutral command-line executable. No product feasibility conclusion can be drawn until the same behaviors are tested independently with the final signed menu-app identity on the stable release toolchain and physical-device matrix.

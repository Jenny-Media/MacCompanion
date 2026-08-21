# Client decoder and bounded render construction evidence

Date: 2026-08-20

Environment: Xcode 27 beta toolchain; package and iOS Simulator compilation

## Scope

The shared AVCC validator now supplies the exact same bounded configuration and
access-unit profile to Mac publication and client decoding. The client pure
authority:

- creates and invalidates explicit decoder generations;
- requires configuration and a clean keyframe after every discontinuity or
  reconfiguration;
- binds every command and callback to the complete surface fence, media
  sequence, timeline, dimensions, and generation;
- discards stale/out-of-order callbacks; and
- retains only one opaque latest-frame reference and blanks it on reset/end.

The concrete client-platform adapter compile-checks H.264 format-description,
block/sample-buffer, and asynchronous VideoToolbox decompression construction.
Its callback verifies exact pixel format, dimensions, and presentation time
before returning a local pixel buffer plus the pure-authority receipt.

## Result

The public validation entry point passed with 51 indexed fixtures and all 555
Swift tests, including six focused decoder-authority tests. The same run
compile-checked `CompanionClientPlatform` for the arm64 iOS 17 Simulator and
completed both Network-platform builds plus all three no-prompt/no-network
platform probes. Decoder replacement now drains submitted asynchronous frames
before invalidating the prior VideoToolbox session; timestamps outside
CoreMedia's signed range and end records with a mismatched surface fence close
the authority before a platform command is emitted.

## Reproduction

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/maccompanion-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/maccompanion-swiftpm-cache \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
MACCOMPANION_DISABLE_SWIFTPM_SANDBOX=1 \
bash scripts/validate.sh
```

## Boundary not claimed

The adapter is not instantiated by this evidence. No physical H.264 decode,
renderer, pixel-buffer lifetime, frame pacing, blanking screenshot, memory
pressure, thermal, background, orientation, or end-to-end latency result is
claimed. Those remain physical release gates.

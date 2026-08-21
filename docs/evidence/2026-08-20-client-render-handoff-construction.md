# Client render handoff and blanking construction evidence

Date: 2026-08-20

Environment: Xcode 27 beta toolchain; package and iOS Simulator compilation

## Scope

The client callback boundary now uses one lock-serialized pending slot and one
scheduled main-actor drain. Generation/sequence ordering prevents late older
callbacks from replacing a newer pending frame, a pending decoder failure
cannot be overwritten before classification, and concurrent callback pressure
does not allocate one UI task per frame.

The compile-checked main-actor coordinator is the sole composition point for
the decoder authority, VideoToolbox adapter, mailbox, and renderer. It admits
the exact callback receipt before presentation and synchronously blanks on
configuration, discontinuity, end, interruption, decoder failure, renderer
failure, and close. The UIKit surface accepts only exact v0 pixel format and
dimensions, constructs a display-immediate sample locally, uses aspect fit,
flushes pending layer work, and removes the image on blank.

## Result

The public validation entry point passed with 51 indexed fixtures and all 560
Swift tests. Five focused mailbox tests include 1,000 concurrent out-of-order
offers converging on the highest sequence. The same run compile-checked the
main-actor UIKit/AVFoundation composition for the arm64 iOS 17 Simulator,
completed both Network-platform builds, and passed all three
no-prompt/no-network platform probes.

## Reproduction

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/maccompanion-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/maccompanion-swiftpm-cache \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
MACCOMPANION_DISABLE_SWIFTPM_SANDBOX=1 \
bash scripts/validate.sh
```

## Boundary not claimed

No UIKit view or display layer was instantiated. There is no physical
blanking screenshot, decoded-frame presentation, display-layer asynchronous
failure observation, orientation/background transition, frame pacing, memory
pressure, or latency evidence. Those remain physical release gates.

# Virtual-display capture diagnosis

Disposable, metadata-only Mac-side probes, independent of the iOS app and not
linked into release targets. They require existing Screen Recording access; they
never request a grant, inspect/export pixels, type input, or change security,
power preferences or installed apps. A temporary display can cause macOS to
rearrange windows. The runner terminates its own helper in `finally`.

`MetadataCapture.swift` enumerates a specified display and counts ScreenCaptureKit
frame-status callbacks for five seconds, or checks only a screenshot's dimensions.
The `watch` mode records sixty one-second intervals, including the lid state and
display flags. A physical test delivered frames while closed, then lost the source
when WindowServer put the display to sleep. Its first sample was already closed,
so it does not establish the effect of pre-creating a display with the lid open.
Do not describe this run as a successful before/after pre-creation comparison.

`LegacyCapture.m` counts legacy CGDisplayStream callbacks for comparison only. That
API is deprecated in macOS 14 and obsolete in macOS 15; compiling with a macOS 14
deployment target does not make it a supported shipping fallback on newer macOS.
It is not part of a proposed client/server implementation.

Build with stable Xcode, keeping output and module caches outside Git:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -module-cache-path /private/tmp/maccompanion-vd-module-cache \
  -parse-as-library Experiments/VirtualDisplayCaptureProbe/MetadataCapture.swift \
  -o /private/tmp/maccompanion-vd-metadata-20261006

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun clang \
  -mmacosx-version-min=14.0 -fobjc-arc -fblocks \
  -framework Foundation -framework CoreGraphics \
  Experiments/VirtualDisplayCaptureProbe/LegacyCapture.m \
  -o /private/tmp/maccompanion-vd-legacy-20261006
```

Pass the existing MacTools virtual-display helper and compiled probe as explicit
arguments. The default runner performs stream and screenshot checks, then cleans
up. Its optional fourth argument is `watch` or `legacy`. Capture requires the
normal logged-in GUI session; sandbox-restricted display metadata may be incomplete.

See [investigation evidence](../../docs/evidence/2026-10-06-black-desktop-decoder.md).

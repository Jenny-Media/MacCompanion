# Capture/Encode Smoke Construction Evidence

Date: 2026-08-21

Environment: disposable `PlatformAuthorityProbe` under Xcode 27 beta on macOS
27.0 build 26A5416b. This is unsigned construction and a live permission-denied
preflight result. It is not real-pixel, signed-target, physical-device, or
release evidence.

## Boundary completed

The explicit `--capture-encode-smoke` command first calls
`CGPreflightScreenCaptureAccess()`. Permission denial returns before shareable-
content enumeration, `SCStream` construction, or VideoToolbox allocation. When
permission is already present, the inert construction path selects only the
display matching `CGMainDisplayID()` and composes the production Desktop
ScreenCaptureKit session, newest-only stream owner, low-latency VideoToolbox
session, and encoder owner at the frozen 1,920x1,200/30 fps profile.

The coordinator races one validated clean H.264 keyframe against closed capture
or encoder termination, cancellation, and a five-second timeout. A successful
sample is accepted only with exact dimensions, complete-frame admission,
nonempty validated decoder configuration and access unit, and clean-keyframe
truth. Success, timeout, and cancellation stop exactly once; terminal paths
use the production owner's cleanup. The command never requests permission and
the repository gate never invokes a TCC-sensitive route.

Output is a fixed 17-key JSON object. It contains no pixels, encoded bytes,
content-dependent byte counts, display IDs, app/window names or counts, bundle
identifiers, paths, raw timestamps, or Apple error descriptions. It makes no
hardware-encoder claim.

## Verification

- Eight injected tests cover exact mutually exclusive argument parsing,
  permission denial with no graph construction, missing main display,
  construction/start/terminal failures, exact clean-sample success, invalid
  sample terminal cleanup, timeout/cancellation, capture-stop failure, exact
  stop counts, and the closed JSON key set.
- The live command returned exit code 2 with
  `permissionPreflightGranted: false`, `result: permissionNotGranted`, null
  encoded dimensions/elapsed time, and every sample-validation flag false.
- The live denial produced no prompt and no permission-state mutation was
  requested. No real capture or encoder was constructed by that branch.

## Remaining gates

- Manually grant Screen Recording to the exact provisional executable on a
  designated test account, relaunch if macOS requires it, and require one clean
  validated sample within five seconds followed by bounded teardown.
- Confirm that no screenshot, media file, AVCC/access-unit blob, or content log
  is created, then revoke permission during a later run and prove closed
  termination.
- Repeat through the final signed menu-app identity and separately prove final
  TCC attribution, persistent-capture entitlement behavior, lock transitions,
  physical iPhone decode/render, latency, and energy/resource bounds.

# Simulator live-Control regression lab

Date: 2026-08-28. Local Xcode 27 beta / iOS 27 Simulator evidence, not stable-toolchain or release acceptance.

## Result and entry point

The disposable Simulator app can now run a live Control regression against
an isolated Mac test host without a physical iPhone, QR scanning, Face ID,
privacy prompts, registering an Agent, or changing the installed apps.

```sh
bash scripts/verify_simulator_features.sh
```

Use a booted iOS Simulator. The script preferentially selects a booted iPhone;
`MACCOMPANION_SIMULATOR_ID` selects another booted iOS device. Run one harness
instance per Simulator at a time. Temporary test keys/bootstrap files are
removed and the owned host process is stopped on exit. Logs and XCTest
attachments remain in the printed temporary evidence directory.

For repeated live-only runs:

```sh
MACCOMPANION_LAB_ONLY_LIVE=1 MACCOMPANION_LAB_ITERATIONS=3 \
  bash scripts/verify_simulator_features.sh
```

## Coverage boundaries

| Lane | Production behavior exercised | Deliberately simulated |
| --- | --- | --- |
| Live Control | Primary request/reply routing, P256 approval signature, role-product activation, runtime leases, H.264 encoder/decoder/display, surface handoff, UIKit gestures, composer, native keyboard, Stop/reconnect | Already-paired/authenticated primary, grant, role bootstrap, software presence signer, focus events, generated pixels, no-post input sink |
| Closed UI | Observe/status/activity, typed Act action, route guidance, lifecycle presentation, surface picker, Control controls | Status/action results, routes, reachability, and product fixtures |
| Pairing regressions | Normative crypto vectors, canonical pairing messages, dropped-completion recovery and exact-attempt ownership | Fault-injected transports/storage; no live QR camera or Secure Enclave |

The live lane uses separate loopback primary, input, and media sockets. It
asserts advancing decoded sequences **and visible non-black screenshot pixels**,
including after surface changes and reconnect. It crosses several lease
renewals, taps and pinches, repeats automatic focused-region/Desktop switching,
delays the primary selection response so media can arrive first, verifies
composed text and the exact native-keyboard sequence at the host, verifies
pointer/physical-key delivery, forcibly disconnects, reconnects, and stops.

App/window target discovery is covered by closed UI and package tests, not a
live Mac Accessibility inventory in this lane. Real TLS negotiation, real
pairing, persistent Agent/Keychain behavior, ScreenCaptureKit/TCC, actual input
posting, physical-network changes, and Face ID still need their separate
platform/device checks. This lab is not Stage 3 market-MVP or release evidence.

## Repairs found while bringing up the lab

- The real decoder did not explicitly request IOSurface-backed output. The
  Simulator decoded frames but displayed black. Requesting those buffers
  made the visible-pixel regression pass.
- The renderer used a buffer-level attachment for the sample-level
  immediate-display flag. It now uses the per-sample attachment dictionary
  and no longer flushes every frame before enqueueing. Apple's
  [display-layer contract](https://developer.apple.com/documentation/avfoundation/avsamplebufferdisplaylayer/enqueue(_:))
  distinguishes the attachment APIs and requires IOSurface-backed image buffers.
- Test-only setup mistakes were corrected separately: the initial paired
  record must be monitor-only, focus events have a two-second maximum
  lifetime, and focused-region descriptors require an application binding.
  These were fixture errors, not changes to production authorization rules.
- Frequent test telemetry originally rebuilt the Control view during menu
  presentation and prevented XCTest from reaching idle. A separate observed
  telemetry subview now owns those updates. Failure state is retained rather
  than overwritten with an obsolete Streaming label.
- A repeated run then exposed an intermittent beta Simulator animation-idle
  timeout during composer dismissal despite successful input delivery and
  advancing video. UIKit/SwiftUI animations are disabled in live-test mode
  only. Production animations are unchanged; animation performance is not
  covered by this test lane.
- Existing UI tests now scroll to offscreen controls on the smaller iPhone
  Simulator instead of assuming every row is visible simultaneously.
- Post-run inspection caught XCTest relocating the app data container. The
  runner now re-resolves the installed harness container on exit, removes
  the bootstrap from both original/current locations, preserves the run's
  failure status, and fails if current-container cleanup cannot be confirmed.

## Validation

- Full eight-test UI suite passed on iPhone 17 Simulator: **8 tests, 0 failures**,
  194.5 seconds. Evidence: `/private/tmp/maccompanion-feature-tests.lKztkL/features.xcresult`.
- With the test-only animation safeguard, **three consecutive live repetitions
  passed**, in 64.2, 62.7, and 62.6 seconds. No animation-idle timeout or host
  failure was recorded. Evidence:
  `/private/tmp/maccompanion-feature-tests.UaksHD/features.xcresult`.
- Final `bash scripts/validate.sh` passed: **1,714 Swift tests** across the package
  and platform probe, repository policy/fixture checks, and platform build checks.
  Log: `/private/tmp/maccompanion-simulator-lab-final-validation.log`.
- `git diff --check` and the new release-isolation check passed.
- Earlier live-only run also passed the pairing-regression checkpoint:
  `/private/tmp/maccompanion-feature-tests.fzR6Kc/`.
- The complete eight-test run also passed its pairing-regression checkpoint
  (`/private/tmp/maccompanion-feature-tests.lKztkL/pairing.log`).
- After the container-relocation cleanup repair, another live run and pairing
  checkpoint passed (`/private/tmp/maccompanion-feature-tests.p9dewP/`).
  Post-run inspection confirmed no bootstrap fixture remained in any data
  container on the selected Simulator, the host fixture was removed, and the
  isolated host process had stopped.

The beta toolchain emitted an auxiliary diagnostic-collection warning about
finding `simctl`; it did not prevent successful test execution or creation of
the `.xcresult` and screenshot attachments. A stable Xcode run remains required.

## Isolation

All bootstrap/signing shortcuts live under `Experiments/`. The host rejects
Release builds and binds only `127.0.0.1`; the client composition rejects
non-Debug and non-Simulator builds. Each run uses fresh software keys and a
private temporary bootstrap token. Shipping source/project dependency checks
reject references to the lab. No production grant, privacy permission, or
paired-device database was changed by these tests.

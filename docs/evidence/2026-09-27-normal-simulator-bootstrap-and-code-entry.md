# Normal iOS Simulator bootstrap and pairing code entry

Follow-up: [Simulator Keychain and live pairing verification](2026-09-27-normal-simulator-keychain-and-live-pairing.md) resolves the subsequent identity-key entitlement failure and proves normal-app live comparison/cancellation. This document retains the earlier code-entry checkpoint.

Date: 2026-09-27

## Product change

The admitted normal native Debug Simulator root selects an explicit first-party
Simulator bootstrap. The default bootstrap remains the protected-device path.
The development selector and storage-profile case compile only for Debug iOS
Simulator, and are absent from the physical-device executable. Simulator storage
uses `dev.maccompanion.simulator/iOS/v1` and a separate identity Keychain tag.
It checks regular-file/directory shape, symlink denial, exact private POSIX
permissions, backup exclusion, canonical installation identity and existing
single-host/route consistency. It does not claim hardware file protection.

Security.framework key custody may use software-backed keys in this mode;
existing approval user-presence requirements remain. This checkpoint never
created an identity key or attempted approval. Pairing, signatures, certificate
admission and independent Observe/Act/Control semantics are unchanged and retain
the existing golden cryptographic vectors. No experiment implementation is linked
into the normal app. The normal Simulator UI identifies its development mode.
The contract and single-index admission fixture were updated first.

The normal pairing UI now offers **Enter Pairing Code** alongside scanning. A
standard text-entry sheet supports typing and iOS's native text paste controls.
Use Code submits the exact text to the existing strict QR parser; dismissal or
submission clears the editor. No custom clipboard read runs on the UI thread.
The normal root supplies the same receivePairingScan handler used by the scanner.

## Verified normal-app UI

The normal application bundle `media.jenny.maccompanion.ios` now reaches
**Connect to Mac** in dedicated Simulator `8FF65ABB-572E-4EE4-9A9F-F61AA302A586`.
It no longer stops at the missing file-protection attribute. A repeatable XCTest
uses the normal root and real text editor/keyboard to prove:

- Invalid typed code is rejected and Try Again returns to entry/scanning.
- A runtime synthetic code, derived from the manifest-indexed public QR fixture,
  reaches the explicitly unverified fingerprint preview and Connect Securely.
- No connection or approval is made; no paired success is shown.
- Cancel returns to scanning. The authoritative fixture is unchanged.

One test passed, zero failed/skipped/expected failures. The runner verifies actual
xcresult counts and the Simulator platform, source/fixture readback and embedded
native framework equality. It records the tested executable separately from the
baseline build. Native text paste itself is not verified by this typing test.

Runner: `scripts/verify_normal_native_pairing_ui.py`.

Report: `/private/tmp/maccompanion-normal-pairing-ui-20260927-v4/report.json`

Report SHA-256: `8a671099f4972755f38d81316f86085da9469e8bc1b78f41ae653a9b38e8a990`

Native source inputs: `a1268e375bde85a8e230eb968b180aa946f28b72195ba25ca491e1831f38be4c`

Tested executable SHA-256: `420e9192a89a11040571c2f32c03d130b3f09e58eb48fcf6c54a4985040b6c01`

The normal app was relaunched after the test and remains at scanning/code entry.

## Builds and guards

Current native frameworks and normal app builds passed for both SDKs. Normal
builds disable Debug-dylib layout so executable hashes bind the actual app code.
The symbol check confirms the Simulator constructors are present in the Simulator
executable and absent from the physical-device executable; neither has a Debug
code dylib. Guard report: `/private/tmp/maccompanion-normal-bootstrap-compiled-guards-20260927.json`.

Simulator baseline: `/private/tmp/maccompanion-normal-simulator-bootstrap-build-20260927-v5`.

Device baseline: `/private/tmp/maccompanion-normal-device-bootstrap-build-20260927-v5`.

Stable Xcode 27.0 `bash scripts/validate.sh` passed, including 110 indexed fixtures,
package tests and required platform builds. Log:
`/private/tmp/maccompanion-normal-simulator-bootstrap-validation-v5.log`.

## Failed approaches retained

The Simulator clipboard command returned an empty pasteboard. Interactive tooling
reported taps without an observed transition, so acceptance moved to XCTest.
A direct clipboard reader froze the app's main thread in UIKit's string coercion;
its local process sample is retained at
`/private/tmp/maccompanion-normal-paste-stall-sample.txt`.
The system asynchronous paste control avoided the freeze but did not deliver
text in the tested Simulator transfer. Both failed test runs remain local; they
are not acceptance evidence. The final text editor has no direct clipboard reader
and its typed input, validation, preview and cancellation pass in XCTest.

## Remaining acceptance

This proves normal-app startup and unverified code-entry UI, not completed pairing,
hardware key custody, approval presence, a normal paired LAN primary or native
Control. The next normal-app step is authenticated pairing/connection and Control
with preserved approval semantics. Signed Mac GUI/TCC continuity, physical-phone
installation/acceptance, actual input, App/Window native capture, visible-area
bitrate and current corresponding-source assembly remain open.

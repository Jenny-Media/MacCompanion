# Normal App and Window native playback in Simulator

## Verified result

The normal iOS Debug app completes live pairing with the signed disposable Mac
Agent/menu and a source-built Sunshine host. In separate paired UI journeys it
opens Control, reads the real local ScreenCaptureKit target catalog, selects a
disposable animated App or its Window, and presents a fresh Moonlight stream
from that selected target. Each journey verifies current input admission and
keyboard, pointer, modifier, and shortcut delivery after selection. Stop retires
the stream, and a later explicit Control request presents a third native stream
without pairing again.

The App and Window journeys each pass one UI test and one exact owned pair-key
cleanup test, with three native presentations, host cleanup, and restoration of
the dedicated QA Simulator's original app and data. The Window journey also
verifies the selected window identity. Both use iOS Simulator
`8FF65ABB-572E-4EE4-9A9F-F61AA302A586` and the same source-built native host
package and normal iOS app binary.

## Failure and repair

The real target catalog exceeded the former local-XPC reply size and inventory
limit. The local lease transport now admits a bounded 192-entry inventory in a
64 KiB response, while other responses retain their smaller cap. Selection
tokens now survive 120 seconds of picker use and are revalidated against the
current source and authority at redemption. Native client enrollment admits
Desktop, App, and Window targets under their existing signed fields; Focused
Region remains denied.

The selected Sunshine child initially failed to open its private context because
the parent's root still contained the macOS `/tmp` symlink. The parent now
resolves that root with `realpath` before handing it to the child's strict
no-follow directory walk. Real App frames then reached the selected capture
filter but were rejected as future by a 5 ms timestamp limit. The filter now
allows up to 100 ms future skew while retaining monotonic frame ordering and
the two-second maximum age. The normative specifications and indexed fixtures
were updated for these changes; focused tests cover physical-root resolution,
symlink alias rejection, timestamp acceptance and rejection, and inventory and
enrollment bounds.

## Evidence boundary

- App run: `/private/tmp/maccompanion-native-app-timestamp-fix-simulator-20260928-v2/report.json`,
  SHA-256 `574d56d7b42daee71cd2ad2f3e9434be1bd5a4d28c29dca9d0ce2dd015c1ba3c`.
- Window run: `/private/tmp/maccompanion-native-window-timestamp-fix-simulator-20260928/report.json`,
  SHA-256 `2da8bb8e8a878556875688bd88dcba9b7ee39accfc0b3e07ea759387dcada1a5`.
- Normal iOS app binary SHA-256:
  `ab04fded620702066f192dbab7a27a642ca6045f4ff3727a2e84331cdbcdff3a`.
- Verified native host package manifest SHA-256:
  `044218fd1dfc85fc0d557027eae178485c9576421bc5f50fa628e9cb01a00883`.
- Indexed fixtures: 115 passed. Stable repository validation: passed.

The final input sink is synthetic, and the separate signed test process
substitutes Mac human consent. The normal installed Mac GUI, its continuous TCC
attribution, paired LAN, physical iPhone playback, and actual macOS system input
remain unverified. Viewport bitrate and current corresponding-source assembly
also remain open. Private reports and logs are test-only evidence; no screenshot,
typed content, or pairing secret is retained in source.

## Current iOS source recheck

After the display reply and Stop-status test changes, the exact current iOS
source fingerprint is
`5294389075d7388ceafb13f05672667eef254feeb986c12c115df8b4536f5c06`.
Fresh paired normal-app Simulator journeys again passed both real App and real
Window selection, three native presentations each, keyboard, pointer and
Shift+Tab input delivery, Stop, client key cleanup, host cleanup and original
Simulator app/data restoration. The Simulator executable SHA-256 is
`629a47fc96253fc3861a81532a78182b5a6fd1f7221558b98c35200ffdbbc7ae`.

- Current Window report:
  `/private/tmp/maccompanion-current-source-selected-window-final-20260928/report.json`,
  SHA-256 `5b20cf5975d7e0fd885849a72b5ef081b02dc3cd12a8f54ab4292c1893420a17`.
- Current App report:
  `/private/tmp/maccompanion-current-source-selected-app-20260928/report.json`,
  SHA-256 `22089a2e431a65a73bd53156b5e83ddbee0b41b2beb364a9358c49c70906b9bf`.

Three preceding Window attempts exposed a brittle UI test step after Shift+Tab:
the short sheet's offscreen Shift or Copy control was unavailable or did not
produce an observed input event, and a quick Copy button was not hittable after
scrolling. Those attempts passed selected Window playback and Shift+Tab but
failed the later Copy assertion. The later recheck below covers Copy and
Shift+Tab in all three journeys. Physical-device touch behavior remains open.

The required repository validation passed after the current App/Window test
change with 116 indexed fixtures. Private log:
`/private/tmp/maccompanion-validate-20260928-current-targets-final.log`,
SHA-256 `c98d5dbea72afa06f275f0d890608dbfc97edb60894a791d6649a9067e9607bf`.

## Shortcut and Control toolbar recheck

The simulator-only device-protection warning occupied the bottom safe area
during Control and covered the keyboard, shortcut, and Stop toolbar. It now
appears during setup and leaves the paired workspace's controls unobstructed.
The paired UI test uses the shortcut sheet in display order: select Shift,
send Copy, then send Tab. It requires a new admitted host input event for each
shortcut, and checks that the keyboard and Stop toolbar buttons are touchable
after closing the sheet.

Fresh paired Desktop, selected App, and selected Window Simulator journeys
pass on normal app executable SHA-256
`755a84acc485dbb5d907e5d6177437e71ac7cb697be4bacdb1c69df4ec73d0c5`.
Each run reports three native presentations, keyboard and pointer delivery,
both shortcuts, Stop, a later explicit Control restart, paired-key cleanup,
host cleanup, and original Simulator state restoration. The iOS source input
fingerprint remains
`5294389075d7388ceafb13f05672667eef254feeb986c12c115df8b4536f5c06`;
the warning change is simulator-only.

- Desktop report: `/private/tmp/maccompanion-shortcuts-sheet-order-desktop-20260928/report.json`,
  SHA-256 `b6b925ff0acf371f9450615d0494a10828db03a688d1b4bcb3d5b4cbf69f8c89`.
- App report: `/private/tmp/maccompanion-shortcuts-sheet-order-app-retry-20260928/report.json`,
  SHA-256 `fc1d293df55987cf90841b790ab4f0c6f43d4964e3e69228abee0bf518379e80`.
- Window report: `/private/tmp/maccompanion-shortcuts-sheet-order-window-20260928/report.json`,
  SHA-256 `be2a063ce01cf8c66bcbe1549579b9452900799ddd3457dbee2e6d35869cf611`.

An initial selected App rerun failed before pairing because the temporary Mac
helper could not be signed while the disk had 469 MiB free. Removing only
completed, rebuildable test build caches restored space; the fresh App run
passed. Required `bash scripts/validate.sh` also passed with 116 indexed
fixtures under Xcode 27.0. Private validation log:
`/private/tmp/maccompanion-validate-20260928-shortcut-banner-final.log`,
SHA-256 `91bfeb847b9c42aadbfde5d23d44b168680575cb7946c792fb6a69fe6691c260`.

These tests retain substituted Mac consent and a synthetic final system-input
sink. The installed iPhone app already contains the non-simulator Control
source, but the phone was locked when a physical launch was attempted.
Physical playback, actual Mac input posting, and installed Mac GUI capture
therefore remain unverified.

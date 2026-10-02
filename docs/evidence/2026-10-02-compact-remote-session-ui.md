# Compact remote session interface

Date: 2026-10-02 local. The user requested this interface pass before everyday
physical testing, using Screens screenshots as interaction references. The
working [Shared Display recovery](2026-10-02-shared-display-native-recovery.md)
was committed first as `2f118fe`.

## Changes

- Choose Display gives the topology diagram an explicit canvas and positions
  each tile by its center. The old offsets did not enlarge the intrinsic ZStack
  bounds, so its centered frame displaced the complete diagram outside the
  selectable area. Full names, resolutions and the current-display checkmark
  appear in readable selection rows below the contained map. The picker remains
  a sheet, preserving the admitted native renderer.
- One compact bar contains Keyboard, Escape, Tab, Shift, Control, Option, Command
  and session options. It stays above the native iOS keyboard. The bar's armed
  modifiers apply to the next supported key and then clear; selecting a modifier
  emits no remote held-key effect. Keyboard dismissal, input retirement and
  surface replacement clear the local selection.
- One Close/Stop action replaces the duplicate Back and Stop controls. Display,
  surface, pointer mode, zoom and extended shortcuts are available through the
  bar's session menu. Close/Stop remains accessible with the keyboard open.

The normative input mapping and existing manifest-indexed input fixture precede
the software-keyboard chord mapping. Unmodified commits retain Unicode text;
single supported modified ASCII keys use existing balanced HID chords, including
Shift for uppercase and shifted punctuation. Unsupported modified commits emit
nothing. Keyboard/Text grants, secure-focus checks, wire messages, signing and
pairing semantics remain unchanged.

## Verification

- Full `bash scripts/validate.sh` passes on stable Xcode 27.0 (`27A266a`), with
  118 indexed fixtures. The final validation log is listed below.
- The focused software-keyboard regression consumes ten cases from the sole
  manifest-indexed fixture, including balanced Command/Control/Option/Shift
  chords, Unicode preservation and omission of unsupported modified commits.
- Both native client SDKs rebuild for source input SHA-256
  `bcbeae582e98802b4f3a8e6dbbd70ad439824005ecfd84961c181923dcb3c75f`.
  The embedded native lifecycle suite passes 12 tests with no failures.
- Normal Simulator and iPhone development builds pass using the current native
  SDKs, with the normal source root and no reference probe. The signed physical
  build does not substitute approval user presence.
- The complete normal-app Simulator journey passes runtime containment of every
  display tile, one Close/Stop control, bar placement above the native keyboard,
  and clearing Command after a software-keyboard chord. It also passes both
  Shared Display replacements, real Window selection, keyboard/pointer/modifier/
  shortcut delivery, Stop/start and cleanup, with five fresh presentations.
- Private XCTest screenshots were visually inspected for the contained display
  map, readable rows, single Close/Stop and keyboard bar. Test keys are deleted,
  the disposable host is retired, and original Simulator app/data are restored.

The Simulator journey substitutes human Mac consent and final input effects.
It does not establish physical keyboard effects or everyday acceptance.

## Installed development update

The update is installed on the freshly verified physical iPhone 18 Pro Max.
Its existing application identity and signed entitlements are preserved, its
profile permits that phone, and strict signature verification passes. Signed
executable SHA-256:
`341f2fae0dd53dcd8fe9bb701ad47d9638de5089653cdd703b2823431fc815b2`.
CoreDevice confirms the normal `media.jenny.maccompanion.ios` app is installed.
Existing app data and pairing were retained; no uninstall or reset occurred.

The launch request was denied because the phone was locked. The user has been
asked to unlock it and open the app for a focused display/keyboard check. Physical
confirmation of this new interface remains pending. The already installed Mac
and Agent continue to use the prior verified Shared Display repair; this client
interface pass requires no Mac host change.

## Remaining work

The [All Displays plan](../plans/2026-10-02-remote-session-ui.md) recommends an
optional combined live overview with zoom. The existing host capture and input
geometry admit one physical display. Combined capture, exact topology and pointer
routing therefore require a separate host feature; All Displays is not yet
implemented or exposed in this interface pass.

Everyday physical input/recovery/elapsed testing, native Release admission,
distribution signing, Mac notarization and refreshed corresponding-source
delivery remain open. The prior frozen source archive predates these changes.

## Private evidence

Screenshots, profiles, device identifiers, runtime stores and input content remain
outside the repository:

- Final validation: `/private/tmp/maccompanion-compact-controls-final-validation-20261002.log`.
- Focused mapping regression: `/private/tmp/maccompanion-compact-keyboard-regression-20261002.log`.
- Native source inventory: `/private/tmp/maccompanion-native-compact-controls-20261002/native-video-candidate-inventory.json`.
- Native lifecycle tests: `/private/tmp/maccompanion-native-compact-controls-20261002/logs/embedded-lifecycle-tests.log`.
- Passing normal-app journey: `/private/tmp/maccompanion-native-compact-controls-journey-20261002/report.json` and `result.xcresult`.
- Private UI captures: `/private/tmp/maccompanion-compact-controls-screens-20261002/manifest.json`.
- Normal device build: `/private/tmp/maccompanion-normal-iphone18-compact-controls-20261002/build-report.json`.
- Signature verification: `/private/tmp/maccompanion-iphone18-compact-controls-signature-20261002.json`.
- Install, launch denial and installed-app readback: `/private/tmp/maccompanion-iphone18-compact-controls-install-20261002.json`, `/private/tmp/maccompanion-iphone18-compact-controls-launch-20261002.json`, and `/private/tmp/maccompanion-iphone18-compact-controls-installed-app-20261002.json`.

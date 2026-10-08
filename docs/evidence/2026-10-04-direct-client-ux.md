# Standalone client UX follow-up — 2026-10-04

## Scope and diagnosis

The user confirms the standalone direct app works. Display selection disappeared
because the removed helper had supplied display bounds; the direct composition
had no replacement metadata callback. The viewer also retained the ambiguous
Pointer → Drag → Pan cycle and both My Macs and Disconnect navigation.

## Changes

- Request Apple display-layout pseudo-encoding 1105 through LibVNCClient’s existing
  extension interface. Independently bound/decode version-5 metadata; do not
  modify upstream, authentication, resolution or display arrangement. One pending
  layout callback is coalesced, generation-fenced and discarded after Stop.
- Use compatible normalized regions to crop presentation and confine pointer
  input. Removed/invalid bounds return to the working combined desktop. The
  complete framebuffer is still received. Unknown revisions cannot invent crops.
- Pointer and Trackpad are the only mouse modes. Trackpad motion is relative to
  the cursor, tap clicks in place, two fingers scroll, and hold-and-move drags in
  both modes. Mode/view/lifecycle cancellation releases held buttons. Pinch and
  two-finger double tap remain local; canvas pan uses two fingers in Pointer and
  three in Trackpad.
- One Done button disconnects and returns to My Macs. Connect is inside the
  sign-in form, never a second active-session exit. Native diagnostics no longer
  appear as counters in the user-facing header.
- Searchable/sorted My Macs, visible management menu, Add button, empty state,
  labeled editor, separate setup guide and saved-login removal. Existing record
  format, atomic storage and credential deletion contracts are preserved.

## Verification

- Actual hosted native/Swift tests: 12 passed, zero failed/skipped. Result:
  `/private/tmp/maccompanion-direct-vnc-ui-final-tests-20261004.xcresult`.
  Includes metadata stream framing, stale callbacks, absolute/relative cursor
  behavior, button release, scroll events, changing/missing display IDs and
  resize fallback; retains direct connection and library regressions.
- Actual native parser: 12 authoritative metadata cases cover truncation,
  duplicates, overflow, unknown versions, degenerate/out-of-bounds records,
  mirrored rectangles and opaque trailing bytes. Indexed manifest hash updated.
- Required `bash scripts/validate.sh`: stable Xcode 27.0, exit 0. Evidence:
  `/private/tmp/maccompanion-direct-vnc-ui-validation-final-20261004.log`.
  All 133 indexed fixtures and full repository gates pass.
- Actual Simulator screens inspected: My Macs, management menu/editor, viewer,
  Pointer/Trackpad menu, gesture help and Done navigation. No Mac password or real desktop
  pixels were captured. Screenshots remain outside Git.
- Normal source-built iPhone app, existing profile/device/Keychain group and deep
  signature verified. Current application input hashes match signed installation.
  Binary SHA-256: `c5d68376c4b9c0cfbae1742460fad756e39f9862db09868a6a5111081459666e`.
- iPhone 18 Pro Max install succeeded, database sequence 8132:
  `/private/tmp/maccompanion-direct-vnc-ui-install-20261004.json`.
  Signed report: `/private/tmp/maccompanion-direct-vnc-ui-signed-ios-20261004/report.json`.
- Automatic physical launch denied by iOS because the device is locked. The
  updated app is installed, not uninstalled/recreated; saved data is preserved.

## Open acceptance

The subsequent phone screenshot still showed only All Displays. The capability
request defect and new indicator picker are tracked in
`2026-10-04-direct-display-picker.md`; this entry records the earlier build.
Physical gesture behavior still requires the phone check. Synthetic acceptance does not prove server support. For an
unsupported layout version the menu retains All Displays with an explanation.
No Mac helper is introduced. Public secure transport/distribution and longer
physical recovery/soak gates remain open. No commit, push or public deploy.

## Primary implementation reference

The [iShareScreen display parser](https://github.com/renegadelink/iShareScreen/blob/main/src/isharescreen/proxy/protocol/rfb.py)
and [its metadata framing](https://github.com/renegadelink/iShareScreen/blob/main/src/isharescreen/proxy/session.py)
provide the observed version-5 body/record format; our independently implemented
parser rejects malformed layouts atomically and leaves framebuffer sizing to
existing standard RFB handling.

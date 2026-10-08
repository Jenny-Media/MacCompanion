# Direct display selection repair — 2026-10-04

## Reproduction and cause

The user's physical screenshot shows only All Displays despite a combined
multi-display desktop. The first repair requested Apple layout encoding 1105
alone and tested only direct parsing of synthetic bodies.

A content-free iPhone snapshot from that build reports 0 display-layout messages
while framebuffer updates and input continue. It does not establish acceptance
on the user's multi-display Mac. The installed macOS 27.2 (26B5091g) server's
HandleSetEncodingsMessage sets its legacy send-display-info capability for 1101;
1105 separately selects the newer record format. SendResolutionChargeToViewer
checks the legacy capability before invoking EncodeDisplayInfo. Therefore
requesting only 1105 never opens that delivery gate on this server.

Read-only static analysis of Apple's existing screensharingd, SHA-256
`dfe1dca5d0b9fcea010702822e9d1a1793b7d1a209c1d0c9d2d1f115434cc7a4`,
identified these arm64e paths:

- 0x10003d604: 1101 enables the send-display-info flag.
- 0x10003d2f4: 1105 selects display-info version 2.
- 0x100024c6c: display delivery checks the send-display-info flag.
- 0x10001beb8: enabled delivery chooses the new format.

The disassembly and numeric runtime snapshots remain in private temporary
storage. No raw payload, pixels, endpoints, credentials or typed content was
retained in the checkout.

## Changes

- Request 1101 followed by 1105 through the pinned upstream extension API.
  Consume legacy 1101 bodies without applying unsupported geometry.
  Authentication and upstream source stay unchanged.
- Update the normative direct profile and its sole indexed fixture first.
- The actual-library stream regression now captures SetEncodings, checks both
  capabilities against the authoritative fixture, and delivers framed metadata
  through HandleRFBServerMessage and the production extension callback.
- Replace the text-only action menu with a compact native display picker.
  Each display has an aspect-correct arrangement indicator, numeric dimensions
  and selected checkmark. All Displays highlights the complete arrangement.
  Resolve selection against the latest layout ID; refresh an open picker when
  layout or framebuffer geometry changes. Invalid/missing geometry retains
  the complete desktop with explanatory text.
- Selection remains local crop/input confinement on the current RFB owner.
  No helper, new session, remote resolution or rearrangement message is added.
- A bounded latest development diagnostic cache contains fixed counters and
  numeric display geometry only; no credentials, images, endpoint or input text.

## Verification and installation

- 14 native/Swift hosted Simulator tests passed, 0 failed/skipped:
  `/private/tmp/maccompanion-display-negotiation-tests-20261004.xcresult`.
- Actual native parser: 12 authoritative layout-boundary cases pass, plus
  existing endpoint/login vectors. Manifest canonical hash updated.
- The native arrangement picker was visually inspected using only synthetic
  geometry. The actual popover is readable, contained and shows selected state.
  Screenshot and xcresult remain outside Git.
- Required `bash scripts/validate.sh`: stable Xcode 27.0, confirmed exit 0.
  Log: `/private/tmp/maccompanion-display-picker-validation-20261004.log`.
- Signed normal iPhone 18 Pro Max app installed successfully, database sequence
  8148; saved application data and the existing Keychain group are preserved.
  All installed application input hashes match the current source.
  Install receipt: `/private/tmp/maccompanion-display-picker-install-20261004.json`.
  Signed report: `/private/tmp/maccompanion-display-picker-signed-ios-20261004/report.json`.
  Signed binary SHA-256: `540714ca23b245d9c55ae2f9b3f394ba9045a7139b87e6bf91caa824ff79b9ff`.

- Automatic launch was denied by iOS because the device is locked. The app
  is installed and can be opened after unlock.

## Physical acceptance

A fresh connection to the user's multi-display M5 is requested. Successful live
metadata parsing and display-to-display switching have not yet been confirmed
for this installed correction. Do not treat the synthetic tests or install as
physical acceptance. Public distribution/transport gates remain separate.
No commit, push or public deployment was requested.

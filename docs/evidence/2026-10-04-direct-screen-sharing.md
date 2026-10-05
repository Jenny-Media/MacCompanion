# Standalone Screen Sharing client — 2026-10-04

## Product and runtime

The product owner explicitly removed required and optional Mac helper apps.
The normal VNC development iOS entry point now starts DirectMacLibraryRootV1.
Its build links LibVNCClient and OpenSSL, with no MacCompanionKit package products
or native Sunshine/Moonlight engine. Symbol inspection of the final signed app
finds no IOSClientReleaseApplicationV1, NetworkClientDesktopTunnelV1 or
ClientInteractivePrimaryChannelV0 runtime. Legacy source, grants and fixtures
remain for compatibility; the standalone client does not instantiate them.

The direct RFB owner resolves once and connects to validated local numeric
IPv4/IPv6 endpoints at TCP 5900. It keeps the pinned upstream ARD-only login
scheme, bounded framebuffer/cursor handling and ordered one-shot modifier input.
Stop cancels DNS wait/TCP/handshake and bounds a stalled read. Replacement viewers
fence old status/frame/cursor callbacks and wait for prior native retirement.
Display and zoom changes make no new RFB connection.

My Macs saves multiple names/addresses with atomic publication and visible read
failure. Direct login retention has a separate Keychain service and existing
Keychain entitlements. Address changes, removal and opting out delete the direct
login. Legacy credentials and pairing keys are not reused or erased.

Exact window fitting and individual-display selection are deferred because the
server's complete display/window metadata has not been verified. The combined
desktop and tap-centered zoom/fit remain available. ARD login encryption does not
encrypt framebuffer/input traffic or pin the peer. Setup and website disclose a
trusted-local-network development connection; secure transport is a release gate.

## Verification

- Stable Xcode 27.0 (27A266a), required bash scripts/validate.sh: exit 0.
  Evidence: /private/tmp/maccompanion-direct-vnc-validation-final-20261004.log.
- 133 sole-index fixtures validated; actual native helpers pass 21 numeric endpoint
  and seven UTF-8 login boundaries, plus existing keyboard/cursor/viewport cases.
- Nine hosted Simulator tests pass, zero failures/skips, including a greeting from
  built-in Screen Sharing through the actual native direct connector; no real
  credentials, framebuffer request or input are sent by this greeting check.
  Result: /private/tmp/maccompanion-direct-vnc-tests-20261004.xcresult.
- Other hosted checks: no-auth refusal, stalled-handshake Stop, old-owner status
  fencing, multiple-Mac persistence/deletion, corrupt-file preservation, viewport,
  cursor and retired cursor delivery. Synthetic input/pixels only.
- Actual UI add/save/open-login verification initially reproduced disabled Save
  after editing a sheet's address. A dedicated editor owns its input state;
  Save now enables and returns the new row, which opens the direct login viewer.
- launchctl bootout stopped the Mac Companion Agent; the menu app was terminated.
  A subsequent process inventory confirms zero host/Agent processes. Apple's
  Screen Sharing still serves its greeting. Installed Mac files were not deleted.
- Website standalone setup response verified at http://127.0.0.1:4173/. Browser
  automation was rejected by its URL policy; no alternate browser workaround used.

## Device delivery

The normal iPhone update is development-signed with the existing profile and
Keychain group, deep-signature verified and installed on the iPhone 18 Pro Max.
The matching source-input digest check passes after install.

Final signed app:
/private/tmp/maccompanion-direct-vnc-signed-ios-ready-20261004/Mac Companion.app

Binary SHA256:
b5029db0b5ccd03cdddd3c6052d29b314ccb125be010e2a1bdff970a25bcd074

CoreDevice install evidence:
/private/tmp/maccompanion-direct-vnc-device-ready-install-20261004.json

Automatic launch was denied because the phone is locked. The user has been asked
to add this Mac and sign in directly in the app, keeping the password out of chat.
A 30-second physical desktop session is pending. Longer switching, background,
network recovery, resize/input/cursor acceptance and production admission remain
open. The tests above do not establish physical or production reliability.

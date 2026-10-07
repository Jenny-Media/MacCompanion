# External TestFlight review package

Updated 2026-10-06 for the user-authorized public beta. This replaces the legacy
Observe/Act/pairing review draft with the product in
[remote-desktop-mvp.md](remote-desktop-mvp.md): one iOS client using built-in
macOS Screen Sharing and optional Remote Login. No Mac app or helper is required.

Apple's [external testing instructions](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers)
require an externally eligible upload and Beta App Review. Builds uploaded as
TestFlight Internal Only cannot be added to the public group. Public beta
authorization does not close the separate production release gates.

## Beta app description

Your Mac, from your iPhone. Mac Companion connects directly to your Mac's
built-in Screen Sharing for remote desktop and to Remote Login for an SSH
Terminal. No Mac Companion app or helper needs to be installed on the Mac.

Use Pointer or Trackpad controls, a keyboard with modifier keys, display
selection, zoom, and a floating controls menu. Save multiple Macs with local
and private-VPN addresses. Terminal supports passwords and named Ed25519 SSH
keys. Optional Face ID protects local app access; optional iCloud sync is off
by default and excludes passwords and private keys.

Use a trusted local network or private VPN. Screen Sharing desktop and input
traffic are not encrypted by this app. The Mac must be awake and accessible,
and you must have permission to access its account. During this beta, keep a
Mac notebook's lid open; virtual-display-only closed-lid capture remains under
investigation. iOS 26 or later is required.

Basic desktop and Terminal functions remain free. Optional Pro features use
Apple's TestFlight sandbox; beta purchases do not charge real money.

## What to test — 1.0 (5)

1. Enable Screen Sharing on a Mac you own, add its local/private-VPN address,
   and connect with an allowed Mac account. Keep a Mac notebook's lid open.
2. Try the compact login sheet with a saved login and with manually entered
   credentials. Check progress, cancellation, retry, and Connection Details.
3. Test Pointer and Trackpad input, zoom, display selection, keyboard/modifiers,
   press-and-slide controls, and background/resume. Check that the full desktop
   appears after login, reconnect, and display layout changes.
4. Optionally enable Remote Login, then open Terminal from that Mac's menu.
   Verify the SSH fingerprint through a trusted channel. Try password or key
   login, number/modifier keys, the floating menu, and keyboard/fullscreen mode.
5. Try light/dark appearance, landscape, and larger text. On iPhone Duo, check
   expanded and tabletop layouts.

Send the app/build and OS versions plus the exact issue. Remove passwords,
private keys, sensitive screen content, and private network details from feedback.

## Beta App Review notes

Mac Companion is a generic remote-desktop and SSH client for a user-owned Mac.
There is no Mac Companion account, vendor relay, hosted Mac, software catalog,
remote app installation, or Mac Companion helper. Mirrored software runs on
the reviewer's Mac. This build uses built-in macOS Screen Sharing (RFB/VNC)
and optional Remote Login (SSH), independently.

Review setup:
1. Keep a reviewer-owned Mac awake on the same trusted local network as the
   iPhone. For a Mac notebook, leave the lid open during this beta.
2. On the Mac, open System Settings > General > Sharing > Screen Sharing.
   Enable it and allow your reviewer-controlled Mac account. Use its local
   address or hostname shown in Sharing.
3. In the iOS app choose Add Mac, enter a name and that address, and Save.
   Tap the saved Mac, enter the allowed Mac account credentials directly in
   the app, and Connect. No vendor account or supplied demo login is needed.
4. Test generic desktop control. The floating controls menu includes display,
   input, view, connection details, and Done actions. Display selection crops
   the shared desktop locally; there is no individual app/window capture.
5. Optional Terminal: enable Remote Login for the reviewer account on the Mac.
   Open the saved Mac's menu > Terminal, verify the SSH server fingerprint
   against a trusted Mac-side value, then connect with the reviewer account.
   Terminal does not require a desktop session.

Screen Sharing login uses the Mac account authentication supported by macOS;
desktop pixels and subsequent input are not encrypted by this app. The review
path is a trusted LAN; users can also use their own private VPN. SSH encrypts
Terminal traffic. Saved credentials and private SSH keys are in this device's
Keychain. Optional Face ID and iCloud settings are off by default; iCloud sync
excludes passwords, private keys, trusted SSH fingerprints, and snippets.

Pro purchases and the 14-day trial are optional. Basic desktop and Terminal
work without Pro. TestFlight uses Apple's purchase sandbox. The app does not
have a mandatory vendor sign-in. Reviewer-controlled Mac account authentication
is required only to reach that Mac.

Requirements: iOS 26 or later; a reachable Mac with Screen Sharing and/or Remote
Login enabled. Physical host testing currently uses macOS 27. Some closed-lid
virtual-display configurations can stall macOS capture; keep the lid open.

Support: https://mac.jenny.media/support/
Privacy: https://mac.jenny.media/privacy/
Feedback email: hijennytv@gmail.com

## Candidate and delivery evidence

- Use the existing exact app/widget identifiers and App Store signing profiles.
- Commit the approved source and bind the archive report to its input hashes.
- Keep signing material, archive/upload logs, and screenshots outside Git.
- Preserve the separate stable-toolchain, RC archive, physical acceptance,
  upload, processing, internal assignment, Beta App Review, and public-link states.
- Enter current contact information from the authorized App Store Connect account.
  Do not put personal reviewer credentials or account secrets in review notes.
- Record submitted metadata and Apple's exact review status in release evidence;
  a submission is not approval or public App Store availability.

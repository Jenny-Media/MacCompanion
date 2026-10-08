# Shared app artwork and local website preview — 2026-10-03

## Scope

The user approved the Linked screens icon and requested integration into the
local Mac and iOS apps plus a local website preview. The original built-in
imagegen artwork is retained at `Branding/app-icon.png`, with its exact prompt
in `Branding/README.md`. Master SHA-256:
`35c27b49f0eb1a90294625f8a3de7c502187127dd932f445efd561921f418d04`.

`scripts/export_brand_assets.py` uses macOS sips to resample that artwork into
native app catalogs and website assets. The macOS catalog includes ten native
size/scale entries; iOS uses one opaque 1024-pixel universal source. Both normal
targets select AppIcon. The checked-in Xcode project is regenerated. The existing
Mac local-command URL scheme is now explicitly retained in project.yml so
regeneration preserves the existing Info.plist declaration. No authentication,
pairing, grants, wire behavior, signing identity, or streaming code changed.

No branded launch delay or extra splash screen is added. No public release,
public website deployment, source publication, or TestFlight delivery occurred.

## Verification and installation

- Required `bash scripts/validate.sh` passes with stable Xcode 27.0 and 121
  indexed fixtures. Private log:
  `/private/tmp/maccompanion-brand-stable-validation-20261003.log`.
- Signed normal Mac/Agent, normal native iPhone, and normal native Simulator
  builds pass. Both iOS builds retain the previously verified native source
  fingerprint `df38cd48ab2d5d40813da4135d5162e9e03337a0d02628fed507a07018d94bb2`.
  The icon change requires no native framework rebuild.
- Compiled macOS output contains AppIcon.icns and Assets.car with AppIcon bound
  in Info.plist. iOS output contains Assets.car, device icon renditions, and
  iPhone/iPad CFBundleIcons entries bound to AppIcon.
- The Mac app is installed and launched at
  `/Users/yihong/Applications/Mac Companion.app`. The existing Agent service,
  signed entitlements, and all 119 pinned Sunshine files are retained. The
  installed icon resource matches the signed stage. Rollback copy:
  `/private/tmp/maccompanion-mac-pre-brand-20261003.app`. Private receipt:
  `/private/tmp/maccompanion-brand-mac-installed-20261003.json`.
- The paired physical iPhone 18 Pro Max installation succeeds using the same
  application identity, profile and signed entitlements, without uninstall or
  data reset. Private receipt:
  `/private/tmp/maccompanion-brand-iphone18-install-20261003.json`. Automatic
  launch is denied because the phone is locked, not because of an app crash.
- The normal Simulator app installs, launches, and visibly renders its pairing
  entry screen. This verifies launch, not physical streaming/input acceptance.

## Website

Static authoring is in `Website/dist`; local instructions are in
`Website/README.md`. Local preview: <http://127.0.0.1:4173/>. The server binds only
to loopback. The site explains separate Observe/Act/Control access, keyboard
controls, two-app setup, compatibility, licensing and current beta availability.
Public downloads and TestFlight are explicitly unavailable; All Displays and
connection reuse are described as pending work. No external form, analytics,
credentials, fonts or private screenshots are included.

JavaScript syntax, successful HTTP serving, browser rendering, loaded image
assets, feature tabs, keyboard tab navigation, FAQ disclosure, and a 430-pixel
mobile layout without horizontal overflow pass. Browser console shows no
warnings or errors. Screenshots and receipts remain private outside Git.
Private summary: `/private/tmp/maccompanion-brand-local-preview-20261003.json`.

Physical-device icon/launch acceptance awaits unlock. The existing streaming
reconnection delay and production distribution gates remain separate work.

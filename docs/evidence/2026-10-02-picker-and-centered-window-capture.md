# Useful target picker and centered Window capture

Toolchain: stable Xcode 27.0 (`27A266a`). This is development testing and
installation evidence, not production distribution or physical acceptance.

## Physical findings

The iPhone 18 Pro Max's content-free trace matches three separate failure paths:

- A Window native launch failed with `invalidResponse`. The new bounded host
  diagnostics report `selected-capture-sample-rejected=7`, then stream error 6
  and `no-working-encoder`.
- A later selection failed local target resolution with `sourceUnavailable`,
  ending the primary connection after the window had briefly appeared.
- Another replacement connected, then the backend watcher retired with
  `permitCurrent=false`, `selectedCaptureCurrent=true`; the native driver
  disconnected with code -102. This trace alone does not establish which owner
  first retired the permit. No independent claim that this last race is fixed.

The screenshots also show disabled helper applications and generic window labels.

## Reproduction and repair

A private ScreenCaptureKit metadata-only probe captured six visible Chrome and
ChatGPT windows without saving pixels or titles. Their logical size was 2560 by
1036 and their even encoded size 1920 by 776. Default independent-window output
started at x=0. The admitted centered aspect-fit rectangle starts at approximately
x=1.23552 encoded pixels. This exceeds the one-pixel sample check and reproduces
the code-7 rejection. Explicit `destinationRect` placement reduced the measured
origin error below 0.000001 pixels and size error below 0.0001 in all six captures.

Selected App/Window streams now explicitly request the centered aspect-fit output
rectangle. Sample checks, source ownership, exact geometry, expiry and input
admission remain unchanged. Three indexed placement regressions fail against the
old default configuration and pass with the repair, alongside the existing 19
lifecycle/sample cases. A partially off-screen owned red-window probe did not
reproduce the failure; no clipping workaround was introduced.

## Picker and recovery

Normative specification and authoritative fixtures precede these wire changes:

- Each picker candidate carries a nullable bounded `windowTitle`. Only the active
  authenticated Control picker may use it. Whitespace is normalized, control and
  bidirectional formatting scalars removed, and titles truncated at character
  boundaries to 128 UTF-8 bytes. No title reaches audit, diagnostics, persistent
  stores, Observe or Act. No additional path/URL/Accessibility query enriches it.
- Only eligible on-screen layer-zero windows with supported capture size enter
  the catalogue. Apps without eligible windows are omitted. App selections need
  a supported crop on the selected display. Unavailable choices are hidden;
  independently capturable Windows on another active display remain selectable.
- A consumed, exactly bound App/Window token whose live source disappeared or
  became uncapturable can produce an explicit fresh Desktop replacement on the
  already authorized selected display. Both revisions advance once and clean
  presentation acknowledgement still precedes input. Invalid, stale, expired,
  wrong-kind, excluded and ownership-mismatched targets do not qualify.
- A genuine runtime failure keeps the failed Remote Control screen visible until
  the user closes it, with recovery guidance, instead of an unexplained return to
  the workspace. This presentation change does not keep failed capture or input
  authority alive.

The 65536-byte inventory transport bound remains unchanged; an oversized complete
inventory still fails closed. Both normal apps must be updated together for the
new required nullable wire key. Pairing and independent product grants are unchanged.

## Verification

Full required `bash scripts/validate.sh` passes with all 118 indexed fixtures.
Both native SDKs, 12 native lifecycle tests and normal Simulator, iPhone, Mac and
Agent builds pass. The fresh source-built Sunshine package is independently
verified with production first-party supervisor, relocatable dependencies and
119 catalogued files. The signed development host is pinned by catalogue digest
`c820bded599f3dd66ac94f5aa9fb3226803b209187276e67f38cd52d20fd7404`.

The normal-app static wide-Window journey did not reach pairing or streaming.
An initial attempt encountered duplicate Developer ID certificate names. Two
subsequent exact-signer attempts (Developer ID and Apple Development) reached
`menu-ready` and `pairing-composed`, then local XPC invalidation before the isolated
loopback endpoint was ready; the consent bridge closed. No listener-port conflict
or console lock was observed. Owned processes/jobs retired and original Simulator
state was restored. No successful streaming or vanished-picker-Window acceptance
is claimed for this candidate. The setup failure remains to be diagnosed, and the
new disappearance journey has not run successfully.

The signed normal Mac update is installed at
`/Users/yihong/Applications/Mac Companion.app`. Its exact signed app, Agent
entitlements and new 119-file host catalog are verified. The existing Agent
service restarts and listens on port 59653. The prior app is recoverable at
`/private/tmp/maccompanion-mac-pre-picker-centered-20261002.app`.
The normal iPhone update preserves the exact existing signed entitlements and
profile; its signed executable SHA-256 is
`18466457b8b4024d58731b37d2797b61ad2ab0876135c45d09767d0c88a1f58a`.
CoreDevice confirms installation, launch and installed-app readback on the verified
iPhone 18 Pro Max under the existing `media.jenny.maccompanion.ios` identifier.
Existing app data and pairing were retained; this is not physical streaming
acceptance of the new build.
Physical retry, everyday elapsed acceptance, Release admission,
corresponding-source refresh and production distribution gates remain open.

## Private evidence

- Physical trace: `/private/tmp/maccompanion-picker-return-iphone18-runtime-20261002.log`.
- Matched fixed host codes: `/private/tmp/maccompanion-picker-return-capture-codes-20261002.log`.
- Matched host timeline: `/private/tmp/maccompanion-picker-return-host-events-20261002.log`.
- Geometry reproduction and repaired metadata: `/private/tmp/maccompanion-real-window-geometry-20261002/even-report.json` and `destination-report.json`.
- Before/after placement regressions: `/private/tmp/maccompanion-centered-capture-before-20261002.log` and `maccompanion-centered-capture-after-20261002.log`.
- Final validation: `/private/tmp/maccompanion-picker-centered-handoff-stable-validation-20261002.log`.
- Source host: `/private/tmp/maccompanion-picker-centered-native-host-build-20261002/provenance.json`.
- Verified package: `/private/tmp/maccompanion-picker-centered-native-host-package-20261002/host-package.json` and `production-supervisor.json`.
- Signed host: `/private/tmp/maccompanion-picker-centered-signed-host-20261002/report.json`.
- Mac staging: `/private/tmp/maccompanion-mac-picker-centered-stage-20261002.json`.
- iPhone signature: `/private/tmp/maccompanion-picker-centered-iphone18-signature-20261002.json`.

- Normal journey setup failure: `/private/tmp/maccompanion-native-picker-centered-static-window-journey-20261002-v3/report.json`.
- Mac installation: `/private/tmp/maccompanion-mac-picker-centered-installed-20261002.json`.
- iPhone installation/launch/readback: `/private/tmp/maccompanion-picker-centered-iphone18-install-20261002.json`, `maccompanion-picker-centered-iphone18-launch-20261002.json`, and `maccompanion-picker-centered-iphone18-installed-app-20261002.json`.

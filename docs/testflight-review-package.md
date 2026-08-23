# External TestFlight review package

Status: prepared draft; do not paste into App Store Connect until every
candidate-bound placeholder and readiness check below is complete.

Last policy check: 2026-08-23 against Apple's [App Review
Guidelines](https://developer.apple.com/app-store/review/guidelines/),
[TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview),
[test-information instructions](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/),
and [`SCContentSharingPicker`
guidance](https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker).
Recheck all four before submission because the guidance can change.

## 1. Submission posture

The first external build is an honest LAN-first review build of a generic
companion for a reviewer-owned Mac. It does not use a Mac Companion account,
vendor relay, cloud Mac, software catalog, remote installation, or hosted
application service.

The review path demonstrates three independently useful and independently
authorized areas:

1. **Observe:** fresh Mac status without opening a video stream.
2. **Act:** one bounded, named, auditable action (`setAudioMuted`).
3. **Control:** a generic full-Desktop mirror first, followed optionally by
   generic app/window focus and Smart Zoom.

Every mirrored application executes and renders on the reviewer's Mac. App and
Window Focus are filters over software already present on that Mac, not an app
catalog. All macOS permissions and device grants are approved locally. The
review path uses the same LAN and does not require Tailscale or another private
route.

This positioning does not guarantee approval. Guideline 4.2.3(i) says an app
should work without requiring another app, while Mac Companion intentionally
requires its directly distributed Mac host. Guideline 4.2.7 adds conditions
when a remote desktop mirrors specific software rather than generically
mirroring the host. The submission must disclose both facts and seek early
classification evidence; it must not hide the Mac dependency or portray App
Focus as a software storefront.

## 2. Candidate-bound prerequisites

Do not submit the first external build until all items are true:

- [ ] Explicit iOS App ID and distribution provisioning profile are bound to
      `media.jenny.maccompanion.ios`; no wildcard development profile is used.
- [ ] The exact iOS build has completed the physical pairing, Observe, Act,
      Control, lock, reconnect, permission-revocation, and stop scenarios.
- [ ] The corresponding Mac build is Developer ID-signed, notarized, stapled,
      Gatekeeper-accepted, and downloadable over HTTPS from a stable public URL.
- [ ] Apple has approved any managed capture entitlement present in the review
      build, and the notes describe its exact use truthfully.
- [ ] The public Mac download page shows version, build, SHA-256, minimum macOS,
      installation, permission, uninstall, and support information.
- [ ] A clean reviewer Mac plus clean iPhone rehearsal completes the instructions
      below without private engineering knowledge.
- [ ] Review contact name, international-format phone, monitored email, and
      feedback email are final.
- [ ] Export-compliance answers match the shipped peer-to-peer cryptography.
- [ ] Privacy manifest, App Privacy answers, support URL, and privacy-policy URL
      match the exact candidate.
- [ ] Review notes remain within App Store Connect's 4,000-character bound and
      contain no placeholder, expiring credential, private key, or internal URL.

## 3. TestFlight metadata draft

### Beta app description

Mac Companion helps you check, operate, and control a Mac you own. Pair over
your local network to view fresh Mac status, run explicitly approved actions,
or open a live full-desktop session with mouse and keyboard control. App Focus,
Window Focus, and Smart Zoom make the desktop easier to use on a phone without
turning Mac Companion into a software catalog. A separately downloaded Mac
Companion host is required. Connections are direct; Jenny Media does not run a
relay or Mac Companion account service.

### What to test

Please test setup on a Mac and iPhone connected to the same LAN:

1. Install and open the supplied Mac Companion build.
2. Enable Remote Access and approve only the macOS permissions explained by the
   app.
3. Pair the iPhone by QR code and confirm the matching security code on both
   devices.
4. Confirm that Observe shows fresh Mac status without opening Remote Control.
5. Approve and run Set Audio Muted, then verify the Mac's output mute state.
6. Start Desktop control, move the pointer, type into non-sensitive test text,
   and try App Focus, Window Focus, and automatic Smart Zoom.
7. Stop control locally, revoke the iPhone, and confirm it cannot reconnect.

Please report any unclear permission wording, pairing failure, stale status,
unexpected input, reconnect failure, or difficulty leaving Remote Control.
Do not enter personal passwords or other sensitive text during beta testing.

### Feedback email

`[MONITORED FEEDBACK EMAIL]`

## 4. Beta App Review information draft

### Sign-in required

No. Mac Companion has no account or vendor cloud login. Review instead requires
the supplied Mac build and a reviewer-controlled Mac on the same LAN.

### Contact

- First name: `[RELEASE CONTACT FIRST NAME]`
- Last name: `[RELEASE CONTACT LAST NAME]`
- Email: `[MONITORED REVIEW EMAIL]`
- Phone: `[INTERNATIONAL-FORMAT PHONE]`

### Review notes

Mac Companion is a generic companion for a Mac owned and controlled by the
reviewer. It requires the separately distributed Mac app below; there is no
Mac Companion account, relay, hosted Mac, software catalog, or remote software
installation.

Mac build: `[HTTPS DOWNLOAD URL]`
Version/build: `[MAC VERSION]` (`[MAC BUILD]`)
SHA-256: `[DMG SHA-256]`
Minimum macOS: macOS 26.0
Minimum iOS/iPadOS: iOS/iPadOS 26.0

Setup:
1. On a reviewer-owned Mac, download the DMG, drag Mac Companion to
   Applications, and open it through the normal Gatekeeper flow.
2. Choose Enable Remote Access. macOS shows the relevant privacy controls;
   approve Screen Recording and Accessibility only when the app explains why
   each is needed.
3. Keep the Mac and iPhone on the same LAN. In the iOS app choose Pair a Mac,
   scan the QR code shown by the Mac, and confirm the matching security code on
   both devices. Camera access is requested only after Scan is chosen.
4. Observe shows fresh host status without video. Approved Actions contains the
   bounded Set Audio Muted action and requires a device grant. Remote Control is
   separately granted and starts with a generic full-Desktop mirror. App Focus,
   Window Focus, and Smart Zoom only filter software already executing and
   rendering on that Mac; they do not browse, purchase, install, or host apps.
5. The Mac status item remains visible during control and can stop the session
   immediately. Revoke the phone from Mac Companion to verify that reconnect is
   denied.

All traffic in this review path is direct over the local network. All mirrored
software executes and renders on the reviewer-owned Mac. The product also has
Observe and bounded Act interfaces that do not depend on a screen stream. We
have disclosed the required Mac companion because of Guideline 4.2.3(i), and
we welcome guidance if Apple classifies this generic user-owned-host design
differently under Guideline 4.2.7.

Persistent capture entitlement: `[APPROVED / NOT PRESENT IN THIS BUILD; EXACT
EXPLANATION]`

Support contact during review: `[NAME, EMAIL, PHONE]`

## 5. Reviewer attachments and stable resources

Prepare, hash, and inspect these exact resources before attaching or linking:

- A one-page setup PDF with the exact Mac/iOS versions and QR/SAS flow.
- A short first-run recording showing Mac installation, local permission
  explanations, QR pairing, Observe, one bounded Act action, generic Desktop
  control, visible Mac activity, local Stop, and device revocation.
- Screenshots of the Mac permission/status UI and the iOS Observe, Approved
  Actions, and Desktop screens. Do not use personal data or another app's UI.
- The stable HTTPS Mac download page and notarized DMG.
- A concise troubleshooting page for Local Network denial, camera denial,
  Screen Recording denial, Accessibility denial, and stale pairing removal.

## 6. Rehearsal and decision record

Record one clean rehearsal with candidate hashes, devices/OS versions, elapsed
setup time, every prompt observed, and whether all numbered review steps passed.
If the reviewer path requires an undocumented step, private credential,
engineering shell command, Tailscale, or a permission not described above, the
package is not ready.

If TestFlight App Review rejects the Mac dependency or remote-desktop
classification, preserve the exact message and candidate metadata. Respond
factually through App Store Connect. Product alternatives are: clarify and
appeal with evidence, alter the independent iOS utility, constrain the review
build to LAN/generic Desktop behavior, or record an evidence-backed App Store
no-go. Do not disguise functionality or submit materially different hidden
behavior.

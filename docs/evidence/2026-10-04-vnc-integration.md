# Normal-app VNC migration

Status: the normal Mac and iPhone development updates are installed. The Retina
allocation guard and unused legacy-media producer are corrected. The user's
physical iPhone 18 Pro Max check confirms the desktop stays visible for at least
30 seconds. Content-free counters corroborate 406 presented frames, six local
view changes on one VNC connection and four successful host lease renewals over
approximately 37 seconds. Final stable validation and the normal Mac build pass.
Longer recovery and interaction acceptance remain open; this is not a
production-readiness claim.

The subsequent display-confinement and window-aware smart-zoom updates are also
signed and installed on both normal apps. Stable validation, both app builds
and a hosted normal-viewer Simulator test pass. The Mac app and Agent run from
the updated bundle. The iPhone installation succeeds, but automatic launch is
denied while the phone is locked. Physical crop, window-hit and gesture
acceptance remain pending.

## Integrated transport and authority

- Independently promoted `Native/VNC` sources use pinned LibVNCClient 0.9.15.
  Normal targets do not import the disposable prototype app.
- The existing pinned TLS 1.3, application-authenticated primary carries bounded,
  ordered RFB bytes. The host destination is fixed to `127.0.0.1:5900`, the
  already enabled Apple Screen Sharing service. No caller-supplied endpoint or
  plaintext LAN fallback is admitted.
- The existing golden pairing and trusted Control session signatures remain
  unchanged. Opening and ongoing reads/writes require the exact current Control
  session, primary, device epoch, grants, policy and runtime lease. Idle authority
  is rechecked every 200 ms. Stop, retirement, expiry and primary loss close the
  relay.
- Saved Macs, pairing keys, signing requirements and Keychain groups are retained.
  Inner Mac login retention is a separate opt-in Keychain item, saved only after
  successful login and removed when the Mac is forgotten. Users enter their
  credentials directly in the app. No credentials, pixels or input are logged.
- The Mac Companion Mac app and Agent remain part of the connection: they provide
  approved pairing, the authenticated encrypted relay, current runtime authority,
  the visible indicator, Stop and bounded window lookup. Apple's built-in Screen
  Sharing server supplies the actual desktop and handles pointer/keyboard input.
  The current normal development path does not start Sunshine/Moonlight.
- Desktop display selection, All Displays, zoom and pan use one RFB framebuffer.
  They do not restart the transport. A selected display now crops the image and
  scrollable canvas, with translated and bounded pointer coordinates. Window
  smart zoom fits a host-reported visible window within that canvas. App/window
  chooser integration remains a migration gate; isolated window capture is not
  claimed.

## Established first integrated failure

Three physical attempts on the iPhone 18 Pro Max show the same fixed counters:
the paired Control request is accepted, the encrypted tunnel opens, one ARD
credential callback occurs, macOS authentication succeeds (handshake stage 4),
then the viewer rejects framebuffer allocation (failure stage 9).

This establishes the allocation guard as the failing check. It excludes rejected
Mac credentials and tunnel-opening failure for these attempts. The old guard
allows no axis above 8192 and at most 64 MiB of RGBA pixels. Mac display metadata
shows physical resolutions of 5120 by 2134 and 3024 by 1964. A combined 8144 by
2134 image requires 69,517,184 bytes, exceeding that memory limit. The corrected
physical attempt confirms exactly 8144 by 2134. Authentication and allocation
complete, and nine frames are presented in approximately two seconds.

The corrected guard permits positive axes through 16384 and at most 96 MiB of
RGBA pixels. It checks both limits before allocation and preserves the single
pending-frame bound. Eight authoritative fixture cases exercise the combined
Retina image, exact memory boundary, over-budget image, axis boundary, zero,
negative and oversized dimensions. Numeric width, height, update and presented
frame counters identify the next result without recording screen content.

## Second failure: unused legacy producer retires the host

The corrected iPhone attempt at 17:24:28 on 2026-10-04 (America/New_York)
authenticates, allocates and presents video. At 17:24:32.088 the Mac cancels its
authenticated local menu connection, then ends Interactive authority. The
Screen Sharing relay closes, and the next primary admission check fails with
`admissionChanged`. The framebuffer counters report no new allocation error.

Source tracing establishes a migration defect: the old Control composition still
starts ScreenCaptureKit and a VideoToolbox encoder. Its first legacy media record
drains through local XPC to `MacLocalXPCInteractiveRoleDataRouteV1`, which suspends
until a legacy media role consumes it. The VNC client opens no such role. The
server's unchanged three-second media publication deadline retires the local menu
connection, producing the observed session teardown.

The normal Debug host now selects `MacScreenSharingLeaseAdapterV1`: it installs
the same validated Desktop execution lease and visible indicator, checks screen
permission, adopts only exact renewals and clears its binding on Stop. It creates
no capture stream, encoder or legacy media records, and supplies no native
backend factory. The old deadlines and failure handling remain enforced. Release
composition retains its existing gates. Recovery reconstructs the same selected
engine. Indexed regression cases cover current lease, denied permission,
duplicate install, exact/stale renewal and renewal after Stop; a full runtime
test checks that the legacy queue remains empty across renewal and that lease
expiry clears the indicator and releases input.

## Physical check after the runtime correction

The user confirms that the desktop stays visible when asked to keep it open for
at least 30 seconds. The installed iPhone's content-free counters at 17:39:04
through 17:39:42 on 2026-10-04 (America/New_York) independently establish:

- Authentication and allocation complete at 8144 by 2134, with failure counter 0.
- Presented frames advance from 0 to 406 and framebuffer updates from 0 to 526.
- The local view-change count advances from 0 to 6 while connection starts remains
  1; view selection does not reconnect RFB in this run.
- The Mac renews the same runtime four times, approximately eight seconds apart.
  Its log contains no legacy capture preparation, stream startup, publication
  timeout or `admissionChanged` failure in this check.
- The interval ends with a runtime revoke and remotely closed primary. A second
  connection authenticates and advances to 454 cumulative frames before another
  revoke. These logs do not identify the user's reason for ending either session,
  so they do not establish background recovery or an intentional Stop test.

This passes the short sustained-playback and six-view-change check and excludes
the earlier three-second legacy-publication teardown for the measured interval.
It does not establish indefinite reliability, correct display/input mapping or
keyboard, resize, Spaces and background/foreground acceptance.

## Keyboard follow-up

The user confirms basic keyboard input works, but toolbar modifiers remain held
after a shortcut and standalone Shift cannot be sent. Source inspection identifies
the initiating defect: `remoteKey:` toggles a persistent remote modifier key-down,
while text and special-key paths never consume or release it. Shift uses that
same toggle path, with no balanced standalone press action.

The corrected viewer selects modifiers locally for one key. The native keyboard
builds one ordered group containing modifier downs, the key down/up and reverse
modifier ups, then clears selection. Text commits, empty-field Backspace, Escape,
Tab, Return and arrows use this shared path. Only the first scalar of a text
commit consumes the selection; marked text stays local until committed. Holding
a modifier sends it alone as a balanced pair; More also contains Shift only.
Stop, background, failure and disconnect reset local selection. Session queue
admission accepts the whole group or none, preserving the existing bounded queue
and disconnect cleanup for keys actually sent.

Seventeen manifest-indexed synthetic event-order cases and four atomic admission
boundaries pass against the actual native keyboard source. Required stable
`bash scripts/validate.sh` passes, including those cases and all 130 fixtures.
The normal iPhone app rebuilds, is signed with its existing profile and Keychain
entitlements, and installs successfully on the iPhone 18 Pro Max. Physical
modifier-release and standalone Shift acceptance remain pending. No Mac runtime
change or new pairing is required for this keyboard correction.

Updated iPhone executable SHA-256:
`b46449c39872de4994aafccf4bcb00ec71f8edaa10e6f4bb806a54a02bf277d9`.
Updated iPhone source-map SHA-256:
`9cd54203db1c78ed1f6edc6f0612da811e15abfeae2cf59f8d955965402c000f`.
The earlier installed binding below describes the sustained-video check before
this keyboard update. Private keyboard build, validation, signing and device
installation receipts use `/private/tmp/maccompanion-vnc-keyboard-*` and
`/private/tmp/maccompanion-normal-vnc-signed-ios-keyboard-20261004`.

## Display confinement and window-aware smart zoom

The user reports that selecting a display only zooms the combined desktop;
pinching out or panning can still reach another display. Source inspection
confirms that selection previously called `zoomToRect` on the full-framebuffer
image, leaving the full canvas and minimum zoom intact. It was a viewport
shortcut, rather than display confinement.

The viewer now creates a selected-display CGImage crop and sizes its scrollable
canvas to that crop. Minimum zoom fits that display, and every pointer path
translates local coordinates by the crop origin. Taps outside the crop are
rejected; an active drag is clamped and released before selection, resize or
Stop. All Displays explicitly restores the combined framebuffer. Invalid or
mismatched layout metadata clears the canvas and asks for a layout refresh,
without silently exposing another display. This limits presentation and pointer
movement; the host still transmits the combined RFB framebuffer.

The user's chosen smart-zoom behavior is to fit the window under the finger.
A two-finger double tap requests the topmost ordinary visible window bounds at
that point, intersects them with the selected crop and fits the resulting
rectangle. Repeating the gesture returns to the full selected display. More
also provides Smart Zoom at the center and Fit View. Ordinary remote clicks
retain their existing behavior. Layout changes, display selection and Stop
invalidate pending replies; normal video updates preserve the current zoom.

Normative specification and manifest-indexed fixtures add `windowQuery` and
`windowGeometry` to the existing Desktop tunnel. A bounded 16-byte query
identifies its stream sequence, point and framebuffer size. The 24-byte reply
echoes that query and carries only a bounded rectangle; zero means no hit.
Authentication, pairing, operation signatures and grants are unchanged. Both
host lookup and response publication recheck the exact current Desktop Control
authority. The client accepts only the matching query, times out after two
seconds and releases the waiter on retirement. Metadata is never forwarded into
LibVNCClient's RFB stream. macOS uses current display and on-screen window bounds;
window names, titles, input and pixels are not retained or transmitted by this
lookup. The VNC connection remains open throughout the operation.

A final source review exposes a concurrency defect in the new metadata path:
the query reserves its stream sequence before starting a child send task, and
the primary sender can suspend during authentication/admission. Another input
write can overtake it. A gated regression reproduces out-of-order completion
while the first write is suspended. Client sends and host events now reserve an
ordered send task alongside their stream sequence and wait for the predecessor
before entering the primary sender. Close also prevents remaining chunks of a
suspended write from being sent. Retirement rejects queued client writes;
the host rechecks authority before a queued nonterminal event is sent. The
ordering and retirement regressions pass. A separate greeting-only loopback
probe confirms window geometry cannot overtake a suspended RFB greeting; it
uses synthetic window bounds and supplies no credentials or pixel requests.

Verification on stable Xcode 27.0:

- Required `bash scripts/validate.sh` exits successfully with 132 indexed
  fixtures, the actual native viewport gate, wire bounds, authenticated replay
  rejection, window projection and tunnel lifecycle regressions.
- Indexed viewport cases cover eight crops, seven pointer mappings and three
  window intersections. Projection covers topmost ordering, negative display
  origins, clipping, no hit and framebuffer aspect mismatch.
- A hosted XCTest of the actual normal viewer passes on the MacCompanion VNC QA
  Simulator: cropped image dimensions, minimum zoom, pointer offset, window
  fitting, stale-reply rejection, 60 display changes and zoom preservation across
  video frames. It uses synthetic images and a fake session; it does not establish
  native window enumeration, physical gesture recognition or live network timing.
- Final normal Mac and iPhone builds pass. Both candidates are signed and deep
  verified with existing identities, entitlements, requirements and Keychain
  groups. Mac installation preserves a private rollback bundle and restarts the
  normal app and Agent. iPhone installation succeeds on the iPhone 18 Pro Max;
  its automatic launch is denied because the phone is locked. No re-pairing is
  required.

The final Mac installer first stops before bundle replacement because an earlier
rollback filename already exists. Fresh staging and rollback names preserve that
copy, and the retry succeeds. Final installed Mach-O digests match the signed
candidate; the normal Mac app and Agent are verified running from that bundle.
The unused prepared copy is retained privately outside Applications.

Updated viewport candidate binding:

- Mac source-input digest: `d48575aacd3f0ec5bc34a918318058a18145f249baf47569960a9d7c6ad953d2`.
- Mac main executable SHA-256: `3111cfab8176e99fc864b86f5f2a18cf24d4141d39fad5bef221246cc2f88756`.
- iPhone build-input map SHA-256: `813708233289b7f71e0c85e1af386a8e122ae065109aa18afea2684f40403741`.
- iPhone executable SHA-256: `7bc8b496458fea91c375effa6062dbc2626e3808f1d037dfa456d7028d2c19ad`.

Private validation/build/install receipts use
`/private/tmp/maccompanion-vnc-viewport-*`; signed candidates use
`/private/tmp/maccompanion-normal-vnc-*-viewport-ready-20261004*`. The final full
validation log is `maccompanion-vnc-viewport-validation-ready-20261004.log`;
ordering regression logs retain the failing-before and passing-after results.
The Simulator result
bundle is `/private/tmp/maccompanion-vnc-viewport-ui-20261004.xcresult`. Physical
display confinement, real window fitting, keyboard modifier behavior and the
remaining recovery/soak gates are still open.

## Cursor and consistent zoom toggle

The user reports that cursor position is absent and asks for the two-finger
double tap to toggle between zoom in and fitting the display. Inspection of the
normal viewer and pinned LibVNCClient establishes the missing cursor path:
`useRemoteCursor` defaults to false, the session installs neither shape nor
position handlers, and UIKit has no local cursor overlay.

The session now requests standard RFB XCursor, RichCursor and PointerPos
pseudo-encodings and installs both handlers. Bounded masked BGRX data converts
to RGBA with an in-bounds hotspot, admitting at most 256 pixels per axis. An
unsupported shape uses an outlined local arrow. One pending cursor presentation
is generation-fenced and dropped after Stop. The overlay responds immediately
to local pointer input, accepts valid server updates, aligns its hotspot through
crop/zoom/pan coordinates and remains readable in a fitted view. It is clipped
to the selected canvas, hidden outside it and cleared on resize, backgrounding
and disconnect. Only shape/position counters are added to diagnostics, with no
coordinates or pixels recorded. The existing encrypted relay and authority
checks carry these ordinary RFB bytes without a new Mac Companion wire kind.

Smart zoom now returns to fit from any zoomed view, including a manual pinch.
From fit, a smaller window under the tap remains the preferred target. Empty
desktop, a full-size window or unavailable lookup uses a bounded two-times-fit
zoom centered on the tap. Repeating the gesture while lookup is pending cancels
the presentation; stale replies cannot restore zoom. No VNC reconnection or
remote click is introduced.

Stable Xcode 27.0 verification passes:

- Three hosted actual-viewer/session tests on Simulator cover crop, pointer
  mapping, window fit, 60 view changes, manual-zoom toggling, no-window fallback,
  pending/stale replies, cursor crop/hotspot alignment across zoom and pan,
  immediate local input feedback, actual native RGBA delivery and Stop fencing.
  They use synthetic frames, cursor pixels and a fake input session.
- Eight indexed cursor conversion cases, five crop-position cases, five readable
  hotspot cases and five bounded zoom targets pass against the actual native
  helpers. The sole fixture manifest remains authoritative.
- Required `bash scripts/validate.sh` exits successfully with 132 fixtures and
  all existing wire, authority, ordering, retirement and native gates.
- The normal iPhone build passes and is signed/deep verified with the existing
  development identity, profile and Keychain group. The compatible Mac runtime
  already installed for the preceding viewport update needs no server code
  change. Real server cursor updates and physical gesture acceptance remain open.

The signed update installs successfully on the iPhone 18 Pro Max. Pairing and
the per-Mac Keychain group are preserved. Automatic launch is denied by iOS
because the phone is locked; the physical check requires opening the app after
unlocking it.

Signed iPhone executable SHA-256:
`9270797f5bcd28c2c267c7997949f0daf81a38d3b9a6f860462420f129ddc1d1`.
Build-input map SHA-256:
`fcc7ba8367f63cc7135eac6dfe7a0d864bc0db554772f1db0fef9dde1e1dd1b7`.
Private build/validation/install receipts use `/private/tmp/maccompanion-vnc-cursor-*`;
the signed candidate is `/private/tmp/maccompanion-normal-vnc-signed-ios-cursor-20261004`.
Simulator results are `/private/tmp/maccompanion-vnc-cursor-ui-20261004.xcresult`.

## Verification and installation

- Stable Xcode 27.0 (27A266a) builds the normal Mac host, iPhone viewer and
  Simulator viewer. The Simulator installs, launches and shows normal unpaired
  onboarding; this does not establish authenticated physical playback.
- Wire tests exercise the indexed envelopes, chunk and field bounds. Client
  transport tests cover ordering, sequence rejection, retired tunnel events and
  primary loss. Host tests cover closed-before-start and authority retirement.
- The opt-in loopback test obtains only the RFB greeting and closes after idle
  authority loss. A separate pinned LibVNCClient socket-bridge probe reaches the
  ARD credential callback without supplying credentials or requesting pixels.
- Native socket transport tests cover byte ordering, single descriptor transfer,
  idempotent start/stop and EOF. Allocation boundary cases pass.
- Required stable `bash scripts/validate.sh` passes for the final runtime
  correction, including the new indexed lease tests, allocation boundary gate
  and 130 fixtures. An earlier validation of the incomplete test harness fails
  compilation/linking; the final complete run passes after its fixture support
  dependency and protocol conformance are corrected.
- Final Mac and iPhone updates are signed and verified with existing development
  identities and installed in the normal app locations. The iPhone update is
  reopened for the user's direct-login playback check. Private rollback copies,
  installation receipts and content-free diagnostics remain outside Git.

Installed candidate binding:

- Mac source-input digest: `51daa783d99170347c1e1a89d847d43bf09ceb11a2d9dd50153d14e311003839`.
- Mac main executable SHA-256: `f7e5791173ba57acbf6de1e5ef5e97922c49fb6391689d673a7d78bf4263a9d7`.
- iPhone build-input map SHA-256: `c423e777a8c63762581ee934e74fcd2326109f376de48018e8b5288aef35c495`.
- iPhone executable SHA-256: `76bd3324da31f4515f02f8e3d694447b48ec762f509a50160200f411b4945758`.

Private evidence uses `/private/tmp/maccompanion-vnc-*` and
`/private/tmp/maccompanion-normal-vnc-*`. No raw runtime log or capture is added
to this document.

## Remaining migration and acceptance gates

1. Extend the passed short playback and six-view-change check to a longer session;
   verify display/input mapping, pointer, keyboard and modifiers.
2. Test background/foreground, Spaces, window resize, Stop, revocation and repeated
   connections, followed by latency/bandwidth measurements.
3. Wire a meaningful app/window focus or crop chooser to the persistent desktop,
   preserving display coordinates and input mapping without RFB restart.
4. Complete permanent dependency, Apple signing, packaging and release gates.
   The generated development build report explicitly remains `releaseAdmitted:
   false`; no TestFlight, notarization or public release is established.

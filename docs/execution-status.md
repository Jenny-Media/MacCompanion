## 2026-10-07 — Active Terminal menu and shared category clipping

Installed build 14's preceding source is committed locally as `987c265`.
Terminal's Session menu now keeps Connection Details, App Settings and Exit;
saved-Mac settings retain account and SSH key configuration. The shared quick
panel measures native button content at its actual width, fixing clipped View &
Display and Keyboard & Input symbols and captions at enlarged text sizes.
Required stable-Xcode validation and **12** focused hosted checks pass.
Before/after geometry and synthetic screenshots verify both session modes;
full-system captures verify the shorter Terminal menu in both palettes.
See [menu and icon layout evidence](session-menu-icon-layout-20261007.md).
This follow-up is committed as `264d45f`. Normal development **1.0 (15)** is
built, signed, installed and launched on iPhone 18 Pro Max. All **577** source
inputs, the signed binary and retained app/widget and private Keychain identities
are verified. CoreDevice confirms build 15, installation sequence **9128** and
launch PID **16281**. Physical acceptance is pending; no TestFlight publication
occurred.

## 2026-10-07 — Terminal number row is optional

Keyboard & Input now includes a free Show Number Row choice, enabled by default.
It applies immediately, returns 48 points to output when hidden, and is remembered
for future sessions. The persistent modifier bar and independent custom-key row
are retained. Required stable-Xcode validation and **11** focused hosted checks
pass; **4** full-system synthetic Simulator captures verify row and menu states.
See the [number-row follow-up](terminal-persistent-toolbar-20261007.md#follow-up-optional-number-row).
Normal development **1.0 (14)** includes this choice, the persistent Terminal bar
and above-button popovers. It is built, signed, installed and launched on iPhone
18 Pro Max. All **577** source inputs, the signed binary, existing app/widget
identities and private Keychain groups are verified. CoreDevice confirms build
14 and installation sequence **9120**. Source is committed as `987c265`.
Physical acceptance is pending; no push or TestFlight publication occurred.

## 2026-10-07 — Terminal controls share a persistent modifier bar

Terminal now keeps keyboard and menu buttons at the ends of one persistent
modifier bar. The middle keys scroll on narrow screens, numbers appear while
the software keyboard is open, and the separate 68-point button dock is removed.
The keyboard toggle is directly on the bar; the shared menu interactions and
above-button placement are retained. Required stable-Xcode validation and **13**
focused hosted checks pass; **8** full-system synthetic Simulator captures verify
both palettes and keyboard states. See the
[persistent toolbar evidence](terminal-persistent-toolbar-20261007.md).
This follow-up is included in installed normal development **1.0 (14)** above.
Source is committed as `987c265`; physical acceptance remains pending. It has
not been pushed or published.

## 2026-10-07 — Floating control menus open above the button

Desktop, Trackpad & Keyboard and Terminal now share one native popover setup
that places button-anchored menus above the controls button. The display picker
uses the same setup, and pushed submenus retain the original anchor. UIKit owns
fitting, scrolling and keyboard avoidance. The existing press-and-slide panel
already opens above the button.

Required stable-Xcode validation and **8** distinct focused hosted checks pass.
An opt-in synthetic sweep verifies **34** menu/panel states, including keyboard
open/closed geometry and reachability of the last action. **8** full-system
Simulator captures verify visible Desktop and Terminal placement, including
the keyboard and both Terminal palettes. See the
[floating menu audit](floating-menu-placement-20261007.md).
This follow-up is included in installed normal development **1.0 (14)** above.
Source is committed as `987c265`; physical acceptance remains pending. It has
not been pushed or published.

## 2026-10-07 — Centered connection cards have clearer separation

Desktop, Trackpad & Keyboard and Terminal now share an elevated system surface,
adaptive edge, soft shadow and theme-aware dimming over the passive saved-Mac
backdrop. Progress Cancel uses a native blue treatment and remains available.
The centered placement and connection behavior are preserved.

Required stable-Xcode validation and **8** focused hosted checks pass. **36**
synthetic app-window captures cover login, progress and recovery across both
themes, large text and increased contrast. The existing opaque Reduce
Transparency fallback is preserved in code; its rendering still needs a device
check because the Simulator did not expose the enabled setting to UIKit.
See [connection card evidence](connection-card-separation-20261007.md).
Normal development **1.0 (13)** is built and signed with all **577** source inputs
and the signed binary verified, retaining the existing app/widget and private
Keychain identities. The first installation attempt could not acquire CoreDevice
connectivity and power assertions. The user's authorized retry installed and
launched the update on iPhone 18 Pro Max; CoreDevice confirms version/build and
installation sequence **9104**. Physical acceptance remains pending. This
follow-up is committed as `987c265` and has not been pushed or published to TestFlight.

## 2026-10-07 — Trackpad & Keyboard login matches Desktop

Trackpad & Keyboard now identifies its mode in Desktop's shared centered sign-in
card. Both modes share adaptive login, progress and recovery placement, including
folded-screen keyboard avoidance. Required stable-Xcode validation and **30**
distinct focused hosted checks pass; synthetic captures verify both themes and
large text. Normal development **1.0 (12)** is installed and launched on iPhone
18 Pro Max, with all **577** source inputs, the signed binary, version/build and
installation sequence **9088** verified. Physical acceptance remains pending.
See [shared login evidence](input-only-login-20261007.md). This follow-up is
committed as `987c265` and has not been pushed or published to TestFlight.

## 2026-10-07 — Native Remote Desktop scrolling accepted on iPhone

The connected desktop canvas now reaches the top screen edge and pans behind
status icons using UIKit's automatic scroll-edge treatment, matching Terminal.
Fit Display, sign-in and input-only mode retain unobscured content. Keyboard
resizing, cursor following and restored zoom/center share inset-aware viewport
geometry. Required stable-Xcode validation and **45** distinct focused hosted
checks pass; eight synthetic full-system captures remain outside Git.

Normal development **1.0 (11)** is built and signed with all **577** inputs and
the signed binary verified. It is installed and launched on iPhone 18 Pro Max;
CoreDevice confirms build 11 and installation sequence **9080**. The first attempt
could not acquire connectivity and power assertions; the user's later authorized
retry succeeded. The user confirmed the desktop result looks good and requested
a local commit. This follow-up has not been pushed or uploaded to TestFlight.
See [desktop scrolling evidence](desktop-immersive-scrolling-20261007.md).

## 2026-10-07 — Native Terminal scrolling accepted on iPhone

Terminal history now scrolls behind the status icons using UIKit's automatic
scroll-edge effect. The custom fade is removed; initial output and sign-in stay
below the icons, with the usable whole-row PTY grid and keyboard layout preserved.
Required stable-Xcode validation and all **23** focused regressions pass. Eight
synthetic full-system captures verify both palettes and keyboard states. The
normal app and extension match all **577** build inputs and retain the existing
app, widget and private Keychain identities.

Local development **1.0 (10)** is installed and launched on iPhone 18 Pro Max;
CoreDevice confirms build 10 and installation sequence **9072**. The user
confirmed the native scrolling result with a physical screenshot. They also
previously confirmed quick app switching retains the Terminal connection.
The user requested a local commit; these follow-ups have not been published to
TestFlight. See [native scroll-edge evidence](terminal-native-scroll-edge-20261007.md)
and [Terminal lifecycle evidence](terminal-lifecycle-20261007.md).

## 2026-10-07 — Terminal shell retention and whole-row viewport

Established SSH shells now survive brief app switches: reads and input pause,
foreground/unlock resumes the same PTY, and Dynamic Island offers Terminal Resume
and scoped End actions. A repeated-switch resume race is covered and corrected.
The viewport uses whole terminal rows with an eight-point gap below the status
safe area, fixing partial first rows with the keyboard open or closed. Required
stable validation passes, with **36** focused hosted Simulator checks and a final
paused-Island layout check passing. Eight fresh synthetic system captures verify
the terminal boundary and palettes. The final normal app and extension match all
577 input hashes. Local development **1.0 (8)** is installed and launched on iPhone
18 Pro Max (sequence **9056**), with version read-back and existing private app/
widget identities verified. The user subsequently confirmed quick app switching
works; the viewport was later refined as recorded above. iOS still controls
longer background execution; Live Activities do not grant indefinite networking.
See [Terminal lifecycle evidence](terminal-lifecycle-20261007.md).

## 2026-10-07 — Physical screenshot layout corrections

Session menu headings remain below the navigation bar, spacing fits actual rows,
and a native Done control replaces the emphasized checkmark. Terminal reserves a
controls dock outside output and uses one keyboard-avoidance owner. Desktop's
status area and controls now match its black canvas, restoring the chosen app
theme on sign-in. Stable required validation and all **44** focused Simulator
checks pass. Eight fresh synthetic full-system captures verify the keyboard and
status areas. The source-matched normal **1.0 (7)** development update is installed
and launched on iPhone 18 Pro Max (sequence **8976**), with version/build read-back
and the existing app/widget Keychain identities verified. Physical session
acceptance remains pending. See [session UI polish](session-ui-polish-20261007.md).

## 2026-10-07 — Consistent session controls and centered sign-in

Terminal now has an immersive status area and keyboard palette. Desktop and
Terminal share floating controls and content-sized category menus. Sign-in and
progress cards are centered, and connection details use concise, provider-neutral
copy. Stable required validation, the normal iOS Simulator build, and all **42**
focused Simulator checks pass. See [session UI polish](session-ui-polish-20261007.md)
for changes, test evidence and local capture locations. The source-matched,
development-signed **1.0 (6)** update is installed and launched on iPhone 18 Pro
Max (sequence 8968), retaining the existing app and private Keychain identities.
Physical feature acceptance and TestFlight delivery of this checkpoint remain
pending.

## 2026-10-06 — France excluded from App Store distribution

The product owner explicitly requested dropping France support. App Store Connect
availability was changed from 175 to **174 countries or regions**, removing only
France. Its Europe availability table confirms **France: Not Available**. The
existing outside-France encryption answer remains applicable to the planned store
release. The normal iOS app and its cryptography are unchanged; no new build is
needed for this distribution setting.

The **Lifetime Pro** and **14-day Trial** in-app products also exclude France.
Both reloaded product pages report **174 of 175 countries or regions selected**;
their availability selectors confirm France is unchecked. Product prices and
trial terms are unchanged. Required stable-Xcode `bash scripts/validate.sh` passes
for this records-only update.

TestFlight public links expose device/OS criteria but no country filter. Store
availability does not provide verified regional enforcement for this beta link.
The prepared **100-tester** public link remains inactive pending the owner's choice
of controlled outside-France invitations or an explicitly unfiltered public link.
Build **1.0 (5)** has already been submitted to Beta App Review.

## 2026-10-06 — Build 5 uploaded for the authorized public beta

Approved app changes are committed as `768708b`. Stable required validation passes;
the fresh device build and optimized signed **1.0 (5)** archive preserve all 577
input hashes, existing identities, private Keychain groups and deep signatures.
Xcode confirms normal App Store Connect upload success. Apple processed build 5;
the unchanged standard-encryption/outside-France declaration and focused testing
notes are saved. The existing internal group confirms **1.0 (5), Testing**. The
normal upload has Internal Only disabled for external review eligibility.

The beta description, website URLs and user-supplied review contact are saved.
After fresh user confirmation, **Public Beta** was created and **1.0 (5)** was
submitted to Beta App Review. App Store Connect confirms **Waiting for Review**,
zero external testers and one assigned build. The public-link limit is prepared
as **100**, with activation pending the France scope discussion; no public link
is active. Apple's French-document footnote specifically addresses App Store
distribution in France; required encryption documents also precede beta review.
France classification and documentation remain unresolved. Submission does not
establish approval or public availability. See
[public-beta evidence](evidence/2026-10-06-public-beta-testflight.md).

## 2026-10-06 — Approved Desktop and Terminal connection sheets

The approved v2 entry design is implemented: a compact bottom sheet over a blurred
saved-Mac context, shared identity header, grouped credentials, quiet Save login,
one primary action, concise actual progress and inline recovery. Connection Details
retains full explanations and fixed diagnostics. Saved-login automatic entry,
SSH trust checks and headerless connected Terminal controls remain intact.
Light/dark, keyboard, accessibility text and adaptive landscape layouts are covered.

Stable normal Simulator build passes with 577 matching input hashes. The full
hosted QA suite passes 129 tests with one intentional skip and no failures; a final
10-test recovery/layout/capture run passes after the details-retention adjustment.
Required stable validation, local comparison browser checks and final diff checks
pass. Native screenshots stay outside Git. No iPhone install, commit or TestFlight
upload occurred. See [approved-sheet evidence](evidence/2026-10-06-approved-connection-sheets.md).

## 2026-10-06 — Concise login and headerless Terminal controls

Saved Terminal login starts on entry with one eligible connection attempt;
Desktop's automatic saved-login entry is preserved. Manual login has one Connect
action; active attempts show progress and Cancel. Explanations remain in
Details/Options. Connected Terminal has no top title/navigation bar and uses
floating tap/press-and-slide controls above the software keyboard.

Final stable normal Simulator build and hosted direct-client QA pass: 129 tests,
one intentional skip, zero failures. Required stable validation and final diff
checks pass. Synthetic light/dark/large-text views and the full Simulator system
keyboard were inspected. No iPhone install, commit or TestFlight upload occurred.
See [login and Terminal evidence](evidence/2026-10-06-login-terminal-controls.md).

The host capture investigation is paused. Findings, source clues and the
controlled follow-up plan are preserved in the
[MacTools closed-lid handoff](evidence/2026-10-06-mactools-closed-lid-capture.md).

## 2026-10-06 — Black desktop traced to closed-lid virtual-display capture

The user confirms that opening M5's lid restores the desktop using the already
installed local development build 5. Closed-lid Mac-side Screen Sharing image-read
RPCs failed, and an independent capture-status probe delivered zero frames from
the only active MacTools virtual display. With the lid open, the physical display
is active, the same probe delivers 155 complete frames in five seconds, and the
iPhone diagnostic reports 55 advancing desktop presentations without decode errors.

This confirms the failing host configuration, while attribution between the
virtual-display provider and macOS capture remains unresolved. Open-lid acceptance
does not establish virtual-display-only or exact TestFlight-build reliability.
The separately reproduced pinned ZRLE false-success defect is guarded in the local
client, but that correction did not resolve this host capture failure. Stable
validation, the focused complete 4K rendering regression and earlier hosted QA
pass. No new Mac helper, host setting change or TestFlight upload occurred.
See [black-desktop investigation](evidence/2026-10-06-black-desktop-decoder.md).

The follow-up ran the same installed MacTools virtual-display helper with the
lid open. ScreenCaptureKit delivered 10 complete / 146 idle callbacks, screenshot
creation succeeded, and a separate diagnostic legacy stream delivered 10 complete
callbacks. The helper's descriptor and Retina mode therefore work with an active
physical display. MacTools' creation handshake and ongoing health check do not
verify frame delivery. Earlier WindowServer logs show a display sleep/wake sequence
at lid closure; transition-induced capture stalling remains the strongest hypothesis.
A retained-display physical test delivered 81 complete frames with the lid closed,
then lost its capture source exactly when WindowServer put the display to sleep.
The display later became active again, but the terminated stream did not recover.
The initial sample was already closed, and concurrent unrelated Simulator UI
automation and additional display churn limit original-trigger attribution. The
intended single-display pre-creation comparison remains unperformed.
Temporary probe displays were removed; no MacTools/client source or installed
app was changed. Exact internal macOS attribution remains unproven.
Diagnostic compilation and syntax/diff checks pass. Two full validation attempts
stopped at Swift temporary-object creation with `No space left on device`; unrelated
files were preserved. After the physical probe, the current full stable-Xcode
`bash scripts/validate.sh` rerun completed with exit status 0. This validates the
diagnostic source, without claiming a MacTools repair or closed-lid reliability.

## 2026-10-06 — Adaptive client internal TestFlight build 4 ready

Source `ef90c1e` is committed and delivered as **1.0 (4)** to the existing
Internal Testing group. App Store Connect confirms **Internal, Testing**, with
one existing tester. What to Test and the unchanged standard-encryption /
outside-France answers are saved. Required stable validation and both 121-test
Simulator lanes pass, with five opt-in capture skips per lane.

The archive uses Xcode 27.1 RC so guarded Duo APIs are included, while maintaining
iOS 26.0 compatibility and the existing app/widget signing and Keychain groups.
RC evidence remains provisional; exact-build physical acceptance, physical Duo
and actual Split View remain separate. No external/public release occurred.
See [adaptive TestFlight evidence](evidence/2026-10-06-adaptive-testflight.md).

## 2026-10-05 — Direct client internal TestFlight ready

The normal direct iOS client is archived as `1.0 (1)` using stable Xcode 27.0,
optimized without DEBUG, and signed with the existing Apple Distribution identity.
The app and session widget use matching App Store profiles; exact identities,
existing private Keychain groups, disabled debugging and deep signatures verify.
Required stable repository validation passes after the archive script changes.

Xcode Organizer confirms Uploaded to Apple using TestFlight Internal Only.
The existing account holder is in the Internal Testing group with automatic
distribution off. Apple processed build `f1be75fa-aba2-4423-aa3f-af02cefa6920`;
What to Test is saved. The user confirmed the internal beta is outside France;
the standard-encryption declaration and France No answer were saved. The group
now has 1 tester and 1 build, with `1.0 (1)` marked Internal and Testing. The
existing account holder is Invited; acceptance and physical TestFlight
installation remain unconfirmed. OpenSSL's missing dSYM is an upload warning;
app/widget symbols are present. No public release or external beta submission occurred and dependency
release admission remains false. See
[internal TestFlight evidence](evidence/2026-10-05-internal-testflight.md).

## 2026-10-05 — App Store products, $9.99 Lifetime Pro and 14-day trial

The existing iOS App ID is registered and Mac Companion's App Store Connect record
6819496840 is created. Lifetime Pro (6819497277) has a saved US base price of
$9.99; the separate free 14-day Trial (6819497930) is a zero-price non-consumable.
Both have saved localization, availability, notes and purchase-screen review
images. The basic app download is free. These are Prepare for Submission records,
not live or approved purchases; no review submission or release occurred.

The normal direct client supports explicit trial enrollment, verified original
purchase-date expiry, restored history without restarting, revoked-trial exclusion
and lifetime upgrade. No automatic billing or Mac helper is introduced. Stable
full validation, 85 hosted Simulator tests, a separate capture test and the normal
Simulator rebuild pass. The wrapper's post-test container lookup failed after the
Simulator shut down, so its separate OpenSSH postcheck is not claimed as repeated.
Physical installation of this trial change and App Store purchase acceptance remain
pending. This supersedes earlier unregistered iOS/store-record statements.
See [pricing, trial and review evidence](evidence/2026-10-05-lifetime-price-and-pro-trial.md).

## 2026-10-05 — Named SSH keys, key setup, Terminal keyboard and Lifetime Pro

The normal direct iOS client now has an independent named key library with neutral
reuse, explicit per-Mac/account selections, migration and encrypted private backup.
Install Key on This Mac is in each Mac's settings and verifies a fresh key login
before selecting it. Terminal adds a persistent number row, one-shot/locked
modifiers, navigation/function keys, custom Pro rows and local snippets. The
permanent basic free tier and verified StoreKit non-consumable Lifetime Pro flow
preserve existing excess records and active sessions. No Mac helper is introduced.

82 hosted Simulator tests and independent OpenSSH/setup safety checks pass.
Three independent code/screenshot reviews led to fixes for key selection,
keyboard modifiers, setup duplicate detection, entitlement loading and form layout.
An intermittent SSH startup hang was traced to reading the server banner before
parser attachment; a deterministic regression verifies the corrected ordering.
Eleven Simulator screenshots are captured outside Git. Required stable-Xcode
repository validation passes. The normal Simulator and iPhone builds are refreshed
after review. The development-signed app/widget pass deep signature and exact
entitlement checks, and installation/launch succeed on iPhone 18 Pro Max (sequence
8364), preserving the existing app and Keychain identity.
Actual product creation/pricing/store review and
physical feature acceptance remain separate; no public release occurred.
See [implementation and verification evidence](evidence/2026-10-05-key-library-terminal-pro.md).

## 2026-10-05 — Expanded island curved-edge correction

The physical screenshot of sequence 8348 showed that the remaining upper symbols
were clipped by the curved mask. Expanded content now uses only the inset bottom
region: desktop symbol, Mac name and phase share the header below the camera,
followed by Resume and End. Compact/minimal presentation is unchanged. Eight
hosted session tests, narrow/larger-text render checks, required stable-Xcode
validation and normal device build/signing checks pass. Installed and launched
on iPhone 18 Pro Max, sequence 8356. The user confirms the expanded layout works,
passing physical acceptance for the reported clipping issue. See
[edge evidence](evidence/2026-10-05-island-edge-insets.md).

## 2026-10-05 — Expanded Dynamic Island layout

Expanded status and Mac identity now use the full-width region below the camera;
small symbols occupy the narrow top regions. The name allows two lines and the
compact actions say Resume and End, retaining the full End Session accessible
label. Narrow widths and larger text fit within the bottom-region height budget.
Eight hosted session tests, required stable-Xcode validation and normal device
build/signing checks pass. Installed and launched on iPhone 18 Pro Max, sequence
8348. Actual physical expanded-island visual acceptance remains separate; the
Simulator registered the activity but did not visibly expand it. See
[layout evidence](evidence/2026-10-05-island-expanded-layout.md).

## 2026-10-05 — SSH keys and optional iCloud sync

Terminal now offers Ed25519 key creation, encrypted OpenSSH import and public-key
installation instructions. Private keys remain device-only; server trust still
precedes authentication with no password fallback. iCloud library sync is opt-in,
default off, using the existing Keychain access group with explicit privacy consent
and separate cloud-copy deletion. Passwords, private keys, server trust and saved
text remain local. 73 hosted Simulator tests, full stable-Xcode validation, normal
physical build and deep signing checks pass. The finished update is installed on
iPhone 18 Pro Max (sequence 8332); automatic launch was denied because the phone
was locked. Actual cross-device cloud delivery and physical
key-login acceptance are separate. See [evidence](evidence/2026-10-05-ssh-keys-icloud-sync.md).

## 2026-10-05 — Appearance and menu organization

System/Light/Dark app appearance, independent Terminal colors, adaptive login and
native controls, grouped Mac/session menus, native submenu/back navigation and
section-scoped preference editing are implemented. 65 hosted Simulator tests and
required full repository validation pass. Normal device build and signature checks
pass; the completed update is installed on iPhone 18 Pro Max (sequence 8324).
Post-install launch was denied because the phone was locked; physical acceptance
is separate. See [audit evidence](evidence/2026-10-05-appearance-menu-audit.md).

## 2026-10-05 — Client unlock, Terminal and input modes

All five authorized features are implemented in the normal direct iOS development
composition: optional Face ID/passcode app unlock, fullscreen keyboard-bar hiding,
SSH Terminal, atomic Pointer taps and Trackpad & Keyboard without video. No Mac
helper or legacy services start. 61 hosted Simulator tests and stable-toolchain full
validation pass. Final device build and deep signing verification pass. The completed update is
installed on iPhone 18 Pro Max (database sequence 8308). Physical acceptance remains
separate; details are recorded in
[evidence](evidence/2026-10-05-client-access-terminal-input-modes.md).

# Mac Companion Execution and Blocker Ledger

## Current Dynamic Island identity and End Session — 2026-10-05

Compact presentation shows the Mac name and a phase symbol. Expanded/Lock Screen
presentation shows the name, phase, Resume and End Session. The background-only
Live Activity intent targets the unique current activity ID and shares the app's
deliberate exit path. Retired or repeated actions cannot end a replacement viewer;
an orphaned activity is dismissed without starting a connection. Opt-out and
recovery policies remain intact; no Mac helper or ongoing background mode is added.

Fifty hosted Simulator tests, rendered shared card checks, required stable-Xcode
validation, normal device build and source/signature/intent metadata verification
pass. The update is installed and opened on iPhone 18 Pro Max (sequence 8292),
preserving app data. Physical island layout and action delivery acceptance remain
pending. See [island action evidence](evidence/2026-10-05-island-session-actions.md).

## Current Mac editor clarity and default port — 2026-10-05

The Add/Edit Mac toolbar now contains Cancel and Save. Address-only Reorder/Done
is scoped to the Connection Addresses heading and shown for multiple addresses.
Clearing Port now resolves to 5900 for validation, shared-address information and
persistence; invalid nonempty ports remain rejected. Default placeholder/help
explain the behavior, and custom ports remain editable without forgetting login.

Forty-six hosted Simulator tests, rendered editor checks, required stable-Xcode
validation, normal device build and source/signature verification pass. The update
is installed on iPhone 18 Pro Max (sequence 8284), preserving app data. Automatic
launch is denied because the phone is locked; physical editor acceptance remains
pending. See [editor evidence](evidence/2026-10-05-editor-default-port.md).

## Current Follow Cursor adjustment — 2026-10-05

Zoomed Trackpad mode now pans near the viewport edges to keep iPhone-originated
mouse movement/dragging visible, preserving zoom and the selected display crop.
Manual pan/pinch suspends following until the next trackpad gesture. Keyboard
resizing uses the current available viewport. Delayed server cursor updates do
not move the view. Held dragging uses fixed overlay coordinates to avoid feeding
automatic pan back into mouse movement. Follow Cursor defaults on per Mac and
has an opt-out in Input & Quick Actions. It adds no idle polling, frame copies,
input events, network requests, reconnect or Mac helper.

Forty-four hosted tests and eight indexed geometry cases pass. The settings
opt-out is checked in a rendered Simulator view. The normal iPhone build and
source/signature verification pass; the update is installed on iPhone 18 Pro Max
(sequence 8204), preserving app data. Required stable-Xcode validation and
automatic launch pass. The user confirms Follow Cursor works well on the installed
iPhone update, passing the basic physical behavior/feel check. Sustained corner
cases and measured energy/frame-time overhead remain unverified. See
[Follow Cursor evidence](evidence/2026-10-05-follow-cursor.md).

## Current keyboard viewport adjustment — 2026-10-04

A docked keyboard now reduces the desktop viewport and raises the keyboard strip
and floating controls using the system animation. Fit follows available space;
zoomed views retain relative zoom/center, and dismissal restores the prior view
when its display crop remains valid. Display/framebuffer changes invalidate stale
restoration. The keyboard button switches to a down-chevron keyboard symbol and
Hide Keyboard accessible label while input owns focus. No RFB reconnect, Mac
desktop resize or helper is involved.

Thirty-nine hosted tests pass, including actual UIKit viewport/first-responder
checks. Required stable-Xcode validation, the normal device build and
source/signature verification pass; the update
is installed and launched on iPhone 18 Pro Max (sequence 8196), preserving app
data. Physical keyboard acceptance is pending. See
[keyboard viewport evidence](evidence/2026-10-04-keyboard-viewport.md).

## Current saved-login and shared-address correction — 2026-10-04

Address/port edits now preserve the saved login for that Mac UUID. Cross-record
endpoint sharing is allowed and displays an informational editor note; accounts
remain isolated by UUID. Only explicit Forget Saved Login, retention opt-out or
record removal delete the credential. This supersedes the route-edit deletion
policy in the prior session-interface update. Previously deleted logins require
one new entry; they cannot be recovered by this correction.

Thirty-six hosted tests, rendered Simulator duplicate-address saving, required
stable-Xcode validation, the normal iPhone build and signature/source verification
pass. Installation initially fails with CoreDevice 4016 while the phone's trusted
developer tunnel is unavailable. After the user unlocks iPhone 18 Pro Max, the
retry installs successfully (sequence 8188), preserving app data. The correction's
credential/address behavior still needs physical acceptance. See
[login-retention evidence](evidence/2026-10-04-library-login-retention.md).

## Current session interface and private VPN routes — 2026-10-04

The direct iOS client now supports 1–8 ordered addresses per Mac and an advanced
port setting. Version-1 saved Macs migrate without changing their UUID/login;
fallback ends at the first TCP success and never retries authentication on a
different address. The previous IPv4 filter incorrectly rejected Tailscale's
100.64.0.0/10 range. The corrected filter retains public-address rejection and
exact resolved-sockaddr connection. The user confirms Tailscale IPv4 now works
on the installed iPhone update.

The login identifies the selected Mac, keeps native AutoFill and per-Mac saved
credentials, and shows actual progress until a fresh desktop frame. A healthy
session has no routine Connected label. One bottom-right native glass button
offers primary press-and-slide quick actions and categorized controls, with
deliberate Exit to My Macs. The keyboard strip stays directly available. Pointer
speed/acceleration is adjustable per Mac; mode and a verified display selection
are remembered. Custom shortcuts/text are device-local per-Mac Keychain entries;
unreadable entries remain preserved. Atomic custom-action queue admission cannot
disconnect or partially send an action when the queue is busy.

Thirty-three hosted tests and required stable-Xcode validation pass. Rendered
login, address/advanced-port editor, synthetic controls and display picker checks
pass. The normal device build matches 480 source input hashes; signatures,
existing Keychain group and ActivityKit extension verify. The update is installed
and launched on iPhone 18 Pro Max (installation sequence 8180), preserving app
data. The user confirms the requested IPv4 connection and press-slide menu test
works. Automatic route fallback, credential-manager selection across machines,
custom actions, speed/display restoration and sustained physical reliability
remain for physical acceptance. No Mac helper is added. See
[session interface evidence](evidence/2026-10-04-session-interface-private-routes.md).

## Current direct session recovery and optional status — 2026-10-04

The established direct RFB connection now pauses its owner on inactivity instead
of closing immediately. It releases input, sleeps without frame processing, and
requests a full refresh on foreground return. A failed/1500-ms resume makes one
replacement attempt, preserving verified display, zoom, viewport center and
mouse mode. Pending handshakes still cancel; Done permanently retires the viewer.
A one-second bounded UIKit task finishes input release and the paused status;
there is no perpetual background streaming or execution mode.

The generated normal iOS development app includes an optional ActivityKit session
extension. My Macs > Session Settings defaults “Show session in Dynamic Island”
on; opt-out and dismissal are respected independently of recovery. It publishes
Connected, Paused or Reconnecting and resumes only a saved Mac. No Mac helper,
new authentication, relay/APNs or permanent release identity is added.

Twenty-two hosted tests pass, including actual native same-socket pause/resume
and actual ActivityKit start/update/end. The rendered settings UI and persisted
toggle pass Simulator checks. Required stable validation and the normal device
build pass. The matching signed update/extension are installed and launched on
iPhone 18 Pro Max, preserving app data and its existing Keychain group. The user
confirms short background return through Dynamic Island resumes the desktop with
display and zoom preserved. Fixed device counters show one connection start,
two retained resumes and two resume frames, with failure stage zero. Long
background/lock/process-termination recovery, input after return and sustained
physical reliability remain pending. See [session recovery evidence](evidence/2026-10-04-session-recovery-live-activity.md).

## Current standalone-client UX follow-up — 2026-10-04

The user confirms the installed standalone app works. The next update adds
bounded Apple VNC display-layout decoding directly in the iPhone session,
without a Mac helper or a reconnect. Individual display crops remain conditional
on compatible metadata; malformed/unknown layout returns to All Displays and
cannot blank a working framebuffer. Twelve native/Swift hosted tests pass,
including stream framing, stale metadata, relative trackpad motion, drag release
and selected-display updates. Required stable validation passes. Twelve
authoritative display-layout boundary
cases join the existing endpoint/login fixture.

The viewer offers only Pointer and Trackpad, hold-to-drag in both, and one Done
action to disconnect and return to My Macs. The searchable Mac library has a
visible manage menu, labeled editor, login removal, an empty state and a separate
setup guide. The matching source-built, signed update is installed on iPhone 18
Pro Max with its data and signing group preserved. Automatic launch is denied
because the phone is locked. Live display detection and physical gesture
acceptance remain pending. See [client UX evidence](evidence/2026-10-04-direct-client-ux.md).

## Current standalone-client migration — 2026-10-04

The product owner chose one iOS app and built-in macOS Screen Sharing, with no
optional helper. The normal VNC development app now starts a direct My Macs
library and native RFB connection; it does not create the legacy identity,
pairing, primary, Control lease or Agent/tunnel runtime. Saved login uses a
separate direct Keychain service with existing signing groups unchanged.

The Mac app and launchd Agent were stopped. Built-in Screen Sharing still
responds; an actual native connector in Simulator reads its RFB greeting without
credentials or pixel/input requests. Nine hosted tests pass: direct greeting,
no-auth rejection, stalled-handshake cancellation, old-owner status fencing,
multiple-Mac persistence/deletion, damaged-file preservation and existing
viewport/cursor tests. The actual direct library UI builds and opens in Simulator.
There are 133 indexed fixtures, including 21 endpoint and seven login boundaries.

At the initial standalone checkpoint, exact window fitting and individual-display
selection were deferred; the UX follow-up above adds bounded display metadata. ARD login
protects credentials but does not encrypt desktop/input traffic or pin the host;
the development setup discloses this. Secure transport and public release remain
open gates. Full stable validation and the matching signed iPhone build/install pass. The
Add Mac editor was corrected after UI verification found stale sheet state; the
actual add/save/open-login flow now passes in Simulator. Automatic phone launch
is denied because it is locked. Physical sustained acceptance remains pending.
See [standalone-client evidence](evidence/2026-10-04-direct-screen-sharing.md).

## Historical paired-host migration checkpoints

Latest migration: [normal-app VNC integration evidence](evidence/2026-10-04-vnc-integration.md).
VNC is integrated in the normal development apps over the existing authenticated
TLS primary, retaining pairing and current Control lease checks. Both final
updates are signed and installed. The bounded Retina allocation correction
presents nine physical video frames. A separate unused legacy media publication
then reaches its three-second XPC deadline and retires the host. A VNC-specific
lease adapter removes that producer with existing lease, indicator and Stop
checks preserved. Its final stable validation and Mac build pass; the signed
correction is installed. The user confirms at least 30 seconds of visible desktop
on the iPhone 18 Pro Max. Content-free logs corroborate 406 frames, six local view
changes on one VNC connection and four successful lease renewals over about 37
seconds, without the old capture producer or publication timeout. This passes a
short sustained-playback check. Selected app/window viewing, physical interaction
and recovery/soak acceptance and permanent release admission remain open.

Keyboard follow-up: basic input is physically confirmed. Toolbar modifiers were
persistent remote key-downs and never released after a shortcut. The iPhone
correction sends one-shot balanced chords, clears selection and provides a
standalone modifier press by holding the button, plus More > Shift only.
Seventeen indexed keyboard cases, four atomic queue bounds, required stable
validation and the normal iPhone build pass. The signed normal iPhone update is
installed with existing pairing and Keychain entitlements preserved. Physical
modifier and standalone Shift acceptance remain pending.

Viewport follow-up: display selection previously zoomed the full desktop without
limiting its canvas. The normal viewer now crops both the image and scrollable
canvas to the selected display, translating and bounding pointer coordinates.
Two-finger double tap fits the topmost visible Mac window at that point; repeating
it returns to the full selected display. The bounded window metadata query uses
the existing authenticated Desktop tunnel and current Control checks, leaving
VNC connected. Stable required validation passes with 132 indexed fixtures, and
normal Mac/iPhone builds pass. A hosted actual-viewer Simulator test passes crop,
input mapping, window fitting, stale replies and 60 display changes. Final
source review also reproduces a send-order race when the primary sender
suspends: window metadata can overtake input or RFB data. Client and host sends
are now serialized in stream order, with queued-write retirement and per-chunk
close guards. The suspended-send and greeting-only host regressions pass. Matching
signed updates are installed on both normal apps with pairing/signing preserved;
the updated Mac app and Agent run. The iPhone is locked, so automatic launch is
denied. Physical confinement, native window-hit/gesture acceptance and the
remaining interaction/recovery/soak gates remain pending.

Cursor/toggle follow-up: LibVNCClient remote cursor support was disabled, no
shape/position handlers were installed and UIKit had no local pointer overlay.
The session now requests standard RFB cursor updates and bounds/converts masked
cursor pixels; the viewer shows immediate local pointer feedback, aligns native
hotspots through crop/zoom/pan and fences cursor delivery after Stop. Two-finger
double tap returns to fit after any zoom, including manual pinch. From fit it
prefers the window under the tap, with a two-times-fit fallback for an empty or
full-size target. Three hosted actual-viewer/session Simulator tests, indexed
cursor/zoom cases, required stable validation and the normal iPhone build pass.
The signed correction is installed on the iPhone 18 Pro Max, preserving pairing
and Keychain groups. Real server cursor and physical gesture acceptance remain
pending. The existing Mac Companion app/Agent supplies pairing, the encrypted
tunnel and session/Stop controls; built-in macOS Screen Sharing supplies the
desktop and input engine.

Latest physical investigation: [view-switch failure evidence](evidence/2026-10-04-native-physical-switch-failure.md).
The latest affected-phone attempt completes three retained switches, then
disconnects before the fourth replacement presents video. The native child
reports exact content-placement rejection (sample stage 7, stream error 6),
before watchdog cleanup; both capture and the original permit remain current.
A native regression reproduces those same codes. Normative fixture-backed
bounded placement discard repairs that path: mismatched frames confer no video
or input readiness, the first matching frame closes the interval, and Stop,
revocation and a two-second no-sample timeout remain enforced. Native regression
coverage, final required stable validation and the normal Mac build pass. The
rebuilt source host is signed with its exact catalog pinned. The first staging
attempt exposes unsigned Xcode Debug implementation libraries at launch; that
packaging defect is corrected by verifying/signing every normal Mach-O before
its containing bundle. The corrected normal Mac update is installed and
launched, with main app, Agent and existing listener ready. Existing pairing,
signing and the compatible physical iPhone client are retained. Physical
repeated-switch acceptance remains pending. This is a
specific initiating check, not evidence that the separate earlier lookup/input
failures or overall physical reliability are resolved.

Earlier attempts: the affected phone's journal and installed Mac logs establish an input rejection
after a completed switch and native preparation failure during a later switch.
Both retire the complete Control session. The underlying rejecting checks are
not yet established. A diagnostic-only signed Mac update is installed with
pairing and signing preserved; required stable validation passes on rerun.
The user's next attempt completes four retained switches, then fails in the Mac
selected-surface lookup during `prepareReplacement`, before native preparation.
The exact subcheck is still merged into `local.unavailable`; a refined diagnostic
candidate names existing admission, scope, geometry and live-window checks.
Its focused tests, required stable validation and normal Mac build pass; it is
signed, installed and launched with existing pairing and signing preserved.
Mirroring subsequently connects. Two direct attempts fail before any switch in
native TLS startup (code 2). A local probe reproduces an IPv4 route-format defect:
interface debug text includes a percent suffix rejected by the numeric parser.
Normative fixture-backed reconstruction from the exact IPv4 bytes repairs that
boundary; certificate validation, pairing and IPv6 handling remain unchanged.
Focused regressions, required stable validation and matching normal Mac/iPhone
builds pass. Both updates are signed and installed with existing pairing/signing
preserved; the new Mac app and Agent listener run. Mirroring reconnects and
physical startup passes: verified launch, advancing video for approximately
220 seconds and input admission. The earlier native TLS code-2 failure does
not recur, but the prior actual endpoint text was not recorded. Mirroring
does not activate the client toolbar, so no switch is performed in that run;
a direct phone attempt is requested to capture the refined rejection check.
Backgrounding then returns to the authenticated workspace; that observation
is not counted as successful Control resume. The switching root cause remains
unresolved in that earlier attempt. The earlier Simulator campaign does not establish physical
reliability or production readiness.

Latest reliability work: [implementation and acceptance ledger](evidence/2026-10-03-native-reliability.md)
and [measured plan](native-reliability-plan.md). Complete transition fencing and
content-free timing are implemented. A normal Simulator run measured 22 switches
at 4,658 ms p95 on the previously installed reconnection path. Retained native
connection ownership is now connected in source across the normal adapters.
The first three live candidates failed initial startup, exposing a Retina pixel
mismatch, a four-second XPC activation deadline collision and a stopped encoder
probe handoff. The native bridge regression passes after joined retirement.
A Mac restart interrupted the fourth run and cleared raw temporary evidence;
the recorded ledger distinguishes those summaries from fresh checks.
The rebuilt environment now starts video. Its first retained display switch
failed because the native depacketizer stripped the selected-surface marker.
The admitted source-copy patch and actual H.264/HEVC parser regressions repair
that path; a premature old input-readiness callback is also fenced. The new
live candidate passed four retained switches. Its two longer campaigns failed
after 25 and 19 successes; neither meets acceptance. Deterministic regressions
then exposed and repaired an atomic command/receipt read race. The repaired
source passes normal Mac/device/Simulator builds and required full stable
validation with 125 indexed fixtures. Its 200-switch retest failed after 101
successful retained switches, with native disconnect preceding a failed-owner
transfer. The initiating disconnect remains unresolved. Resize recovery passes
under the original Control session. A new candidate rechecks renderer state
after asynchronous capability probing and adds fixed, content-free native
terminal reasons. Its 23 native engine/adapter tests, required final stable
validation and four-switch/six-presentation retained journey pass. Its full
campaign also passes 202 retained switches and 204 advancing presentations,
with exactly two host/video starts for two Control sessions and complete cleanup.
Median is 691 ms and p95 1,526 ms in Simulator; physical timing is unverified.
A remaining preflight busy-state ordering gap was reproduced with suspended
probe tests and repaired. All 27 native tests, required stable validation and
the six-presentation resize recovery journey pass on the final source. Final
matching updates are installed and launched, preserving pairing identities.
Background/network recovery passes six advancing presentations. The final-source
UI journey completed 202 switches, but failed its evidence gate because the
collector cached a relocated Simulator container path and missed log rotation.
A separate supplementary diagnostic assessment preserves 202 complete switches
and 204 advancing presentations, with p95 1,126 ms; the original failure remains.
The collector repair passes six regressions, stable validation and a normal live
smoke that records one actual container relocation. Selected-window closure and
movement each recover Desktop/input under the same Control. A one-minute
Desktop hold survives a visibly verified Finder full-screen Space round trip;
ordinary multi-Desktop cycling remains pending. The new final-source 200-switch
campaign failed after 144 completed retained switches: fresh video appeared,
then the server terminated before input admission on the next switch. Its
complete journal covers an actual container relocation and atomic rotation.
Cleanup and original Simulator restoration pass. The initiating server
termination is under investigation; the repeated-switch gate remains open.
An independent deterministic backend-watcher race also retires healthy completed
retention after a suspended phase check. Normative fixture-backed local lifecycle
generation fencing repairs it; both healthy-retention and actual-Control-loss
regressions pass. Required stable validation and both SDK/all normal builds pass.
That earlier watcher-fix update was installed on both normal apps. iOS refused
launch while the affected phone was locked. Its complete 200-switch campaign fails after
63 retained switches and one successful fresh Desktop recovery; the following
retained Window handoff times out without a new presentation. The Mac process
watchdog reports failed Control/capture validation with the deadline still valid.
All cleanup passes. A diagnostic-only follow-up classifies the exact local
validation failure; the watcher phase repair alone does not resolve reliability.
That follow-up also fails after 151 retained switches: the native child reports
selection-predicate failure before the Mac watchdog, then fresh Desktop recovery
succeeds. XCTest fails when the keyboard does not return during that unexpected
recovery. The complete journal and all cleanup pass; successful transition traces
do not erase the terminal loss. An expanded controlled resize/reselection test
passes seven advancing presentations and reuses the recovered host for the next
Window. Earlier native selection/handoff classifiers are now implemented with
indexed closed vocabulary and passing native contract tests; their source-bound
diagnostic rebuild and required stable validation pass. That source then fails
a controlled resize: an exact health command escapes retirement as unavailable,
invalidates local XPC and cancels Desktop recovery through primary teardown.
A gated regression reproduces the shared-drain publication race in 32/32 attempts.
Publishing retired ownership inside the shared task repairs all 32; wrong-scope,
malformed-evidence and stale-retire checks remain passing. Open pickers now show
recovery and disable ignored choices while preserving Cancel. The new normal
Simulator build passes. An open-picker follow-up exposed stale surface-bound
inventory after recovery; the UI now refreshes that inventory before enabling
selection. Final stable validation, both SDKs and all normal builds pass. The
complete resize/reselection journey passes seven advancing presentations and
four retained handoffs with recovered-host reuse. The final-source repeated-switch
gate passes 202 retained transitions and 204 advancing presentations with exactly
one host/native connection per Control session and complete rotated/relocated
journal cleanup. Both normal updates are installed with existing pairing/signing
preserved. Mac app and Agent listener run; iOS refuses launch while the phone is
locked. Final-source movement/reselection and background/network recovery pass;
selected-window closure also recovers Desktop/input under the original Control
and passes cleanup. A one-minute final-source Desktop hold passes, but its
Mission Control automation times out before an actual Space change is observed;
that run does not establish Spaces acceptance. Simulator median is 912 ms and p95
1,180 ms, still above the latency target.
Physical acceptance, one-hour session, ordinary multi-Desktop Spaces and native
Sunshine/Moonlight comparison remain open.
A missing Mac development profile previously prevented
Agent execution; the existing compatible profile restored launch. At that earlier
checkpoint both Mac processes and the iPhone process launched. Physical playback
and long-session/recovery acceptance remain pending.
iPhone Mirroring needs the user's first-time setup
for the affected phone. Acceptance is in progress; the app is not production ready.

Latest product checkpoint: [remote-desktop MVP and pairing access](evidence/2026-10-03-remote-desktop-mvp.md).
The product owner chose one remote-desktop pairing flow and no per-session
Face ID/Touch ID confirmation. Observe and Act are removed from the main phone
workspace and website. New normal-app pairing atomically includes fixed
screen/input authority with disclosed Mac consent. Both normal apps select the
explicit trusted-device session profile and use the existing protected paired
session key for a fresh bound challenge; there is no cross-key fallback or
new wire-controlled policy. Existing Control-enabled devices retain their
keys/grants and need no re-pairing. Monitor-only devices retain their one-time
local upgrade. Stop, revocation, OS permissions and session/input fencing remain.
The missed initial granted-pairing client completion check is fixed. New golden
vectors and signing/grant regressions pass. Two existing network test-harness
scheduling assumptions were corrected without changing product networking.
Required full stable Xcode 27.0 validation passes with 123 indexed fixtures.
The focused normal Simulator journey passes fresh pairing, durable restart,
two native video/input sessions and Stop/key/state cleanup. Signed normal
Mac/Agent and iPhone 18 Pro Max updates are installed and launched, with existing
identities and native package retained. Local website preview is ready at
`http://127.0.0.1:4173/`. The extended Shared Display journey from the earlier
checkpoint stopped at an undelivered picker tap; view switching, physical
acceptance and production release gates remain pending. All changes remain
local and uncommitted.

## 2026-09-26 streaming engine and licensing decision

Latest branding checkpoint: [shared artwork and local website preview](evidence/2026-10-03-branding-local-preview.md).
The approved Linked screens artwork is integrated into both normal app targets
and the local website. Stable validation with 121 fixtures and all three normal
Mac/device/Simulator builds pass. Signed updates are installed on the Mac and
iPhone 18 Pro Max with existing pairing identities and entitlements retained.
The Mac launches and the normal Simulator renders its entry screen; physical
iPhone launch awaits unlock. The local website preview is ready, with responsive
layout and working feature tabs and FAQ. No public deployment or release occurred.

Latest keyboard checkpoint: [keyboard availability and installation](evidence/2026-10-03-keyboard-availability.md).
The local iOS keyboard opens throughout approved Control without Text/focus
preflight and remains available across view pauses. Delivery stays fenced until
fresh native presentation; paused commits and local composition are discarded.
Pickers restore an already-open keyboard. Unicode Text keeps its existing grant
and secure-focus checks; supported physical-key fallback remains under Keyboard
authority. Seven UIKit/coordinator tests, the five-presentation normal paired
Simulator switch journey and stable validation with 121 fixtures pass. Signed
normal Mac and iPhone 18 Pro Max updates are installed with existing pairing
identities and entitlements retained. Physical acceptance and connection reuse
remain pending.

Latest foreground recovery checkpoint: [foreground recovery and setup latency](evidence/2026-10-03-native-foreground-recovery.md).
Short background returns can make one fresh Desktop/native enrollment under
the exact still-current original Control approval and expiry. Old preparation,
renderer, enrollment and pending view selection drain before fresh admission.
Temporary inactive states fence input without retiring video. Canceled view
selection preserves Control; genuine primary loss exposes workspace recovery.
Asynchronous certificate commands and early inert client identity preparation
remove setup stalls. The normal Simulator foreground journey passes six native
presentations, three background recoveries including a held selection,
network-loss/reconnect, explicit Control restart, input and cleanup. Six UIKit
coordinator tests and both normal iOS/Mac builds pass. Separate display and
Window switches measure 2.2–3.1 seconds; normal switching still reconnects.
Required final stable validation passes with 120 fixtures. Signed normal Mac
and iPhone 18 Pro Max updates are installed and launched with existing pairing
and entitlements preserved. Complete connection reuse, physical acceptance and production
distribution gates remain open.

Latest input/view recovery checkpoint: [input, Finder and resize recovery](evidence/2026-10-02-input-switch-finder-resize-recovery.md).
One ordered and paced input worker coalesces pending cursor motion, fences old
geometry, and preserves button/key order. Native replacement stays opaque until
a fresh frame. Finder App crops consistently exclude background/overlay windows.
Exact retired native health is non-authorizing and leaves current Control usable.
A resized selected Window now gets one foreground Desktop recovery under fresh
primary Control and the original expiry, with new presentation acknowledgement.
Eight focused tests, 14 renderer lifecycle tests and required full stable Xcode
27.0 validation pass with 118 indexed fixtures. The normal Simulator resize
journey passes six native presentations, current-session Desktop recovery,
input, Stop/restart and cleanup. A second stale-picker disappearance journey
passes five presentations and keyboard/modifier/shortcut/pointer delivery.
The earlier failed live run exhausted disk space; its cleanup passed and only
completed disposable build caches were pruned before the successful rerun.
Signed normal Mac/Agent and iPhone 18 Pro Max updates are installed with existing
identities, entitlements, pairing and data retained. Physical Finder/resize/input
acceptance and latency measurement remain pending. Seamless resize tracking,
All Displays, the older permit-retirement/-102 trace, updated corresponding-source
closure, everyday acceptance and production distribution gates remain open.

Previous picker/capture checkpoint: [useful picker and centered Window capture](evidence/2026-10-02-picker-and-centered-window-capture.md).
The user reports intermittent return to the workspace and unhelpful picker rows.
A metadata-only probe reproduces the Window code-7 failure: platform output is
at the top-left while the admitted geometry expects centered fractional padding.
Explicit output placement fixes that measured mismatch without relaxing sample
checks. Titles are bounded transient Control-only metadata, helper/unavailable
choices are omitted, and exactly bound disappeared sources can acknowledge a
fresh Desktop replacement. Runtime failure keeps visible recovery guidance until
closed. Before/after placement regressions, all 118 fixtures, full stable Xcode
27.0 validation, both native SDKs, 12 lifecycle tests and normal app builds pass.
The signed Mac/Agent update with the new pinned host catalog is installed and
listening; the signed normal iPhone update is installed and launched on the
verified iPhone 18 Pro Max, with the existing pairing retained.
The new normal-app Simulator journey fails during disposable-service setup before
pairing; Window streaming/disappearance acceptance is unverified for this
candidate. The separate physical permit-retirement/-102 trace, physical retry,
everyday acceptance and production distribution gates remain open.

Previous physical App/Window checkpoint: [native launch investigation](evidence/2026-10-02-native-app-switch-investigation.md).
The user reports display switching now works, but App/Window switching still
fails. The physical trace reaches acknowledged capture, native enrollment and
server/application-list validation, then fails native launch response parsing.
The underlying capture/encoder cause is not yet established. Animated and static
selected App normal Simulator journeys both pass with five fresh presentations.
Bounded fixed capture diagnostics now survive owned-child cleanup; indexed
vocabulary/file-safety tests and full stable Xcode 27.0 validation with all 118
fixtures pass. The signed diagnostic Mac update is installed and its existing
Agent listener is verified; the iPhone remains on the preceding repair build.
A physical repeat is requested. App/Window failure remains unresolved, and
everyday acceptance and production release gates remain open.

Latest replacement reliability checkpoint: [native Window and repeated view repair](evidence/2026-10-02-native-window-and-replacement-repair.md).
The physical iPhone reports Window failure and blank video after display changes.
Matched content-free traces reproduce a reset rejection during replacement
preparation; inspection also finds native Window capture incorrectly restricted
to the Desktop's display. Normative specs and indexed fixtures precede both
repairs. Before/after regressions, all 118 fixtures, full stable Xcode 27.0
validation, both native SDKs and 12 lifecycle tests pass. The expanded normal-app
Simulator journey deliberately places the Window on another physical display
and passes both display switches, Window/input, Stop/start and cleanup with five
fresh presentations. Signed normal Mac and iPhone 18 Pro Max updates are
installed and launched with existing identities and pairing. Physical retry
confirmation remains pending; everyday and production release gates remain open.

Latest interface checkpoint: [compact remote session controls](evidence/2026-10-02-compact-remote-session-ui.md).
Choose Display contains its topology and provides readable selection rows. One
bar above the native keyboard exposes Escape, Tab and one-shot modifiers; one
Close/Stop replaces duplicate navigation/Stop controls. Indexed chord vectors,
both native SDKs, 12 embedded lifecycle tests, full stable Xcode 27.0 validation,
and the normal-app Simulator display/window/input/Stop journey pass. Private
screenshots were inspected. The signed normal update is installed on the iPhone
18 Pro Max with existing identity/data; launch was denied because the phone was
locked. Physical UI/input confirmation remains pending. All Displays has an
explicit capture/input plan and is not implemented. Everyday acceptance and
production release gates remain open.

Latest Shared Display checkpoint: [native display recovery](evidence/2026-10-02-shared-display-native-recovery.md).
The iPhone 18 Pro Max report is reproduced in the normal Simulator app. Shared
Display now preserves the visible renderer with a sheet. Fresh display enrollment
also exposed an invalid ordering comparison between independent authenticated
menu publication and Control activity counters. Normative specs and indexed
fixtures precede both corrected runtime guards; exact authority bindings remain
enforced. Before/after regressions, both native SDK builds, 16 lifecycle tests,
and full stable Xcode 27.0 validation pass. The expanded normal-client journey
passes both display replacements, selected Window/input, Stop/start and cleanup
with five fresh presentations. Signed normal Mac and iPhone 18 Pro Max updates
are installed and launched with existing identities. On 2026-10-02 local the user
confirms the repaired Shared Display flow works on the physical iPhone 18 Pro Max.
Production release and elapsed acceptance gates remain open.

Latest usability and source checkpoint: [enrollment ownership and frozen-source
preparation](evidence/2026-10-01-native-owner-usability-and-source-preparation.md).
The App/Window picker searches privacy-limited names/ordinals. A deterministic
regression proves an old enrollment owner's post-join compensation could cancel
a fresh reservation; scoped local ownership and completed-cancel publication
repair it without changing wire/signature/grant semantics. The 18 ordering cases,
both SDK builds, installed signed iPhone 17 Pro Max update, and full stable Xcode
27.0 validation with 118 fixtures pass. Ten normal-app Simulator sessions pass
after compilation finishes. An earlier run lost local XPC after a media reply
timeout under concurrent source rebuilds; its cause remains unproven. The frozen
current source archive reconstructs runtime/codecs/Web/host/both client SDKs and
a portable host package. Separate normal-client App and Window selection pass
against that archive-built host with three fresh presentations and input
delivery in each journey. The three-session normal-client background/primary-cut
recovery journey also passes against the archive host. Physical input approval,
the loaded-session stall,
native Release admission, distribution profiles, source delivery review,
notarization, and the final acceptance/elapsed soak gates remain open.

Latest physical reliability checkpoint: [installed enrollment and route
repair](evidence/2026-10-01-installed-native-enrollment-and-route-repair.md).
The user's iPhone 17 Pro Max authenticates using its saved pair. Physical testing
reproduced a bundled OpenSSL lookup into a missing developer build tree; the
signed installed Mac now explicitly uses its catalog-bound configuration.
Enrollment and managed-host startup then completed, exposing a missing measured
numeric route for DNS/Bonjour primaries. The client now retains the exact verified
transport's numeric address, with selection/replacement/termination fences.
Regression tests, 116 fixtures and full validation on stable Xcode 27.0 pass.
The final signed normal iOS native build is installed on the iPhone 17 Pro Max.
User Touch ID approval enabled physical tracing. The primary selected IPv6 while
the managed host listened only on IPv4; the signed installed development Mac
now uses dual-stack listeners. Real native video ran for more than four minutes;
Stop retired the host and preserved authentication. A fresh second session
exposed native admission incorrectly requiring equality between the advancing
activity receipt revision and unchanged menu publication revision. The correction
is installed; its regression fails before and passes after the change, with all
11 native bridge tests and final full repository validation passing. Physical
Stop/start on the same primary now passes without re-pairing or reconnecting;
the second session streamed for more than 21 minutes. The App shortcut switched
the Mac application. Failed-product retirement now targets the captured exact
session/primary, rejects stale and duplicate Stop, and uses terminal UI text.
The 18 ordering cases, concurrent retirement regression and five iOS coordinator
tests pass. Physical backgrounding exposed a hidden legacy bootstrap decoder
failure; foreground authenticated reconnect passes. Native construction now
suppresses legacy decoding after verified bootstrap acknowledgement while
retaining media admission and replacement bootstrap gates. A fresh physical session
verifies that suppression, advancing native video and background retirement without
the hidden decoder failure. Foreground saved-pair authentication passes after the
ten-second background grace expires. Native display selection exposed an existing
active-owner rejection; exact-session failed-product Stop physically passes for
that failure. The display drain/replacement correction is signed and installed;
the physical display switch now passes with fresh native presentation input
admission and advancing video, without reconnect or pairing. All four selected
native/legacy App/Display ordering cases pass. Real pointer/text/modifiers and
selected App/Window focus remain pending. The signed normal iOS client
containing the background and display recovery repairs is
installed on the physical iPhone 17 Pro Max; the saved pair authenticates after
installation. Final stable-Xcode validation passes with 118 indexed fixtures.

Latest installed Mac recovery checkpoint: [Agent entitlement preservation and
real dashboard reconnect](evidence/2026-09-28-agent-entitlement-preservation-and-installed-recovery.md).
The development stager now retains the Agent's required signed Keychain
entitlement; a fresh signed normal Mac app is installed. Its window shows Agent
ready, private listener listening and Control allowed, and returns to that
state after the Agent is restarted without replacing the dashboard process.
The normal iOS QA Simulator is unpaired to this installed Mac. The paired
physical iPhone app launches, but its Remote Control request showed the
generic **Command did not complete** alert. Content-free Agent audit events
show an earlier approved session remained active during six subsequent
requests from the same device; the host's active-session guard likely rejected
them. The initial session failure remains unexplained. Physical video and
input acceptance remain open.

Latest Mac dashboard recovery checkpoint: [fresh Control composition after
local XPC replacement](evidence/2026-09-28-dashboard-fresh-runtime-recovery.md).
The normal dashboard now awaits old adapter invalidation and constructs fresh
Control runtime, queue and capture owners for its replacement connection only
after the persistent indicator is inactive. Focused tests and stable validation
pass. This source checkpoint preceded the corrected signed installation above;
native playback remains unverified.

Latest Control reliability checkpoint: [normal app session soak and iPhone update](evidence/2026-09-28-native-session-soak-and-device-refresh.md). The updated normal iOS app is installed on the paired iPhone 18 Pro Max. Two ten-session Simulator soaks, a 30-minute Control hold, and another ten-session run with 120 immediate post-Stop status reads pass. A disposable test bridge now waits for its prior response socket to close; the cause of one earlier intermittent Stop-status EOF is still unproven. Repository validation passes with 116 fixtures. Physical playback remains unverified while device launch is unavailable.

Latest repeated Window/Desktop checkpoint: [normal app transition soak](evidence/2026-09-28-window-transition-soak.md). Exact correlation routing fixes the Control exit when display refresh overlaps surface inventory. The paired normal iPhone Simulator app passes 20 Window/Desktop transitions and 22 native presentations across two Control sessions, with keyboard, pointer, modifiers and shortcuts. The updated normal iOS native build is installed on the paired iPhone 18 Pro Max; iOS refused launch while locked. The signed normal Mac Debug app from the [earlier installation checkpoint](evidence/2026-09-28-normal-native-installed-candidates.md) remains installed. Physical launch, installed Mac TCC continuity, real input and LAN playback remain unverified. Stable validation with 116 fixtures passes.

Latest normal native App and Window checkpoint: [selected-target playback in the normal iOS Simulator app](evidence/2026-09-28-normal-native-app-window-simulator.md). Separate paired UI journeys now pass again on the current iOS source: real App and Window selection, selected native playback, keyboard, pointer and Shift+Tab delivery, Stop and fresh Control, with three native presentations each. Exact-key cleanup, host retirement and original Simulator app/data restoration pass. The Mac peer is disposable with substituted human consent and synthetic final input. Viewport bitrate, current corresponding-source assembly, installed Mac GUI/TCC and paired LAN/physical acceptance remain open.

Previous native surface switch: [Desktop reselection in the normal iOS Simulator app](evidence/2026-09-27-normal-native-desktop-reselection.md). The old native permit now drains only an exact retired reset, and the client blanks old-surface rendering during replacement. A full paired UI journey passes a fresh Desktop presentation and input admission after selection, keyboard/pointer/Shift+Tab/Copy, Stop, then a third presentation in a new Control session. The exact-key cleanup test, host retirement and original Simulator app/data restoration pass. The Mac peer is disposable with substituted human consent and synthetic final input.

Latest normal recovery fix: [initial acknowledgement ordering](evidence/2026-09-27-initial-acknowledgement-ordering.md). A real-channel reproduction rejects an early valid host reply before the fix. Pending state is now stored before sending; send completion preserves the committed reply and current ownership. Eighteen primary-channel and eight activation cases pass. The new normal Simulator candidate passes its complete three-session journey, including the previously failed second session, background restart guidance, inputs, Stop, disconnect/Reconnect and a third fresh session. Exact-key cleanup, host retirement and original Simulator app/data restoration pass. Both SDK/normal builds and stable validation with 112 fixtures pass. Native App/Window capture, viewport bitrate, current source assembly, installed Mac GUI/TCC and paired LAN/physical acceptance remain open.

Latest Observe reliability candidate: [manual refresh and liveness ordering](evidence/2026-09-27-observe-refresh-liveness-priority.md). A reproduced manual refresh collision with a pending automatic status check is fixed through one bounded local reservation, router-committed release, separate fresh request and visible refresh progress. Thirteen Observe tests, both SDK/normal builds and stable validation with 111 fixtures pass. The complete normal Simulator journey fails on the second Control session's initial screen receipt, after first-session background/Stop/status checks pass. Cleanup and original Simulator app/data restoration pass. The new candidate does not inherit earlier native recovery acceptance; overlapping initial render callbacks are the next investigation.

Latest normal recovery checkpoint: [normal iOS Simulator background and reconnect](evidence/2026-09-27-normal-native-recovery-simulator.md). The normal root passes three native sessions with keyboard, pointer, Shift+Tab, Copy, real background input fencing, explicit restart and host-induced primary connection loss/reconnect without pairing again. The final candidate shows clear restart guidance, disables unavailable controls and preserves Stop after foreground return. Host retirement, exact-key cleanup and original Simulator app/data restoration pass; both SDK builds and stable validation with 110 fixtures pass. One earlier post-background status command failure remains unexplained, with content-free diagnostics now enabled. Installed Mac GUI/TCC, paired LAN/physical, native App/Window capture, visible-area bitrate and current source assembly remain open.

Latest normal native Control checkpoint: [normal iOS Simulator sessions](evidence/2026-09-27-normal-native-control-simulator.md). The normal iOS app pairs, configures/reopens its saved route, obtains a separate Control grant and passes two native presentation/input-admission sessions with iOS keyboard, pointer, Shift+Tab, Copy and Stop/restart against the disposable signed Mac host. Observe remains authenticated after Stop. One UI and one exact-key cleanup test pass; host cleanup and original Simulator app/data restoration pass. Final input remains synthetic and human Mac consent is substituted. Normal background/connection recovery, installed Mac GUI/TCC, paired LAN/physical, native App/Window capture, visible-area bitrate and current source assembly remain open.

Latest normal workspace checkpoint: [completed pairing and restart](evidence/2026-09-27-normal-paired-workspace-and-restart.md). The normal Simulator app completes live pairing with explicit disposable Mac test consent, saves its public pair, configures a private route and reads live status. Reopening reuses the saved pair/route, authenticates and reads live status again. Observe-only permission remains separate from Control. One UI test and one exact-key cleanup test pass; host cleanup, original app/data restoration and stable validation with 110 fixtures pass. Normal native Control, installed Mac GUI/TCC, paired LAN and physical acceptance remain next.

Latest normal live pairing checkpoint: [Simulator Keychain and live pairing](evidence/2026-09-27-normal-simulator-keychain-and-live-pairing.md). The missing Simulator Keychain entitlement caused identity preparation to fail before TLS. Xcode-packaged development entitlements now resolve it with original approval requirements preserved. A real normal-app test reaches verified comparison over live pinned TLS, then cancels with no Mac approval or paired state; disposable host cleanup passes. Both SDK builds, compiled device exclusion and stable validation with 110 fixtures pass. Completed pairing, normal primary/Control and installed Mac/LAN/physical acceptance remain next.

Latest normal Simulator checkpoint: [normal bootstrap and code entry](evidence/2026-09-27-normal-simulator-bootstrap-and-code-entry.md). The normal admitted Debug Simulator app now reaches pairing using isolated development storage/software-backed custody; physical/default protection and approval presence remain. Standard code entry, invalid rejection, unverified preview and cancellation pass a real normal-app UI test. Both SDK/framework/normal builds, compiled device exclusion and stable validation with 110 fixtures pass. Completed pairing, normal LAN/Control, physical custody and installation remain open.

Latest network listener checkpoint: [managed IPv4 access](evidence/2026-09-27-managed-native-ipv4-listener.md). Normal Mac Debug now selects trusted IPv4-interface native listening after existing Control enrollment. The live non-loopback host probe passes certificate isolation, encrypted launch, downgrade denial, sealed routes and network listener retirement. Stable validation, the normal Mac build, fresh signed staging and four rebuilt-host Simulator video/control/recovery sessions with the IPv4 listener pass. The Simulator primary remains loopback and final input synthetic. The staged app is not installed or launched. Full normal paired LAN/physical acceptance remains open.

Latest network prerequisite: [mandatory managed encryption](evidence/2026-09-27-managed-native-encryption.md). The production backend now requires upstream LAN/WAN transport encryption. Live rejection of missing/zero encrypted-RTSP support and plaintext RTSP, valid encrypted launch, certificate isolation and revocation cleanup pass. Stable repository validation and four fresh visible Simulator sessions with controls, recovery and cleanup also pass. Final input remains synthetic. That checkpoint retained loopback; the subsequent managed IPv4 listener checkpoint records the network change. Normal installed/paired and physical acceptance remain open.

Latest client source-rebuild checkpoint: [extracted client rebuild](evidence/2026-09-27-extracted-native-client-rebuild.md).
Both historical client SDKs rebuild from the pinned packet using its frozen builder
and verified source-built OpenSSL. Twelve dedicated Simulator component tests,
six framework inventories and immutable source/dependency readback pass. This
historical adapter contains its original reference probe and is not admitted as
the current normal-app candidate. Current source snapshot assembly and matched
current host/client acceptance remain next; corresponding-source completion and
installed normal-app/physical acceptance remain open.

Latest archive-package checkpoint: [rebuilt portable host](evidence/2026-09-27-archive-rebuilt-portable-host.md).
The archive-rebuilt host now has a distinct verified development package with ten
native binaries, rebuilt OpenSSL, source-bound production supervisor and complete
linked-library notices. Relocation without search overrides, credential CLI,
tamper rejection and stable validation pass. Historical package verification is
preserved. Fresh live acceptance is recorded separately; no permanent catalog or
installed app was changed. Full client source reconstruction/current source
assembly and normal paired/physical acceptance remain open.

Latest host source-rebuild checkpoint: [extracted Sunshine rebuild](evidence/2026-09-27-extracted-native-host-rebuild.md).
Sunshine now rebuilds from the pinned source packet with the rebuilt runtime/codecs,
local Boost/JSON archives and all 193 offline npm inputs. Final link/readback and
stable validation pass: 25 static inputs, seven runtime libraries and 82 Web assets.
The version command passes with explicit verified development library paths; the
unbundled default loader lacks miniupnpc resolution. Portable packaging, startup
and fresh video acceptance remain next, alongside client source reconstruction and
current corresponding-source assembly. Installed apps are unchanged.

Latest codec source-rebuild checkpoint: [extracted native codec rebuild](evidence/2026-09-27-extracted-native-codec-rebuild.md).
All seven host codec libraries now rebuild from the explicitly pinned source
packet with 183 installed files and inspected macOS 26.0 deployment commands.
Archive-specific tag/version adaptations are recorded in a separate working copy;
the retained payload remains unchanged and an incorrect source pin is rejected.
These are fresh artifacts, without new playback acceptance. Full Sunshine/client
reconstruction and corresponding-source assembly remain open. The running installed
Mac app and separate Sunshine app were left intact.

Latest normal iOS selection checkpoint: [production client adapters and normal app build](evidence/2026-09-27-normal-ios-native-development.md).
First-party video/TLS/launch adapters now live under `Native/Client`; the default
SDK excludes the reference surface probe. The normal root selects these adapters
in an explicit Debug-only development project with verified engine artifacts.
Both SDK builds, twelve component tests, six-framework inventory, normal app
builds for both SDKs and stable repository validation pass. The normal app was
installed and launched only in the dedicated Simulator. It stops before pairing:
its required file-protection attribute is absent there. No storage/key-custody
requirement was relaxed. Normal paired Control acceptance, signed Mac GUI/TCC
continuity, installation on physical devices and real input remain open.

Latest normal Mac selection checkpoint: [bundled native selection](evidence/2026-09-27-normal-mac-bundled-native-selection.md).
The normal Mac root now supplies the development factory when its signed containing
bundle has the exact compiled catalog and complete admitted host inventory. The
normal Debug build, resource rejection tests, signed normal app staging and actual
production factory selection pass. Release does not select this authority. The
installed Mac app is unchanged; normal paired GUI/session acceptance,
TCC continuity, installation and real input/physical acceptance remain open.

Latest resource-construction checkpoint: [production supervisor package](evidence/2026-09-27-production-supervisor-package.md).
The new portable host contains a source-bound production supervisor built for macOS
26 with the explicit stable SDK. Closed provenance, dependency/signature checks and
four tamper-rejection checks pass, followed by signed app-owned native launch,
renewals and Stop, and four visible sessions in the dedicated Simulator. The first
Simulator run lost its Agent before pairing; the sequential rerun passes and both
reports are retained. Normal containing-app resource/factory selection, installation,
real input and physical acceptance remain open.

Latest production Mac wrapper checkpoint: [managed-host promotion](evidence/2026-09-27-production-managed-host-wrapper.md).
The process/enrollment implementations now live in the normal Mac platform module,
with experimental aliases and an explicit artifact-validating factory. The finite
supervisor has a production source path. Real lifecycle tests, the normal Mac
Debug build, iPhone SDK build and signed app-owned native launch/renewal/Stop pass.
Default native factories, foreign artifact admission and installed normal-app
acceptance remain open; this checkpoint does not claim physical or real input
acceptance.

Latest Mac process checkpoint: [native menu app privacy attribution](evidence/2026-09-27-native-menu-app-tcc-attribution.md).
Fresh TCC traces show earlier command-line capture attributed to Codex. A real
signed app launched through macOS attributes the native child to MacCompanion.
A Developer ID requirement mismatched the installed development grant; the exact
installed Apple Development requirement produces allowed ScreenCapture records
and passes native launch, two renewals, Stop/Observe and cleanup. The runner now
verifies and reports the actual portable host/TLS inputs and rejects invalid
signing references with cleanup. [ADR-0003](adr/0003-managed-native-video-process.md)
records the measured development arrangement. Permanent dependency/signature/
privacy admission and normal factory selection remain open; no installed normal
native app, physical iPhone or real input acceptance is claimed.

Latest normal-app wiring checkpoint: [iPhone native composition hook](evidence/2026-09-27-normal-app-native-composition-hook.md).
The normal workspace now forwards an optional native Control factory, with a
paired-host signer and current-primary route reader. The Simulator harness uses
this shared construction. Both native SDK builds, twelve component tests,
six-framework inventory and the normal iPhone Simulator build pass. A background
retirement regression in the first extraction was corrected; the final four live
sessions pass with controls, background/route recovery, Stop/Observe and cleanup.
Input effects remain synthetic. Default native factories remain unset; production
host identity/capture/TCC and dependency admission precede selecting the engine
in both normal apps. Installation and physical/system-input acceptance remain open.

Latest source-delivery checkpoint: [native candidate source-input archive](evidence/2026-09-27-native-candidate-source-inputs.md).
A file-bound archive retains 42 pinned source components, 17,355 files/symlinks,
six verified source archives and the exact Mac/iPhone/Simulator build bindings.
Safe extraction, full readback, changed-source rejection and stable validation
pass. The [extracted dependency and offline Web UI checkpoint](evidence/2026-09-27-extracted-native-source-dependency-rebuild.md) now proves six rebuilt dependency configurations and an offline install/build using all 193 npm archives. Full native source reconstruction/rebuild and assembled corresponding-source delivery remain open; completion and permanent admission remain false.

Latest integration checkpoint: [source-built portable native host](evidence/2026-09-27-source-built-portable-native-host.md).
The four source-built runtime dependencies and seven codec libraries now feed
a verified portable development package. The x265 assembly deployment warning
is repaired; every inspected codec object targets macOS 26.0. Signature/integrity,
relocation/startup/credential checks and stable validation with 109 fixtures pass.
Four live Simulator sessions pass with video, keyboard/modifiers/shortcuts,
pointer, background/reconnect recovery, Stop, Observe and cleanup. Input effects
remain synthetic behind the real native permit. Complete transitive source and
permanent process/TCC admission, normal-app composition, installation and physical
system-input acceptance remain open. Physical macOS 26 runtime compatibility has
not been tested.

Previous live integration evidence: [portable native host development package](evidence/2026-09-27-portable-native-host-package.md).
The packaged host now carries all six linked runtime dylibs, its certificate CLI
and process supervisor. Loader-relative references, strict signatures, file/symlink
integrity and construction provenance are verified. Relocation/startup/credential
checks pass and a changed dependency is rejected. Four live native Simulator
sessions pass through this package with controls, background revocation, route-loss
recovery, Stop/restart, fresh Observe and cleanup verified. The client retains its
source-built OpenSSL candidate. Host/transitive source/build provenance and permanent
process/TCC admission remain next, followed by normal-app composition and signed
installation. Ad-hoc development signatures and a synthetic input sink do not
prove actual system input, LAN, installed-product or physical behavior. Native
focused App/Window capture and visible-area bitrate remain open.

The owner approved developing both apps around Sunshine and Moonlight and
accepted GPL licensing. The [integration plan](sunshine-moonlight-integration-plan.md)
now governs this engine migration. Combined distribution uses GPL-3.0 with
retained Apache-2.0 and upstream notices under `../LICENSING.md`. This supersedes
the Apache-only product direction in the historical entries below. Corresponding
source, exact dependency admission, process/TCC ownership, session/input fences,
Apple distribution review, and existing release gates still require evidence.
Disposable upstream experiments remain outside permanent targets. This decision
does not admit new wire/security semantics or change Observe/Act/Control grants.

Implementation checkpoint: [Sunshine/Moonlight foundation](evidence/2026-09-26-sunshine-moonlight-foundation.md).
Pinned source-built host and reference client reached a decoded Desktop frame
on the dedicated Simulator with audio explicitly disabled. The experimental
video component builds for Simulator and iPhone and passes four native lifecycle
tests; its process supervisor passes four real-process tests. These components
remain under `Experiments/`. Normal-app composition, credential enrollment,
dependency/TCC admission, physical installation, and device acceptance are open.
The user's existing installed host configuration was not used by the experiment.

Simulator follow-up: [extracted-engine live playback and teardown](evidence/2026-09-26-simulator-embedded-moonlight.md)
now proves two decoded-frame/Stop/drain sequences through the extracted framework
in the reference client, including a fresh stream after teardown. Required server
codec metadata and real network-failure coverage were repaired; the final native
suite passed four tests and repository validation exited 0. This remains a
reference-client experiment; normal MacCompanion composition is still open.

Native-owner follow-up: [normal UIKit owner and enrollment verifier](evidence/2026-09-26-native-video-owner-and-enrollment.md)
adds a production native surface/owner and Desktop injection hook, exact decoded
geometry, immediate blanking and drained Stop, golden enrollment signing, and
a single-use host attestation verifier. Twelve native tests passed; ten reference
frame/Stop checks and a fresh final packaged check passed with native input
disabled. Both unsigned SDK components and their complete framework inventory
are available. Authenticated certificate registration, normal managed host
startup, native input presentation admission, automatic normal-app composition,
signed installation, and physical acceptance remain unfinished. This checkpoint
does not claim the requested usable engine replacement is complete.

Managed-host follow-up: [local enrollment and managed startup](evidence/2026-09-26-managed-native-host-enrollment.md)
adds production host and client attestation owners and an isolated experimental
Sunshine backend. Golden-vector, startup race, key-custody cancellation, exact
certificate admission, port conflict, revocation, and private-state cleanup
checks passed. The normal authenticated primary records, native client launch,
presentation/input admission, permanent process/dependency gates, normal-app
composition, signed installation, and physical acceptance remain open.

Primary-enrollment follow-up: [authenticated Control enrollment routing](evidence/2026-09-26-native-video-primary-enrollment.md)
adds closed indexed request/challenge/proof/ready/cancel records, optional normal
host dispatch, store-bound native runtime composition, client correlated waits,
and a role-owned enrollment session. Stop/late-result, display-mismatch, and
durable-grant-loss checks pass; stable repository validation and both SDK builds
pass. Native TLS/launch, the concrete Mac runtime provider, automatic UIKit
startup, native presentation/input admission, packaging/TCC, signed installation,
and physical acceptance remain open. The normal apps do not yet automatically
select native video.

Native-client follow-up: [in-memory TLS, launch adapter and normal startup hook](evidence/2026-09-26-native-client-tls-launch.md)
adds temporary native identity creation, exact host pin/client-key possession,
bounded HTTPS and XML, sole-Desktop/encrypted-route launch construction, joined
TLS/video/enrollment retirement, and optional automatic UIKit preparation after
initial Desktop acknowledgement. Eight real TLS cases, actual enrolled-client
Sunshine metadata access, fifteen Simulator component tests and both SDK builds
pass. The concrete Mac runtime provider, sealed phone-facing host, dependency/
TCC packaging, complete live native startup/presentation, normal app configuration,
signed installation and physical acceptance remain open.

Managed-profile follow-up: [sealed managed native host](evidence/2026-09-27-sealed-managed-native-host.md)
adds a local managed profile that disables upstream administration/plaintext
listeners and native pair/resume/appasset routes, and preserves the configured
native runtime across normal Mac bootstrap. Actual admitted-client/forbidden-route
and listener checks, eight TLS cases, fifteen Simulator checks, both SDK builds
and stable repository validation pass. All artifacts match one source snapshot.
The host remains loopback-only; authenticated Mac runtime construction, normal-app
composition, native presentation/input, packaging and installation remain open.

Runtime-snapshot follow-up: [authenticated native runtime projection](evidence/2026-09-27-authenticated-native-runtime-snapshot.md)
adds atomic acknowledged-Desktop projection, bounded generation-bound local XPC
snapshot records, concrete Mac route mapping and active-primary/menu-generation
checks before and after runtime/backend suspensions, plus immediate native
admission retirement during pending Stop. Nine focused checks, final stable
repository validation, fifteen native Simulator checks, both SDK builds and
matching host/TLS probes pass. The normal Control regression also passed three
UI journeys and five pairing checks; full native XPC/enrollment is still unproved. Menu-owned backend operations, approved physical display resolution,
automatic client composition, native presentation/input and installation remain open.


Menu-backend follow-up: [menu-owned native host operations](evidence/2026-09-27-menu-owned-native-backend.md)
adds bounded backend records on the authenticated local route, an inert Agent
proxy, acknowledged-runtime/physical-display joins, a menu-owned factory seam,
and joined cleanup with early Stop admission fencing. Four menu lifecycle and
two proxy cancellation/correlation checks pass, along with final stable repository
validation, fifteen native Simulator checks, three normal Control journeys, five
pairing regressions and both SDK builds. All native artifacts match one source
snapshot. The actual managed Sunshine host
passes through the production proxy/menu owner using an explicitly in-process
record bridge. Complete authenticated native XPC/primary startup, automatic
client composition, native presentation/input, packaging and installation remain
open. The default normal app has no admitted experimental host factory.

Real-menu launch follow-up: [production menu admission and native launch](evidence/2026-09-27-real-menu-native-launch.md)
replaces the synthetic acknowledged snapshot in the managed host probe with the
production menu runtime. Unacknowledged preparation is rejected; actual menu Stop
retires the host. The in-memory admitted client completes a real sole-Desktop
HTTPS launch and the shared iOS parser verifies its encrypted stream address.
Authenticated local XPC/primary enrollment, decoded normal-app playback, native
input, packaging and installation remain open. Platform bootstrap effects are
explicit substitutes and this probe does not claim phone presentation.

Authenticated-native follow-up: [signed primary/XPC launch and renewal continuity](evidence/2026-09-27-authenticated-native-launch-and-renewal.md)
now joins real production pairing, authenticated primary Control, signed local
XPC and the managed host. It repairs native two-hour/four-hour limit mismatches,
a shadowed runtime snapshot read, and premature retirement at descriptor freshness
expiry. Native enrollment, mutual TLS Desktop launch, continuity across two Control
renewals, joined Stop cleanup and same-primary Observe all pass. Stable validation,
both SDK builds, fifteen native Simulator checks, three normal Control journeys,
five pairing checks, eight TLS checks and managed host admission pass at one
source snapshot. Visible decoded native playback in
the normal client, native presentation/input, permanent dependency/TCC packaging,
installation and physical acceptance remain open.

Status date: 2026-09-08

This is the living execution authority for the staged plan. A blocker applies only to work that names it as a dependency. Work in every other safe lane continues. Evidence links point to repository artifacts or reproducible commands; secrets and Apple-account records remain outside the repository.

Development testing policy (2026-08-28): follow the
[Simulator-first gate](simulator-first-testing.md). This supersedes older
physical-test-next-step wording for day-to-day debugging. Do not return to or
interrupt the physical iPhone without a fresh explicit user request.
The [2026-08-28 Simulator checkpoint](evidence/2026-08-28-simulator-first-gate.md)
records longer soak/reconnect coverage, the keyboard Stop fix, lab teardown
repair, and the remaining shipping-lifecycle integration gap.
The [integrated Simulator checkpoint](evidence/2026-08-28-integrated-simulator-control.md)
now combines production route/lifecycle/role/workspace owners with live Control
over isolated transports and records the readiness-navigation repair. Its
explicit limits still exclude shipping TLS/bootstrap and physical-device proof.
The final integrated checkpoint passed 9 repeated checks, the full 13-test
Simulator suite, and 1,725 repository tests; the production iOS Release target
also built unsigned for Simulator. Navigation-readiness and retired-callback
repairs are in source; the installed Mac app and physical iPhone were untouched.

The [authenticated Simulator journey](evidence/2026-08-28-authenticated-simulator-journey.md)
adds production TLS/pairing/session authentication, disposable durable stores,
actual process restarts, and same-primary Stop-to-Observe verification. It
found and repaired host status timestamp and cached-CPU-sampling defects.
The final real-window checkpoint passed three consecutive authenticated
journeys, all 15 full-suite Simulator tests, and 1,736 repository tests.
Pairing regressions, Release builds, and disposable-host/credential cleanup
also passed. Consult that checkpoint for the exact evidence and remaining
release-bootstrap, physical-network, and hardware-custody gaps. Software test
keys and simulated consent never enter release targets; the physical iPhone
and installed Mac app/Agent were untouched.

The [Agent-renewal Simulator checkpoint](evidence/2026-08-28-agent-renewal-simulator.md)
adds the production lease scheduler to authenticated journeys and fault-tests
lost renewal receipts and lease expiry. It exposed and repaired active-stream
failure propagation that left a blank live view and keyboard after media
ended. The focused real-window test, all sixteen full-suite Simulator tests,
five pairing regressions, 1,740 repository tests, Agent Release compilation,
and unsigned iOS Simulator Release compilation passed. Temporary credentials,
the run lock, and disposable host processes were confirmed removed. Lease
issuance and final Agent/XPC admission remain isolated-test gaps, not certified
shipping behavior. The installed products and physical iPhone were untouched.

The [isolated Agent/XPC checkpoint](evidence/2026-08-28-isolated-agent-xpc.md)
adds 24 signed, multi-process startup/bootstrap/status checks, passed in three
consecutive runs with verified disposable job/process/state cleanup. Repository
validation passed 1,742 tests, and Release symbol inspection confirmed the new
Debug test seams are absent. This narrows the local-XPC gap without claiming
full Keychain-backed startup or Interactive/presentation XPC integration. The
installed products, Simulator, and physical iPhone were untouched.

## Status vocabulary

Active execution objective (2026-08-29): freeze a reproducible Stage 2
physical-alpha candidate from the current late-Stage-2 worktree. Reconcile the
roadmap, organize the implementation and evidence into coherent commits, pass
full validation, build/install the exact signed candidate, and execute the
safely automatable and explicitly authorized physical checks. The earlier
[pre-physical MVP readiness goal](pre-physical-execution-plan.md) is complete as
a historical preparation boundary. Its one-day campaign is superseded evidence
and cannot establish readiness for the current source. A fresh seven-day soak
starts only after the new candidate is stable and frozen. This does not relax
any release, device, or external-account authority gate.

Latest checkpoint: [signed Act cancellation and recovery](evidence/2026-08-28-act-concurrency-recovery.md)
extends the matrix to 55 cases. A real signed run reproduced a network reader
blocking status/cancel behind pending Act execution. Bounded execution response
handling fixes that, with overflow, late-response, revalidation and liveness
regressions. Authenticated raw-client denial, same-primary status/cancel,
at-most-once cancellation hook and post-effect crash recovery to outcomeUnknown
without retry now pass. The prior signed Act grants, Observe/Control separation
and revocation cases remain included. Full validation passes 1,769 tests across
42 runners. Three consecutive 55/55 signed runs, Release test-seam exclusion
and independent cleanup verification pass; exact evidence is in the checkpoint.
Hardware audio, custody, capture/input/indicator effects remain substituted.
The later [startup and signed menu-handshake stress checkpoint](evidence/2026-08-29-agent-startup-handshake-stress.md)
passes 200 consecutive launches, including 50 complete presentation handshakes,
under the unchanged deadline and verifies exact cleanup. This retires the older
launch/handshake timeouts as historical evidence rather than a current required-
path failure. Physical administration UI, broader installed lifecycle and
hardware/storage fault evidence remain on their explicit later gates.
The Stage 2 candidate goal is active, not complete.

The [Stage 2 candidate worktree audit](evidence/2026-08-29-stage-2-candidate-worktree-audit.md)
records the 315-path starting state, the product and signed-lab commit
boundaries, the repaired stale-soak and single-device-harness assumptions, and
the remaining candidate construction and physical gates.

The original 21-item implementation sequence is now status-reconciled in
[Implementation Orchestration section 7](implementation-orchestration.md#7-first-issue-sequence).
It distinguishes locally integrated work from physical, external, release, and
publication evidence. In particular, the Stage 2 core and its framing are
integrated, while entitlement response, full lifecycle/compatibility proof,
release packaging, frozen-candidate soak, and private-route evidence remain
open. The public GitHub repository has no corresponding issue or pull-request
records, so these planning numbers must not be described as closed GitHub
issues.

The first exact-candidate multi-device run exposed deterministic primary
ping-pong rather than a route failure: the historical singleton primary owner
allowed the iPhone and iPad to replace one another continuously. The
[multi-device primary-isolation checkpoint](evidence/2026-08-29-multi-device-primary-isolation.md)
replaces that construction assumption with up to eight retained exact primary
sessions, connection-scoped terminal cleanup and Interactive teardown, while
preserving one global active Control session. Full repository validation passes;
the failed candidate is superseded and a new exact signed candidate plus
physical two-device confirmation remain active work. Any older
`one-Mac/one-phone` or primary-replacement wording below is historical evidence,
not the current Stage 2 contract.

The superseding multi-device candidate removed primary replacement, then a
physical iPhone console isolated a separate reconnect trigger: a VideoToolbox
submission failure caused the client media pump to cancel the otherwise valid
session. The [decoder-pressure recovery checkpoint](evidence/2026-08-30-physical-decoder-pressure-recovery.md)
keeps only documented temporary decoder unavailability and explicit real-time
frame drops nonterminal, retains exact status for all terminal failures, and
passes the real-window Simulator journey plus complete repository validation.
An exact signed replacement on both devices and simultaneous physical
confirmation remain required; this checkpoint is not Stage 2 acceptance.

- `active`: work can proceed now.
- `ready`: prerequisites are satisfied and work is queued.
- `blocked-external`: an external approval, account value, machine, or user decision is required.
- `blocked-design`: a normative decision must be reconciled before implementation.
- `passed`: exit evidence is recorded.
- `no-go`: evidence rejects the capability for the supported product.
- `deferred`: the capability remains optional and has a recorded reason and re-entry condition.

## Resolved execution decisions

- Official bundle and code-signing identifiers use the Jenny Media-controlled `media.jenny` prefix: `media.jenny.maccompanion` for the Mac containing app, `media.jenny.maccompanion.agent` for the app-wrapped per-user Agent, `media.jenny.maccompanion.ios` for the iOS/iPadOS client, and role-suffixed identifiers under `media.jenny.maccompanion.xpc` if XPC services are retained. The Team ID is confirmed privately and the explicit Mac containing-app App ID `media.jenny.maccompanion` is registered. The [Agent Keychain provisioning repair](evidence/2026-08-23-agent-keychain-provisioning-repair.md) proves the Agent's exact signed application identifier and private Keychain group under an embedded wildcard team development profile; an explicit Agent App ID plus matching Developer ID profile remains required for external distribution. The iOS and any retained XPC App IDs are not yet registered.
- The release floor remains macOS 26.0 and iOS/iPadOS 26.0 with stable Xcode 26.6 and Swift 6.3. Installed Xcode 27 beta is permitted for development, compatibility, signing setup, device work, and currently supported TestFlight uploads, but stable Xcode 26.6 remains required for final signed release evidence.
- Development signing may use identities installed on this development Mac. Developer ID, App Store distribution, notarization, Sparkle, and promotion credentials remain in a separately controlled release environment. The [permanent containing-app build](evidence/2026-08-21-permanent-mac-containing-app-target.md), [current signing revalidation](evidence/2026-08-22-signing-identity-revalidation.md), and [Agent provisioning repair](evidence/2026-08-23-agent-keychain-provisioning-repair.md) prove the exact distinct code-signing identifiers and a profile-authorized development Agent. The earlier zero-identity result was a restricted-sandbox Keychain-visibility artifact; no replacement certificate was required. The later first-enable failure was a distinct missing-Agent-profile defect. Final explicit Agent Developer ID provisioning, controlled custody, and promotion remain release-environment gates.
- Execution prefers the shortest signed, physical, runnable product slice over more construction-only infrastructure whenever that slice is unblocked: permanent targets, LAN pairing and reconnection, Observe, `setAudioMuted`, then Desktop video plus mouse and keyboard. App Focus, Window Focus, Smart Zoom, and interaction adaptation remain Stage 2 exit requirements but do not delay the first Desktop Control build.
- First pairing is foreground and same-LAN. A paired device may later reconnect only over ordinary private LAN routes or explicitly saved user-managed private endpoints such as Tailscale MagicDNS, private DNS, IPv4, or IPv6. Route classification never grants authority and Mac Companion does not infer Tailscale from interfaces, DNS, or installed processes.
- Through Stage 3, “full control” means the separately granted live pixel stream, mouse and keyboard input, plus independently granted bounded capabilities. Shell, arbitrary SSH commands, general files, clipboard, audio, automation, provider execution, and future capabilities remain outside the MVP and never inherit Control authorization.
- The local repository now carries the byte-exact Apache-2.0 license plus mutually linked draft Mac Companion/Jenny Media trademark, security, contribution, and conduct policies. They remain subject to written legal review and unpublished on the already-public remote. GitHub private vulnerability reporting is the intended initial security channel but is not operational until enabled and verified. No further push or contribution intake occurs until policy approval/publication, full-history review, and provider-side repository protections are resolved.
- The completion boundary is a signed, installable external Stage 3 beta with market-MVP evidence. Stages 4–7 may close with evidence-backed `passed`, `no-go`, or `deferred` decisions; they are not required to ship speculative breadth.
- The [2026-08-23 competitive task matrix](research/2026-08-23-competitive-task-matrix.md) completes the official-source teardown required by the product-evidence workstream. It classifies direct LAN/private routes, QR/local approval, hardware video, touch/keyboard, reconnect, and app/window focus as category parity; preserves independently useful Observe/Act/Control, revision-safe adaptive interaction, and truthful authorization/recovery as hypotheses for cohort proof; records official-source conflicts and unknown measured time to first controllable frame; and defers Stages 4–7 behind narrow evidence-based re-entry gates rather than competitor feature breadth.
- [ADR-0002](adr/0002-stage-3-product-evidence.md) fixes the beachhead, current workarounds, qualifying Observe/Act/Control jobs, smallest Stage 3 slice, separate 10–20-person calibration and at-least-15-person confirmatory cohorts, exact denominators/thresholds, safety overrides, and a no-telemetry user-exported evidence boundary before cohort results exist. The bundle-independent study kernel, local report owner, explicit product capture, authenticated route binding, and tester-reviewed finalization are complete. The [participant disclosure and retention schedule](stage-3-participant-disclosure-and-retention.md) now provides a concrete data inventory, TestFlight separation, withdrawal process, deletion schedule, and approval checklist, but remains a draft with required contact/region placeholders. Calibration and confirmatory enrollment stay disabled until legal/privacy approval, signed physical verification, and the actual cohort gates.
- The [permanent Agent host-recovery service](evidence/2026-08-23-permanent-agent-host-recovery-service.md) supersedes the earlier authentication-only recovery selection: production preparation now selects one recovery-only readiness, source-unavailable status, review/resume/withdrawal, and exact-command product. The [completion acknowledgement](evidence/2026-08-23-host-recovery-completion-acknowledgement.md) adds exact receipt echo, atomic replay-journal retirement, completed-recovery startup replay, and one-shot restart convergence. Pairing, bootstrap, update, Interactive, listener, and provider authorities remain construction-rejected in that profile. Signed two-process recovery and real Keychain replacement remain open.

## Current lanes

| Lane | Stage | Status | Current evidence | Blocker or next proof | Independent work that continues |
| --- | --- | --- | --- | --- | --- |
| Design baseline | 0A | passed | Reconciled product documents, ledger, ADR, threat model, permission matrix, three-agent audit, baseline commit `432354c`, and local implementation checkpoint `c92ce7b` | Keep implementation evidence synchronized with the resolved execution decisions | All implementation lanes use this authority |
| Protocol trust kernel | 0B | passed | Normative v0.1 mini-RFC; 64 indexed protocol, Interactive Control, local-IPC, model, binary, and crypto fixtures; pure `CompanionDomain`, `CompanionWire`, and `CompanionSecurity`; restricted RFC 8785 Unicode/safe-integer canonicalization, closed capability schemas/registry, exact operation-approval signatures, strict bounded canonical host-certificate inspection, closed operation and paged capability-discovery messages, programmatic frame-size enforcement, and a closed safe error body; fixture-backed domain/wire/security tests; public unsigned CI workflow | Remote CI result is pending the next published branch; floating-point schemas remain denied unless a later profile passes complete ECMAScript number vectors | IPC interfaces, status sampling, and disposable platform probes |
| Public repository readiness | 0A | active | The [public CI supply-chain boundary](evidence/2026-08-20-public-ci-supply-chain-hardening.md) grants read-only contents access, pins checkout v6.1.0 to its full verified commit, disables persisted credentials, and rejects movable remote-action tags and container tags before compilation; the [repository material boundary](evidence/2026-08-20-repository-material-boundary.md) scans every publishable file and reachable historical blob/path and rejects high-confidence credential, signing, private-database, symlink-escape, and oversize forms through 14 fixtures. The [dependency policy](evidence/2026-08-20-swift-dependency-policy.md) keeps all four Swift manifests and three repository edges local while its [v1 exact Sparkle admission](evidence/2026-08-23-exact-sparkle-dependency-admission.md) permits only Sparkle 2.9.6 in the Mac containing app, bound to its full revision, upstream digests, shared lockfile, privacy settings, consumer, and archive sanitizer. Twelve manifest and twelve Xcode dependency fixtures reject every other remote package, binary target, executable plugin, consumer, or topology. A [2026-08-23 live audit](evidence/2026-08-23-public-repository-live-audit.md) confirms the remote is public, detects no license, has no `main` protection or ruleset, and has secret scanning/push protection/validity/non-provider scanning plus Dependabot security updates disabled while the audited local branch was 74 commits ahead and unpushed | Complete legal review; publish mutually consistent license, trademark, contribution, and security policies; enable and verify private reporting and provider protections; re-scan the exact local range; then obtain exact-head confirmation before any push. Any further production dependency needs its own necessity, provenance, license, privacy, signing, and replacement review | Unsigned fixtures, packages, experiments, documentation, and CI policy continue locally without pushing |
| Distribution evidence | 0A/3 | active | The [release evidence v0.2 profile, validator, and unsigned generator](evidence/2026-08-20-release-evidence-manifest-construction.md) separate unsigned construction, signed candidate, and promotion-ready claims; 18 indexed fixtures prove closed schemas, compatibility/target binding, artifact/executable/notary/SBOM requirements, physical-scenario and human-approval gates, secret exclusion, placeholder rejection, nonzero invalid CLI behavior, and closed Mac update-profile authority; every evidence reference is size/hash bound, file verification rejects mutation and symlink/path escape, and generated manifests use atomic no-clobber publication while retaining exact source/toolchain facts without credentials; the [deterministic SPDX 2.3 source dependency SBOM](evidence/2026-08-20-source-dependency-sbom.md) is live-policy-bound and proven by 10 fixtures plus byte-identical generation; the [Sparkle nested Developer ID packaging checkpoint](evidence/2026-08-23-sparkle-nested-developer-id-packaging.md) adds an 11-case no-overwrite packager, corrects an outer-`codesign`-masked ad-hoc helper defect, verifies five universal Developer ID subjects, signs the APFS/UDZO DMG, and proves exact three-container equivalence on Xcode 27 beta while retaining explicit false notarization, stapling, Sparkle-signature, and promotion claims; the [signed-candidate update-profile binding](evidence/2026-08-23-signed-candidate-update-profile-binding.md) cross-checks the v0.2 manifest against the exact canonical app archive | Real signed candidates require stable Xcode/signing custody, two accepted notarization phases, post-staple correlation, artifact-complete SBOM and reviewed licenses, physical matrices, Sparkle/App Store records, and human approval | Local release construction can continue without uploading or publishing; notarization remains separately authorization-gated |
| Exact-candidate artifact SBOM | 0A/3 | active | The [v0.1 profile and construction](evidence/2026-08-21-exact-candidate-artifact-sbom.md) stream and inventory executable-bearing ZIPs, emit reciprocal `filesAnalyzed: true` SPDX with SHA-1/SHA-256 and package verification codes, enforce byte-canonical evidence, publish a mode-0600 no-overwrite directory, and bind archive/release/source/target/executable facts; 26 adversarial fixtures and 18 end-to-end release/graph integrations cover deterministic generation, unsafe/polyglot archives, valid and corrupt data descriptors, standard and cyclic symlinks, source-SBOM substitution, metadata substitution, executable path/mode, Sparkle divergence, post-generation mutation, graph omission/symlink/nested-code omission, duplicate executable subjects, and iOS/combined target binding | Real signed archives, an independently pinned SPDX validator, stable release toolchain evidence, reviewed licenses, and platform-verified complete signed-code graph remain required before a signed-candidate claim | The generator and verifier are bundle-independent and ready for release-job integration |
| Signed-code construction discovery, correlation, and policy | 0A/3 | active | The per-executable [construction correlation](evidence/2026-08-21-signed-code-construction-correlation.md), complete [discovery graph](evidence/2026-08-21-signed-code-construction-discovery.md), independently pinned [signing policy](evidence/2026-08-21-signing-policy-construction.md), [fixed-tool runner](evidence/2026-08-22-platform-signing-fixed-tool-runner.md), exact [subject reconstruction](evidence/2026-08-22-platform-signing-subject-reconstruction.md), and [whole-subject verification executor](evidence/2026-08-22-platform-codesign-verification-execution.md) bind exact artifacts, Mach-O objects, architecture slices, tools, raw streams, and policy. The [per-architecture construction](evidence/2026-08-22-per-architecture-signature-inspection-construction.md) independently parses embedded CodeDirectory, designated requirement, CMS, runtime, and duplicate-safe XML entitlements. The [protected architecture executor](evidence/2026-08-22-per-architecture-signature-inspection-execution.md) now requires freshly revalidated whole-subject success, rehashes the complete candidate around each fixed call, retains only a bounded contiguous private certificate chain, and composes embedded, Apple-display, certificate, entitlement, and policy facts. The [semantic DER-entitlement equality checkpoint](evidence/2026-08-22-der-entitlement-semantic-equality.md) independently decodes the measured CoreEntitlements v1 grammar, requires exact XML/DER tagged-policy equality, and retains both blob digests while rejecting DER-only signatures. The [outer codesign checkpoint](evidence/2026-08-22-outer-codesign-verification-construction.md) adds one exact immutable Mac-only `--deep` consistency plan and executor with a closed Apple-tool-measured grammar. The [outer prerequisite correlation](evidence/2026-08-22-outer-codesign-prerequisite-correlation.md) now requires every exact whole-object and architecture record to pass fresh subject, raw-output, certificate, embedded-signature, display, entitlement, and policy reinspection before the outer invocation and repeats the same complete reinspection afterward. The [canonical construction record](evidence/2026-08-22-canonical-platform-signing-construction-record.md) recomposes those facts against exact canonical release/SBOM/graph/policy references, the fixed environment and tool, reconstructed subjects, and target-specific unresolved gates under the 8 MiB profile. The [Mac app Gatekeeper/stapler checkpoint](evidence/2026-08-22-mac-gatekeeper-stapler-construction.md) adds exact `spctl` and directly pinned Xcode `stapler validate` plans only after the correlated signing result, rehashes around both, and repeats the prerequisite afterward. The [two-phase notarization checkpoint](evidence/2026-08-22-two-phase-notarization-correlation-construction.md) replaces the invalid one-submission release assumption with distinct transient-app-ZIP and final-content-DMG acceptances, exact upload hash/name/UUID/raw-log correlation, zero issues, nonempty tickets, and temporal ordering. Its adversarial corpus additionally rejects upload substitution, warnings, unknown/duplicate keys, a single release submission, UUID reuse, reversed phases, removed gates, and attempted acceptance promotion | Add protected `notarytool` execution and both post-staple byte-transition correlations, then final app/DMG assessment; run the real final candidates; add the exported IPA artifact and prove stable-Xcode/final-identity/notarization/physical/promotion evidence | All accepted notary results are synthetic construction inputs; no Mac Companion upload or staple occurred, every canonical record remains `platformAcceptanceEligible: false`, and valid construction still emits `signedCodePlatformVerificationRequired` |

Latest signing-distribution checkpoint, superseding the protected-execution portion of the row above: the [protected notarytool executor](evidence/2026-08-22-protected-notarytool-execution-construction.md) now pins each exact upload into a private immutable copy, uses fixed shell-free non-waiting submit and later info/log calls, rehashes before/after execution and after raw-evidence reopening, and removes the credential profile plus absolute private path from retained records. Injected adversarial tests prove warning, mutation, symlink, profile, submission, and upload-substitution rejection without contacting Apple. Real authorized execution and successful-JSON measurement, both staple transitions, final app/DMG assessment, packaging correlation, and release gates remain open.
| Mac packaging equivalence | 0A/3 | active | The [v0.1 profile, generator, verifier, recovery command, and construction evidence](evidence/2026-08-21-mac-packaging-equivalence.md) bind the exact application ZIP, Sparkle archive, and sole release DMG to one parent-closed canonical app tree; disk tools consume only a private mode-0400 copy made from the already-hashed descriptor; 24 receipt fixtures, 8 attach-free tree/xattr cases, 5 release-integration cases, 3 partial-attach/recovery cases, 6 fail-closed recovery-refusal cases, 2 interrupted recovery-record update cases, and one concurrent pathname-substitution case prove closed canonical evidence and recovery; 2 explicit temporary APFS/UDZO reinspection cases passed on macOS 27/Xcode 27 beta. The current [Sparkle nested Developer ID packaging checkpoint](evidence/2026-08-23-sparkle-nested-developer-id-packaging.md) adds exact five-subject signature checks, exclusive publication, and a real signed-DMG inspection proving one 117-entry Sparkle-containing app tree across both ZIPs and the DMG | Repeat on stable macOS 26/Xcode 26.6 and the final post-staple candidate; add final Gatekeeper acceptance and post-notary byte correlation | Attach-free validation remains in public CI; final platform reinspection is restricted to the trusted, exclusive release lane |
| Apple privacy manifests | 0A/3 | active | The [closed privacy-manifest profile](evidence/2026-08-20-apple-privacy-manifest-boundary.md) owns strict candidate resources for the iOS app, Mac containing app, and Mac Agent; 12 fixtures reject tracking, collection, domains, schema/key/category/reason failures; live validation inventories 14 covered macOS source records and proves that an iOS-reachable call is either absent or whole-file macOS-guarded using the current SwiftPM graph; the [containing-app build](evidence/2026-08-21-permanent-mac-containing-app-target.md), [embedded Agent target](evidence/2026-08-21-permanent-embedded-mac-agent-target.md), and [permanent iOS target](evidence/2026-08-22-permanent-ios-application-target.md) bind all three indexed resources into their release-shaped target topology | Final-candidate bundle inspection remains; re-review Apple's catalog and actual App Privacy answers before submission; any SDK, telemetry, data-flow, covered-API, or topology change reopens the policy | All permanent target resources are bound; final-candidate work continues |
| Apple identifiers and permanent targets | 0A | active | Jenny Media LLC Team ID is confirmed privately; `media.jenny` is the confirmed company-controlled reverse-DNS prefix; the explicit Mac containing-app App ID `media.jenny.maccompanion` is registered; its [checked-in permanent menu-app target](evidence/2026-08-21-permanent-mac-containing-app-target.md) embeds an [app-wrapped, profile-capable Agent](evidence/2026-08-23-agent-keychain-provisioning-repair.md) with exact application-identifier and private Keychain-group claims; an Apple Development build embeds an eligible team profile and strict-verifies the complete nested app; the [permanent iOS target](evidence/2026-08-22-permanent-ios-application-target.md) fixes `media.jenny.maccompanion.ios`, iOS/iPadOS 26.0, exact declarations, protected restart storage, and an unsigned dual-architecture Simulator build without tracked team, credential, profile, or entitlement authority | Complete a fresh visible Agent-enable/readiness attempt; register explicit Agent and iOS/iPadOS App IDs and create matching distribution profiles before external release | Signed Mac/Agent acceptance and unsigned iOS composition can proceed independently |
| Persistent capture request | 0A | blocked-external | Account Holder eligibility, final Mac App ID, form answers, explanation, and Apple authorization acknowledgement are verified and prepared. A submission attempt on 2026-08-21 was not accepted because Apple requires an App Store URL and numeric App Apple ID even for this directly distributed, unreleased Mac product. An Apple Developer Support Entitlements case was opened the same day; its Case ID is retained privately | Wait for Apple's direct-distribution/prerelease guidance, then use only the confirmed truthful App Store URL/Apple ID path, complete the preserved request, and retain its private confirmation/status | Observe, protocol, lifecycle, ordinary-consent capture experiments, and non-persistent Control work continue |
| Stable release toolchain and distribution custody | 0A | blocked-external | The [signing revalidation](evidence/2026-08-22-signing-identity-revalidation.md), signed physical launch baseline, [exact signed source checkpoint](evidence/2026-08-23-exact-head-signed-construction.md), and [Agent provisioning repair](evidence/2026-08-23-agent-keychain-provisioning-repair.md) prove the installed Apple Development identity, exact app/Agent identifiers, shared team, strict signatures, hardened runtime, and an eligible Agent development profile on Xcode 27 beta. Only Xcode 27 beta (`27A5218g`) is installed; stable Xcode 26.6, an explicit Agent Developer ID profile, and controlled final distribution custody remain absent from this workspace | Install stable macOS 26/Xcode 26.6; create and inspect the explicit Agent Developer ID profile in the controlled release environment; then repeat exact signed platform, physical, Developer ID, notarization, and packaging evidence | Signed development and physical work can proceed on Xcode 27 beta; final acceptance and promotion remain blocked on stable Xcode plus controlled distribution custody |
| Process and local IPC | 0A | active | ADR-0001, a [signed peer-identity probe](evidence/2026-08-21-signed-local-xpc-peer-identity-probe.md) proving reciprocal same-team exact identifiers plus closed hello shape and version rejection on Xcode 27 beta, a [production local-XPC handshake](evidence/2026-08-21-production-local-xpc-handshake-construction.md) binding the permanent Mach service and targets to exact reciprocal requirements and a closed non-authorizing hello, plus a [menu-readiness binding](evidence/2026-08-21-local-xpc-menu-readiness-binding.md) adding one exact acknowledged post-authentication message, ordered lifecycle publication, authenticated replacement fencing and cancellation, and exact fail-closed transport escalation, plus a [content-free status binding](evidence/2026-08-21-local-xpc-status-binding.md) adding closed method authorization, typed canonical bounded snapshots, single-flight timeouts, and generation-fenced replies while, at that checkpoint, the permanent Agent remained authentication-only; a [sealed local-XPC Agent and dashboard product composition](evidence/2026-08-21-local-xpc-product-composition.md) now derives lifecycle and typed status from the same complete Agent services, drives ordered menu authentication-readiness-status consumption, preserves recoverable source-unavailable retry, and retires stale dashboard generations; the [Agent release storage root](evidence/2026-08-21-agent-release-storage-root.md) uses a fixed release factory for one canonical private Application Support root with handle-bound databases and a cross-process-locked emergency deny latch, preserves active-latch recovery state, and returns the required-audit composition without treating diagnostic paths as a same-UID sandbox; the [prepared Agent product bootstrap](evidence/2026-08-21-prepared-agent-product-bootstrap.md) adds one-use listener-free identity/TLS/primary preparation and a separate inert top-layer storage/primary/XPC owner without accepting a pre-authenticated review surface; the [authenticated menu presentation-surface router](evidence/2026-08-21-authenticated-menu-presentation-surface-router.md) adds strict generation high-water and private issuance-token fences, shared activation and retirement barriers, post-acknowledgement stale compensation, and an endpoint-only non-waiting terminal-fence capability without adding XPC presentation messages or runtime activation; the [authenticated menu presentation contract](evidence/2026-08-21-authenticated-menu-presentation-contract.md) freezes five explicit publish/withdraw authorizations, exact reply sets, a separate 4,096-byte canonical payload bound, nonzero withdrawal IDs, and fresh-review versus durable-resume semantics; the [exact envelope layer](evidence/2026-08-21-exact-menu-presentation-envelopes.md) adds five operation-specific C parsers/senders, closed acknowledgements and publish-only rejection classification, exact UUID sizing, and synchronous Swift borrowed-byte copies without a generation endpoint or menu receiver; the [authenticated current-ready sender](evidence/2026-08-21-authenticated-menu-presentation-sender.md) adds exact-ready cached opaque issuance, the shared one-active-plus-seven-queued production FIFO, three-second reply fencing, weak-sender terminal latching, and a peer-wide status-and-presentation fence before one session cancel while permanent targets remain inert; a normative shared-payload profile, closed caller/endpoint/method matrix, bounded content-free status/events/export models, 2 indexed diagnostic fixtures, and 57 IPC tests; pairing creation and dismissal are menu-only, strict, Agent-fact-owned, exact-replay, tombstone-before-success, and QR-construction-compensated; complete SAS, transcript, key-fingerprint, policy, and local-name pairing decisions are strict, retry-fenced, and atomically persisted; the [already-authorized local pairing-review delivery](evidence/2026-08-20-local-pairing-review-delivery.md) adds exact pending-authority equality, surface acknowledgement, terminal withdrawal, endpoint-loss cancellation, exact post-commit replay, a revision-fenced Mac owner/reducer, and a compile-checked SAS/name sheet without treating the bundle seam as peer authentication; device-name administration is decode-validated and exactly correlated; grant decisions bind the Agent review, locally shown device name, exact current/proposed sets and revision fences; `CompanionAgent` adds 190 tests for fail-closed provider loading and startup reconciliation, one-Mac/one-phone primary replacement, pairing delivery/withdrawal and unavailable-review closure, registry-generation/full-descriptor/effect-bound one-time reviews, shared publication replacement, visible-review invalidation, replacement-versus-commit exclusion, bounded replay receipts, atomic SQLite compare/approve/queued-work fence/audit commit with injected rollback, unchanged declines, ordered remote-then-runtime stop, exact pending/active dispatcher invalidation, a [store-bound required-audit Interactive product root](evidence/2026-08-20-interactive-product-composition.md), [signature-bound initial runtime preparation](evidence/2026-08-20-initial-runtime-preparation.md), a [root-bound Observe status authority](evidence/2026-08-20-root-bound-host-status.md), a [durable host-identity release root](evidence/2026-08-20-durable-host-identity-root.md), [recoverable host-identity startup](evidence/2026-08-20-host-identity-startup-coordinator.md), [confirmed host-identity recovery](evidence/2026-08-20-host-identity-confirmed-recovery.md), [local recovery confirmation composition](evidence/2026-08-21-local-host-identity-recovery-composition.md), [unified Agent network startup](evidence/2026-08-20-agent-network-product-startup.md), four-effect menu teardown receipts, lifecycle and registry-publication audit isolation, and Agent-issued initial and replacement surface coordination through exact runtime preparation and clean-media acknowledgement, plus primary-channel sequencing, opaque target resolution, and generation-bound listener-handoff race fencing; a [coherent content-free local-status authority](evidence/2026-08-20-local-status-authority-construction.md) with source-owned updates, unique read sequences, count-only SQLite/provider adapters, exact listener projection, and fail-closed deny-latch/storage posture, plus a [source-scoped route authority](evidence/2026-08-20-local-route-monitor-authority.md) that preserves independent listener/Bonjour LAN evidence while expiring only authenticated configured-route contributions, and an [already-authorized local-status read capability](evidence/2026-08-20-local-status-read-service.md) with one clock sample, closed failure, and unique concurrent sequences, all issued by a [single fail-closed local-service root](evidence/2026-08-20-agent-local-service-root.md) with package-owned raw authority and source-specific facets; the [Agent sanitized diagnostic export](evidence/2026-08-21-agent-diagnostic-export-service.md) adds a boot-scoped newest-256 event ring, write-only producer facet, validated root-issued export capability, closed source failure, and explicit menu-app plus CLI authorization without becoming durable audit history; the [Mac Agent administration dashboard](evidence/2026-08-21-mac-agent-dashboard-construction.md) adds a revalidating content-free first-party shell, typed administration intents, and connection-generation/sequence/time fences that prevent stale local replies from restoring availability; the [Mac dashboard action coordinator](evidence/2026-08-21-mac-dashboard-action-coordinator.md) centralizes admission and serialized execution for all seven actions, preserves completed/not-completed/outcome-unknown results, revalidates exports, and fences late effects across authority replacement; the [sealed lifecycle observation source composition](evidence/2026-08-21-lifecycle-observation-source-composition.md) binds Agent self-ready to the complete service graph and issues serialized menu-generation readiness/invalidation capabilities only after platform authentication, without caller roles or PID/status inference; Interactive install/renew/revoke/surface-transition messages carry decode-validated 10-second leases and correlated readiness/safety receipts; the [permanent menu dashboard lifecycle bridge](evidence/2026-08-22-permanent-menu-dashboard-lifecycle.md) replaces synthetic menu status with a retained real product owner while keeping transport start disconnected; the [permanent Agent single-service selector](evidence/2026-08-22-permanent-agent-single-service-selection.md) revalidates canonical durable state and starts exactly one hidden profile: readiness/status for enabled, disabled bootstrap for canonical disabled state, the distinct recovery-only profile for durable recovery, and none before first unlock, with no cross-profile fallback; the [permanent menu application launch](evidence/2026-08-22-permanent-menu-application-launch.md) binds exactly-once dashboard start to AppKit launch behind a package-owned delegate while keeping raw transport authority outside SwiftUI; [signing revalidation](evidence/2026-08-22-signing-identity-revalidation.md) proves a strict-valid same-team Apple Development app and embedded Agent; the [disabled-Agent bootstrap protocol](evidence/2026-08-22-disabled-agent-bootstrap-protocol.md) freezes a five-minute revision-bound consent command that grants no capability and cannot claim readiness; the [production Agent bootstrap binding](evidence/2026-08-22-agent-bootstrap-production-binding.md) injects the preparation-owned durable authority only for disabled startup, fences five-second exact XPC operations, and latches launchd restart after acknowledged or unacknowledgeable durable enablement; the [permanent Agent host-recovery service](evidence/2026-08-23-permanent-agent-host-recovery-service.md) now binds fresh and durable-resume recovery preparation to one recovery-only readiness, unavailable-status, presentation, and exact-command product without pairing, bootstrap, update, Interactive, listener, or provider authority; the [completion acknowledgement](evidence/2026-08-23-host-recovery-completion-acknowledgement.md) binds the exact validated receipt to atomic replay-journal retirement, completed-recovery startup replay, and a one-shot post-reply-or-failure restart latch; the [foreground remote-access setup](evidence/2026-08-22-foreground-remote-access-setup.md) adds exact Agent-only registration acquisition, the same-team menu bootstrap client, fixed explicit consent, owned-registration rollback, ambiguity retention, receipt-gated menu convergence, and registration-routed fresh dashboard construction in the permanent app | Run reciprocal signed clean-state disabled-to-ready acceptance before presentation or network ingress | Signed construction, the complete foreground/menu transaction, durable Agent transition, restart request, and dashboard routing are complete; signed launchd execution plus fresh readiness/status proof remain |
| Agent lifecycle | 0A/1 | active | Pure lifecycle reducer distinguishes explicit enable/disable, lock, logout/login, agent crash, and menu crash; Observe survives only eligible menu failure while Control requires both processes; a [bundle-independent lifecycle audit producer](evidence/2026-08-20-lifecycle-audit-producer-construction.md) validates completed reducer transitions and emits only coarse stable global enabled-intent/Observe-availability events after state/effects exist; the [login-role effect executor, convergence wrapper, and label-free `SMAppService` seam](evidence/2026-08-20-login-role-effect-executor-construction.md) register Agent then menu before enablement commit, roll partial enablement back in reverse, accept disable cleanup only after remote-safety completion, attempt both unregistrations after failure, require exact postconditions, converge idempotent and effect-then-error states, preserve closed approval/missing-service recovery reasons, fail closed on future statuses, project all current framework statuses, and await unregistration completion; the [dashboard lifecycle product composition](evidence/2026-08-21-dashboard-lifecycle-product-composition.md) adds exact prepare/compare-and-commit enablement, stale-state compensation, remote-safe disable ordering, truthful process-start failure, and same-desired-state convergence; the [durable lifecycle intent and restart reconciler](evidence/2026-08-21-durable-lifecycle-intent-reconciliation.md) adds strict canonical revision-fenced atomic desired-state storage, durable-intent-first mutation, safe-disabled absence, fresh non-ready startup state, exact read-back convergence, and enabled/disabled/login-state restart repair; the [generation-fenced process observation owner](evidence/2026-08-21-process-observation-and-lifecycle-aba-fencing.md) adds boot lifecycle revision, per-role epochs, ABA-safe prepared commits, exact-generation readiness/termination, replacement teardown, stale-callback rejection, and closed exact recovery outcomes; the [sealed lifecycle observation source composition](evidence/2026-08-21-lifecycle-observation-source-composition.md) binds Agent ready to the complete required-audit service graph and menu ready/loss to one post-authentication exact-generation connection capability with serialized terminal replay; the [bounded process recovery scheduler](evidence/2026-08-21-bounded-process-recovery-scheduling.md) adds three fixed idempotent menu-start retries fenced by exact lifecycle revision, role epoch, eligibility, and replacement observation; the [permanent SMAppService identity composition](evidence/2026-08-21-permanent-smappservice-identity-composition.md) retains the exact Agent plist and main-app services through the raw/converging/executor chain, while signed negative launch proof shows construction neither registers nor starts the Agent; the [Agent release storage root](evidence/2026-08-21-agent-release-storage-root.md) adds one canonical mode-0700 Application Support hierarchy, bounded mode-0600 security and audit databases, the emergency deny latch, post-construction handle/path binding, and ten reopen/path/concurrency tests; 79 focused reducer/producer/executor/convergence/platform tests prove recovery, non-recovery, privacy, storage-failure isolation, compensation, phase rejection, reentrancy rejection, status convergence, future-status rejection, exact status mapping, atomic persistence, crash-boundary convergence, restart repair, readiness separation, ABA fencing, and process-generation recovery; the [foreground setup composition](evidence/2026-08-22-foreground-remote-access-setup.md) adds same-actor registration acquisition ownership, pre-send compensation limited to the role introduced by setup, safe preexisting-role retention under ambiguity, exact disabled-offer decline cleanup, receipt-gated menu registration, and launch routing that never derives readiness from `SMAppService` | Prove approval/login/lock/crash/disable/logout/update/uninstall on clean users, beginning with the signed disabled-to-ready transaction | Bundle-independent lifecycle, registration ownership, storage, observation, and permanent setup composition are complete; signed platform and physical evidence follow |
| Remote transport | 0B/1 | active | Strict framing/replay/in-flight/reconnect rules, including closed Interactive request/response sets; golden exact P-256 SPKI/TBS DER, verified self-signed X.509 assembly, strict canonical certificate parsing/self-signature/current-validity verification, and 90-day same-key lifecycle; a [compile-tested host custody constructor](evidence/2026-08-20-host-identity-custody-construction.md) uses an exact bounded tag, prompt-free `AfterFirstUnlockThisDeviceOnly` private-key usage, Secure Enclave preference, exact same-key issuance, strict reinspection, and in-memory `SecIdentity` composition without exposing private bytes; a [recoverable host-identity startup coordinator](evidence/2026-08-20-host-identity-startup-coordinator.md) durably fixes the candidate UUID and exact tag before pending key creation, resumes the same key after failure, loads valid listener identity without rotation, and same-key replaces invalid certificates under a stale-write fence; [confirmed destructive recovery](evidence/2026-08-20-host-identity-confirmed-recovery.md) fences every old authority before new-key preparation, deletes the retired key while its tag remains durable, and atomically rotates identity; a [unified Agent network startup](evidence/2026-08-20-agent-network-product-startup.md) binds that result through exact-store primary bootstrap and final certificate comparison before listener consumption; a sealed one-shot host listener constructor binds that exact identity, fingerprint, current leaf, TLS 1.3-only bounds, disabled resumption/early data, and no local endpoint reuse without exposing mutable parameters or starting the listener; its listener owner wraps each exact accepted connection, evaluates negotiated TLS metadata only after readiness, and exposes only a one-use verified pump handoff; fail-closed TLS 1.3/no-early-data client pin/role admission; distinct host-listener TLS 1.3/no-early-data/served-identity binding; explicit pre-unlock/key-loss recovery decisions; a [no-network rejecting Network.framework construction probe](evidence/2026-08-20-network-tls-construction.md); a pure immutable-pin dial-round executor that selects only an authenticated exact-endpoint winner, cancels denial/late work, closes every late or mismatched authenticated route, and retains command-send authority on the winner; one reconnect owner that binds foreground/reachability/candidate changes, exact-round cancellation, connected-route cleanup, terminal denial, and bounded backoff; a one-shot client TLS attempt context binding one route/pin/callback/exact connection reference through a strict single-leaf `SecTrust` evaluator; a concrete compile-checked client route attempter owning readiness timeout, exact handoff, fresh session, denial mapping, command send, and cancellation; injected synchronization tests prove recoverable waiting, ready/failure, timeout/cancel, first-result-wins, and late-success rejection; and separate [host and client primary frame pumps](evidence/2026-08-20-network-primary-frame-pump.md) with serialized I/O and byte-independent deadlines, plus a sealed Agent listener service with a generation-bound lifecycle-owned exact pump handoff and a [content-free root-status binding](evidence/2026-08-20-agent-listener-status-binding.md); ingress follows Observe availability; injected frame-I/O boundaries prove host opaque-challenge framing, client hello framing, first-send failure, malformed input, receive failure, remote denial, and exactly-once teardown without opening a route; 36 transport, 13 host-identity/certificate, 15 host-custody/startup/recovery construction, 13 host Network-platform, and 33 client Network-platform construction/evaluator/fault tests | Execute and inspect host Keychain/Secure Enclave custody under the final signed Agent, physically execute accepted-connection metadata extraction and handoff, then prove multi-route/proxy behavior | Socket-independent diagnostics and no-network platform composition |
| Observation freshness | 1 | active | Receipt subtracts host-reported age plus full request RTT, then expires on a client monotonic deadline; disconnection always yields `unreachable`; platform-neutral presentation keeps retry/background/manual/action cause separate from retained data state; Interactive presentation additionally prevents disconnected retained sessions from claiming control, lock, or a live surface while preserving local Mac identity and coarse route class; 14 tests cover exact expiry, impossible clocks, every connection cause, control/view, lock, and terminal-recovery mapping | Bind to native iOS UI and measure snapshot RTT/reconnect p95 on physical devices | Localized copy, layout, and diagnostics can proceed without a socket |
| Security persistence | 0A/1 | active | Normative v0 storage and exact operation-binding profiles; schema-v7 migration with a durable pre-Keychain bootstrap candidate, atomic reviewed-recovery intent, and last-recovery receipt; atomic canonical grant replacement/reviewed resume with epoch and grant fencing; local-only confirmed device names with atomic content-free events and admission joins; atomic host bootstrap completion/certificate replacement/recovery fencing/replacement; idempotent digest-bound operation admission; no-eviction per-device quota and 30-day terminal retention; exact execution-claim revalidation; suspend/revoke queued-work fencing; crash-to-`outcomeUnknown` recovery; atomic queued/in-flight startup reconciliation with fault rollback; preallocated dual-slot deny latch with retained-inode binding and cross-process transaction locks; a separately quota-bounded 16 MiB detailed audit store with scoped gaps, exact current-grant self filtering, authenticated host/client pagination, and privacy-preserving bounded iOS/Mac history projection; one Agent mutation boundary now serializes registry/provider publication with local grant review/commit, invalidates reviews before post-commit audit, and preserves the committed result under audit failure/drop; the [real security-store](evidence/2026-08-21-security-store-sqlite-full-wal.md) and [detailed-audit-store](evidence/2026-08-21-audit-store-sqlite-full-wal.md) pager-full/WAL recovery proofs require atomic rollback under `SQLITE_FULL`, continued readability, truthful durable-gap state, truncating checkpoints, exact integrity, capacity recovery, and successful resumption; [shared SQLite storage-path hardening](evidence/2026-08-21-sqlite-storage-path-hardening.md) binds canonical owner-controlled parents, exact 0600 single-link regular database/sidecar artifacts, secure creation, and no-follow SQLite opens; the [three-boundary torn-WAL recovery matrix](evidence/2026-08-21-security-store-torn-wal.md) permits only refusal or whole-transaction recovery; 69 passing persistence/audit/latch tests | Simultaneous physical-volume exhaustion across both databases and the deny latch, main-database and directory-entry torn-write loops, Keychain cross-store crash drills, signed-bundle container/owner/Data Protection verification, signed-XPC local-history execution, and stable-toolchain release evidence | Native provider adapters and additional local IPC can proceed independently |
| Application pairing | 0B/1 | active | The host boot-scoped authority enforces random 32-byte secret/nonce material, five-minute monotonic expiry, five-proof limit, exact transcript/HMAC/signature/SAS verification, transcript-bound local decision, atomic SQLite consumption, and strict bounded QR payload encoding; the client authority refuses bytes before QR-pinned TLS, binds both public keys and nonces into the transcript, constructs the exact secret proof and fixed-width signature through an injected signer, fences cancellation and concurrent proof calls across the asynchronous signing boundary, verifies the host transcript/SAS/expiry response, clears the one-time secret, and publishes only a correctly correlated monitor-only final identity; presentation exposes only a secret-free untrusted preview, requires explicit acceptance before a start intent, upgrades fingerprint trust only after pinned TLS, shows SAS only after verified transcript convergence, and remains `saving` until exact durable commit; client custody separates nonexportable reconnect and fresh-presence approval keys behind opaque references and the publication authority revalidates both before one complete retry-safe store transaction; strict canonical local encoding rejects unknown/noncanonical/broadened records; the concrete bundle-independent file adapter bounds inventory and record size, applies 0700/0600 permissions, fsyncs temporary data before same-directory rename and the directory afterward, rejects conflicting identities and visible unknown state, and converges across injected pre/post-rename faults; restart preflight against the real adapter adopts exact committed keys, removes only true orphans, and preserves conflicts; `CompanionClientPlatform` compile-checks role-specific this-device-only/Secure Enclave key construction, public-only registration, LocalAuthentication approval prompts, direct-message ECDSA signing, and DER-to-raw conversion; 107 host/client pairing, local review delivery, Mac approval presentation, and shared-listener ingress, QR, presentation, custody, platform-profile, publication, storage, recovery, network-construction, and [signing-reentrancy](evidence/2026-08-20-client-pairing-signing-reentrancy.md) tests plus the [client pairing application owner](evidence/2026-08-20-client-pairing-application-owner.md) and [no-relay pairing adapter](evidence/2026-08-20-client-pairing-network-construction.md) cover nonmutating paths, immutable-pin route racing, serialized fragmented framing, exact deadline propagation, sanitized failure, cancellation, and durable-commit convergence; the [one-shot VisionKit scanner and Core Image renderer](evidence/2026-08-20-pairing-qr-io-construction.md) are package-constructed and cross-compiled with four logic/render tests; the [Agent-owned local pairing-session composition](evidence/2026-08-20-local-pairing-session-composition.md) adds strict create/dismiss payloads, one-visible-code lifecycle, expiry, replay, compensating tombstones, and durable-commit race fencing; the [local SAS/name pairing approval composition](evidence/2026-08-20-local-pairing-approval-construction.md) binds validated key fingerprints, complete local review, approval-only name, decline-null, policy/expiry fences, one-use outcome, and atomic device/name persistence; the [host pairing wire owner](evidence/2026-08-20-host-pairing-wire-owner.md) binds verified TLS identity, exact begin/prove correlation, shared replay, trusted-local review publication, and durable terminal completion while deferring expiry across an in-flight local commit; the [role-safe host listener ingress and pairing pump](evidence/2026-08-20-host-listener-ingress-construction.md) classify only exact first-frame auth/pairing traffic without over-read, preserve one-use TLS/socket authority, send silent durable completion, keep pairing independent from primary, and delay primary replacement until valid proof reaches ready; the [already-authorized local pairing-review delivery and SAS/name sheet](evidence/2026-08-20-local-pairing-review-delivery.md) bind exact pending review, surface acknowledgement, terminal withdrawal, endpoint-loss cancellation, exact receipt replay, and revision-fenced Mac presentation; the [listener-owned pairing-context composition](evidence/2026-08-20-listener-pairing-context-composition.md) gates new QR codes on exact listener plus Bonjour readiness and consumes active or suspended sessions on withdrawal or terminal loss; the [exact listener-pairing factory](evidence/2026-08-20-listener-pairing-factory.md) derives QR identity, Bonjour service, and port from the same consumed TLS configuration; the [sealed pairing product composition](evidence/2026-08-20-pairing-product-composition.md) binds that listener context to one required-audit security store, QR session owner, host proof authority, decision owner, and authorized review service through a production-only aggregate; the [Mac pairing presentation reducer](evidence/2026-08-20-mac-pairing-presentation-reducer.md) preserves exact command retries, rejects mismatched receipts, and erases the QR on invalidation; the [value-driven Mac pairing sheet](evidence/2026-08-20-mac-pairing-sheet-construction.md) keeps unconfirmed codes visible and never treats implicit close as cancellation success; the [Mac pairing application owner](evidence/2026-08-20-mac-pairing-application-owner.md) composes exact authenticated-local command retries with bounded expiry, cleanup, receipt-adversary handling, and generation-fenced Agent loss without moving pairing authority into UI | Physical QR scan round trip, signed physical camera permission/recovery, Keychain/Secure Enclave creation/access-control/prompt tests, final iOS access group and container Data Protection/backup configuration, live certificate-pinned transport convergence, production same-team exact-identifier XPC transport, restart/error audit detail, and physical-device exchange remain | Application authentication and identity-neutral transport orchestration |
| Application authentication | 0B/1 | active | Unknown/inactive client IDs receive opaque challenges; 10-second challenges are bounded and single-use; golden-vector proof verification re-reads the current device and epoch before returning a principal; session description correlates to `auth.proof`; a [fixture-backed non-authorizing configured-route request/ack, primary-session integration, and generation-fenced Agent projection](evidence/2026-08-20-authenticated-route-protocol.md), a [revision-bound client reconnect, durable route-update, bootstrap, lifecycle, and package-UI composition](evidence/2026-08-20-client-configured-reconnect-composition.md), a [durable-session-key-bound reconnect security composition](evidence/2026-08-20-client-reconnect-security-composition.md), and a [store-bound configured-route Network/UIKit product](evidence/2026-08-20-client-configured-route-network-product.md) bind opaque provenance to the authenticated connection with strict sequence, inclusive 30-second freshness, byte-independent expiry, replacement fencing, LAN preservation, and diagnostic-failure isolation; one host primary-session owner binds listener identity, exact proof correlation, replay, 45-second liveness, per-command durable-principal revalidation, status/Act/discovery/Interactive routing, and exactly-once Interactive authority teardown; separate host and client Network.framework adapters enforce length framing, serialized fail-closed backpressure, disconnect closure, and byte-independent auth/liveness timers after independently verified same-connection handoff; the client one-shot TLS context prevents route/pin/callback/connection substitution and uses the strict single-leaf Security evaluator; the host sealed-listener path prevents connection/binding substitution by constructing a one-use pump authority only from the exact ready connection's negotiated metadata; the concrete route attempter maps only closed remote authentication errors to terminal denial and otherwise preserves transient route failure; injected latches prove cancellation and first-terminal-result semantics; injected client and host frame-I/O boundaries drive real hello/challenge framing, malformed input, send/receive failures, closed remote denial, and idempotent teardown through the pumps; the client authority refuses auth before pinned TLS, owns bidirectional handshake replay/correlation and the same exact deadline, delegates fixed-width signing without key custody, verifies paired host/device IDs, and publishes no connection identity before description success; one opaque session-reference adapter supplies pairing and reconnect signing without approval-key access; 81 authentication/mapper/host-session/client-session/host-and-client-Network/configured-route tests plus custody tests cover the boundary | Instantiate the composed network application owner in the permanent target plus rendered/signed configured-route UI evidence; physical listener metadata execution, live TLS callback ordering, Security.framework signer physical execution, pinned physical convergence, and physical-device exchange remain | Bonjour and foreground client orchestration |
| Discovery and routes | 0B/1 | active | `_maccompanion._tcp`/`local.` is frozen; endpoint text is canonical and closed; TXT metadata is limited to protocol major and an untrusted 64-bit host hint; 3 discovery tests reject ambiguous routes and metadata injection; the sealed TLS listener now preconfigures that exact service and collapses service-registration add/remove callbacks into closed LAN evidence; [no-network construction probe](evidence/2026-08-20-network-discovery-construction.md) maps the profile to Network.framework | Start advertise/browse only in a disposable signed identity, then prove Local Network grant/deny/recovery and route changes on physical identities/devices | Reconnect and route-ranking state can proceed without Local Network permission |
| Capture/input feasibility | 0A | active | Isolated probe compiles ScreenCaptureKit, Accessibility, Core Graphics, VideoToolbox, and `SMAppService`; an availability-gated package factory maps the frozen dimensions/frame-rate/queue-depth/video-range/cursor/audio profile into `SCStreamConfiguration`; a [menu-owned opaque target catalog](evidence/2026-08-20-opaque-target-catalog-construction.md) sanitizes app/window inventory, consumes transient tokens, rechecks live ownership and exclusions, and compile-checks exact selected-display application and desktop-independent window filters without enumeration; 6 tests prove profile bounds, privacy/lifetime invariants, explicit self-exclusion, and aspect-fit construction; a concrete but uninstantiated `SCStream` adapter plus bounded one-newest event owner normalize only complete exact-profile frames and serialize start/stop/system/sample/encoder failures, with 7 in-memory/injected tests; an injectable VideoToolbox policy plus concrete session driver applies realtime High 4.1 with no frame reordering and bounded bitrate/frame-rate/keyframe properties, with 4 tests proving exact order and fail-fast rejection; bounded CoreMedia extraction builds strict AVCC configuration/access units and normalized samples, with 8 tests covering exact construction, extension form, preallocation bounds, real in-memory format-description/block/sample extraction, attachment-derived keyframe truth, and timeline validation; the latency-first encoder owner plus concrete compile-checked `VTCompressionSession` adapter enforce one in flight, one latest waiter, clean recovery after replacement, awaited runtime backpressure, callback correlation, queue rejection, and exact terminal cleanup, with 7 injected tests; 8 publisher tests prove lease-fenced configuration/access-unit/discontinuity/end records, clean recovery, sequence-preserving new-surface fences, terminal rejection, and timeline bounds through the actual runtime action validator; the runtime now suppresses input across exact +1 Agent-issued surface replacements until discontinuity, configuration, clean keyframe, and exact acknowledgement complete; unposted pointer-event construction and pure input-event inspection remain no-post; the [2026-08-20 non-prompting CLI baseline](evidence/2026-08-20-platform-authority-preflight.md) remains no-grant/no-post/no-enumeration/no-stream/no-encoder-allocation; the [explicit capture/encode smoke construction](evidence/2026-08-21-capture-encode-smoke-construction.md) adds exact command parsing, production-owner composition, closed timeout/cleanup outcomes, eight injected tests, and a live permission-denied no-graph report without claiming real pixels | Run separate signed-menu-app Screen Recording, Accessibility observation, real encode, post-event, and lock probes after final IDs | Bind the catalog through authenticated final-identity XPC and physically prove filter/display transforms; continue no-prompt platform composition |
| App Review | 0A/3 | active | Current Apple guidance was rechecked on 2026-08-23; the [external TestFlight review package](testflight-review-package.md) now contains honest LAN-first positioning, 4.2.3(i)/4.2.7 risk treatment, candidate prerequisites, beta description, What to Test, no-account review notes, exact reviewer steps, attachments, clean rehearsal, and rejection/no-go paths without creating an App Store Connect record or submission | Replace candidate-bound placeholders only after explicit iOS App ID/provisioning, notarized Mac download, managed-entitlement disposition, physical scenario matrix, final privacy/export answers, and clean reviewer rehearsal | Internal TestFlight construction and physical product evidence continue; external submission remains explicit and human-authorized |
| Observe alpha | 1 | active | The v0 trust kernel, permission-free macOS metrics sampler, durable compare-and-swap generation/revision authority, validated host-to-wire response composition, single-owner foreground reconnect policy plus immutable-pin route-round execution, and honest monotonic freshness assessment pass locally; failed samples or commits produce no response and consume no revision. The [authenticated client Observe owner](evidence/2026-08-21-client-observe-channel.md) binds status and privacy-limited self-audit reads to the exact primary connection and router lane, fixes generation and strictly increases revisions, computes conservative monotonic freshness, retains disconnected status only as unreachable, preserves audit cursor/gap evidence, and publishes only after the router generation check; the real injected primary pump routes both Observe status and Act catalog responses through the concrete bridge. The [first-party Observe UI](evidence/2026-08-21-client-observe-ui.md) now presents distinct waiting/live/stale/unreachable/unavailable truth, validated Mac health, bounded scoped activity and explicit history gaps without a Control entry; five projection tests, iOS cross-compile, and the six-test Simulator accessibility flow pass | Instantiate the bridge and event-to-presentation binding from the configured-route application product and permanent target, then complete a physical paired exchange after release-shaped identities/lifecycle exist | Signed-target composition and disposable lifecycle/Bonjour probes |
| Bounded Act alpha | 1 | active | Exact effect/authorization/provider-bound operation digest; restricted RFC 8785 corpus; closed schema/registry and invoke/approval/status/cancel wire flow; one validated immutable registry/provider publication now backs local grant review, discovery, admission, release-path provider resolution, execution, and cancellation, while old provider references remain valid only for already-retained in-flight snapshots; the release coordinator retains exactly one publication from invoke/approval admission through provider effect; the authenticated command coordinator hard-gates ingress on startup reconciliation, scopes operations to the principal, preserves original parameters through approval, and resolves exact providers; correlated command dispatch returns only closed status/approval/error responses; the host primary session constructs operation context from its authenticated principal and authentication-issued connection ID after replay and durable-principal checks; the client primary session publishes that connection identity only after pinned TLS, exact proof correlation, and paired host/device verification; separate compile-only Network.framework pumps bind both primary-session contracts to serialized framed I/O and independent deadlines without claiming live trusted sockets; privacy-limited discovery returns only durably granted and currently installed descriptors in bounded stale-fenced pages without provider inventory; the client publishes catalogs only after every fence-matched page and renders live results only after invoked-descriptor schema validation, mapping unknown terminal identifiers to a generic failure; the [independent client Act path](evidence/2026-08-21-client-act-path.md) adds a catalog/session-fenced one-operation owner, complete closed-schema parameter drafts, an approval-key-only fresh-presence signer, exact invoke/approval/status/cancel correlation, late-signature invalidation, same-operation ambiguous-delivery recovery, granted-only Approved Actions UI, complete effect review, and distinct delivery/outcome/result states without starting Control; the authenticated Act channel composes exact-correlated pagination and one-operation routing; the connection-scoped primary router adds closed Observe/Act/Control lanes, exact replay/correlation/deadline admission, generation-gated publication, old-primary fencing, and a real pump bridge while preserving same-ID recovery and late-signature invalidation; the expanded disposable harness proves a typed mute edit and verified result with no socket, credential, or signer; transactional execution claim; monotonic host deadline with conservative `outcomeUnknown`; closed results/failures and cancellation; atomic no-retry startup reconciliation; exact post-start provider removal that retains unrelated provider references; Mac-only desired-state `setAudioMuted` candidate checks Core Audio property/settable state and verifies read-back with locked use disabled; the [native MVP Agent provider composition](evidence/2026-08-21-native-mvp-agent-provider-composition.md) now constructs that reviewed descriptor and exact live Core Audio provider as one value consumed by the complete Agent network startup, eliminating release-target registry/loader drift while remaining inert before admitted execution; the [bounded keep-awake candidate](evidence/2026-08-21-native-bounded-keep-awake-provider.md) adds explicit start-until/stop descriptors and an inert public-IOPM adapter capped at four hours while remaining outside the advertised registry pending physical and UX proof; the proposed three-state [system-appearance action](evidence/2026-08-21-native-system-appearance-no-go.md) is an evidence-backed no-go, with validation rejecting undocumented global mutation and Agent/native-provider Apple Events; 105 focused operation/discovery/wire/native-provider/transport/host-session/client-session/client-UI and native-product-composition tests plus persistence fault tests cover publication validation/replacement, concurrent complete-snapshot reads, multi-consumer generation fencing, one-read invoke retention, review/commit serialization, pagination, grant filtering, stale cursors, partial-catalog discard, safe results, delayed replay, approval execution, ownership, safe error disclosure, reply-kind fencing, missing providers, deadlines, cancellation races, provider removal during pending approval and running cancellation, recovery, and exact first-party startup publication | Instantiate the complete startup-reconciled Agent network product and primary-router bridge from permanent targets; complete verified same-socket certificate/trust handoff; run physical approval-key, authenticated operation exchange, and explicit no-prompt Core Audio support/mutation/read-back tests on signed clean devices; external adapters still require process/channel termination proof | Additional bounded native adapters, signed-target composition, and physical evidence can proceed behind the contract |
| Adaptive Control | 2 | active | Normative bundle-independent session/surface, session/channel-message, security, 96-byte media, reliable-input, macOS mapping, host/client admission/presentation, client security-composition, host command-composition, menu-app execution, and local-warning profiles; 18 indexed Interactive Control fixtures; focused coverage in the 1,270-test Swift suite enforces approval/session limits, privacy/fences, media/input framing, authenticated host routing and exactly-once teardown, closed client reply sets, current grant/menu/display/name admission, stable SQLite plus visible-menu revision joins and a [store-bound required-audit product composition](evidence/2026-08-20-interactive-product-composition.md), Security.framework material generation, correlated host challenge/proof dispatch, final-runtime revalidation, reentrant-request exclusion, disconnect/install-race compensation, exact local pending/transition/active dispatcher shutdown, final host input admission, exact primary-bound fresh-presence approval signatures plus a [selected-primary Control session owner](evidence/2026-08-21-client-primary-control-session.md), closed correlated handshakes, pinned-TLS mutually proven role channels, one-shot approval/channel authorities, atomic session/bootstrap creation with rollback, [signature-bound one-use initial runtime preparation](evidence/2026-08-20-initial-runtime-preparation.md), decode-validated bounded local execution leases, correlated readiness/safety receipts, Agent-issued exact +1 surface-replacement leases, fail-closed runtime preparation receipts, transition-ordered discontinuity/configuration/clean-keyframe admission, relative-validity wire descriptors materialized only on the client monotonic clock, distinct initial-Desktop configuration/clean-keyframe/acknowledgement gating, closed primary target-inventory and surface select/acknowledge sequencing, session-scoped opaque-token expiry and consumption, shared sequence handoff, and exact reply-gated input resumption; the single visible-menu runtime owner serializes effects, shows identity before capture, expires without traffic, terminates on Agent IPC loss, resumes partial fail-closed cleanup without repeating completed effects, correlates input envelope/fence/class/current lease in the same actor turn as its bounded synchronous platform post, strictly validates AVCC configuration/NAL/keyframe structure, and owns digest-bound gap-free bounded media enqueue across renewal with fail-closed queue backpressure; the bounded queue never evicts, rejects mixed sessions, and is purged before renderer blanking; the compile-checked capture-to-publication chain admits only complete exact-profile frames, keeps one newest callback plus one latest encoder waiter, awaits lease-fenced runtime acceptance, emits configuration before clean video, preserves sequence through discontinuity/new-surface fences, and terminates on any sample/encoder/runtime failure; the [bundle-independent client mapper](evidence/2026-08-20-client-input-mapping-construction.md) enforces half-open render geometry, direct-touch/trackpad modes, balanced drags, reset-on-mode-change, bounded scroll, and closed keyboard actions while a thin main-actor UIKit seam is iOS-Simulator compile-checked; the [generation-fenced client decoder](evidence/2026-08-20-client-decoder-construction.md) shares AVCC validation with the host, requires clean reset boundaries, rejects stale callbacks, retains one latest frame, and compile-checks VideoToolbox construction; the [bounded render handoff](evidence/2026-08-20-client-render-handoff-construction.md) orders callback generations and sequences, holds one pending result and one scheduled main-actor drain, and compile-checks exact-format UIKit display-layer presentation plus synchronous blanking; macOS planning maps supported HID and modifiers, tracks/reset releases, and binds constructed Core Graphics batches to exact display/coordinate geometry without posting or off-display buttons; a [compile-checked SwiftUI-to-UIKit live surface](evidence/2026-08-20-client-live-surface-construction.md) binds aspect-fit gesture geometry to one decoder/renderer session and resets plus blanks on disable or teardown; a [package-level iOS UI](evidence/2026-08-20-client-ui-construction.md) preserves unverified/verified pairing, durable-saving, connection, view/control/lock, and Remote-Control-optional distinctions through closed value-driven intents and adds a Desktop/app/numbered-window picker without window titles; Mac presentation keeps durable grant expansion, phone approval, one-session warning, and active stop state distinct while preserving every effect fact, and its local stop closes only after exact Agent authority/runtime completion | Final identities plus physical capture, encode/decode/render, physical UIKit recognizer/renderer evidence, post-event, lock, network latency, authenticated local UI, and safety evidence still gate a usable alpha; authenticated XPC binding and physical app/window filter execution remain open | Pairing/native UI, concrete client identity/key storage, authenticated XPC admission proof and physical transition evidence can continue independently |
| Route classification | 1/3 | active | A [source-scoped generation/freshness authority](evidence/2026-08-20-local-route-monitor-authority.md), [listener-plus-Bonjour LAN authority](evidence/2026-08-20-agent-lan-route-evidence.md), [authenticated configured-route protocol plus Agent projection](evidence/2026-08-20-authenticated-route-protocol.md), and a [fixture-backed client catalog/session state](evidence/2026-08-20-client-configured-route-construction.md) plus [durable reconnect/edit/bootstrap/lifecycle/UI composition](evidence/2026-08-20-client-configured-reconnect-composition.md) pass bundle-independent tests; the [application lifecycle binding](evidence/2026-08-20-client-application-lifecycle-binding.md) serializes UIKit activity and injected scheduling-only reachability through durable-before-dial reconciliation and carries the exact validated lifecycle snapshot; the [private-access guidance contract](private-route-guidance.md) verifies lifecycle coherence, maps every reconnect phase, withholds contradictions, and keeps the disposable iOS harness live across controller-internal completion without socket authority; `privateDNS`/`privateNetwork` derive only from explicit configured provenance on the exact authenticated primary, never DNS/interface/process inference; [primary-source review](research/2026-08-20-route-classification-policy.md) records why generic `NWPath` inference is a no-go | Instantiate the composed owner in the signed target without granting guidance route authority, and physically prove final-identity listener/Bonjour and configured private-DNS/user-managed-private-network routes | Local status reads, listener/discovery composition, UI guidance, and every non-route lane continue |
| No-relay beta | 3 | active | Route-independent identity is fixed; the competitive matrix, [product-evidence ADR](adr/0002-stage-3-product-evidence.md), and external-review strategy are recorded; signed permanent Mac/iOS products and no-relay route composition exist; the [study-evidence kernel](evidence/2026-08-23-stage-3-study-evidence-kernel.md) implements a strict content-free report, prohibited-field corpus, and exact cohort evaluator; the [local report owner](evidence/2026-08-23-stage-3-local-report-owner.md) adds atomic bounded storage plus exact preview, explicit export, and destructive delete; [local enrollment and initial capture](evidence/2026-08-23-stage-3-local-enrollment-capture.md) adds explicit dogfood/day-session gates and pairing/connection/Observe bindings; [explicit Act and Control capture](evidence/2026-08-23-stage-3-act-control-capture.md) adds tester-confirmed mute outcomes and content-free per-mode Control duration; [authenticated route and final review](evidence/2026-08-23-stage-3-route-and-final-review.md) completes local capture with exact winning-route provenance, explicit Observe jobs, physical returns, comprehension, safety/recovery review, and immutable finalization; the [exact-source signed readiness refresh](evidence/2026-08-23-stage-3-signed-readiness-refresh.md) binds fresh signed Mac/iOS development constructions and exact iPhone installation to source `349706d` while leaving both apps unlaunched and the Agent absent; the [participant disclosure and retention draft](stage-3-participant-disclosure-and-retention.md) fixes the proposed data inventory, TestFlight boundary, withdrawal flow, deletion schedule, and pre-enrollment approval checklist | Confirm persistent Agent enablement at action time, then run signed physical same-LAN pairing, Observe/Act/Control/private-route/report proof; obtain legal/privacy approval and replace disclosure placeholders; resolve persistent-capture disposition, notarized distribution, and separate calibration plus confirmatory cohort evidence | Signed physical testing, distribution, and disclosure review continue independently |
| MacTools/provider work | 4 | deferred | The [competitive task matrix](research/2026-08-23-competitive-task-matrix.md) records workflow breadth as a signal but not a Stage 3 requirement | Confirmatory repeated nonvisual job plus one action better owned by MacTools/another provider and a bounded non-shell contract | No bridge implementation before the gate |
| Semantic/native surfaces | 5 | deferred | The matrix records app/window focus as parity and focused-text/semantic content risk | Repeated job that App/Window Focus and Smart Zoom cannot complete well, plus a reviewed surface with secure/private fallback | No semantic authority inferred from Accessibility data |
| Administrator capabilities | 6 | deferred | The matrix records separate per-capability deferral; competitor bundles do not transfer security evidence | Per-capability repeated job, local grant, threat model, isolation, physical failure proof, revocation/audit, and independent security review | One capability cannot reopen or block another |
| Assisted operation | 7 | deferred | Direct three-path product remains sufficient; untrusted-planner boundary is documented | Earlier gates, one validated assisted job with measured advantage, injection tests, and complete data/cost/offline policy | No model receives control authority implicitly |

Latest permanent-iOS checkpoint, superseding the target-composition and
signed-target-next-step wording in the Apple-target, Observe, Bounded Act,
Adaptive Control, and route-classification rows: the
[permanent iOS release composition](evidence/2026-08-22-permanent-ios-release-composition.md)
now owns protected QR/SAS pairing, crash-recoverable first-route publication,
configured no-relay reconnect, and the first-party Observe, Approved Actions,
and independently authorized Remote Control workspace from the permanent
target. It starts no configured connection before explicit route provenance
and cannot infer authority from routing, reachability, or app lifecycle. The
remaining proof is registered-identity signing and physical same-LAN pairing,
followed by live Observe, `setAudioMuted`, and Interactive media/input evidence.

Latest disabled-Agent durable-authority checkpoint, superseding the durable
owner portion of the Process/local-IPC and Agent-lifecycle next steps: the
[Agent bootstrap durable authority](evidence/2026-08-22-agent-bootstrap-durable-authority.md)
now issues revision-bound expiring offers and commits exact enabled successor
intent through the existing locked atomic store. Exact read-back is required
after every write outcome, exact command replay is write-free, and generation
plus operation high-water fences prevent suspended storage work from crossing
peer replacement. The next proof is injection into the exact XPC handler,
successful-receipt service retirement, explicit Agent-only setup registration,
and foreground menu-client composition.

Latest disabled-Agent bootstrap-transport checkpoint, superseding the
exact-envelope next-step wording in the Process and local IPC row: the
[exact bootstrap transport](evidence/2026-08-22-disabled-agent-bootstrap-transport.md)
now binds the two frozen methods to four closed XPC dictionaries, nonempty
4,096-byte canonical codecs, and one ordered generation/operation-fenced offer
then enable transaction. It rejects overlap, offer substitution, malformed
receipts, timeout, cancellation, peer replacement, and delayed callbacks
without adding durable mutation, readiness, presentation, or network authority.
The next proof is the Agent-owned serialized durable offer/enable handler plus
explicit foreground Agent-only setup registration and menu-client composition.

Latest process/local-IPC checkpoint, superseding the receiver-next-step wording
in the Stage 0A row: the [authenticated menu product composition](evidence/2026-08-21-authenticated-menu-product-composition.md)
now connects accepted lifecycle readiness to the exact sender/router, binds the
production dashboard receiver to menu-owned presenters with awaited teardown,
and lets the prepared Agent wait for a replaceable authenticated menu authority
before one-use construction of a nonescaping unstarted network product.
Authenticated replacement and endpoint-terminal paths immediately fence the
old generation; menu loss cancels pending visible review state while leaving
primary ingress and Observe nonterminal for a later ready generation.
The [coordinated Agent network-listener activation](evidence/2026-08-21-coordinated-agent-network-listener-activation.md)
now retains exact listener construction/start/rollback inside the same
nonescaping product owner and leaves readiness to Network callbacks. Live
request-context composition, permanent-target activation, and signed
two-process evidence remain gated.

The [Interactive lease local-XPC checkpoint](evidence/2026-08-22-interactive-lease-local-xpc-transport.md)
fixes and implements exact install, renewal, and revoke transport between one
authenticated-and-ready Agent/menu generation. The later initial-Desktop
checkpoint adds preparation as the fourth operation on the same cross-family
transaction gate. Strict canonical payloads, asymmetric bounded deadlines,
exact receipt correlation, and generation-wide failure on ambiguity preserve
fail-closed ownership. Connection loss invokes local unacknowledged runtime
invalidation. This transport carries no input or media and does not itself
activate capture or posting; the existing stable pairing/recovery authority
remains Control-free.

The [Interactive runtime composition boundary](evidence/2026-08-22-interactive-runtime-composition-boundary.md)
now forwards the exact lease lifecycle into one serialized menu runtime with a
sticky cleanup-failure latch. Its Agent owner double-revalidates durable and
visible admission around opaque Desktop preparation, transfers channel
credentials only after the exact install receipt, renews only the exact current
lease after another final admission read, and requires correlated four-effect
revocation or compensation. The subsequent
[opaque-display and lease-scheduling checkpoint](evidence/2026-08-22-opaque-display-and-lease-scheduling.md)
retains the physical main-display mapping only in the menu-platform module,
publishes its opaque UUID, refuses redirection after display loss, and renews
from exact acknowledged lease deadlines without retrying ambiguity. Concrete
platform effects and secondary channel handoff remain Control composition
gates.

The [initial Desktop runtime transport checkpoint](evidence/2026-08-22-initial-desktop-runtime-transport.md)
now adds Desktop preparation as the fourth operation on the authenticated
runtime transport's shared single-flight gate. The menu resolves the exact
admission-published opaque display through the same process-local mapper and
returns only a bounded, exactly correlated descriptor without ScreenCaptureKit
enumeration or platform effects. Install now carries that complete descriptor,
binds it to every lease surface dimension during construction and decoding,
revalidates Desktop kind plus monotonic validity before indicator/capture, and
passes the full command into the capture seam. The later
[permanent Agent runtime binding](evidence/2026-08-22-permanent-agent-interactive-runtime-binding.md)
installs one stable fail-closed authority in the dispatcher before XPC and
binds only the exact authenticated-ready generation through its cached opaque
endpoint. The server queue rechecks that generation and its private issuance
token, so stale endpoints cannot redirect work to replacements; menu loss and
product finish serially retire the bound owner. The later
[persistent Control indicator and expiry](evidence/2026-08-22-persistent-control-indicator-and-expiry.md)
makes the permanent target construct the menu runtime, publishes a named
menu-bar and open-menu indicator with local Stop, keeps it visible while any
prior safety effect is uncertain, and schedules exact monotonic expiry with
renewal replacement, stale-token rejection, and early-wake correction. The
later
[host Interactive role-ingress checkpoint](evidence/2026-08-22-host-interactive-role-ingress.md)
adds strict secondary-role classification and mutual proof on the shared TLS
listener, keeps one-time credentials inside the exact generation-bound Agent
runtime, and retains only a same-client/primary/session/epoch input-media pair.
The later
[host Interactive role-data-plane checkpoint](evidence/2026-08-22-host-interactive-role-data-plane.md)
transfers the concrete pair to one generation- and runtime-fenced Agent owner,
applies bounded exact input framing, and enforces one-record-at-a-time media
backpressure with paired fail-closed teardown. The full 1,449-test Swift
catalog, cross-builds, and eight platform probes pass. Authenticated local-XPC
input/media routing plus concrete capture/frame/input adapters remain the next
independent Control slice.
The subsequent
[authenticated local-XPC Interactive role-data checkpoint](evidence/2026-08-22-authenticated-local-xpc-role-data-transport.md)
closes that process boundary with exact input and media dictionaries,
independent generation-fenced single-flight lanes, asymmetric deadlines, and
generation-wide fail-closed invalidation. Input reconstructs its full command
fence only inside the active serialized menu runtime. Media uses a zero-buffer
Agent rendezvous that withholds the menu acknowledgement until the exact
network media role takes the complete record. Production binds both directions
only to the current authenticated menu generation. Concrete ScreenCaptureKit,
VideoToolbox, queue-drain, Core Graphics posting, and signed physical evidence
remain the next independent Control slice.

The [concrete macOS Interactive effects checkpoint](evidence/2026-08-22-concrete-macos-interactive-effects.md)
now closes that construction slice in the permanent menu application. The
exact authenticated lease activates a Desktop-only ScreenCaptureKit stream,
bounded real-time VideoToolbox H.264 owner, non-evicting queue with one
acknowledged local-XPC publication in flight, and the sole release Core
Graphics HID-post boundary. Construction remains inert; display mapping and
input permission are revalidated before capture starts; event planning commits
only after complete construction/posting; and failure withdraws the queue
callback and invokes ordered four-effect cleanup. The indexed fixture count is
71 and the full 1,461-test Swift catalog, macOS/iOS cross-builds, and eight
platform probes pass on Xcode 27 beta. A flaky pre-existing synthetic
route-racing barrier was corrected and passed 20 isolated repetitions. Signed
two-process TCC behavior, real posted input, physical iPhone pixels and
latency, lock/takeover, final-identity XPC, and stable-Xcode evidence remain the
next Control gates; persistent capture authorization remains independent and
is not claimed by this ordinary-consent implementation.

The [permanent Agent Interactive-material checkpoint](evidence/2026-08-23-permanent-agent-interactive-materials.md)
closes the last construction-only material source in that release path. The
Agent now retains the Security.framework cryptographic generator across the
existing authenticated-menu replacement of visible admission, runtime, and
surface-control authorities. Preparation still starts no effect, and visible
admission plus runtime remain fail-closed before menu binding, but an admitted
Control request can now create its bounded approval challenge and distinct
one-time input/media credentials instead of terminating at the inert material
seam. Signed two-process approval, channel activation, pixels, input, lock, and
latency remain physical gates.

The [permanent menu host-recovery command checkpoint](evidence/2026-08-23-permanent-menu-host-recovery-command.md)
removes the release menu application's unconditional unavailable recovery
client. The reviewed recovery owner now submits its exact retained command
through the dashboard product and one authenticated-generation single-flight
XPC envelope, decodes a dedicated canonical bounded receipt, and requires
complete receipt correlation before success. Pairing and destructive recovery
share transport serialization but retain separate injected Agent handler
interfaces. Timeout, cancellation after send, malformed or mismatched reply,
and endpoint loss invalidate the generation and never trigger an automatic
semantic retry. The recovery-only permanent Agent service now publishes the
review/resume and installs this handler; its exact completion acknowledgement
atomically retires replay state before a one-shot Agent restart. Signed
two-process execution and Keychain replacement are not claimed.

The [visible Interactive admission checkpoint](evidence/2026-08-22-visible-interactive-admission-contract.md)
now carries the closed canonical menu-process generation, exact revision, and
optional opaque selected-display publication through an independent
authenticated local-XPC request/ack transaction. The permanent Agent inserts
one stable authority into both its durable-plus-visible admission reader and
the presentation-capable XPC profile; the menu publishes revision 1 after
readiness and before status. Exact replay, +1 replacement, bounded deadlines,
and generation-loss withdrawal fail closed. The initial display is nil and
grants nothing. The following opaque-display checkpoint now replaces that nil
with a menu-owned random token for the current main online display while
keeping the physical identifier process-local and non-presentational.

The [conservative network request-context checkpoint](evidence/2026-08-22-conservative-network-request-contexts.md)
now supplies live clocks, unique response IDs, and an owned public macOS
session/lifecycle source for that listener seam. [Primary-source API
research](research/2026-08-22-public-macos-session-state.md) found no documented
lock-state discriminator: same-user/on-console/login-complete remains ambiguous
and maps to `otherConsoleUserActive`, never unlocked or locked. Sleep and
terminal lifecycle signals fail closed. Permanent-target invocation, Act and
Control availability, and signed runtime evidence remain separate gates.

The [other-console lifecycle checkpoint](evidence/2026-08-22-other-console-lifecycle-fail-closed.md)
now carries that conservative state through the product lifecycle instead of
forcing it into active, locked, or logged-out. A ready enabled Agent preserves
Observe while another or ambiguous console user is active, but local
administration and new Interactive Control require a positively observed active
configured-user session; a takeover ends current Interactive Control without
closing the primary Observe session. Lock currently follows the same
fail-closed teardown until the ordered genuine-lock-surface transition is
implemented and physically proven. The [inert Agent application lifecycle
facade](evidence/2026-08-22-inert-agent-application-lifecycle-facade.md) now
retains that lifecycle and the conservative request contexts behind one owner.
Construction is safe-disabled and observer-free; start observes only public
workspace lifecycle, and explicit or deinitializing terminal finish cannot
resurrect state even through retained context closures. It creates no
storage, Keychain, XPC, listener, process, login-role, or readiness authority.
The [durable-intent-ordered inert product preparation
checkpoint](evidence/2026-08-22-durable-intent-agent-preparation.md) now loads
the exact durable intent from its dedicated release-storage subdirectory before
constructing primary inputs, rejects invented positive lifecycle state, and
retains a ready prepared product behind its canonical lifecycle snapshot and
terminal finish only. Construction may reconcile durable storage and host
identity, but readiness-producing local-XPC construction is deferred; it starts
no observer, XPC service, listener, process, login role, pairing session, or
readiness path. The [permanent Agent inert-preparation
integration](evidence/2026-08-22-permanent-agent-inert-preparation.md) now
invokes that facade through a narrow application product. Ready preparation
opens only its selected enabled or disabled service; durable local recovery now
opens the distinct recovery-only product, while first-unlock wait alone exits
so the configured launchd policy may retry. Preparation or
XPC-start failure exits closed, and a ready XPC-start failure awaits prepared-
root retirement. The executable cannot import broad product, network, or lifecycle
platform authority and still activates no observer, product XPC, listener,
process, login role, pairing, readiness, Observe, Act, or Control path.

Local device administration now includes a [bundle-independent active-revoke
convergence path](evidence/2026-08-21-local-device-revocation-convergence.md):
closed five-minute review/command/receipt values, an independent primary-ingress
security fence, proactive session/route/Interactive teardown, exact stale-state
comparison, schema-v8 durable command/receipt journaling, latch-backed atomic
SQLite revoke, startup reconciliation, content-free status convergence, and
cross-restart exact replay for the tombstone lifetime. Issue 13 remains active
until final authenticated-XPC, indicator truth, and signed physical sub-second
evidence pass.

## Public repository remediation

The 2026-08-21 read-only remote audit found that
`Jenny-Media/MacCompanion` is already public, with no declared license, branch
ruleset, classic branch protection, Actions run, private vulnerability
reporting, secret scanning, validity checks, or push protection. The published
root currently contains only `.gitignore`, `README.md`, and `docs`. The local
tree now assigns `@xcv58`, the sole visible Jenny Media member and authenticated
administrator, through `.github/CODEOWNERS` and pauses external contributions
until approved license, contribution, trademark, and private-reporting policies
exist. No remote setting or published file was changed. Provider controls,
private reporting, license approval, history review, and publication of the
local safeguards remain urgent authorized work rather than future launch tasks.

The subsequent [local open-source policy bundle](evidence/2026-08-23-open-source-policy-bundle.md)
adds the exact Apache-2.0 text, `NOTICE`, separate draft trademark and security
terms, the contribution hold, conduct expectations, README discovery, and a
cross-file validation gate. This closes the missing-file construction gap only.
Written legal approval, an operational and independently checked private-report
route, provider protections, exact-head history review, and explicit
confirmation before any push remain open.

## Immediate milestone

The [bundle-independent diagnostic CLI v0.1 contract](evidence/2026-08-21-diagnostic-cli-contract.md)
now fixes the only commands admitted by the authenticated local-IPC matrix:
content-free status, sanitized diagnostics export, local help, and version.
One authoritative fixture owns valid/invalid arguments, exact request plans,
fixed text, and eight closed failure mappings. The pure `CompanionCLI` target
revalidates typed values before text or compact sorted JSON and has no
executable, transport, file writer, or identity claim. Seven focused tests pass;
the permanent `maccompanionctl` still requires final signing identity and
physical signed final-identity XPC evidence for the CLI role.

The [Agent sanitized diagnostic export service](evidence/2026-08-21-agent-diagnostic-export-service.md)
now closes the source behind both CLI export and the dashboard intent. One
boot-scoped Agent authority assigns content-free event sequences, retains only
the newest 256 entries, and exposes coordinators only to a write-only publisher
facet. The root-issued exporter combines those events with a fresh validated
status snapshot and maps every source/construction failure to one closed error.
The menu app and CLI are explicitly admitted by the closed method matrix; the proven menu-app identity still requires production XPC composition,
while the CLI needs its own permanent identity before either receives the
capability. Seven new Agent tests and one IPC boundary test bring the measured
suite to 1,061 tests, including 185 Agent and 43 IPC tests.

The [Mac Agent administration dashboard](evidence/2026-08-21-mac-agent-dashboard-construction.md)
now gives the menu application a coherent content-free entry surface for
enabled intent, lifecycle, listener, closed route kinds, security posture,
bounded inventory/session counts, and sanitized warnings. Its application
owner revalidates every snapshot and binds it to one increasing local
connection generation; sequence replay, time regression, replacement, loss,
and delayed callbacks cannot restore stale availability. The SwiftUI shell
emits only typed enable, disable, retry, pairing, devices, activity, and
diagnostics intents and keeps the one-device pairing gate explicit. Fourteen
focused tests pass. Production final-identity XPC composition and signed lifecycle
effects remain separate gates.

The [Mac dashboard action coordinator](evidence/2026-08-21-mac-dashboard-action-coordinator.md)
now gives those typed intents one execution owner and one admission policy
shared with SwiftUI. All seven actions re-read and revalidate current status;
effects serialize, local navigation remains effect-free, diagnostics are
revalidated, and the existing pairing owner reports completion only with a
visible Agent-issued receipt. Closed completed, not-completed, and
outcome-unknown results remain distinct. Authority replacement fences a
suspended revision without letting its late completion overwrite current
state. Twelve new tests pass; final lifecycle, status, and diagnostic adapters
still require signed-target peer and platform composition.

The [dashboard lifecycle product composition](evidence/2026-08-21-dashboard-lifecycle-product-composition.md)
now supplies the concrete lifecycle adapter behind that action owner. The
[durable lifecycle intent and restart reconciler](evidence/2026-08-21-durable-lifecycle-intent-reconciliation.md)
extends it with strict revision-fenced atomic desired-state storage. Commands
persist the user's choice before live mutation; missing storage defaults to
disabled; startup restores no stale readiness; and enabled, disabled, and
logged-out states converge roles, reducer state, and eligible start requests.
Forty-four product/platform tests plus the real-root revision/epoch integration
pass. Final signed service construction, authenticated observation sources, and
physical lifecycle evidence are the remaining lifecycle gates.

The [login-role effect executor](evidence/2026-08-20-login-role-effect-executor-construction.md)
now registers both roles before an enable transition may commit and accepts
disable unregistration only after remote teardown. Eight focused tests prove
exact Agent-then-menu registration, reverse rollback, best-effort two-role
disable cleanup, closed failure receipts, explicit readiness handoff, phase
rejection, and reentrancy rejection. The status-aware convergence wrapper adds
thirteen tests for idempotency, exact
postconditions, approval recovery, missing-service detection, and
effect-then-error races. The label-free `CompanionAgentPlatform` adapter maps all
four current `SMAppService` statuses and awaits asynchronous unregister
completion. The generation-fenced observation owner now keeps both roles
starting until exact final-source ready, rejects stale callbacks, and requests
only exact recovery effects. Final-identity construction must supply the
authenticated menu process/IPC adapter without inventing readiness from service
registration, status, start requests, or PID presence. The Agent source is now
bound to the complete required-audit service graph.

The [client application lifecycle binding](evidence/2026-08-20-client-application-lifecycle-binding.md)
now serializes application-global UIKit activity and injected reachability into
the durable configured-route lifecycle. Package tests prove no pre-start or
background dial, reconciliation before the first attempt, active-route closure
on background, one-round re-arming, and fail-closed invalid time. The
[disposable iOS harness](evidence/2026-08-20-client-ui-simulator-harness.md)
passed six UI tests, including a real Home/reactivation transition that starts
exactly one additional synthetic round without opening a socket.

The [independent client Act path](evidence/2026-08-21-client-act-path.md)
closes the previous product-shell gap: Approved Actions are now reachable from
the paired-Mac workspace without entering Remote Control. The bundle-independent
owner binds one operation to the authenticated client/host/device/connection
and exact catalog fence, validates typed schema parameters and results, uses
the separately protected user-presence approval key, discards late signatures,
and queries the same durable operation after ambiguous delivery. Nine focused
tests plus six authenticated-channel race tests pass, the iOS UI cross-compiles, and the six-test disposable harness
edits and completes a typed mute action while asserting that no Control entry
appears in the Act flow. The real primary Network pump now satisfies the narrow
authenticated byte-sender boundary, with catalog pagination and operation
interpretation retained by the Act owner. The
[client primary router](evidence/2026-08-21-client-primary-router.md) now adds
closed Observe/Act/Control request lanes, exact correlation and replay,
generation-gated publication, old-primary fencing, and an authentication-time
bridge that routes real injected pump catalog and status exchanges into their
Act and Observe owners. The
[client Observe owner](evidence/2026-08-21-client-observe-channel.md) adds exact
host/generation/revision status admission, conservative live/stale/unreachable
assessment, bounded self-audit pagination with explicit gap evidence, and
invalidation-wins publication. Six focused owner tests and the authenticated
pump integration pass.
The [configured-route primary product](evidence/2026-08-21-configured-primary-product.md)
now constructs an inert Observe/Act/Control bridge per authenticated parallel
route and
publishes handles and host/connection-tagged events only after the reconnect
state machine accepts that exact winner. A two-route race, real injected-pump
status exchange, selected teardown, and pre-selection termination prove that
losing or stale candidates remain invisible. The
[selected-primary Control session owner](evidence/2026-08-21-client-primary-control-session.md)
adds exact primary binding, explicit Desktop request, fresh Control-only user
presence, the correlated approval continuation, accepted role offers,
typed denial/retry, and stale-route teardown without claiming that the role
channels are active. Permanent-target instantiation, physical approval-key
execution, signed Core Audio mutation, and a physical authenticated exchange
remain explicit gates.

The [client secondary role handshake](evidence/2026-08-21-client-secondary-role-handshake.md)
now binds accepted input/media offers to the exact winning endpoint retained
outside presentation state. Its injected pump performs bounded four-byte
big-endian framing, exact fragmented reads, pinned-role mutual proof, a fixed
30-second monotonic deadline, and no post-accept over-read. A concrete
Network.framework role connector, paired socket-generation owner, clean-media
activation, and physical media/input evidence remain the next gates.

The [concrete client role Network owner](evidence/2026-08-21-client-secondary-role-network.md)
now consumes role-neutral one-shot TLS evidence from each exact live
`NWConnection`, opens input and media only on the selected endpoint, rechecks
the current primary after both proofs, and closes every ready sibling on role
failure or replacement. Configured-product initial Desktop activation now
consumes the ready media socket through a bounded exact-read pump and the
primary descriptor/acknowledgement exchange; live physical exchange remains
open.

The [configured-product role binding](evidence/2026-08-21-client-role-product-binding.md)
now starts the exact pair only after application state retains the accepted
Control value, fences late completion by activation generation, and retires the
pair on retry, rejection, failure, replacement, or exact primary termination.
Its role-channels-ready state remains below presentation. The
[initial Desktop activation owner](evidence/2026-08-21-client-initial-desktop-activation.md)
now drives exact media records through VideoToolbox/render composition and
withholds acknowledgement until a renderer-issued current clean-frame receipt.
The exact primary reply gates a serialized reliable-input sender and UIKit
gesture enablement. The subsequent [continuous media authority handoff](evidence/2026-08-21-client-continuous-media-handoff.md)
keeps admitting exact-surface delta frames while that reply is pending and
transfers the same configured media and reliable-input authorities into steady
surface control without resetting either sequence. Exact-connection and
accepted-session-fenced lifecycle
publication now advances the selected-primary workspace through channel
connection, channel readiness, initial verified-frame preparation, active, and
stage-specific failure without permitting skipped or backward transitions.

The [remote Control stop exchange](evidence/2026-08-21-client-remote-control-stop.md)
is now closed and canonical. The client retires its role pair when the exact end
request is enqueued but reports remote completion only after the correlated
receipt. The host clears admission before awaiting input release, capture stop,
media purge, and output blanking, and sends that receipt only after the safety
boundary completes. Duplicate, early, stale-connection, and wrong-session
events cannot repeat teardown or advance the selected-primary state.

The [first-party selected-primary live screen](evidence/2026-08-21-client-primary-live-control-screen.md)
now requests full Control separately from opening media, owns the UIKit
decoder/render/input product across SwiftUI navigation, waits for the exact
verified-frame acknowledgement before enabling input, offers touch and trackpad
modes, and invokes the typed remote Stop path. The six-test no-network
Simulator harness renders that production destination, exposes the Touch mode,
opens its actual software keyboard, emits typed payloads from visible key taps,
then proves Stop returns to the workspace and dismisses the keyboard. Observe
and Approved Actions remain peers and do not require opening or retaining the
live screen. A manual stateless iOS keyboard forwards bounded text/delete
actions while retaining no remote field value; focus-aware Smart Input remains
a separate gated surface.

The [client primary workspace](evidence/2026-08-21-client-primary-workspace.md)
now consumes that selected product through one expected-host, exact-connection
state owner. Its latest-one revision stream rejects out-of-order UI work,
retains disconnected status only as unreachable, clears all Act authority on
teardown, clears old status on replacement, distinguishes catalog errors from
operation errors, and exposes typed command methods rather than raw bytes. A
first-party SwiftUI workspace makes Observe, Act, and Control separate peers;
opening the Control entry is only an intent and grants no session authority;
the separate typed command starts the selected-primary approval flow, and the
entry remains disabled while preparation is in flight or has failed while an
active session may reopen its already-owned live surface. The
1,129-test hardened package and iOS cross-compile pass. Permanent-target
instantiation and physical private-route evidence remain explicit gates.

The [coarse reachability source](evidence/2026-08-20-client-coarse-reachability-construction.md)
now maps Network.framework path status to a pessimistic Boolean stream with no
endpoint, interface, DNS, VPN, or provenance authority. Two tests prove closed
mapping, one-start lifecycle, idempotent stop, stream completion, and late-event
rejection; the concrete source cross-compiles for iOS. A
[single application-global owner](evidence/2026-08-20-client-network-application-owner-construction.md)
now fixes pessimistic startup, bridge/source stop ordering, and terminal failure
containment. The composed harness passes six UI tests, including exactly-once
failure reporting with no dial after an invalid round. The next client milestone
is permanent-target instantiation and signed physical airplane-mode, Wi-Fi,
background, and private-route recovery evidence. Identity, Keychain, live
private-route, lock-session, and latency gates remain external and do not block
other bundle-independent work.

Latest Adaptive Control construction checkpoint, superseding the
authenticated-XPC/app-window-transition next-step wording above: the
[adaptive surface runtime binding](evidence/2026-08-23-adaptive-surface-runtime-binding.md)
connects the permanent Agent's authenticated primary surface dispatcher to an
exact-generation local-XPC family and a menu-only opaque
ScreenCaptureKit target owner. Desktop, application, window, and Desktop
escape-hatch transitions now use ordered input release, source preparation,
runtime fence/lease commit, activation, discontinuity/configuration/clean-frame
gating, and exact acknowledgement before input resumes. Replacement leases
rearm their exact expiry deadline, stale sessions cannot trigger recovery for
another session, and window input uses retained global bounds plus the backing
scale of the containing display. The full gate passes 71 indexed fixtures,
1,467 `MacCompanionKit` tests, 8 platform probes, cross-builds, and the unsigned
permanent app build. Signed installation/Agent enablement, TCC consent, live
two-process pixels/input, physical iPhone, lock/takeover, latency, and reconnect
evidence remain open; none blocks continued bundle-independent work.

The subsequent [adaptive client surface switching](evidence/2026-08-23-adaptive-client-surface-switching.md)
binds that host runtime to the permanent iOS live product. **View** requests a
fresh privacy-limited application/window inventory, keeps Desktop as an escape
hatch, and drives one reset-before-select replacement exchange. Input remains
inert across selection and media transition; decoder admission alone is no
longer sufficient, because the client must prove the exact clean frame was
rendered before acknowledgement and must validate the host's exact reply
before resuming input. The 45-test Interactive Client and 46-test Client
Network Platform suites pass; the full gate passes 71 fixtures, the 1,468-test
Swift catalog, macOS/iOS cross-builds, unsigned permanent application builds,
and eight platform probes. Focus-pushed Smart Zoom and Smart Input remain
fixture-first work; signed installation, TCC, real pixels/input, and
physical-iPhone evidence remain open external gates.

The [manual visual Smart Zoom fallback](evidence/2026-08-23-manual-visual-smart-zoom.md)
now gives every live pixel surface an explicit local 1x-to-4x pinch, bounded
pan, and Fit mode without changing the host surface or authority fence. It
resets and suppresses remote gestures during adjustment, inverse-maps direct
points and trackpad deltas afterward, and returns to Fit on viewport, encoded
surface, replacement, or lifecycle changes. The 48-test Interactive Client
suite passes; the full gate passes 71 fixtures, the 1,471-test Swift catalog,
macOS/iOS cross-builds, unsigned permanent application builds, and eight
platform probes. This closes the manual visual fallback, not focus-assisted
Smart Zoom: the current strict request/reply primary owner cannot accept an
unsolicited focus event without a separately frozen ordered event lane. Signed
installation, TCC, real pixels/input, physical-iPhone gestures, focus latency,
and lock behavior remain open evidence gates.

The [ordered focus-event lane and client admission](evidence/2026-08-23-ordered-focus-event-lane.md)
now replaces that strict request/reply limitation with one closed Control event
kind. It has an independent replay window and exact sequence, carries only the
current surface fence plus privacy-filtered focus shape, and cannot resolve or
consume a command. Its short-lived one-use target token feeds only the existing
reset, select, clean-frame, acknowledgement, and input-resumption exchange; a
paused event suppresses local input until recovery. The full gate passes 73
fixtures, the 1,477-test Swift catalog, macOS/iOS cross-builds, unsigned
permanent application builds, and eight platform probes. The host
Accessibility observer/token issuer and automatic iOS application are next;
signed installation, TCC, real pixels/input, physical-iPhone focus behavior,
latency, and lock behavior remain open evidence gates.

The following [host focus-event capability authority](evidence/2026-08-23-host-focus-event-authority.md)
now gives the Agent latest-only, one-use admission for a sanitized focus
candidate. Every token is bound to the exact event identity/sequence, current
surface fence, focus projection, and local expiry, cannot be reused within the
session, and is consumed before the menu resolver must reproduce the exact
Focused Region descriptor. A current Focused Region cannot change focus unless
input was first reported paused. The full gate passes 73 fixtures, the
1,482-test Swift catalog, all cross-builds/unsigned permanent builds, and eight
platform probes. Accessibility observation, authenticated local candidate
delivery, primary-stream event sending, live crop construction, and automatic
iOS application remain the next safe lanes; signed and physical evidence
remains open.

The subsequent [host event transport and Accessibility projection](evidence/2026-08-23-host-event-transport-and-ax-projection.md)
now gives the authenticated primary frame pump one serialized event/reply write
lane and admits only the frozen null-correlation focus event after readiness.
The menu-platform Accessibility reader immediately projects the focused element
to a closed category, editable/secure flags, and bounded normalized geometry;
it never reads content, labels, titles, descriptions, identifiers, or selected
text, and unsafe or clipped geometry falls back closed. The full gate passes 73
fixtures, the 1,485-test Swift catalog, all cross-builds/unsigned permanent
builds, and eight platform probes. Authenticated local-XPC candidate delivery,
live observation, Agent product emission, ScreenCaptureKit crop construction,
and automatic iOS application remain the next safe lanes; signed TCC and
physical evidence remains open.

The following [authenticated focus-candidate local XPC](evidence/2026-08-23-authenticated-focus-candidate-xpc.md)
extends that family to ten closed operations. One canonical request/reply binds
the exact current session, epoch, surface, surface revision, and coordinate
revision while carrying only the sanitized target/focus/reason/input-paused
candidate. The menu retains current global input bounds, assigns opaque stable
focus identity from the reduced tuple, and—when an existing Focused Region
changes—releases posted input once and keeps new input closed until the normal
replacement acknowledgement. The full gate passes 73 fixtures, the 1,488-test
Swift catalog, all cross-builds/unsigned permanent builds, and eight platform
probes. A permanent Agent observation/event owner, focused-region capture crop,
automatic iOS application, and signed physical evidence remain open.

The [permanent focus-event observer](evidence/2026-08-23-permanent-focus-event-observer.md)
now closes the live Agent publication lane. It polls only when the exact
server-issued primary connection ID still matches the acknowledged Interactive
session, fences menu-generation replacement across suspension, creates the
ordered one-use event through the existing Agent surface authority, and sends
through the current authenticated primary's serialized write lane. Publication
failure revokes the token and closes surface control. The full gate passes 73
fixtures, the 1,493-test Swift catalog, all cross-builds/unsigned permanent
builds, and eight platform probes. Focused-region ScreenCaptureKit crop
construction, automatic iOS Smart Zoom application, and signed physical
evidence remain open.

The [live Focused Region Smart Zoom checkpoint](evidence/2026-08-23-live-focused-region-smart-zoom.md)
now constructs the bounded ScreenCaptureKit crop and applies the authenticated
event in the permanent iOS product. The menu re-reads the exact reduced focus,
uses display-logical `sourceRect` with global input bounds, and retains an
application-limited display filter for Window-origin Smart Zoom because
ScreenCaptureKit ignores `sourceRect` on single-window filters. The selected
client buffers the first-acknowledgement promotion race, disables input across
the existing two-phase replacement exchange, updates the live descriptor only
after exact acknowledgement, and makes automatic following explicitly
reversible; every manual surface selection opts out. The full gate passes 73
fixtures, the 1,499-test Swift catalog, all cross-builds/unsigned permanent
builds, and eight platform probes. Signed two-process TCC execution, physical
crop pixels, physical-iPhone focus latency/usability, multi-display edges, and
lock behavior remain open without blocking other safe lanes.

The [signed physical launch baseline](evidence/2026-08-23-signed-physical-launch-baseline.md)
now advances the external evidence lane without changing tracked signing
authority. Fresh invocation-only Apple Development builds pass strict
signature inspection for the iOS app and the Mac containing app plus embedded
Agent. The iOS app installs, launches, and survives on a paired physical iPhone
17 Pro Max running iOS 27 beta; the signed Mac containing app launches a live
menu-bar process and status-item scene while the Agent remains absent. The
available iOS profile is wildcard development only, and an unrelated
foreground-app screenshot is intentionally rejected as visual evidence.
Explicit Remote Access enablement/Agent registration requires action-time
confirmation; privacy consent, reciprocal local-XPC readiness, physical
pairing, Observe, Act, Control, and distribution evidence remain open.

The [direct-update trust policy](evidence/2026-08-23-update-trust-policy.md)
now freezes Sparkle 2.9.6 at full upstream revision
`ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a`, distinct release-injected
beta/stable authorities, signed feeds, pre-extraction verification, Ed25519 and
Developer ID trust, notarized whole-bundle replacement, and no initial delta or
installer-package path. A five-minute foreground confirmation is cancelled on
foreground loss; install remains closed until network admission, Control,
bounded work, Agent shutdown, and version compatibility all converge safely.
Thirty-five fixtures pass. The [Sparkle provenance and topology audit](evidence/2026-08-23-sparkle-provenance-and-topology-audit.md)
now binds the clean full revision, upstream manifest, official binary archive,
shared license, safe ZIP/symlink/Mach-O shape, absent upstream privacy manifest,
disabled profiling/custom parameters, and the exact three-object retained
non-sandboxed runtime graph. The subsequent
[exact dependency admission](evidence/2026-08-23-exact-sparkle-dependency-admission.md)
now binds the package and shared resolution, embeds only the required framework,
disables static profiling, strips the XPC services and release tools from
archives, verifies the unsigned three-object topology, and corrects the source
SBOM. No updater object, feed, key, appcast, download, or update action exists
yet.

The [update installation runtime gate](evidence/2026-08-23-update-install-runtime-gate.md)
now admits only a same-channel, increasing-build candidate with every frozen
feed/archive/Developer ID/notarization fact, then serializes five-minute local
foreground confirmation, inactive Control, network-admission closure,
bounded-work drain, Agent stop, exact version match, and one updater handoff.
Every stage rechecks expiry and foreground state; failed partial shutdown
records network-only or Agent-plus-network reconciliation, and reentrant
events cannot relabel consumed handoff authority. Twelve focused tests and the
full 1,511-test gate passed at that checkpoint. The subsequent
[inert Sparkle runtime adapter](evidence/2026-08-23-inert-sparkle-runtime-adapter.md)
adds a bounded release-authority value, unresolved protected build placeholders,
no-authority/no-updater construction, disabled profiling/parameters/headers,
disabled automatic checks/downloads, an explicit informational-probe-only menu
surface, and a fail-closed prohibition on download or installation checks. Its
nine focused tests and the full 1,520-test gate pass. Protected feed values,
Sparkle validation callbacks, signed two-version upgrade, and rollback evidence
remain open. The subsequent
[exact update candidate admission](evidence/2026-08-23-exact-update-candidate-admission.md)
now correlates the reviewed feed item with an independent post-validation
observation, requires all six trust facts, closes direct production construction
of the lower-level candidate, and mints at most one runtime authority. Five new
tests brought that checkpoint to 1,525. The subsequent
[runtime shutdown orchestration](evidence/2026-08-23-update-runtime-shutdown-orchestration.md)
seals the lower-level authority from production consumers, rechecks
foreground/time/Control at every transition, runs the exact four-effect order,
and completes the minimum recorded recovery scope before returning failure.
Five further tests bring the full gate to 1,530; no live updater action ran.
The subsequent
[signed update publication binding](evidence/2026-08-23-signed-update-publication-binding.md)
requires a successfully validated signed appcast, a bounded nonzero archive
length, and one canonical 64-byte Ed25519 signature at informational-candidate
construction, then matches the length and signature exactly at later
admission. An exact Sparkle 2.9.6 source audit also closes an unsafe inference:
`didExtractUpdate` does not attest notarization, and an Ed25519-valid archive
may carry a changed Apple signing identity. Developer ID and notarization facts
therefore remain unavailable until a protected release-evidence bridge binds
them to the same candidate. Two new tests bring the passing full count to
1,532; no live feed, download, extraction, or install action ran.
The subsequent
[update release-evidence projection](evidence/2026-08-23-update-release-evidence-projection.md)
replaces the three release-trust Booleans with a typed, exact-candidate-bound
value carrying five canonical artifact/evidence digests and four required
passing release claims. The permanent adapter now rejects an informational
item unless its signed enclosure has exactly the 17 frozen custom attributes;
unknown, missing, malformed, failed, or substituted fields close the offer.
Five new tests bring the passing full count to 1,537, while every Sparkle
download and installation check remains denied.
The subsequent
[update validation-correlation checkpoint](evidence/2026-08-23-update-validation-correlation.md)
wraps the exact candidate and release evidence in one immutable published value
and makes the lower-level admission owner package-internal. The corrected
single-use actor correlates exact `willExtract` and installer-start events but
does not treat Sparkle 2.9.6's `didExtractUpdate` as validation completion.
Admission opens only at the later `showReadyToInstallAndRelaunch` hold point,
after asynchronous validation and stage-one preparation; mismatch, evidence
substitution, reordering, cancellation, concurrency, or reuse closes it. Seven
tests cover the corrected lifecycle and keep the passing full count at 1,544.
The app still implements none of these callbacks and still cannot start a
download or install.
The subsequent
[Sparkle ready-to-install hold-point bridge](evidence/2026-08-23-sparkle-ready-holdpoint-bridge.md)
adds a compile-verified complete `SPUUserDriver` proxy in the permanent app and
serializes exact `willExtractUpdate` and installer-start callbacks into the
package actor. It intercepts the later readiness reply but cancels with
`.skip`; the source validator rejects an unconditional `.install` reply and
all full/background update checks. The real foreground confirmation and
runtime-effect owner remain open, so no download or installation authority is
enabled.
The subsequent
[update Agent reactivation saga](evidence/2026-08-23-update-agent-reactivation-saga.md)
addresses the Agent's `KeepAlive=true` replacement constraint. One package
owner persists exact source/candidate recovery intent before completed Agent
unregister and advances it only after the process is gone; failure recovery and
startup repair re-register only the exact source or candidate build and clear
the receipt after matching authenticated Agent readiness. Eight injected tests
pass. No live registration or updater action ran; the atomic store and concrete
platform bindings remain open.
The subsequent
[atomic update Agent reactivation store](evidence/2026-08-23-atomic-update-agent-reactivation-store.md)
adds canonical closed receipt encoding and a private, lock-serialized,
no-follow, fsync/rename/directory-fsync compare-and-swap store. Eight tests
cover reopen, phase advance, clear, faults, unsafe filesystem entries, and
concurrent writers. A cached-URL-size mismatch found by the tests was removed
in favor of sole descriptor `fstat` authority. No live Application Support or
Agent mutation ran.
The subsequent
[authenticated Agent build attestation](evidence/2026-08-23-authenticated-agent-build-attestation.md)
extends the reciprocal signed-peer hello acknowledgement with one exact
`UInt64` Agent bundle build, rejects malformed or open dictionaries in C, and
adds a bounded startup-only probe that always cancels its session. Focused
local-XPC tests pass without launching an Agent. Registration state and the
embedded helper file are no longer candidates for running-build evidence; app
startup repair and active-dashboard observation remain to be wired.
The subsequent
[update Agent startup-repair binding](evidence/2026-08-23-update-agent-startup-repair-binding.md)
closes the first of those two wiring gaps. The permanent containing app now
constructs the private atomic store, closed registration mapping, converging
ServiceManagement effects, and bounded authenticated-build readiness, then
runs retained-receipt repair before route reconciliation or dashboard
construction. Missing receipt is effect-free; composition or repair uncertainty
routes unavailable. Seven adapter tests, 49 application-platform tests, and an
unsigned permanent-app build pass. The complete gate passes 1,575 package
tests plus 8 platform probes. No app, Agent, login role, XPC session, or updater
action ran; active-dashboard build retention and runtime shutdown binding
remain next.
The subsequent
[active-dashboard Agent build lifetime](evidence/2026-08-23-active-dashboard-agent-build-lifetime.md)
now retains that exact hello build for one dashboard connection, clears it on
every terminal or ambiguous connection path, and gives production consumers no
mutation API. The permanent app shares the same lifetime with its dashboard and
its candidate-bound Agent-stop factory; startup repair still uses the bounded
one-shot probe. Six focused tests and the unsigned app build pass. The factory
is not invoked, and the complete gate passes 1,579 package tests plus 8 platform
probes. Network close, bounded drain, updater handoff, live Agent shutdown, and
Sparkle installation remain closed.
The subsequent
[reversible update network quiescence](evidence/2026-08-23-reversible-update-network-quiescence.md)
separates reversible listener admission from terminal Agent shutdown, adds
exact authenticated menu-to-Agent close/drain/reopen commands, and composes
them around the existing Agent-stop saga. Race, role-drain, exact-envelope,
authorization, generation, dashboard-lifetime, and minimum-recovery tests pass
without starting any app, Agent, listener, XPC service, login role, or updater.
The complete gate passes 1,590 package tests plus 8 platform probes. The
permanent app still supplies no prepared-installer adapter, so Sparkle's hold
point remains `.skip`; signed two-version execution remains open.
The subsequent
[dashboard update reconciliation](evidence/2026-08-23-update-dashboard-reconciliation.md)
now binds app-level close/drain forwarding to the exact active dashboard and
supplies the shutdown coordinator an inert product-router recovery closure.
Reconciliation is single-flight; explicit current-generation command failure
is retried, unavailable or ambiguous current transport is replaced immediately,
and only one registration-gated replacement may receive up to 40 readiness
attempts at a 250-millisecond cadence. Replacement ambiguity, exhaustion,
registration loss, cancellation, or lifecycle loss stays closed. Six focused
tests pass. The permanent app still has no prepared-installer adapter, and no
app, Agent, login role, XPC service, listener, network connection, or updater
was started. The complete gate passes 1,596 package tests plus 8 platform
probes.
The subsequent
[one-shot prepared-installer reply](evidence/2026-08-23-one-shot-prepared-installer-reply.md)
adds a main-actor owner for the coordinator's final updater effect. Install can
resolve once; explicit cancellation and owner retirement resolve skip; reuse
fails closed. The permanent Sparkle hold point constructs this typed adapter
but still cancels it, while source validation permits the sole install reply
only in the exact closed mapping and forbids any permanent-app start call. Four
focused tests pass. Full update checks, foreground confirmation, coordinator
construction, listener mutation, Agent stop, and installation remain closed;
the complete gate passes 1,598 package tests plus 8 platform probes.
The subsequent
[foreground update-installation owner](evidence/2026-08-23-foreground-update-installation-owner.md)
constructs one main-actor lifecycle around the exact same prepared reply and
runtime coordinator. It serializes confirmation/cancel/install, fences a
suspended confirmation on foreground loss, forwards loss during shutdown into
minimum-scope recovery, maps Control and effect failures to closed presentation
states, and retires unresolved authority on owner loss. Four focused tests
pass. The package owner is not yet bound into the permanent Sparkle callback,
so full update checks, UI confirmation, listener mutation, Agent stop, and
installation remain closed; the complete gate passes 1,602 package tests plus
8 platform probes.
The subsequent
[inert permanent update-runtime composition](evidence/2026-08-23-inert-permanent-update-runtime-composition.md)
carries the validated candidate build on the single-use admission, constructs
the exact candidate-bound Agent-stop owner, requires the current authenticated
dashboard for close/drain, obtains product-router recovery, and samples explicit
application foreground plus indicator-derived inactive/active/cleanup-
uncertain Control state. Focused candidate and indicator tests plus the
permanent source validator pass. The app retains the effect-inert composition,
but Sparkle cannot invoke it; confirmation presentation and safe application-
termination deferral remain next. The complete gate passes 1,602 package tests
plus 8 platform probes.
The subsequent
[ordered update termination barrier](evidence/2026-08-23-ordered-update-termination-barrier.md)
adds a terminal waiter to the foreground owner and proves termination during a
suspended shutdown closes authority, emits skip, and returns only after the
coordinator reaches its recovered terminal state. The permanent AppKit delegate
now returns `terminateLater`, cancels/joins Sparkle validation, awaits product
finish, and replies explicitly instead of relying on best-effort
`applicationWillTerminate` cleanup. Five focused owner tests and the permanent
source validator pass. The ready callback remains unbound; complete-gate counts
are 1,603 package tests plus 8 platform probes.
The subsequent
[permanent update confirmation binding](evidence/2026-08-23-permanent-update-confirmation-binding.md)
binds Sparkle's held ready callback to the exact validation correlation,
candidate-matching permanent runtime composition, one-shot prepared reply, and
foreground installation owner. The menu now presents explicit `Not Now` and
`Install and Restart` decisions, forwards foreground loss, and joins the owner
and its task during ordered termination. The checked-in Xcode project includes
the runtime source, the permanent source validator passes, and an unsigned
Xcode 27 beta app build succeeds. Ordinary checks still call only
`checkForUpdateInformation`; full/background checks, real download/extraction,
listener mutation, Agent stop, and updater handoff remain disabled pending the
signed two-version lane and physical confirmation/recovery evidence.
The final complete gate passes 1,603 package tests plus 8 platform probes; no
package-test count changed in this source-only permanent-target binding.
The subsequent
[release-gated user update check](evidence/2026-08-23-release-gated-user-update-check.md)
adds an exact typed execution profile around the validated release channel and
installed build. Its absence keeps `Check for Updates` information-only;
malformation invalidates the updater; its exact presence upgrades only that
visible action to Sparkle's user-initiated full check. Automatic/background
checks and downloads stay disabled. Two focused authority tests, dependency
and permanent-source validators, and an unsigned app build pass. No check,
network, download, extraction, listener, Agent, or installer action ran. Signed
two-version execution and release-manifest binding remain protected evidence
work.
The complete gate passes 1,605 package tests plus 8 platform probes.
The subsequent
[signed-candidate update-profile binding](evidence/2026-08-23-signed-candidate-update-profile-binding.md)
advances release evidence to v0.2 and makes the Mac foreground update-check
profile an exact target-scoped candidate fact. File verification reads the
bounded canonical application archive's `Info.plist`, normalizes absent or
empty configuration to information-only, and rejects unknown values or any
manifest/archive mismatch. Local Mac packaging also rejects unknown profiles
and records the normalized value in its non-promotional summary. Focused
release, packaging, SBOM, and packaging-equivalence suites pass without
mounting a disk image or running an updater. Signed two-version and physical
recovery evidence remain open.
The complete gate passes 1,605 package tests plus 8 platform probes.

The subsequent
[closed Mac update physical-evidence matrix](evidence/2026-08-23-mac-update-physical-evidence-matrix.md)
replaces opaque promotion-ready upgrade/rollback files with one canonical
twelve-case record bound to the exact candidate, source revision, reviewed
full-check profile, and three release artifacts. Exact observed source or
candidate builds are required for decline, foreground/Control denial,
transition-specific forced loss, successful upgrade, rollback, clean-user, and
no-background-network cases; all thirteen source/case observations are
distinct and transitively verified. Sixteen focused cases pass without running
an app, updater, network, installer, rollback, signing, notarization, or mount.
Signed physical capture remains open.
The subsequent
[closed Mac lifecycle physical-evidence matrix](evidence/2026-08-23-mac-lifecycle-physical-evidence-matrix.md)
closes the other four promotion scenarios around one exact candidate. Its
quarantine, clean-install, permission-revocation, and complete-uninstall cases
fix ordered assertions and exact candidate/removal outcomes, with four
distinct transitively verified observations. Sixteen focused cases pass
without launching or mutating an app, Agent, login role, permission, listener,
pairing, product data, installer, signer, notary service, or publication.
Physical execution remains open.
The subsequent
[closed iOS physical-evidence record](evidence/2026-08-23-ios-physical-evidence-record.md)
replaces the three opaque iOS promotion files with one exact-archive record.
Pairing binds QR/SAS/pin/key-custody facts plus Observe and consented
`setAudioMuted`; Local Network denial must publish no route or broader
authority before same-pin recovery; background reconnect must retire Control,
avoid operation replay, respect first unlock, and require fresh presence.
Sixteen focused cases pass without installing, launching, pairing, prompting,
networking, backgrounding, reconnecting, invoking, or publishing.

## 2026-08-29 pre-physical signed end-to-end checkpoint

The current disposable signed boundary is integrated rather than merely
adjacent. Three exact-source signed Agent + Simulator journeys pass pairing,
durable reconnect, verified Observe, bounded `setAudioMuted`, Control grant and
lease, rendered media, pointer, verified focus/automatic Smart Zoom, native and
ordinary iOS keyboard paths, Stop-to-Observe, client restart,
background/foreground and route-loss recovery. Their shared fingerprint and
cleanup records are in
[the checkpoint](evidence/2026-08-28-signed-agent-simulator-observe-act.md).
The complementary current 55-case signed Agent/XPC matrix covers Agent
graceful/crash restart and adversarial admission/revocation boundaries.

The exact-current full Simulator suite passes 16/16 in 910.204 seconds after
repairing a late terminal render-receipt race and removing Xcode 27 per-key
idleness dependence from the semantic keyboard test. Three generated and three
test-owned real-window live repetitions also pass. Day 1 of a fail-closed,
source-bound seven-date soak is retained in
[`prephysical-soak-ledger.json`](evidence/prephysical-soak-ledger.json). The
daily task was paused at the user's request on 2026-08-29 after preserving Day
1. This is not a seven-day result yet, and no later date will be added unless
the task is explicitly resumed.

The short-duration pre-physical automated gate is now reconciled in
[the 2026-08-29 checkpoint](evidence/2026-08-29-prephysical-automated-gate.md).
Full repository validation and explicitly unsigned, artifact-free release
evidence pass. A source-bound 199.018-second Simulator resource baseline is
retained without treating Debug/Simulator CPU and memory as release budgets.
The [physical acceptance checklist](physical-acceptance-checklist.md) now
consolidates every hardware and release-only remainder. The closed
[performance acceptance profile](../spec/performance-acceptance/v0/README.md)
machine-checks the existing latency, media, durable-cap and soak numbers and
keeps eight evidence-dependent physical measurements explicitly unresolved.
The sole unfinished
automated requirement is six later dates and 518,400 actual elapsed seconds in
the same seven-date soak campaign. Physical iPhone custody, installed
app/Agent lifecycle, final TCC/Keychain, user-owned content, LAN/Bonjour,
stable Xcode 26.6 distribution evidence, signing/notarization/publication and
real-device usability remain separate physical or external gates.

The [Agent startup and signed menu-handshake stress gate](evidence/2026-08-29-agent-startup-handshake-stress.md)
also passes two independent 100-cycle runs against current source. All 200
cycles meet the unchanged ten-second deadline; 50 production-presentation
cycles complete the signed menu handshake, generated presentation flow and
graceful shutdown. Exact disposable jobs and state are absent after both runs.

The [pre-physical completion audit](evidence/2026-08-29-prephysical-completion-audit.md)
is machine-checked as `supersededSource`. It retains the old campaign under its
exact fingerprint but makes no readiness claim for the current worktree. The
current Stage 2 candidate must pass its own validation, physical checks, and a
new exact-source campaign after source freeze.

The old soak scheduler remains paused by explicit user request. Its ledger is
authoritative historical evidence at 1/7 UTC dates; it will not be resumed or
rebound. A distinct campaign may begin only for the frozen candidate.

## 2026-08-30 primary keepalive and congestion recovery

The [source checkpoint](evidence/2026-08-30-primary-keepalive-and-congestion-recovery.md)
adds authenticated ping/pong liveness, a bounded recoverable
Network.framework waiting state, immediate Control-role safety fencing during
uncertain connectivity, and nonterminal encoded-media queue backpressure.
Canonical fixture validation, 141 focused tests, and the complete repository
gate pass. A later exact-source repair prevents a slow diagnostic dashboard
status read from revoking the authenticated XPC generation and unrelated
Control lease. Fresh signed Mac, iPad, and iPhone candidates from `f301469`
passed strict verification and were installed without clearing device data,
pairing, grants, or privacy settings. Both physical clients remained connected;
one explicit Stop cleanly revoked its first Control runtime and a fresh runtime
then passed at least 83 consecutive lease renewals. The new source-bound soak
campaign passed its first 199.421-second run and remains honestly incomplete at
one of seven UTC dates. A later two-device process checkpoint terminated and
relaunched the active iPad client, rejected a stale input endpoint, and installed
a fresh Control runtime; terminating and relaunching the idle iPhone then left
that iPad runtime uninterrupted while the Agent admitted the replacement
primary and retired the stale one at its deadline. The Control lease advanced
from counter 9 through counter 31 across the iPhone overlap, and the final
socket inventory returned to two primaries plus input and media. Recovery keeps
the exact authenticated primary where Network.framework permits it but does
not silently reuse or restart Control authority; a new explicit Control request
remains required after the roles are retired. A subsequent normal menu-app quit
retired Control with `localStop` and relaunched a fresh menu process while the
Agent stayed available. A launchd Agent restart then replaced the process,
restored its private listener and local-XPC menu connection, and admitted one
fresh physical-client primary without restoring old Control roles. The second
client's post-Agent reconnection and a fresh user-present Control request remain
human-visible checkpoints.

## Blocker handling rule

Every blocked item records its affected artifact, evidence needed to unblock it, and parallel work. The project is not globally blocked while any safe in-scope lane remains active or ready. A later-stage capability is complete only with passing exit evidence or an explicit evidence-backed `no-go` or `deferred` disposition.

Production-wrapper acceptance update: both factory rejection tests, stable repository validation, the refreshed six-framework inventory and four visible native Simulator sessions pass. Keyboard/modifier/shortcut/pointer delivery, background and route recovery, Stop/Observe and cleanup remain verified through the synthetic final input sink. See the [production wrapper evidence](evidence/2026-09-27-production-managed-host-wrapper.md) for exact source and report bindings. Signed normal-root selection, the final packaged supervisor, installation and actual input/physical acceptance remain next.

Normal iOS promotion regression acceptance: four visible native sessions passed
with typing/modifiers/shortcuts/pointer, background and route recovery,
Stop/restart and fresh Observe; cleanup was verified. These use the promoted
adapters in the signed harness with substituted custody/consent and synthetic
final input. The [normal iOS evidence](evidence/2026-09-27-normal-ios-native-development.md)
retains exact reports and the separate normal app storage limitation.

Archive-package fresh acceptance update: four visible native Simulator sessions
passed against the exact archive-rebuilt package with video, keyboard/modifiers/
shortcuts/pointer, background and route recovery, Stop/restart, fresh Observe and
verified cleanup. The [rebuilt package evidence](evidence/2026-09-27-archive-rebuilt-portable-host.md)
retains the report and source/package bindings. Final input effects are synthetic;
normal installed-app and physical acceptance remain open.

Selected capture prerequisite: [App/Window geometry and retained selection](evidence/2026-09-27-native-selected-capture-projection.md)
is implemented with exact scope/lease checks, selected bounds/backing scale and
menu-local ScreenCaptureKit objects. Focused tests and stable validation with
113 fixtures pass. Native App/Window capture is still unavailable: the managed
Sunshine implementation and runtime/client gates remain Desktop-only. Continue
with isolated selected-surface capture and actual sample evidence, then rebuilt
normal Simulator acceptance. No physical or installed normal Mac result is
claimed by this checkpoint.

Selected capture API checkpoint: the [native stream adapter and Sunshine API](evidence/2026-09-27-native-selected-stream-adapter.md)
pass fifteen component lifecycle/sample cases, three bridge conditions and a
complete source-built host compile/link/readback. A real descriptor double-close
found during validation is repaired in both local stores; all 131 Agent platform
tests pass. Final stable validation with 114 fixtures passes. Per-operation selected-surface
handoff and actual capture evidence remain next; normal runtime/client enrollment
is still Desktop-only, and App/Window playback has not been accepted.

Selected capture process handoff checkpoint: the [managed selected capture context](evidence/2026-09-27-managed-selected-capture-context.md)
binds the committed menu target to one private operation and makes the source-built
Sunshine child revalidate its exact process/window, bounds, scale and expiry.
Unsafe records and changed targets fail closed without Desktop fallback. The
source-pinned disposable host compiles/links both first-party ARC classes;
focused native/Swift tests and stable validation with 115 fixtures pass.
Normal backend/runtime/client gates are still Desktop-only. Actual selected
frames, fresh normal Simulator playback, viewport bitrate, current source
assembly and installed/physical acceptance remain open.

Selected App/Window live capture checkpoint: the [signed Mac probe](evidence/2026-09-27-selected-app-window-live-capture.md)
receives real Window and App frames through a private operation context and the
first-party ScreenCaptureKit adapter. The live test exposed and fixed a retained
color crash plus legitimate sample resampling and tiny timestamp skew. The
normal Mac backend owner now routes an exact current selection into the native
factory; 23 focused Swift cases and 17 native sample cases pass, and the final
source-built host links the capture classes. This proves the capture component,
not normal child playback: normal runtime/client transition and native
re-enrollment remain Desktop-only, with fresh Simulator, installed Mac and
physical acceptance still pending.

Selected capture admission safety: the same [live capture checkpoint](evidence/2026-09-27-selected-app-window-live-capture.md)
now binds the acknowledged surface kind into the canonical local native snapshot.
Receipt decoding still admits Desktop only; the backend owner requires a matching
menu-selected object for any future App/Window admission. Focused backend and
snapshot rejection tests pass. Normal App/Window playback remains pending.

Native session reliability checkpoint: the [normal app soak and iPhone update](evidence/2026-09-28-native-session-soak-and-device-refresh.md)
repairs an early display catalog/selection reply hang. The exact updated normal
iOS source passes two ten-session Simulator Control start/Stop soaks and a
30-minute single-session Simulator hold with continuing host video and input.
A disposable bridge handoff adjustment also passes ten sessions followed by
another ten sessions with 120 immediate post-Stop status reads, idle capture
and media cleanup, and Simulator restoration. Stable validation passes with
116 fixtures. An earlier repeat-run Stop-status transport failure remains an
intermittent risk because its exact cause is unproven. The updated development
iOS app is installed on the paired iPhone 18 Pro Max, but iOS denied launch
while the phone was locked. Physical playback, actual Mac input, installed Mac
GUI capture, viewport bitrate and release gates remain open.

Normal Control toolbar recheck: the [current Simulator evidence](evidence/2026-09-28-normal-native-app-window-simulator.md#shortcut-and-control-toolbar-recheck)
records the simulator-only setup warning leaving paired Control controls
touchable. Fresh normal-app Desktop, selected App, and selected Window paired
Simulator journeys each pass Copy, Shift+Tab, keyboard and pointer delivery,
three native presentations, Stop/restart, key cleanup, host cleanup and
Simulator restoration. The required Xcode 27.0 validation passes with 116
indexed fixtures. The physical iPhone remained locked at the attempted launch;
installed-app playback, real Mac input, installed Mac GUI capture, viewport
bitrate and release acceptance remain open.

Native client continuity checkpoint: the [one-minute frame-progress evidence](evidence/2026-09-28-native-frame-continuity.md)
adds a content-free, Debug-only count of picture samples accepted by the iOS
display layer. A paired normal-app Simulator hold passed six rising host media
checks and 20 client progress checkpoints with no stalled checkpoint, despite
four Sunshine IDR-request errors. A current-source selected Window journey
also passed with client frame progress. Full validation passes with 116 indexed
fixtures. The matching normal iOS development app was signed and installed in
place on the paired iPhone; device inventory confirms it. The phone was locked
at the attempted launch, so physical playback, actual Mac input, installed Mac
GUI capture, bandwidth/latency and viewport bitrate remain open.

Selected Window disappearance checkpoint: the [normal-app recovery journey](evidence/2026-09-28-selected-window-close-recovery.md)
closes a disposable selected Window during native playback. The paired iOS
Simulator app shows a failed-session recovery action with Remote Keyboard
disabled; tapping it restores the ability to request Control. The signed Mac
backend invalidates its local endpoint and terminates the managed video host.
One final UI journey, client-key cleanup, host cleanup, and Simulator-state
restoration pass. This adds selected Window loss recovery evidence, while
physical playback, real input, installed Mac GUI capture, bandwidth/latency,
and viewport bitrate remain open.

Selected Window geometry checkpoint: the [move and resize recovery evidence](evidence/2026-09-28-selected-window-geometry-recovery.md)
adds disposable, ready-synchronized Window geometry changes. Move, resize,
and the synchronized close regression each pass normal paired iOS Simulator
fail-closed recovery with old keyboard authority disabled and a usable
failed-session Stop action. A replacement signed disposable Mac menu now passes
the stronger fresh-stream restart check after resize, including sustained
frame progress and a clean final Stop. Installed Mac dashboard recovery and
physical iPhone playback remain unverified.
Automatic geometry re-enrollment also remains unverified.
Two no-delay rapid Stop runs after the restarted keyboard enabled also pass
clean backend retirement, but an earlier run lost the local test endpoint at
this step. Intermittent teardown behavior remains open.

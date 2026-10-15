# Direct macOS Screen Sharing development profile v1

The iOS Desktop local text-extraction tool is specified in
[Copy Text from Screen](copy-text-from-screen.md).

Decision: 2026-10-04. The normal iOS VNC development composition is a standalone
client of built-in macOS Screen Sharing, with no Mac Companion host or Agent.
The historical paired protocol remains compatible but is not instantiated here.
This is a separate connection profile, not an unauthenticated fallback from a
failed paired connection. Permanent Release admission is still gated.

## Connection and authentication

Transport revision: 2026-10-09. Desktop and Trackpad & Keyboard MUST use SSH
to the Mac's built-in Remote Login service, then built-in Screen Sharing through
that encrypted connection. Both services must be enabled; no Mac helper is installed.
There is no direct plaintext RFB fallback.

Connect to the user-selected saved Mac's ordered list of 1–8 endpoints, SSH TCP
port 22 by default, optionally 1–65535 in Advanced settings. Resolve
once, validate each numeric sockaddr, then connect to that exact sockaddr; there
is no second hostname lookup after validation. IPv4 permits RFC1918, loopback
and link-local unicast, plus shared-address-space 100.64.0.0/10 for private VPN
routes such as Tailscale. This range is not proof of a Tailscale tunnel. IPv6 permits loopback, unique-local and link-local
unicast (requiring an interface scope for link-local). IPv4-mapped IPv6 follows
the IPv4 rules. Reject unspecified, multicast, limited broadcast and public addresses.
For one address, resolver wait and TCP connection each have at most eight seconds.
For multiple addresses each phase has at most two seconds, with a sixteen-second
total connection budget. Try configured addresses in order only until TCP succeeds.
Authentication/protocol failures do not advance to another address or retry credentials.
Only explicitly saved addresses are eligible; no inferred alternate hosts are added.
All waits are cancellable. Stop/background cancels a pending handshake; a new connection
waits for the preceding native owner to finish, never overlaps it.

Verify the SSH host key before sending a login. Reuse the saved Mac UUID's SSH
host pin used by Terminal, but never its login or private keys. First use requires
explicit approval of the server fingerprint before saving the pin in the
non-synchronizing, WhenUnlockedThisDeviceOnly Keychain. A changed key, rejected
trust, unavailable Keychain, authentication failure or denied forwarding fails
closed without retrying another address or a plaintext connection.

Authenticate SSH with the entered Desktop Mac account and password. Open one
RFC 4254 `direct-tcpip` channel to **127.0.0.1** on the saved Screen Sharing port
(5900 by default). The forwarding host is fixed; never forward to another host
or create a local TCP listener. SSH authentication has a cancellable 60-second
deadline including fingerprint approval; forwarding has a 10-second deadline.
A socket pair transfers this channel to the existing native RFB owner. Read in
16-KiB chunks. Apply backpressure independently in each direction: pause a
source reader when its own pending writes reach 64 KiB or its destination
channel is unwritable. Pending writes in the reverse direction must not block
that reader. Resume the source reader when its own writes complete or its
destination becomes writable. Close both bridge ends if queued bytes in either
direction exceed 2 MiB. Configure the Desktop SSH maximum packet size to
1 MiB; the pinned NIOSSH implementation also uses that value as its incoming
channel window. The 2-MiB hard relay limit leaves bounded room for a permitted
packet already in flight when the write watermark is reached. This avoids the
128-KiB default window limiting bulk desktop delivery on higher-latency links.
Terminal and Files settings are unchanged. EOF, cancellation and errors close owned descriptors
and channels without replay. Retire the preceding native owner and tunnel before
starting another. Native input releases finish before an established tunnel is
closed; pending handshakes and fingerprint prompts are cancelled immediately.

Inside the encrypted channel the only RFB authentication scheme remains Apple ARD (30) using the
pinned upstream implementation. No no-auth or legacy VNC-password fallback is
allowed. No application pairing/authentication/signature semantics are added.
Login fields must be nonempty, contain no NUL, and fit the upstream 63-byte UTF-8
payload without truncation. Credentials are supplied only to this selected
endpoint. No logs contain credentials, host addresses, names, typed content,
framebuffer pixels or cursor shapes/positions.

Pinned upstream `HandleARDAuth` encrypts the login structure only. SSH provides
server identity verification and encryption of the complete RFB pixel/input
stream. Describe this SSH transport accurately, without inheriting application
pairing or grant claims from the historical paired protocol. Deployment and
physical-device acceptance remain separate release gates.

## Saved Macs and credentials

Store UUID, display name, ordered addresses and port in the direct library. Schema
version 2 reads version-1 single-address records without changing UUIDs or logins;
the next successful edit writes version 2 atomically. The schema is
versioned, capped at 64 records and rejects duplicate UUIDs, duplicate addresses
within one record or malformed records. Different saved Macs may share the same
address/port, including profiles for different accounts. Show an informational
shared-endpoint note in the editor; it must not block saving or combine records.
Write atomically before publishing in-memory changes. Read failure is visible
and never silently overwrites an existing unreadable library.

Mac labels are trimmed, nonempty, at most 80 characters and contain no Unicode
control/format scalars. Named SSH keys use the same control/format rejection.
Ordinary ASCII and Unicode labels MUST retain identical acceptance in Debug and
optimized internal-distribution builds; optimization must not mark valid saved
records unreadable. Validate the actual native predicates in both configurations
against the indexed name cases. Preserve UUIDs, logins and the existing file.

The Add/Edit Mac form exposes editable fields directly. Address reordering uses
a Reorder/Done control within Connection Addresses when multiple addresses exist;
the navigation bar contains Cancel and Save. An empty or whitespace-only port
field means the default port 5900. A nonempty port must parse as an integer in
1–65535; invalid values cannot save. Use the same resolved port for validation,
shared-endpoint information and persistence. Show the default in the empty field
and explain that leaving it blank uses 5900.

Use a distinct direct-login Keychain service, WhenUnlockedThisDeviceOnly,
non-synchronizing and without session presence prompts. Save only after a
successful login when the user opted in; show retention failure. Turning off
retention, explicitly forgetting the login or removing its record deletes its
direct login. Address additions/removals/replacements, port edits, reordering
and renaming preserve the login for the same saved Mac UUID. Addresses are
explicitly user-configured routes for that saved Mac; changing an address does
not establish a cryptographically verified host identity. If an entry is being
repurposed for a different Mac/account, its login can be forgotten explicitly.
Saved logins are keyed by Mac UUID, never by shared app-wide username. Native
Password AutoFill remains user selected; arbitrary Screen Sharing hosts have no
associated-domain credential matching guarantee. Show the selected Mac clearly.
Legacy pairing records and their Keychain entries are neither deleted nor reused.

## Presentation and lifecycle

One native RFB owner handles framebuffer updates and ordered pointer/key input.
Prefer lossless Zlib, then Hextile and Raw pixel encodings. Do not advertise
ZRLE or ZYWRLE with the pinned 0.9.15 decoder: its tile-error path can return
success without filling the rectangle. A fixed-format decoder error must
invalidate that update, prevent presentation and end with recovery stage 103.
Never count a failed decode as baseline coverage or a successfully opened desktop.
Valid fully black desktops remain valid; pixel color is not a readiness check.
Reuse the existing framebuffer/cursor bounds and one-shot modifier contracts.
Display/zoom/pan gestures do not reconnect RFB. The client advertises Apple Display Info (1101), then Display Layout (1105), using the
pinned library extension interface. The legacy 1101 capability enables display-info
delivery in the macOS server; 1105 chooses the newer layout record format.
Consume a length-prefixed 1101 reply without applying legacy geometry.
Decode the length-prefixed 1105 payload only for
version 5: a 20-byte header (version, logical width/height, backing width/height,
eight opaque bytes, display count), followed by 56-byte records. Record offsets
16 and 28 carry a big-endian display ID and backing rect (y0,x0,y1,x1).
Accept 1–32 unique IDs and positive rectangles fully inside backing dimensions
(up to 16384 per axis). Ignore opaque/trailing fields within the uint16 body
length. Consume unsupported/malformed bodies without applying geometry; never
resize or reconnect based on this private metadata. Only use normalized crops
when metadata aspect agrees with the actual framebuffer. A layout replacement
updates selected IDs or returns to All Displays if no longer valid. Selection
confines local presentation/input; the complete framebuffer is still received.
No remote resolution/layout-setting messages are sent. Without verified bounds,
show an explanatory display menu and retain All Displays. Valid rows show a
geometry-only arrangement diagram, dimensions and the current selection;
All Displays highlights every rectangle. Menu choices resolve against the latest
layout by stable display ID, including when the menu stays open during a change. Exact fit-to-window and app/window metadata queries are deferred.
The two-finger double tap zooms around its point from fit, otherwise returns to
fit. Normal clicks continue to control the Mac.

Pointer mode uses absolute finger positioning; Trackpad uses relative movement
independent of finger location. Tap clicks, hold-and-move drags, two-finger
movement scrolls in Trackpad. Three fingers pan the local canvas in Trackpad;
two fingers pan it in Pointer. Desktop pinch and two-finger double tap stay local.
Trackpad & Keyboard mode can send optional native magnification as specified below.
Changing modes, crops, backgrounding, cancellation and exit release held buttons.
One Done action disconnects and returns to My Macs; no separate active-session
Disconnect button is presented. Explicit exit does not reconnect automatically. Temporary
foreground inactivity retires queued/copied input and releases held input while retaining
the established transport and presentation; it does not start desktop restoration.
Background cancels a pending handshake. An established connection cancels queued input and pauses its native owner
without closing the socket, including while initial, review-return or foreground
pixels are pending. Transport establishment is independent of input readiness. Explicit Stop gives
an established socket owner up to 250 ms to release sent keys/buttons/gestures,
including when a baseline reset or mode transition has closed input admission.
Only an incomplete handshake is shut down immediately. The bounded fallback
unblocks stalled reads and is fenced to the stopped connection generation.
A bounded in-flight read may finish before sent
keys/buttons are released. Once release completes, the owner sleeps: no frame
decoding, new update requests, UI presentation or remote input runs while paused. A bounded
UIKit background task bounds input release independently of paused-status publication,
ending within one second or on expiration. A stalled release retires the transport;
a stalled ActivityKit update cannot retire a transport whose release completed.
The task does not maintain an idle connection or stream in the background.
Foreground requests a full framebuffer on the same owner. Input remains blocked
until a complete framebuffer arrives. Every baseline reset closes input, retires
queued input and releases held input. Presentation commits recheck the connection
generation and baseline epoch under the owner lock after the UI callback, before
marking a baseline presented or reopening input. If the socket fails or no framebuffer arrives
within 9000 ms (allowing the bounded baseline refresh window), retire it and make one automatic reconnect attempt. Do not loop
retries or overlap native owners. Background/foreground calls are idempotent.
Preserve the selected display ID, relative zoom, viewport center and mouse mode.
Keep the cached selected-display crop until the replacement frame and matching current
layout converge in either callback order. A received frame retained for this wait is
not a presented desktop: ordinary and composed input remain blocked. Composer entry,
availability and final delivery MUST all enforce this presentation gate. Defer UI
video-mode changes during replacement restoration; they become available after readiness.
A verified missing display falls back to All Displays and fit with a concise notice.
A retained display with changed dimensions remains selected and fits its new geometry;
old relative zoom/center apply only to matching selected-crop pixel dimensions,
including when the overall framebuffer is unchanged. Moving a same-sized crop
to a new origin preserves relative zoom and normalized center. Restoration feedback is a
compact indeterminate indicator delayed 1000 ms, cancelled on readiness or exit.
A retained-owner refresh keeps cached pixels at full opacity and remains paused
until fresh readiness evidence; only a replacement dial announces Reconnecting.
A manual retry remains available after the automatic attempt fails.
Returning to My Macs permanently retires that viewer. Late native frame, cursor
and status callbacks cannot revive a stopped or replaced connection.

## Optional native magnification in Trackpad & Keyboard mode

The direct client may forward pinch to the Mac app at the remote cursor, using
Apple's observed event extension. Desktop pinch continues to zoom the local
image. Native magnification requires the original server banner `RFB 003.889`,
the existing successful ARD-30 login, and a valid version-5 display layout whose
backing dimensions exactly match the current framebuffer. This is conservative
compatibility gating, not an authenticated capability or an Apple compatibility
promise. Unknown hosts/layouts send no extension and no zoom shortcuts. Display
resize or replacement retires pending gestures and reevaluates this gate.

The sole RFB owner sends these bounded messages in the existing input order.
All multibyte fields are big endian. Each has opcode `0x17`, flags zero and a
uint16 payload length. Begin/end boundaries use a 12-byte payload: uint16
version **1**, uint16 kind **1** (begin) or **2** (end), uint32 AppKit touch subtype
**3**, then uint16 framebuffer x/y. Magnification uses a 32-byte payload:
uint16 version **2**, uint16 kind **3**, IEEE-754 double delta, uint16 x/y,
uint64 raw CG phase and uint64 magnification mask **4**. Raw phases are
**1/2/4** (began/changed/ended), distinct from AppKit phase values 1/4/8.

A gesture sends a begin boundary and a zero-delta began magnification, finite
incremental changed deltas in [-0.5, 0.5], then a zero-delta ended magnification
and an end boundary. Begin/end groups are atomic in the input queue. Use
`currentScale / previousScale - 1`, with a positive finite scale, and preserve
a fixed cursor anchor inside the verified framebuffer for the whole gesture.
Reject malformed phases, coordinates or deltas without partial packets or
state changes. Ordinary pointer and key messages keep their existing semantics.

Only one pinch is active at a time. Pending gesture events carry a cancellation
epoch; events already copied by the owner must also check it before delivery.
Cancellation, controls opening, mode/crop/layout changes, background pause and
exit discard pending gestures and end any gesture actually begun. Queue pressure
cancels the gesture rather than dropping its end. No change or end can begin a
new gesture, and no stale pinch is replayed after resume/reconnect. If writing a
boundary fails, retire the connection; never retry the partially written group.
A disconnected socket cannot guarantee delivery of its final release.

The wire layout is derived from the installed Apple client/server and verified
by agent-originated AppKit magnification on the research Mac. See
`Experiments/NativeTrackpadGestureProbe/EVIDENCE.md` for the evidence boundary.
Released macOS compatibility and Preview/Photos acceptance remain separate gates.
No experiment or Mac helper is linked into the iOS app.

## Optional precise two-finger scrolling

Desktop Trackpad and Trackpad & Keyboard mode may forward continuous scroll
through the same conservative Apple banner, ARD-30 and display-layout gate above.
Pinch remains input-only; scrolling is allowed with or without desktop capture.
This optional extension is derived from installed Apple binaries, not an Apple
published protocol guarantee. Unknown hosts retain balanced standard wheel input.

Each scroll is one 58-byte message: opcode `0x17`, header flags zero, uint16
payload length **54**, then this big-endian payload, with offsets from its start:

| Offset | Field |
| --- | --- |
| 0 / 2 | uint16 version **1** / kind **11** |
| 4 / 6 / 8 | int16 line deltas X / Y / Z, all zero |
| 10 / 14 / 18 | int32 signed 16.16 fixed deltas X / Y / Z |
| 22 / 26 / 30 | int32 point deltas X / Y / Z |
| 34 / 38 | uint32 raw CG scroll phase / momentum phase |
| 42 / 46 | uint32 scroll count **1** / flags **2** (continuous bit 1) |
| 50 / 52 | uint16 framebuffer cursor x / y |

X is horizontal and Y vertical. Z is zero. Deltas are finite, bounded to
[-2048, 2048] per axis per update. Fixed deltas are rounded to signed 16.16;
point deltas round to the nearest whole point. Began/changed/ended use raw CG
phases **1/2/4**; began/ended deltas and momentum are zero. There are no outer
magnification touch boundaries. Keep the cursor anchor fixed for the gesture.
Reject invalid phases, transitions, coordinates, or output capacity without
changing encoder state or output. One scroll may be active at a time.

Use three Mac scroll points per phone point at the default Scroll Speed (1×).
The global local-device multiplier is 0.25×–4×, independent of pointer speed,
image zoom and display backing scale. The viewer carries fractional movement
between updates so rounding to whole CG point deltas preserves total motion.
Discard fractions at gesture end/cancel. It applies in both Desktop and Trackpad,
including settings opened without a connected Mac. Unsupported hosts use the
existing six-phone-point wheel threshold scaled by this multiplier and retain
the eight-tick per-update bound. No synthetic momentum is sent.

Scroll events use the same owner queue and cancellation epoch as magnification.
Cancellation, invalid input, opening controls, mode/crop/layout changes, pause,
queue pressure and disconnect retire copied and pending scroll changes and end
any delivered sequence. Scroll survives no pause or reconnect. Live delivery
measurements and compatibility limits are recorded in the experiment evidence.
No new authentication, Mac helper or release dependency is introduced.

## Authoritative fixtures

`spec/fixtures/manifest.json` indexes `direct-screen-sharing-v1.json`. It contains
numeric endpoint, login, version-5 Apple display-layout and native magnification/scroll
packet/lifecycle boundary cases for
the actual native helpers. One layout presentation is pending at a time; newer
metadata replaces the pending value rather than growing a callback queue. No
synthetic server, no-auth path or test credentials are linked into the app.

## Display metadata source

The interoperable parser in [iShareScreen](https://github.com/renegadelink/iShareScreen/blob/main/src/isharescreen/proxy/protocol/rfb.py) documents the observed version-5 header and 56-byte records. This private extension is bounded and optional; unsupported hosts retain the combined desktop. Live macOS acceptance of metadata remains separate from synthetic parser/stream tests.

## Local diagnostic snapshot

The development client may replace one local cache snapshot with fixed numeric
counters, framebuffer dimensions, display-message count, body length, version,
header dimensions, declared count, parse success, and the two rectangle-coordinate
sets from at most 32 records. Never retain the opaque body, endpoints, logins,
pixels, titles or input content. This snapshot does not alter the connection.
It may also include fixed decoder-failure counts and numeric viewer geometry,
zoom, hidden-state and image-presence values to distinguish decoding from layout
failures. No pixel samples or image-derived summaries are retained.

## Session interface and local preferences

Use a focused Mac login card with username/password AutoFill fields, password
visibility and optional per-Mac retention. Saved logins start automatically.
Show actual contacting/signing-in/opening-desktop phases and Cancel; present the
desktop after its first frame. Show actionable failures and allow editing login.
Healthy sessions hide routine Connected text. Connection problems remain visible.

Connection readiness is mode-specific. Desktop requires a complete presented
baseline, including after resume or leaving input-only mode. Trackpad & Keyboard
requires a running, authenticated input owner, but no presented framebuffer:
it deliberately suppresses desktop presentation and regular pixel requests.
Publish its initial Connected state after successful RFB initialization and on
an admitted resume or switch into input-only mode. Paused, stopping, overflowed
or unauthenticated owners cannot publish Connected in either mode. Switching
back to Desktop still requires a fresh complete baseline before Connected.
Outside replacement presentation restoration, forward mode changes to any established
owner, including while Desktop waits for its initial pixels. Retire queued input and release held input on the socket owner before
admitting the new mode. Entering Trackpad & Keyboard reopens input after that
release without requiring a desktop baseline; a superseded mode or presentation
epoch cannot reopen input.

The keyboard/modifier strip remains directly available. One bottom-right glass
controls button opens quick actions, Displays, Input and Session categories, with
one Disconnect action. Press-and-slide is a primary interaction: open while
held, highlight with haptics, commit only on release, cancel outside actions or
when backgrounded. Capture those touches locally; no menu gesture becomes remote
pointer input. Ordinary tap and accessibility actions provide equivalent access.
Disconnect uses a deliberate tap. Panels stay inside safe areas and above the keyboard.
The docked keyboard reduces the desktop viewport as well as raising controls.
Fit follows the available area; zoomed views retain their relative zoom and
center. Dismissal restores the pre-keyboard view when its crop remains valid;
changed display/framebuffer geometry must not restore a stale crop. Follow the
system keyboard animation. The keyboard button shows a dismiss symbol and
Hide Keyboard accessibility label while remote text input is active. Keyboard
presentation changes are local and never reconnect or resize the Mac desktop.

Persist display ID and mouse mode per Mac. Restore a display only against verified
current metadata/framebuffer, otherwise retain All Displays. User-selecting All
Displays clears the saved ID. Trackpad movement accumulates per-event deltas with
bounded acceleration and user speed 0.5–3 (default 1.5); normalize using verified
backing/logical dimensions when available. Speed does not depend on local zoom.

Follow Cursor defaults on and is persisted per Mac, with an opt-out in Input
settings. It operates only in zoomed Trackpad mode during iPhone-originated
pointer movement or dragging. When the cursor enters an edge margin (12% of
each viewport dimension, capped at 64 points), pan only enough to return it to
that margin, clamped to the selected display crop. Keep zoom unchanged. Fit and
Pointer mode do not follow. Manual pan/pinch suspends following until the next
trackpad gesture, and following must not interrupt active viewport gestures,
deceleration, recovery, background state or presented settings.

Use the local pointer target without waiting for the server. Server cursor
notifications alone must not pan the viewport. Trackpad deltas, including held
drag positions, use coordinates independent of viewport translation. Reuse the
existing desktop image and update the scroll offset as pointer events arrive;
do not add an idle polling loop, frame copies, input events or RFB reconnects.

App Settings exposes separate Desktop, Terminal and Trackpad & Keyboard quick-action
profiles without requiring a connected Mac. Session input settings use the same
profiles. A saved profile applies to all Macs in that mode; old per-Mac Desktop
content remains intact and is used until a Desktop profile is saved. Profile
accounts are separate from Mac UUID accounts in the existing local Keychain service.
Terminal profiles reject macOS Command chords and desktop-only actions; Terminal
shortcuts use the existing xterm encoder and saved text uses bracketed paste when
requested by the shell. Existing Pro customization and free standard controls remain.

Two-finger trackpad scrolling uses the existing balanced RFB wheel masks: one tick
per six points, at most eight ticks per gesture update. Keep fractional deltas;
discard excess movement, canceled motion and remainder at the end. Never replay
input after fingers stop or after a lifecycle transition. This changes local gesture
sensitivity, not the wire format or authentication.

Quick actions can be reordered, hidden and augmented with explicitly configured
shortcut chords or saved text (at most 256 Unicode scalars). Store custom content
only in a distinct local, non-synchronizing WhenUnlockedThisDeviceOnly Keychain
entry. Never include it in diagnostics or ActivityKit. Send saved text as balanced
Unicode key events, not a remote clipboard claim. Shortcut modifiers and key are
one balanced group and clear one-shot modifiers. Actions require a ready foreground
session; local display/input settings remain available during recovery.
Admit the complete custom action into the bounded input queue or none of it.
A busy queue reports a retryable issue without partial text or a disconnect.

## iOS session text composer

Desktop, Trackpad & Keyboard and Terminal offer a free **Compose Text** session
Quick Action (also available under Keyboard & Input). Existing untouched default
profiles gain this action; preserve all customized profiles and their disabled
actions. macOS does not expose this tool. Present a small floating text bubble
above the native keyboard, retaining visible session content. Use one multiline
input surface with a full-width editor and an inline bottom row containing Close,
a drag grip and circular arrow Send. Grow the compact bubble with text up to six
preferred body lines, then scroll within the same editor; clamp to keyboard-safe
space and retain readable text at accessibility sizes. Conditional error details
share the footer without overlapping the drag grip or other actions; do not expose a title/presentation toolbar,
Expand/Collapse, Dock/Undock or a grabber-tap expansion action. Close retains the
unsent draft so the user can choose a remote destination; clearing selected text
uses the native editor. Drag within the keyboard-safe area, gently snapping
within 28 points of an edge on release. Relative placement follows keyboard,
orientation and size changes and stays clamped within safe bounds. Track undocked
(including floating and detached split) keyboards. Prefer space above the keyboard;
when that cannot hold the editor, choose readable space below or beside it.
Use a safe-area tracking constraint near the top edge. Retain one mounted native
editor, draft, selection and keyboard focus through movement and layout changes.
Use one native regular Liquid Glass surface for the outer bubble on supported
systems, with a stable filled background behind editable text. The material keeps
its system accessibility adaptations; use a non-glass fallback where unavailable.
Do not stack additional glass surfaces inside the bubble or add presentation controls.
Editor scrolling never moves the bubble. Canceled gestures restore placement;
sending blocks movement and dismissal. Keep 44-point Close/Send hit regions,
readable scrolling text and accessible destination context/validation in narrow,
short landscape and Dynamic Type layouts. Conditional error details remain
reachable. VoiceOver offers movement actions on the grabber. Background, app lock,
connection replacement and session closure clear the ephemeral viewer/PTY-bound
draft and dismiss its editor. Neither draft nor content enters storage, sync,
diagnostics or ActivityKit.

The only delivery action is **Send Text**. It never appends Return. Clipboard
reads require an explicit native Paste action. Preserve spaces and trailing line
breaks; normalize CRLF, CR and Unicode line/paragraph separators to LF. Reject
other C0/C1 controls (including NUL and Escape), except Tab. Bound the editable
draft to 16 KiB UTF-8 without silently truncating pasted content. Desktop sends
at most 256 Unicode scalars; Terminal sends at most 4096 UTF-8 bytes, excluding
bracketed-paste framing. A too-large draft remains editable and cannot be sent.

Desktop delivery uses balanced Unicode RFB key events, with LF represented by
Return and Tab by the Tab keysym, clearing armed modifiers. It is typing into
whatever currently has focus, not clipboard synchronization or semantic field
selection. Every draft containing LF or Tab requires explicit confirmation that
line breaks may submit content/run commands and tabs may change focus. Admit the
whole event group into the existing bounded queue or none of it.

Terminal sends UTF-8 to its existing PTY owner and wraps it in bracketed-paste
markers only when the current terminal mode requests them. Every draft containing
LF or Tab requires explicit confirmation; without bracketed paste these can run
commands or change terminal input. Never describe Send Text as preventing command
execution, even though it adds no extra Return.

Confirmation binds the exact reviewed text. At sending time, recheck app unlock,
foreground/input admission and the originating connection generation. Terminal
composer entry, queue admission and worker writes MUST also wait for the session
to finish its foreground handoff, even if the application is already active. A busy
queue keeps the draft with a non-destructive error. Once admitted, disable editing
and duplicate sends until the local transport write completes or fails. A local
write completion is not remote application consumption. Partial/uncertain writes
are reported without automatic retry; lifecycle interruption retires callbacks
and never replays input. Copy Text review and Desktop baseline resets also retire
composed-text groups and their pending completions under the queue lock.
Composer presentation, availability, queue admission and worker writes use the
mode-specific readiness contract: Desktop requires the current complete presented
baseline, including the first frame after replacement. Retained viewer pixels,
partial coverage and a complete frame awaiting presentation cannot admit text.
Trackpad & Keyboard can compose and send without pixels on its authenticated
input owner. Recheck this readiness under the queue lock before admitting text.
Cancellation also retires event groups already copied
by the VNC worker: resuming input cannot admit their remaining events. Release
keys actually written before cancellation. An interrupted-send warning survives
automatic retained-session replacement until the user acknowledges it.
Saving reusable snippets remains a separate existing
Pro tool with its current limits and protected storage.

The manifest-indexed `ios-text-composer-v1.json` records text normalization,
Unicode/keysym encoding, bracketed-paste framing and confirmation cases. Synthetic
checks do not establish built-in Screen Sharing Unicode compatibility or native
dictation/IME acceptance on a physical iPhone.

## Optional session Live Activity

“Show session in Dynamic Island” is enabled by default, persisted locally and
independent of connection recovery. The ActivityKit widget has no network client,
credentials, remote input or background execution mode. Its scoped End Session
LiveActivityIntent runs in the app process without foregrounding it.
Publish Connected only for a foreground, ready native owner. Temporary foreground
inactivity releases input without changing the established session phase. Actual
background entry presents Paused. Retained Desktop checks keep Paused until fresh
readiness evidence; publish Reconnecting only while replacing a Desktop connection.
End immediately on Done, terminal failure or opt-out. A dismissed activity is not recreated for that session unless the user opts back in.
Connected and paused freshness are bounded to 60 seconds. Renew connected freshness
only on observed connection evidence, with coalesced foreground publication; returning
to a local socket does not prove the peer is alive. Stale presentations offer Open to
Check and never promise a live socket or retained shell. An observed session end retires
activity ownership immediately and ends the activity independently of a stalled update.
Late updates cannot consume a replacement owner. Suspension can delay observation of
a later remote close or activity dismissal; no indefinite background runtime is added.
Only the user-assigned Mac name, opaque saved Mac UUID, Desktop/Terminal kind and phase reach ActivityKit;
no address, account login, pixels or input content. The resume URL accepts only
maccompanion-session://resume/<UUID> or maccompanion-session://resume-terminal/<UUID>
for an existing saved record, with no query,
fragment or credentials. It opens the existing viewer when already selected;
it cannot create an endpoint or start a parallel session. A Terminal route after its
owner view/process is gone opens sign-in without auto-connect and explains that Connect
opens a new shell; ordinary Mac-list entry retains saved-login convenience. An already presented
Desktop or Terminal is kept; a Terminal link cannot accidentally open Desktop.
Old activities without a kind retain Desktop semantics. Activities left by a
previous process are ended before starting a new one. Startup retirement remains
tracked independently of replaceable status publication: an early session end or
opt-out/opt-in cannot discard it or permit new creation before it completes.
Waiting for pending activity work includes this startup retirement, while ending
the currently owned activity remains independent of stalled updates. No APNs or
vendor server is added. Permanent extension identity/signing admission remains gated.

Compact presentation shows a one-line Mac name with a bounded width and a phase
symbol; expanded and Lock Screen presentations show the name, status,
Open (Open to Check when stale) and End Session. The expanded name may use two lines and truncate to fit,
retaining its full accessible label. Its compact ending action may say End,
with the accessible label End Session. Phase text and actions use the full-width
region below the camera, with inset spacing from the curved edges. Expanded
presentation has no glyphs in the camera-adjacent top regions. Minimal
presentation uses the current phase symbol, including a question mark when stale.
Stale cards say Open to check connection and expanded content says Needs checking;
paused/stale Terminal content identifies Terminal without promising a retained shell. End Session targets the opaque
ActivityKit activity ID, not just a saved Mac ID, so a retired button cannot stop
a replacement activity/session. Route the action to the matching existing viewer's
deliberate exit path: retire recovery, release input/stop the native owner, end
the activity and return to My Macs. Repeated or unknown activity IDs do not affect
other sessions. If the app process has no viewer, end only the matching orphaned
activity; never connect, read a login or create a background execution assertion.
The action is not exposed as a general Siri/Shortcuts command.

## Local app lock, presentation modes and pointer admission (2026-10-05)

An opt-in, default-off LocalAuthentication deviceOwnerAuthentication gate protects
local app access. This is an OS app unlock, not protocol authentication or pairing.
Load saved Mac metadata and build the app underneath an opaque privacy cover while
Face ID/passcode runs. Gate credential reads, connect, input and session resume until
success. A biometric prompt's transient inactive state must not relock recursively;
actual background entry covers content and revokes access. Failure/cancel remains
covered with an explicit retry. Cover all presented controllers and app snapshots.
Locking after background entry defaults to immediate. An explicit local 30-second
preference may reuse prior successful access only when the app is active, protected
data is available and a continuous monotonic deadline (including sleep) is unexpired.
Access remains revoked throughout background entry. Protected-data loss, preference
changes and process restart discard reuse; a late retired authentication cannot restore
access. Transient inactivity alone MUST NOT reveal a lock cover or revoke prior
authentication; session input still stops until active. Cover actual background
entry for the app snapshot. On foreground entry remove that snapshot cover before
visible presentation when a valid grace reuse is pending, without granting input
or credential access until active. A successful current authentication MUST reveal
the prepared local interface, enable its local controls and hide the cover together
on the main actor, provided protected data is available and the app has not entered
the background. This current-success handoff may precede UIKit activation; it MUST
NOT resume remote sessions or admit remote input while inactive. Keep the unlocked
session notification and remote-session readiness subject to actual foreground
activation. Reconcile both result/activation orders without repeating authentication
or requiring a new activation event for an already-active success. Retire the local
handoff exception on subsequent inactivity; actual background/protected-data loss
revokes it immediately. A requested Desktop/Terminal route during this handoff waits
for activation, and is retired by background entry or a replacement route.
The opaque Unlock card remains through evaluation, with a disabled Unlocking button.
Successful authentication removes it without a separate Opening or branded screen.
Failure exposes an explicit Unlock retry only with foreground/protected-data readiness.
Keep passcode-availability validation when enabling the preference, but do not
repeat a synchronous policy preflight on every unlock. Evaluate the same policy
asynchronously; a passcode-not-set reply retains the opaque card, records unavailable
authentication and offers the same setup guidance and explicit retry.
After consuming a current successful authentication result, explicitly invalidate
its completed LocalAuthentication context to release the system authentication
presentation. Retire the reply token before cleanup so a cancellation callback
cannot replace success. Context cleanup alone MUST NOT grant access or bypass protected-data, background
or current-attempt checks. Only an accepted successful reply grants local access;
remote-session resume remains gated on actual activation.
A completed failed or canceled attempt stays locked for explicit retry; transient
activation cannot automatically repeat it. Background/protected-data loss retires
pending success and rejects late replies. UIKit activation remains the public remote-session
readiness boundary, not a guarantee of Face ID animation completion; no fixed
animation-duration delay or private system-UI inspection is permitted. Development
phase diagnostics may record bounded fixed phase/outcome names and monotonic numeric
offsets for the raw authentication callback, actor handling, actual activation
notification, separate local/active admission and cover removal, synchronous observer return, initial library
wait and the first eligible native display tick. The display tick is explicitly a
frame-opportunity proxy, never proof of pixel delivery. Retire diagnostic attempts
independently of access; no diagnostic may grant admission or change its timing.
Development diagnostics may additionally retain at most 64 activity samples per
attempt: monotonic offsets, public active/background booleans and numeric main-actor
scheduling delay. Checkpoint successful admission independently of the optional
display probe; missing a display tick must not discard handoff evidence.
Do not record credentials, user/host identifiers, errors, screen or input content;
do not upload these records. Release builds do not persist or probe them.
The library interaction/accessibility gate MUST observe the accepted successful
authentication and application activation directly, without requiring a scene-phase
change. Local reveal and local hit testing MUST share one state transition. Remote
routes MUST observe a separate active-session gate. Losing interaction retires
pending local presentations.

Fullscreen hides the key strip and reclaims its viewport space without a reconnect.
A reachable session-controls button restores it, including keyboard access. Remember
fullscreen per saved Mac. Trackpad & Keyboard hides remote content on a large local
trackpad and stops regular framebuffer requests while preserving the same foreground
input connection. At most one already-requested frame may drain. Returning to Desktop
requests one fresh full frame. Background still releases input and pauses everything.

Pointer taps must enqueue one atomic down/up pair or reject the whole pair. Do not
update a local click as accepted when input admission failed. A short Pointer gesture
with small drift remains a tap; longer movement remains movement, and hold remains
drag. Never retry a click automatically, including the macOS focus-only first click.

## Direct SSH Terminal profile (2026-10-05)

Terminal uses built-in macOS Remote Login on the same saved Mac's private endpoints,
with a separately configurable SSH port (blank means 22), separate per-UUID SSH login
and separate remembered server key. No Mac installation, legacy Agent or custom
pairing/authentication semantics are added. Preserve old library UUIDs and desktop
credentials when migrating to schema 3. Terminal credentials are local nonsync
WhenUnlockedThisDeviceOnly Keychain entries; output/input/passwords are not logged.

Use a pinned standard SSH implementation and a pinned terminal renderer. Validate
and dial the exact sockaddr with the same private-route policy as Desktop, then run
SSH over that connected channel. Only TCP failure may try another configured address;
authentication, server-key rejection and SSH failures must not retry credentials.
Disable automatic socket reads before registering the connected channel. Install the
SSH parser and handshake handlers on its event loop, then enable reads before awaiting
authentication. An early server banner must remain queued until the parser exists;
UI scheduling must not discard bytes or delay the handshake until its timeout.

Before any user authentication, compare the canonical OpenSSH host key. On first
connection, show the SHA256 fingerprint and require explicit trust. A changed key
fails closed and requires forgetting the saved key in Edit Mac before reconnecting.
Never silently accept a changed key, and never use acceptAnything. Fingerprints hash
the decoded SSH public-key wire blob, using SHA256/base64 without padding. The indexed
synthetic vectors are authoritative. Save trust only on an explicit affirmative action.
Open an xterm-256color PTY, forward bytes in order and propagate row/column resize.
Close on explicit exit or actual transport failure. Temporary foreground inactivity and background transitions MUST retain an established
SSH channel and PTY, clear armed modifiers and stop admitting input. Inactivity
retires copied/queued writes and buffers output within the existing memory bound
without pausing reads; actual background or local lock pauses automatic transport reads. An incomplete handshake or key
installation still cancels on inactivity. A bounded UIKit background assertion
bounds read-pause independently of Live Activity updates, then ends within one second
or on expiration. Failure to finish read-pause retires the transport; a completed
read-pause cannot be failed by stalled status publication. The assertion MUST NOT
maintain idle background runtime or polling.
Output already in flight is kept only in a bounded 1 MiB memory buffer, never
rendered while inactive/locked or written to disk. Overflow ends the session with
an actionable error rather than dropping bytes. Foreground/unlock re-enables reads,
flushes pending output in order and applies the latest PTY size to the same shell
before admitting fresh typing, including a grid changed during brief inactivity.
Resuming local reads does not renew verified SSH freshness; fresh peer output does.
Resume MUST wait for active app state and app unlock; late callbacks cannot revive
a stopped/replaced session. No input is queued or replayed across this transition.
Transport loss offers an explicit new shell; never silently reconnect SSH or imply
that a replacement shell restores the prior process. Live Activities use the existing
default-on opt-out setting, identify Terminal, and offer scoped Resume/End actions.
Paused/stale wording MUST NOT promise an indefinitely live connection: iOS may
suspend the app and the server/network may close SSH while it is away.
Never replay shell input on reconnection.
Retain the SSH server's exit status or exit signal until PTY output has drained.
Only a reported exit status of zero, followed by channel closure without a transport
error, returns to My Macs and ends the session's Live Activity. Nonzero status,
exit signal, missing status, and transport failure offer explicit recovery instead.
Never infer shell completion by inspecting typed input. Completion from an old
session cannot dismiss a replacement session; navigation waits for app unlock and
active foreground state. Recovery with retained credentials offers a new shell
without replaying input or claiming to restore the previous process. Ordinary
connection failures do not offer Change Login; authentication failures retain
editable credentials and the Password/SSH Key choice. Issue Details appears only
with additional safe details, and captures the notice when tapped so subsequent
session changes cannot empty or replace the presented issue.
Remote OSC clipboard reads are denied and writes/URL launches require user action.

My Macs uses the leading icon for detected hardware. Name, plain Open Desktop,
Open Terminal or Open Trackpad & Keyboard text, and address share one text column.
The hardware badge and sole trailing menu control center vertically against that
column; the row has no connection-action icon or disclosure chevron. Text wraps
at larger sizes. Desktop's menu item uses a window symbol distinct from hardware.
Library file version 5 persists manual array order. Older files initially retain
the previous alphabetical presentation. Reordering preserves record UUIDs, logins,
server trust, and the selected free Mac. Order is local to each device: cloud
metadata merges preserve surviving local positions and append new records.
iOS initial saved-Mac reads, decoding and validation run off the UI actor and
may overlap app unlock. Loading is distinct from an empty or unreadable library;
persistence and cloud attachment wait for its validated snapshot. Concurrent
load callers share one read, and a superseded read cannot replace newer state.
Storage failure preserves the file and allows retry. Session deep links received
during loading are resolved only after the list is available and still pass
existing app-unlock, activity and membership admission.

## SSH key login and opt-in iCloud library sync

Terminal MAY authenticate with an Ed25519 user key using standard SSH public-key authentication. Keys are created using system cryptographic randomness or imported from a bounded OpenSSH document (maximum 32 KiB). Encrypted imports require their passphrase and bounded bcrypt work (1 through 128 rounds); decoding runs away from the UI actor. Invalid, unsupported, or mismatched key material MUST fail before opening a connection. There is no automatic password fallback. Host-key verification still precedes user authentication.

Named keys have stable UUIDs independent of Macs. A device-local library holds up to 256 keys and explicit per-Mac selected-key/account associations in the existing non-synchronizable, WhenUnlockedThisDeviceOnly Keychain group. Sharing one key across Macs and choosing separate keys are equally supported; the UI MUST NOT recommend either arrangement by default. Legacy per-Mac keys migrate idempotently, retaining the original entry until the new record and association are durably saved. Failed migration MUST preserve the original. Editing addresses or removing a Mac MUST NOT delete a library key used elsewhere. Deleting a key clears its local associations, requires confirmation, and does not claim remote revocation. Unreadable or malformed library data MUST NOT be overwritten.

Private keys and passphrases MUST NOT appear in logs, fixtures, diagnostics, clipboard or cloud library records. Public keys can be copied/exported. Explicit private export requires fresh device-owner authentication, a nonempty passphrase, and a standard encrypted OpenSSH Ed25519 document (aes256-ctr with bcrypt, 32 rounds and fresh salt/check words). Export preparation runs off the UI actor, uses the pinned standard library primitives, and clears temporary documents when dismissed, locked or backgrounded. Plaintext private-key export is not offered. Validate interoperability against OpenSSH, not just the matching importer.

The individual saved Mac settings page offers Install Key on This Mac. The user chooses a library key/account and explicitly supplies bootstrap password or an existing working key. Standard host verification precedes authentication. Installation sends only the public key to that account's ~/.ssh/authorized_keys, preserves all existing lines/options, rejects unsafe symlinks/file ownership, fixes private permissions, and avoids duplicating the same key even when its comment differs. Duplicate detection parses only the actual algorithm/blob fields after any quoted options, never trailing comments. It needs no helper, sudo or server configuration change. Do not automatically retry a command of uncertain outcome. Verify a fresh key-only SSH authentication before saving the selected key/account; retain the bootstrap login and report unverified installation if verification fails. Cancellation/background closes the connection and suppresses late success.

Terminal keyboard accessories show a 1–0 number row whenever the software keyboard is open and standard Esc, Tab, Ctrl, Alt, arrows and additional navigation/function keys. Software modifiers apply once, including Backspace, then release; explicit long press locks them. Shift applies standard shifted symbols to the accessory number row. Legacy Ctrl-Backspace sends control-H and Alt prefixes Escape; enhanced keyboard mode uses its modifier parameter. IME composition deletion keeps the native text-input path. A grouped native range deletion produces only one Ctrl/Alt-modified deletion for the logical keypress; ordinary deletion retains the native count. Input is encoded as xterm data, respecting application cursor mode. Modifiers clear on keyboard dismissal, disconnect or background, and no input is replayed. Command shortcuts are local copy/paste actions, not fabricated remote macOS key events. Pro-only customization permits bounded layouts and saved snippets; the standard number/modifier rows remain free.

## Lifetime Pro and permanent free access (2026-10-05)

The official client has an optional lifetime non-consumable Pro product (`media.jenny.maccompanion.pro.lifetime`, US base price $9.99) and Restore Purchases. Verify StoreKit transactions, their product/type and revocation before unlocking. Resolve initial entitlements before denying paid actions. Free-Mac connections,
first-Mac addition and existing-Mac management MUST NOT wait for initial StoreKit
resolution. Pending paid-dependent actions show progress with a bounded retry
state, never grant unverified Pro access, and recheck unlock/activity and record
membership before presentation; retired requests cannot open a late sheet. Listen for updates and read current entitlements without a custom account/server or per-session online purchase check. Cancelled, pending, unverified and unavailable purchases never unlock Pro or delete user data. Display StoreKit's localized price only when the product is available. The development StoreKit configuration is testing-only and never establishes App Store product availability.

An explicit optional free non-consumable `media.jenny.maccompanion.pro.trial14`, displayed as **14-day Trial**, grants the same Pro features for exactly 1,209,600 seconds from its verified **original** purchase date. It MUST be priced zero before the app offers it. Explain the duration, expiring Pro features, permanent free tier and separate lifetime purchase before starting. There is no automatic billing or renewal. Restore, repeated purchase, another device and reinstall MUST NOT reset the original start date. Read verified trial history, including revoked transactions, to prevent offering a second trial; revoked trials grant no access. Unverified, wrong-product, wrong-type and future-dated transactions grant no trial access. Reevaluate expiry on foreground and with a bounded local deadline while running; no per-frame timer or server is needed. Local time is used offline and is not a tamper-resistant server clock. Lifetime access overrides trial expiry. Expiry/revocation preserves saved data, free selections and active connections.

Free access has no session/time expiry: one saved Mac, one SSH key, Desktop, Trackpad & Keyboard, basic Terminal, local/private-VPN addresses, advanced ports, display selection/zoom, standard keyboard/number row, accessibility, app lock, server verification, diagnostics and key import/export. Pro adds multiple saved Macs, multiple named keys, automatic key installation, customized terminal rows, shortcuts and snippets. Existing extra Macs/keys are preserved for management/export/deletion when Pro is unavailable. A stable free selection remains usable; never terminate an active connection when entitlement changes. Purchasing/restoring unlocks preserved records. Commerce gates never grant SSH trust or change protocol authorization.

iCloud library sync MUST default off on each installation and require explicit consent after a privacy disclosure. It uses synchronizable generic-password items in the app's existing Keychain access group, protected by iCloud Keychain; it does not introduce custom cryptography, a CloudKit container, or app authentication. Sync transports saved Mac UUIDs, names, ordered addresses, ports and non-content session preferences. Passwords, SSH private keys, accepted server keys, saved text, custom actions, app-unlock consent and the sync opt-in itself remain device-local. Cloud data never establishes server trust or opens a session.

Each device writes its own bounded record versions, ordered by logical revision then device UUID. A validated newer tombstone suppresses a deleted Mac without deleting local credentials. Malformed, oversized, duplicate, unsupported or unreadable cloud data MUST preserve local records. Cloud work occurs only while opted in and the app is unlocked; refresh is performed on foreground and explicit request, never per input event. Local saves remain usable offline. Disabling stops reads and writes and retains local Macs and existing cloud copies. Deleting cloud copies is an explicit, separate operation with a warning to disable other devices first. The UI MUST distinguish local Keychain submission from confirmed delivery; it cannot report a successful multi-device sync without evidence.

OpenSSH import and encrypted export accept bcrypt rounds 1 through 128 and salt lengths 1 through 64 after bounded preflight. All padding bytes must match the OpenSSH ascending sequence, allowing a complete cipher block of padding.

## Error and recovery presentation, 2026-10-06

Failures are classified by typed errors and known connection phases, never by
matching vendor error text. Unknown failures remain unknown. Authentication
rejection cannot establish that a public key is absent. Connection details are
local bounded phase/service/settings values, excluding secrets, private keys,
input, pixels and raw vendor output. Cancellation and pending purchases are
neutral outcomes. Failed reads preserve data and must not appear as an empty
library. Presentation does not change existing authentication or entitlements.

Public-key setup records command-not-sent, command-sent, installation-acknowledged
and login-verified phases. Cancellation/timeout never replays setup or input.
An uncertain setup first offers Test Key Login: a fresh key-only authentication
to the verified target, with no password fallback and no remote install command.
Only verified login followed by durable key association reports success. A
failed verification keeps the previous selection and saved password. A changed
SSH server identity blocks authentication and remains an explicit independent
verification decision. Free manual public-key copy/export remains available;
automatic installation keeps its existing Pro/trial gate.

The indexed direct-screen-sharing fixture defines recovery reason and setup
outcome cases. Native recovery cards stay in context, preserve drafts and use
explicit Retry/Reconnect actions. Desktop may restore a compatible viewport;
Terminal reconnect opens a new shell and never restores or replays prior input.

## Desktop baseline readiness, 2026-10-06

Display metadata (1101/1105) MUST NOT mark pixels dirty or establish Desktop
readiness. Initial allocation, resize, host layout changes, resume and leaving input-only mode require
a complete baseline of decoded pixel rectangles before presenting a new image.
Coverage uses two bounded bits per framebuffer pixel, within the existing 96 MiB
framebuffer limit. Black pixels count as received pixels. Valid matching display
geometry excludes only gaps between displays; unknown geometry requires the whole
framebuffer. Overlapping rectangles count once. Retain the last presented image
while waiting; queued images from an older allocation/lifecycle epoch are rejected.

The existing initial nonincremental request remains. An incomplete baseline may
request up to two additional nonincremental refreshes, at least one second apart.
After eight seconds without a complete baseline, end with a recoverable desktop
loading error. No infinite retries, content inspection, or input replay. Diagnostics
contain only readiness, rectangle/pixel counts and refresh counts, never pixels.

## Saved login editing

Edit Mac offers separate Desktop and Terminal password-login editors. The current
login stays in its existing device-local, non-synchronizable per-Mac/service
Keychain item until explicit Save. Fields are masked/privacy-sensitive and drafts
are cleared on dismissal/background. Editing does not connect, alter a Mac account
password, change SSH trust, or change the selected key. Failed/unreadable Keychain
reads block saving; failed writes preserve the draft and the previous saved item.
Validation uses the existing service credential bounds.

## Mac identity presentation and tap destination, 2026-10-08

The direct client may browse `_rfb._tcp` and `_ssh._tcp` in `local.` and query
the same instance's `_device-info._tcp` TXT `model` value. Discovery is bounded
to eight seconds and 128 service instances, only while foreground and unlocked.
It resolves service hosts and numeric addresses for presentation matching only.
It never dials, imports addresses, changes ports, authenticates, or selects a Mac.
Permission denial, missing advertisements and resolution failures preserve manual
setup and the last detected metadata. Reuse persisted metadata on launch,
foreground entry and ordinary editor entry. Automatic detection runs only for a
new Mac's valid addresses or edited address/service-port endpoints, with input
debouncing. Saving before that debounce completes still starts the bounded scan.
An unchanged draft does not repeatedly scan. Refresh Mac Details in the editor
and pull-to-refresh in My Macs explicitly refresh metadata, including previously
unknown models and renamed Macs. Foreground/unlock resumes no automatic scan;
inactivity still cancels an active scan without publishing partial results.

Match only exact normalized configured hostnames or numeric addresses, with the
corresponding saved Screen Sharing/SSH port. Do not match by display name, substring,
or guessed hostname. Multiple distinct matching hosts are ambiguous and cannot
update a record. Publish metadata only after the bounded scan completes; partial
resolutions cannot change saved metadata or an editor's automatic name, including
Save during a scan. Cancelled scans cannot publish partial results. Prefer the
Screen Sharing service name over SSH for the same host.
TXT model data is associated with its exact service instance and domain; it is
bounded to 128 ASCII model characters. Names are trimmed, bounded to 80 characters
and reject control/format characters. These values are untrusted presentation
metadata, never peer identity, authentication, grants, or proof of a Mac model.

New Macs use automatic names by default, with My Mac as an editable fallback.
Existing records retain custom names and opt into Use Detected Name explicitly.
Changing a name disables automatic naming. Detection may update a custom record's
model and detected name but cannot replace its custom name. Unknown models retain
a generic Mac icon. Recognized model families use MacBook, iMac, Mac mini,
Mac Studio or Mac Pro symbols; opaque Apple model IDs use a bounded reviewed table.
Address/service-port edits invalidate previously detected metadata.

Each record saves Open on Tap as Desktop (default), Terminal, or Trackpad &
Keyboard. Row taps open that destination using existing entitlement, login, SSH
trust and connection behavior. The explicit Connect menu overrides it for that
one opening; it does not change the saved default. Session resume URLs retain
their explicit destination. Changing this preference does not start a connection.

Library version 4 adds usesAutomaticName, detectedName, modelIdentifier and
preferredConnection with backward-compatible decoding of versions 1–3. Missing
fields mean custom naming, no detected metadata, and Desktop. Invalid fields
block replacement of stored data. Edits, automatic metadata saves, and optional
iCloud sync retain each record's UUID, separate saved credentials and preferences.
Opt-in sync disclosure includes detected names/models and tap destinations.
The existing indexed direct-screen-sharing fixture defines these cases.

Opaque model mappings are based on Apple's model identification references:
[MacBook Pro](https://support.apple.com/en-us/108052),
[MacBook Air](https://support.apple.com/en-us/102869),
[iMac](https://support.apple.com/en-us/108054),
[Mac mini](https://support.apple.com/en-us/102852),
[Mac Studio](https://support.apple.com/en-us/102231), and
[Mac Pro](https://support.apple.com/en-us/102887).
Bonjour privacy declarations follow Apple's
[TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

### Direct-client cached cursor images


Both native iOS and Mac direct clients advertises Apple cursor encoding 1104 (`0x450`)
through the existing authenticated classic RFB transport. This does not select
Apple's encrypted record layer or alter authentication, ClientInit or input.
Compatibility with a particular Screen Sharing host requires live verification.
A rectangle contains a big-endian uint32 opaque cache identifier and uint32
compressed length, followed by exactly that many zlib bytes. A positive length
stores and selects an image: rectangle width/height are 1–256 and its hotspot
must be inside the image. The decoded payload is exactly width × height × 5
bytes: BGRA pixels followed by a separate alpha plane. Preserve fractional alpha
by converting to premultiplied RGBA. Finished and complete sync-flushed zlib
streams are admitted; corruption, truncation, trailing data, extra output and
compressed lengths above 512 KiB fail the owning connection safely.

A zero compressed length selects a cached identifier, including when rectangle
geometry is zero. Unknown identifiers clear the shape to the local fallback;
identifiers have no semantic meaning. Cache at most 64 images and 4 MiB of pixel
data per socket owner, evicting the least recently used. Clear the cache on new
connection and teardown. Cursor metadata must not satisfy framebuffer coverage
or fabricate a video update. Existing pause, retirement and presentation epochs
also fence these reports. The live-delivery section below defines automatic
update arming and incremental requests; encrypted input remains unchanged.

Both generated direct-client builds deliver empty standard cursor reports through
the exact hash-admitted upstream callback adapter. Standard and Apple reports
replace the shape at the current pointer position even without video damage.
Brief inactivity hides the cursor overlay while retaining the current socket
owner's decoded shape (including a transparent shape), hotspot and position.
The active return restores that presentation without requiring another cursor
report. On the same retained connection, background hides presentation and invalidates
position while retaining the decoded shape/hotspot. Restore the shape after the
current resume boundary without requiring a new host shape report; do not restore
a stale pointer position. An image received before the first complete desktop
frame survives initial geometry setup. Geometry changes invalidate position,
not a valid same-owner shape. Replacement, teardown and explicit empty/unknown
shape reports clear it. Cursor publication cannot cross a pending resume boundary.
Content-free report, visible-image, publication and cache-miss counters describe
wire delivery without claiming context semantics or live host compatibility.


## Live Apple cursor delivery

The direct clients request standard XCursor/RichCursor and Apple cached-cursor
encoding 1104. Decoding a STORE or SELECT is insufficient to keep the server
sending subsequent changes: the classic Apple framebuffer sender must also be
armed. On iOS and macOS, the same socket owner may use Apple's automatic-update control only after
an Apple 3.889 server banner, successful existing ARD authentication and a valid
version-5 display layout matching the bounded framebuffer. Other servers keep
ordinary incremental requests. No authentication, banner reply, encryption or
remote display configuration changes are introduced.

The admitted **classic** control is 16 bytes: opcode 9; three zero reserved bytes;
a big-endian uint32 update period in microseconds; then big-endian uint16 x, y,
width and height. Enable uses period 0 and the full current framebuffer;
disable uses period 0xffffffff and the last subscribed framebuffer. Coordinates
are zero. Positive dimensions must pass the existing 16384-axis / 96-MiB bounds.
This period-based classic layout is verified against the macOS server's opcode-9
reader; do not substitute the separately described high-performance session
fields. The exact enable/disable byte vectors are in the sole indexed VNC fixture.
A zero period adds no delay after the last pixel update. The host also gates
CursorPos delivery on this period; a positive delay can starve host-position
reports while pixel requests continue completing. Transport backpressure still
applies. Busy-screen input responsiveness and host-position delivery require
physical acceptance independently of the byte-vector tests.

Enable after valid layout delivery, renew on every subsequent 1105 layout report
(including an identical layout at an agent transition), framebuffer allocation
or foreground resume, and disable before background-pause completion, input-only
mode or socket retirement. Invalid/unsupported layouts disable this extension.
These controls are owner-serialized. No timer or additional connection is used.
Keep LibVNCClient's response-driven incremental requests active alongside Apple's
automatic delivery. Automatic delivery arms cursor updates but does not replace
incremental requests on a quiet physical desktop. After a complete update,
including a cursor-only update, request changes in the full bounded framebuffer;
never add a polling timer, unbounded request loop, or repeated full refresh.
Explicit baseline refreshes still write non-incremental requests. Suppress requests
only while paused or input-only; the empty update rectangle also prevents a late
capability refresh from requesting pixels in input-only mode. Input-only mode
never enables automatic desktop delivery.
The existing baseline/input/presentation epochs remain authoritative, and the
paused owner sleeps after its bounded release/disable work.

This is a compatibility extension based on the host implementation, not an
Apple-published API. The current server reader interprets bytes 4–7 as the period
and enables automatic delivery unless they are 0xffffffff; bytes 2–3 have no
admitted semantics and remain zero. Independent reverse-engineering also
documents automatic arming and renewal as necessary for live cursor delivery:
[iShareScreen cursor and update notes](https://github.com/renegadelink/iShareScreen/blob/main/docs/apple_vnc_rfc.md#83-cursorimage-0x450)
and [remotex display arming](https://github.com/andrewtheguy/remotex/blob/main/docs/apple-vnc-889.md#the-display-layout).
Physical shape changes remain an acceptance check separate from synthetic wire,
pause/resume and presentation tests. Only numeric delivery counters and aggregate local handling/queue durations are
retained. These durations start when the client handles a server message or
decodes a cursor; they do not measure the host-to-client latency.

## Input service during desktop reads

After the iOS or macOS direct-client RFB handshake succeeds, the sole socket owner installs a
per-client read-service callback and places its RFB descriptor in nonblocking
mode. While a desktop message is incomplete, LibVNCClient services the admitted
input queue before reading more bytes and between waits, at most 10 milliseconds
apart while no new bytes arrive. This is cooperative service on the existing
owner, never a concurrent writer or recursive server-message parser.

Service preserves the existing FIFO, input epoch, held-key/button bookkeeping,
composed-text cancellation and foreground/review/pause/stop admission checks.
Pending release, resume or mode changes must return to the outer owner loop
before new input is serviced. The callback is absent during authentication and
removed before client cleanup. Failed writes still end the connection. The
pinned upstream checkout remains pristine; the generated source adapter admits
only exact recorded header/socket transforms and their patch hashes.

This does not alter authentication, encryption, RFB input bytes, cursor ownership,
automatic-update pacing or SSH transport settings. Incoming cursor metadata must
still wait behind earlier bytes in the same ordered stream. Cooperative service
removes one client-side input wait; it does not prove end-to-end host latency.

## Cursor presentation latency and host movement

The sole receiver MUST drain any bytes already buffered by LibVNCClient before
waiting for socket readability. The library's socket wait does not consult its
read buffer; a cursor report read ahead with image bytes must not wait for a
later network packet. Test a coalesced message batch followed by silence.

On iOS and macOS, publish a decoded cursor shape or position as soon as its
rectangle has been consumed. Do not wait for the remaining desktop rectangles,
framebuffer coverage, or frame publication. Coalesce queued main-thread delivery
to the most recent cursor snapshot of the same socket owner and presentation
epoch. Pause, resume boundaries, replacement and Stop still retire stale snapshots.
This removes client-side waiting after a cursor arrives; it cannot bypass earlier
bytes on the same TCP stream or guarantee host/network latency.

Advertise Apple cursor-position encoding 1100 in addition to standard PointerPos.
An Apple position rectangle contains framebuffer-pixel x/y in its rectangle
header and no payload; do not consume a length or pixel bytes. Its width/height
are zero. Treat it as cursor metadata, never framebuffer coverage or damage.
Apply in-bounds positions to the existing cursor overlay and preserve its decoded
shape/hotspot. An out-of-bounds position becomes unknown. Crop and foreground
presentation rules still apply, and no position is inferred when the host sends
no report. Indexed vectors are in `vnc-desktop-tunnel-v0.1.json`.

A cursor publication includes a position only when that publication carries a
new valid position report. A shape-only change must never replay a cached host
coordinate over a locally predicted pointer. Coalescing a new position with a
shape preserves that position until delivery, but does not make it fresh twice.
On iOS, host position following is automatic and has no setting or menu action.
Render one persistent cursor using the latest actual host shape/hotspot (with an
arrow fallback until a shape arrives). Its displayed hotspot is also the target
for the next Trackpad click. Local input moves this cursor immediately and sends
the same framebuffer coordinates to the Mac. Lifting a finger does not hide the
cursor or adopt a cached host position. There is no separate local aiming ring.

While any local finger, pointer gesture or held drag is active, host observations
may update shape but cannot reposition the visible cursor. Position publications
from a server-message read that began before newer local input are also excluded
from reconciliation. After 200 ms without local contact/input, adopt newly delivered host positions into both
the visible cursor and next-click target together, without generating input.
Discard reports received during that settling interval; never replay them later
from a timer. This interval is a conservative admission gate, not a freshness
acknowledgement. Filter differing positions found among the last 512 distinct local input targets
(including the position at the start of touch). Keep this replay history only in
memory, and retire it at new-connection or framebuffer-geometry boundaries.
A shape-only publication must never move the cursor. In indirect mode, host
positions outside the selected display crop do not replace its visible input
target. Changing that crop retires replay history and initializes an out-of-crop
indirect target at the new crop center. Display selection is not changed by host
movement.

This is conservative automatic reconciliation, not proof of freshness. An old
report outside the bounded history can look like new host motion; genuine host
motion to a retained old local target may be suppressed until it moves elsewhere.
Do not claim that a coordinate match or any timer acknowledges input execution.
RFB positions carry no host timestamp, origin identifier or input acknowledgement.
No unverified Fence command, heartbeat input, polling motion, helper or protocol
change is introduced. macOS position admission remains unchanged.

The single cursor remains visible after finger lift and with touch indicators
disabled. Direct Pointer retains contact/click feedback; video-free Trackpad &
Keyboard shows finger feedback without a desktop cursor overlay. Lifecycle and
presentation epochs still retire obsolete callbacks; review, foreground and
session readiness continue to gate input. Before any local control, retain an initial valid host observation even while
sign-in or the first desktop frame is being presented; this does not enable
input or expose a hidden desktop. A connection with no position report
may initialize its predicted pointer at the center of the selected crop.

Latency diagnostics may retain bounded numeric aggregates for message wall time,
worker-thread CPU time, local unread byte counts, frame copying/presentation,
and SSH relay byte counts/write completion time. Separate post-baseline samples
from initial desktop loading. CPU time is not network latency; unread bytes do
not establish report age, and a relay write completion is not a remote input
acknowledgement. Diagnostics must never retain packet bodies, credentials,
endpoints, screen pixels, keys, or pointer coordinates. Instrumentation must not
change update pacing or transport selection. Cursor presentation diagnostics may
record only booleans distinguishing host-position availability, local aiming,
foreground/readiness and the selected interaction presentation. They must not
retain positions, action arguments, text or endpoints, and no successful local
write is represented as host consumption.

The source implementation documenting this header-only encoding is
[remotex's Apple protocol receiver](https://github.com/andrewtheguy/remotex/blob/main/src/vnc_apple.rs).
The 1100 layout is an interoperability extension rather than an Apple-published
API. Authentication, encryption and remote input packets are unchanged.

## iOS credential management revision, 2026-10-15

The shared local Login & Access profile and active-owner mutation guards in
[Direct Files](direct-files.md#ios-shared-access-revision-2026-10-15) supersede
separate saved Desktop/Terminal password management on iOS. Screen Sharing still
requires its Mac account/password; SSH-key overrides apply to Terminal and its
Files channel. Desktop-originated Files uses Desktop's authenticated SSH account.
SSH host-key verification and all ARD/SSH wire authentication remain unchanged.

## iOS cursor interaction feedback, 2026-10-15

Desktop Pointer, Desktop Trackpad, video-free Trackpad & Keyboard and tabletop
input show local finger indicators using the existing Touch & Haptics settings.
Pointer uses the touched desktop location; Trackpad keeps its indirect aiming
position. Touch feedback never prevents or delays the actual recognizers.
An admitted click pulses once and a held drag strengthens the finger ring.
These effects acknowledge local gesture/input admission, never remote execution.
Only a visible remote result confirms that the Mac acted on the input.

Video-free Trackpad & Keyboard shows finger feedback without a desktop cursor
overlay. Pause, interruption, review, recovery, presentation and mode transitions
retire current finger feedback. Rejected clicks produce no success pulse/haptic.

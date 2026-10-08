# Direct macOS Screen Sharing development profile v1

Decision: 2026-10-04. The normal iOS VNC development composition is a standalone
client of built-in macOS Screen Sharing, with no Mac Companion host or Agent.
The historical paired protocol remains compatible but is not instantiated here.
This is a separate connection profile, not an unauthenticated fallback from a
failed paired connection. Permanent Release admission is still gated.

## Connection and authentication

Connect to the user-selected saved Mac's ordered list of 1–8 endpoints, TCP port
5900 by default, optionally 1–65535 in Advanced settings. Resolve
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

The only production authentication scheme remains Apple ARD (30) using the
pinned upstream implementation. No no-auth or legacy VNC-password fallback is
allowed. No application pairing/authentication/signature semantics are added.
Login fields must be nonempty, contain no NUL, and fit the upstream 63-byte UTF-8
payload without truncation. Credentials are supplied only to this selected
endpoint. No logs contain credentials, host addresses, names, typed content,
framebuffer pixels or cursor shapes/positions.

ARD's credential encryption does not encrypt the subsequent RFB pixel/input
stream and does not pin the server identity. Direct setup discloses that this
development connection is for a trusted local network; encrypted transport is
a release gate. The viewer must never inherit the paired tunnel's encryption
claims. Pinned upstream `HandleARDAuth` encrypts the login structure only.

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
Disconnect button is presented. Explicit exit does not reconnect automatically. Background cancels a pending
handshake. An established connection cancels queued input and pauses its native owner
without closing the socket. A bounded in-flight read may finish before sent
keys/buttons are released. Once release completes, the owner sleeps: no frame
decoding, new update requests, UI presentation or remote input runs while paused. A bounded
UIKit background task only finishes input release and the paused status update,
ending immediately on completion
or expiration; it does not maintain an idle connection or stream in the background.
Foreground requests a full framebuffer on the same owner. Input remains blocked
until a complete framebuffer arrives. If the socket fails or no framebuffer arrives
within 9000 ms (allowing the bounded baseline refresh window), retire it and make one automatic reconnect attempt. Do not loop
retries or overlap native owners. Background/foreground calls are idempotent.
Preserve the selected display ID, relative zoom, viewport center and mouse mode;
reapply only to matching dimensions and verified layout after reconnect. Changed
or missing displays fall back to All Displays and fit. A manual retry remains
available after the automatic attempt fails.
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

## Optional session Live Activity

“Show session in Dynamic Island” is enabled by default, persisted locally and
independent of connection recovery. The ActivityKit widget has no network client,
credentials, remote input or background execution mode. Its scoped End Session
LiveActivityIntent runs in the app process without foregrounding it.
Publish Connected only for a foreground, ready native owner. Publish Paused as
soon as the app resigns active; publish Reconnecting while checking/replacing the
connection. End immediately on Done, terminal failure or opt-out. A dismissed
activity is not recreated for that session unless the user opts back in.
Connected status has a short stale date; stale presentations show “Tap to resume”
instead of promising a live socket. Paused status becomes stale after 15 minutes.
Only the user-assigned Mac name, opaque saved Mac UUID, Desktop/Terminal kind and phase reach ActivityKit;
no address, account login, pixels or input content. The resume URL accepts only
maccompanion-session://resume/<UUID> or maccompanion-session://resume-terminal/<UUID>
for an existing saved record, with no query,
fragment or credentials. It opens the existing viewer when already selected;
it cannot create an endpoint or start a parallel session. An already presented
Desktop or Terminal is kept; a Terminal link cannot accidentally open Desktop.
Old activities without a kind retain Desktop semantics. Activities left by a
previous process are ended before starting a new one. No APNs or vendor server
is added. Permanent extension identity/signing admission remains gated.

Compact presentation shows a one-line Mac name with a bounded width and a phase
symbol; expanded and Lock Screen presentations show the name, status,
Resume and End Session. The expanded name may use two lines and truncate to fit,
retaining its full accessible label. Its compact ending action may say End,
with the accessible label End Session. Phase text and actions use the full-width
region below the camera, with inset spacing from the curved edges. Expanded
presentation has no glyphs in the camera-adjacent top regions. Minimal
presentation retains the desktop symbol. A stale
presentation says Paused rather than Connected. End Session targets the opaque
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
Close on explicit exit or actual transport failure. Inactive/background transitions
MUST retain an established SSH channel and PTY, pause automatic transport reads,
clear armed modifiers and stop admitting input. An incomplete handshake or key
installation still cancels on inactivity. A bounded UIKit background assertion
finishes read-pause and Live Activity status updates, then ends within one second
or on expiration; it MUST NOT maintain idle background runtime or polling.
Output already in flight is kept only in a bounded 1 MiB memory buffer, never
rendered while inactive/locked or written to disk. Overflow ends the session with
an actionable error rather than dropping bytes. Foreground/unlock re-enables reads,
flushes pending output in order and applies the latest PTY size to the same shell.
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

## SSH key login and opt-in iCloud library sync

Terminal MAY authenticate with an Ed25519 user key using standard SSH public-key authentication. Keys are created using system cryptographic randomness or imported from a bounded OpenSSH document (maximum 32 KiB). Encrypted imports require their passphrase and bounded bcrypt work (1 through 128 rounds); decoding runs away from the UI actor. Invalid, unsupported, or mismatched key material MUST fail before opening a connection. There is no automatic password fallback. Host-key verification still precedes user authentication.

Named keys have stable UUIDs independent of Macs. A device-local library holds up to 256 keys and explicit per-Mac selected-key/account associations in the existing non-synchronizable, WhenUnlockedThisDeviceOnly Keychain group. Sharing one key across Macs and choosing separate keys are equally supported; the UI MUST NOT recommend either arrangement by default. Legacy per-Mac keys migrate idempotently, retaining the original entry until the new record and association are durably saved. Failed migration MUST preserve the original. Editing addresses or removing a Mac MUST NOT delete a library key used elsewhere. Deleting a key clears its local associations, requires confirmation, and does not claim remote revocation. Unreadable or malformed library data MUST NOT be overwritten.

Private keys and passphrases MUST NOT appear in logs, fixtures, diagnostics, clipboard or cloud library records. Public keys can be copied/exported. Explicit private export requires fresh device-owner authentication, a nonempty passphrase, and a standard encrypted OpenSSH Ed25519 document (aes256-ctr with bcrypt, 32 rounds and fresh salt/check words). Export preparation runs off the UI actor, uses the pinned standard library primitives, and clears temporary documents when dismissed, locked or backgrounded. Plaintext private-key export is not offered. Validate interoperability against OpenSSH, not just the matching importer.

The individual saved Mac settings page offers Install Key on This Mac. The user chooses a library key/account and explicitly supplies bootstrap password or an existing working key. Standard host verification precedes authentication. Installation sends only the public key to that account's ~/.ssh/authorized_keys, preserves all existing lines/options, rejects unsafe symlinks/file ownership, fixes private permissions, and avoids duplicating the same key even when its comment differs. Duplicate detection parses only the actual algorithm/blob fields after any quoted options, never trailing comments. It needs no helper, sudo or server configuration change. Do not automatically retry a command of uncertain outcome. Verify a fresh key-only SSH authentication before saving the selected key/account; retain the bootstrap login and report unverified installation if verification fails. Cancellation/background closes the connection and suppresses late success.

Terminal keyboard accessories show a 1–0 number row whenever the software keyboard is open and standard Esc, Tab, Ctrl, Alt, arrows and additional navigation/function keys. Software modifiers apply once, including Backspace, then release; explicit long press locks them. Shift applies standard shifted symbols to the accessory number row. Legacy Ctrl-Backspace sends control-H and Alt prefixes Escape; enhanced keyboard mode uses its modifier parameter. IME composition deletion keeps the native text-input path. A grouped native range deletion produces only one Ctrl/Alt-modified deletion for the logical keypress; ordinary deletion retains the native count. Input is encoded as xterm data, respecting application cursor mode. Modifiers clear on keyboard dismissal, disconnect or background, and no input is replayed. Command shortcuts are local copy/paste actions, not fabricated remote macOS key events. Pro-only customization permits bounded layouts and saved snippets; the standard number/modifier rows remain free.

## Lifetime Pro and permanent free access (2026-10-05)

The official client has an optional lifetime non-consumable Pro product (`media.jenny.maccompanion.pro.lifetime`, US base price $9.99) and Restore Purchases. Verify StoreKit transactions, their product/type and revocation before unlocking. Resolve initial entitlements before denying paid actions. Listen for updates and read current entitlements without a custom account/server or per-session online purchase check. Cancelled, pending, unverified and unavailable purchases never unlock Pro or delete user data. Display StoreKit's localized price only when the product is available. The development StoreKit configuration is testing-only and never establishes App Store product availability.

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

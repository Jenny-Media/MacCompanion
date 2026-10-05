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
two fingers pan it in Pointer. Pinch and two-finger double tap stay local.
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
within 1500 ms, retire it and make one automatic reconnect attempt. Do not loop
retries or overlap native owners. Background/foreground calls are idempotent.
Preserve the selected display ID, relative zoom, viewport center and mouse mode;
reapply only to matching dimensions and verified layout after reconnect. Changed
or missing displays fall back to All Displays and fit. A manual retry remains
available after the automatic attempt fails.
Returning to My Macs permanently retires that viewer. Late native frame, cursor
and status callbacks cannot revive a stopped or replaced connection.

## Authoritative fixtures

`spec/fixtures/manifest.json` indexes `direct-screen-sharing-v1.json`. It contains
numeric endpoint, login and version-5 Apple display-layout boundary cases for
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

## Session interface and local preferences

Use a focused Mac login card with username/password AutoFill fields, password
visibility and optional per-Mac retention. Saved logins start automatically.
Show actual contacting/signing-in/opening-desktop phases and Cancel; present the
desktop after its first frame. Show actionable failures and allow editing login.
Healthy sessions hide routine Connected text. Connection problems remain visible.

The keyboard/modifier strip remains directly available. One bottom-right glass
controls button opens quick actions, Displays, Input and Session categories, with
one Exit to My Macs action. Press-and-slide is a primary interaction: open while
held, highlight with haptics, commit only on release, cancel outside actions or
when backgrounded. Capture those touches locally; no menu gesture becomes remote
pointer input. Ordinary tap and accessibility actions provide equivalent access.
Exit uses a deliberate tap. Panels stay inside safe areas and above the keyboard.
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
Only the user-assigned Mac name, opaque saved Mac UUID and phase reach ActivityKit;
no address, account login, pixels or input content. The resume URL accepts only
maccompanion-session://resume/<UUID> for an existing saved record, with no query,
fragment or credentials. It opens the existing viewer when already selected;
it cannot create an endpoint or start a parallel session. Activities left by a
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

Before any user authentication, compare the canonical OpenSSH host key. On first
connection, show the SHA256 fingerprint and require explicit trust. A changed key
fails closed and requires forgetting the saved key in Edit Mac before reconnecting.
Never silently accept a changed key, and never use acceptAnything. Fingerprints hash
the decoded SSH public-key wire blob, using SHA256/base64 without padding. The indexed
synthetic vectors are authoritative. Save trust only on an explicit affirmative action.
Open an xterm-256color PTY, forward bytes in order, propagate row/column resize, and
close the SSH channel on exit/background. Never replay shell input on reconnection.
Remote OSC clipboard reads are denied and writes/URL launches require user action.

## SSH key login and opt-in iCloud library sync

Terminal MAY authenticate with an Ed25519 user key using standard SSH public-key authentication. Keys are created using system cryptographic randomness or imported from a bounded OpenSSH document (maximum 32 KiB). Encrypted imports require their passphrase and bounded bcrypt work (1 through 128 rounds); decoding runs away from the UI actor. Invalid, unsupported, or mismatched key material MUST fail before opening a connection. There is no automatic password fallback. Host-key verification still precedes user authentication. The decoded private seed is stored only in the existing per-Mac, non-synchronizable, WhenUnlockedThisDeviceOnly Keychain. Private keys and passphrases MUST NOT appear in logs, fixtures, diagnostics, exports, or cloud library records. Only the public key can be copied. Removing the local key does not revoke a public key already installed on the Mac.

iCloud library sync MUST default off on each installation and require explicit consent after a privacy disclosure. It uses synchronizable generic-password items in the app's existing Keychain access group, protected by iCloud Keychain; it does not introduce custom cryptography, a CloudKit container, or app authentication. Sync transports saved Mac UUIDs, names, ordered addresses, ports and non-content session preferences. Passwords, SSH private keys, accepted server keys, saved text, custom actions, app-unlock consent and the sync opt-in itself remain device-local. Cloud data never establishes server trust or opens a session.

Each device writes its own bounded record versions, ordered by logical revision then device UUID. A validated newer tombstone suppresses a deleted Mac without deleting local credentials. Malformed, oversized, duplicate, unsupported or unreadable cloud data MUST preserve local records. Cloud work occurs only while opted in and the app is unlocked; refresh is performed on foreground and explicit request, never per input event. Local saves remain usable offline. Disabling stops reads and writes and retains local Macs and existing cloud copies. Deleting cloud copies is an explicit, separate operation with a warning to disable other devices first. The UI MUST distinguish local Keychain submission from confirmed delivery; it cannot report a successful multi-device sync without evidence.

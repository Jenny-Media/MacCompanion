# Remote-desktop MVP decision

Decision: 2026-10-04, explicitly requested by the product owner. This supersedes
the paired Mac-host product decision of 2026-10-03.

The first product is one iOS app connecting directly to built-in macOS Screen
Sharing. There is no required or optional Mac Companion host/helper installation.
The journey is enable Remote Login and Screen Sharing once, add a Mac in the phone, enter the Mac
account login, then connect. Login retention is optional and local to Keychain.
My Macs supports multiple Macs, each with ordered local/private-VPN addresses,
advanced port configuration, names, editing and removal. Saved logins and view/input
preferences are isolated by Mac UUID. Version-1 records migrate on successful edits.
Address/port edits preserve that record's saved login. Different entries can share
an endpoint and still keep separate logins; a shared-address note is informational.

The development path is described by
[direct Screen Sharing](../spec/capability-protocol/v0/direct-screen-sharing.md).
It bypasses the legacy application identity, pairing, Control leases, Agent/XPC,
and desktop tunnel. Existing legacy keys/grants are preserved for compatibility;
they do not authorize or authenticate direct connections. Changing to direct
connections requires adding a Mac address and its Screen Sharing login once.

Pointer, scrolling, keyboard, one-shot modifiers, shortcuts, cursor, pan, zoom,
Done (disconnect and return to My Macs) and background recovery remain core.
Established sessions pause input/frame processing while retaining the socket;
foreground checks it, then makes one replacement attempt if needed, preserving
valid viewport settings. Dynamic Island/Lock Screen session status is optional
(default on), and its toggle does not change connection recovery. The compact
island identifies the Mac with a bounded one-line name and status symbol. Expanded
and Lock Screen views offer Resume and End Session. End Session uses the activity's
unique ID to stop only its matching viewer, retire recovery and remove the island;
it works through an app-process Live Activity intent without opening the app.
No indefinite
background execution is promised. Two-finger double tap toggles
tap-centered zoom and fit. Exact window fitting and the app/window picker are
deferred because their host metadata depended on the removed helper. Never
infer individual display boundaries from an assumed horizontal arrangement.
Request bounded Apple display metadata directly over VNC. Offer individual
display crops only when verified metadata agrees with the framebuffer, and
retain All Displays for hosts without supported metadata. Pointer and Trackpad
are the two mouse modes; hold-and-move provides dragging in either mode.

This direct development implementation connects to validated local IPv4/IPv6
and shared-address-space IPv4 endpoints, including Tailscale addresses. Both devices
need an active private VPN route for remote access. Automatic address fallback stops
after the first TCP connection, before Mac authentication. It uses the existing pinned LibVNCClient Apple ARD login implementation.
Transport revision: 2026-10-09. The iOS client dials the saved SSH port with
validated numeric addresses, verifies the Mac's SSH host key, and opens one
`direct-tcpip` channel to 127.0.0.1 on the saved Screen Sharing port. SSH encrypts
the full desktop and input stream. No plaintext fallback or local TCP listener
is permitted. Desktop and Trackpad & Keyboard need both built-in Remote Login
and Screen Sharing; Terminal needs Remote Login. They share the Mac UUID's SSH
server trust but keep their saved logins separate. Desktop authenticates SSH and
ARD with its entered Mac account/password; Terminal keys are not silently reused.
The app does not provide a public relay or direct public endpoint connection.
Production Simulator, physical-device, licensing and distribution acceptance
remain separate gates; a passing standalone tunnel probe is not release admission.

Observe/Act, custom session confirmations, alternate host engines, vendor relays,
accounts, helper installation and audio are outside this MVP. File transfer is
an approved follow-up described below.
Permanent Apple identities/signing, dependency admission, licensing delivery,
packaging and physical reliability gates in `docs/execution-status.md` remain.

## Session controls follow-up

Desktop and Terminal use a compact connection card centered in the available
region over a blurred passive saved-Mac list until connected. The card has no
drag handle implying swipe dismissal. Reduce Transparency uses an opaque
backdrop. A shared identity header, grouped credentials, quiet Save login and one
full-width primary action keep entry focused. Desktop and Trackpad & Keyboard
share this card and its adaptive layout, including folded-screen keyboard
avoidance; the header identifies the selected mode.
All three modes use an elevated system surface, adaptive edge and soft shadow
over a theme-aware dimmed backdrop. Progress Cancel uses native blue styling.
Healthy Connected text is hidden. The desktop pans behind the status icons with UIKit's
native scroll-edge treatment; Fit uses the unobscured region to keep the full
selected display reachable. Sign-in and input-only mode retain safe-area layout.
Keyboard/modifier controls remain directly accessible,
and a docked keyboard reduces the desktop viewport with the system animation.
Dismissal restores the prior zoom/center when the display crop remains valid;
the keyboard button reflects Show Keyboard or Hide Keyboard.
One floating controls button provides structured Displays, Input and Session
actions. Its category and picker popovers open above the button, with pushed
submenus retaining the same anchor and long menus scrolling when space is limited.
Press-and-slide opens while held, highlights actions and commits on release;
menu touches are captured locally and cancellation never sends input. Tap and
accessibility equivalents remain available. Trackpad speed is adjustable and
accelerated independently of zoom. Restore the last per-Mac display only against
verified current metadata. Custom quick actions support balanced shortcut chords
and sending saved text as typing, with content held only in protected local Keychain.

Keep Pointer Visible defaults on per Mac and is configurable in the session’s mode-specific Controls settings.
In zoomed Trackpad mode, iPhone pointer movement and dragging pan the view only
near its edges, retaining zoom and the selected display. Manual pan/pinch pauses
following until the next trackpad gesture. Mac-originated cursor notifications
do not move the view. Following uses the existing image and gesture-paced scroll
offset updates, with no idle polling, helper or connection change.

### Trackpad touch feedback, 2026-10-08

Trackpad & Keyboard, Desktop Trackpad and the tabletop input pad share soft
finger rings that follow touch immediately and fade on lift. An admitted tap
pulses once with a light system haptic; hold-to-drag strengthens the ring and
plays one distinct haptic when the drag engages. Movement, scrolling and pinch
use visual feedback without continuous haptics. Feedback describes local input
recognition, not a remote execution receipt. Global Show Touch Points and
Trackpad Haptics choices default on and can be saved independently in Desktop
or Trackpad Controls, before connecting or during a session. Menu haptics retain
their separate preference. Reduce Motion replaces the expanding tap pulse with
a fade. Feedback clears on cancellation, mode/layout changes, menu presentation,
sign-in, background and disconnect. No touch positions are persisted.

### Approved client additions, 2026-10-05

The user approved optional local Face ID/passcode app unlock, fullscreen controls,
Trackpad & Keyboard without desktop video, reliable Pointer tap admission, and an
SSH Terminal using built-in Remote Login. These remain iOS-only with no Mac helper.
Local app content loads concurrently behind an opaque privacy cover during unlock.
Desktop and SSH retain separate credentials and protocol/security behavior.

### Appearance and menu organization, 2026-10-05

App Settings offers System (default), Light and Dark appearance for app content,
login, controls, native menus and the privacy cover. Terminal colors separately
offer Follow App (default), Light and Dark. Changing either choice does not replace
the remote session or change the Mac's appearance. Desktop letterboxing remains
black; input-only help uses the app background.

The Mac menu groups Desktop, Trackpad & Keyboard and Terminal under Connect, and
editing/removal under Manage Mac. Credential removal lives only in Edit Mac, with
separate Desktop login, Terminal login and SSH server-key confirmations.
App Settings groups Appearance, Controls, SSH Keys, Sync & Security, and Help.
The library gear opens Settings directly; Help contains Set Up Your Mac. Open
settings and nested sheets observe appearance changes without being recreated.

The floating session menu groups View & Display, Keyboard & Input and Session.
Customizable quick actions follow saved order from the top of the grid and support
tap and press-and-slide. Customize opens an input-free preview of the same native
renderer with drag reordering, accessible move actions and an inline inspector.
The Add Action sheet offers standards that aren't already visible. All changes,
including confirmed Restore Defaults, remain drafts until Save; Cancel discards them. Mac
uses menu rows with the same labels as its session menu. Hidden legacy actions,
profile scope, Pro gating and the 15-total/12-custom limits are preserved.
On iOS Desktop, the default first quick-action row is Mouse Mode and Copy Text;
Fit to Window and Right Click follow. Existing saved profiles keep their choices
and order; Add Action offers Copy Text. View & Display also contains Copy Text
from Screen. This free tool freezes original received pixels with the visible
area selected. Adjust the crop locally, recognize with on-device Vision, then
review and edit text beside the image before Copy or Share. Return to Live
Desktop restores the viewport when its geometry still matches and waits for a
fresh complete frame before reopening remote input. Background, app lock and
session closure clear the temporary review. Terminal and video-free Trackpad &
Keyboard do not offer extraction. macOS clipboard integration remains separate.

Extra Keys groups editing, navigation and special keys; gesture help is separate.
Terminal offers its own keyboard and color
controls. Its persistent modifier bar puts a keyboard toggle on the left and
the shared controls button on the right, with scrolling middle keys on narrow
screens. Number and admitted custom-key rows appear while the software keyboard
is open. Keyboard & Input has a free Show Number Row choice, default On, which
applies immediately and is remembered across sessions. The separate button dock
and menu-based keyboard toggle are removed.
Each remote session has one exit action returning to My Macs.

Desktop and Terminal entry automatically start one connection attempt when a
usable saved login is available. An incomplete login shows account fields and one
Connect action. Active attempts show concise progress and Cancel; setup and
connection explanations live in Connection Details. Login failures appear inline
above retained fields; detailed explanations and fixed diagnostics remain available
under Connection Details. Confirmed SSH-key rejection offers Set Up Key and Use
Password without claiming that a missing public key is the only possible cause.
The layout scrolls for the keyboard or large text and retains compact landscape
credential columns. SSH identity verification still
precedes authentication. Entry and trust-sheet dismissal never retry a failure
automatically.

Connected Terminal is headerless and keeps its emulator mounted across recovery
and layout changes. Its floating controls support tap and press-and-slide, with
Keyboard & Input, Appearance and Session categories. Quick actions include the
keyboard toggle, Paste, Ctrl-C and Done. The number/modifier accessory remains
available while typing; Fn opens extra keys and saved snippets.

### SSH keys and optional iCloud library sync, 2026-10-05

Terminal offers Password or SSH Key login and a named key library. Create or import
Ed25519 OpenSSH keys, rename them and choose a key per Mac/account. Sharing keys
and choosing separate keys are both supported equally. Existing per-Mac keys migrate
durably; removing a Mac clears its selection without deleting a library key.
Public keys can be copied/exported. Private export requires fresh device-owner
authentication and a nonempty passphrase, producing bcrypt/AES-256-CTR OpenSSH
format. Private keys stay in device-only Keychain, and SSH host verification still
precedes any authentication.
RSA/ECDSA and hardware-backed keys are not yet supported. Desktop authentication is
unchanged; SSH keys apply to Terminal only.

Each saved Mac's settings contains **Install Key on This Mac**. The user chooses
a target library key and authenticates with an existing password or working key.
Setup appends only the public key to that account's `authorized_keys`, preserving
other entries and options, rejecting unsafe links/ownership, enforcing private
permissions and avoiding duplicate blobs. A fresh key-only login to the same
verified SSH endpoint must succeed before the saved key selection changes.
Timeout/cancellation never retries the remote command automatically; a partial
installation may remain on the Mac. Nothing installs a Mac app or helper.

### Terminal keyboard and lifetime Pro, 2026-10-05

The software keyboard includes an optional number row, enabled by default. Ctrl/Alt are one-shot on tap
and explicitly locked on hold; Shift, navigation, function keys and common
Ctrl-C/D/Z shortcuts are available in More. Modifiers reset on focus/session loss.
Keys honor application-cursor mode. Pro adds a custom row and protected local
snippets; snippets containing a newline can execute commands on explicit selection.

The basic free tier has no session expiry: one saved Mac, one SSH key, Desktop,
Trackpad & Keyboard, basic Terminal, standard keys/number row, multiple addresses,
ports, displays and zoom. Security, accessibility and key import/export stay free.
Lifetime Pro is one non-consumable purchase for multiple Macs/keys, automatic key
setup and custom keys/actions/snippets. Existing extra records remain editable and
exportable; users can choose the active free Mac/key without deleting data. A
refund or entitlement change never terminates an active connection.

The approved US base price is $9.99 for Lifetime Pro. An optional free non-consumable
14-day Trial unlocks all Pro features for 14 days from its verified original purchase
date. Restore/reinstall cannot reset it. There is no automatic charge or renewal;
basic features remain free after expiry. The Pro screen shows the original end date
and a separate localized lifetime upgrade price before the user starts the trial.

StoreKit verifies the product and transaction type, handles restore and refunds,
and reads local entitlements without a per-session online requirement. The checked
in StoreKit configuration is synthetic local testing only. Real App Store Connect
product approval and review remain separate distribution steps. App Store Connect
now contains Mac Companion (6819496840), Lifetime Pro (6819497277) and 14-day Trial
(6819497930); creation does not mean the purchases are approved or publicly available.

iCloud sync is opt-in and defaults off per installation. A consent screen discloses
the exact synced fields and reliance on Apple Account, trusted-device and iCloud
Keychain protection. Sync uses the existing Keychain access group, with no new Mac
helper or Apple container. Saved Mac UUIDs/names/ordered addresses/ports and display,
mouse-speed/mode, fullscreen and Follow Cursor settings sync. Passwords, private
keys, accepted server keys, saved text/actions, app appearance and app-unlock/sync
consent remain local. Foreground and explicit refresh merge bounded versions and
tombstones, preserving local data on failure. Opting out preserves local Macs and
existing cloud copies; removing cloud copies is a separate confirmed operation.
The app distinguishes Keychain submission from actual cross-device delivery.

### Control profiles and gesture audit, 2026-10-07

App Settings → Controls exposes Desktop, Terminal and Trackpad & Keyboard before
connecting. The matching session settings edit the same shared per-mode quick
actions; pointer speed and Follow Cursor remain per Mac. Existing per-Mac Desktop
quick actions are retained and used until the Desktop profile is saved. Custom
actions remain Pro; basic connection, keyboard, pointer and scroll stay free.

Session menus use Disconnect, an information symbol for Connection Details and
consistent category symbols. Cancel keeps native non-destructive styling. Fit
uses inward arrows; Hide Keyboard uses the keyboard-dismiss symbol. A right-click
action keeps its explicit label, because a pointer glyph cannot identify a mouse
button by itself. Keyboard is used for generic shortcuts, including Terminal
shortcuts that do not have a remote Command modifier.

Two-finger scrolling previously required 18 points per wheel tick; it now requires
six, with at most eight balanced ticks per update and no deferred input. Pinching
currently zooms the local Desktop image, not a Mac app. Input-only mode hides that
image, so its local pinch recognizer is disabled and the guide explains the limit.
Native Mac trackpad magnification is not transmitted by this direct RFB client.
The user’s intended pinch behavior is still awaiting clarification.

### Mac identity and connection defaults, 2026-10-08

My Macs detects the advertised computer name and machine family on the local
network and uses a matching Mac icon. Add/Edit Mac offers Use Detected Name; custom
names remain supported and existing names are preserved. No metadata advertisement
means the saved fallback name and generic icon remain available, including VPN-only
connections. Pull to refresh retries local discovery. Detection installs nothing
and does not connect or change saved routes.

On iPhone, Open on Tap in each Mac's settings chooses Desktop (default), Terminal or
Trackpad & Keyboard. The Connect menu still opens any mode directly. These settings
are free and participate in the existing optional iCloud library sync.

On macOS, the approved 2026-10-09 scope exposes Desktop and Terminal only. A
shared Trackpad default resolves to Desktop without changing the iPhone record;
the native editor preserves it on unrelated edits. See `native-macos-client.md`.

## Settings presentation follow-up

Both clients share compact Mac-details and bounded port fields, structured sync
information, credential privacy guidance, and the Pro presentation. iOS Open on
Tap uses a native menu and a consistently trailing-aligned selected value with
its menu indicator on the same baseline. Require Unlock uses available local authentication terminology; lock
triggers remain platform-specific. Deleting the app's iCloud metadata now uses a
review sheet and final destructive confirmation. Cancellation has no effect;
confirmed deletion retains local Macs and credentials. Other devices with sync
enabled can upload their retained metadata again, so deletion is never presented
as an immediate verified global wipe. This changes presentation and confirmation,
not the Keychain transport, version schema, merge rules, or credential scope.

Pro benefits are informational content with a short Free Version list. Price is
read from StoreKit. Purchase/trial terms sit beside their actions, and operation
progress has a stable location with separate load/purchase/trial/restore states.
The system purchase sheet remains authoritative; cancellation is quiet and
pending approval leaves the app usable. In compact-height or accessibility iOS
layouts, the purchase area scrolls with the content so its controls stay reachable.

## Files companion feature, 2026-10-10

The approved follow-up adds free native SFTP browsing, folder creation and individual
file uploads/downloads to both clients. It adds no connection mode and uses the
existing Remote Login service, SSH login/key settings and host trust. Files owns
its connection independently of Desktop and Terminal. See
[Direct Files v1](../spec/capability-protocol/v0/direct-files.md) for scope,
transfer safety and lifecycle requirements. Rename, delete, folder transfers and
automatic resume remain deferred.

## iOS interruption and return policy

Established Desktop and Terminal sessions distinguish temporary foreground
inactivity from actual background entry. Inactivity releases held/queued input
without replacing the transport or changing the displayed crop. Background entry
pauses frame processing or SSH reads. The one-second background assertion bounds
input cleanup independently of ActivityKit completion; a slow status update cannot
kill a transport whose input release already completed. An observed connection
end retires ownership synchronously and dismisses the Live Activity independently
of pending status updates, even while the viewer is backgrounded. Late completion
of an older update cannot retire or update a replacement activity.

A returning Desktop preserves the cached selected-display crop while a fresh
frame and the replacement connection's display layout converge, in either order.
Only a verified missing selection falls back to the full desktop. Input remains
gated until presentation is ready, including Compose Text entry and delivery.
Video-mode changes wait for replacement restoration to finish. A compact indeterminate indicator appears
after one second of real restoration/reconnection work and disappears on
readiness; brief inactive returns do not show it. The existing one-replacement
limit and nine-second resume deadline remain. Terminal does not silently create
a replacement shell or replay input. Grid changes while inactive are deferred;
return publishes the latest dimensions to the same PTY before fresh input.

Require Unlock continues to default to immediate locking after background entry.
An explicit, local 30-second preference can reuse a recent successful unlock on
foreground return. Access is revoked throughout background entry, and reuse
requires an active app, protected data availability, and an unexpired monotonic
deadline. Protected-data loss, preference changes and process restart discard
reuse. Transient inactivity does not show a lock cover. Actual background entry covers
the app snapshot; valid grace reuse restores presentation before active admission.
Successful current Face ID authentication and current active state admit the main
interface together with controls, credentials and unlocked publication. A success
that arrives while inactive retains the same opaque Unlock card until activation;
the button changes from Unlocking to Opening and stays disabled. There is no
separate branded transition screen; Unlock becomes available for an explicit
foreground retry after failure or cancellation;
activation that arrives first waits for the result. Already-active success proceeds
without another lifecycle event or guessed animation delay. A completed canceled
or failed attempt requires explicit retry. Background/protected-data loss retires
pending success; ordinary interruptions and configured grace retain their policy.
These are local presentation/access gates; legacy application-authentication,
pairing, signatures and recorded grants remain unchanged.

The Island provides contextual return and End actions. Paused/stale content does
not claim that a remote socket or shell remains alive. Stale content offers Open
to Check, and an observed session end immediately ends the activity. Fresh
connection evidence renews a bounded connected freshness date; background state
is always presented as paused. The system may suspend execution, so detection of
a later remote close and timed activity dismissal are not guaranteed while the
app is suspended. No helper, APNs publisher or indefinite background mode is added.

Simulator/AppKit regression checks verify software transitions and synthetic
input only. Signed Passwords/1Password selection, real iPhone authentication and
long-background behavior require final acceptance; physical Vision Pro is used
only for final visionOS acceptance.

The optional unlock grace uses a continuous monotonic clock, including device
sleep, so suspension or wall-clock changes cannot extend its 30-second limit.
Terminal return keeps the last SSH evidence timestamp. Re-enabling reads on an
existing local socket does not verify the peer; fresh SSH output renews status.

Opening a Terminal Live Activity after its owner view or process is gone loads
sign-in details without auto-connect. It explains that the previous session
cannot be recovered in this app; Connect is an explicit choice to open a new
shell. Ordinary Mac-list entry retains the saved-login convenience.


### iOS two-finger secondary click, 2026-10-14

A short two-finger tap sends one balanced standard RFB secondary click. Desktop
Pointer targets the touched location; Desktop Trackpad, video-free Trackpad &
Keyboard and the tabletop trackpad keep the current remote cursor position.
Scrolling, pinching and cancelled or retired touches must not become clicks.
Desktop retains its existing two-finger double-tap smart zoom with precedence
over secondary tap; video-free Trackpad & Keyboard has no image zoom to wait for.
Mode/layout changes, inactivity and opening controls retire pending tap gestures.

Compose Text remains the first free default Quick Action in all iOS modes,
including Trackpad & Keyboard. Untouched old defaults gain it on read. Saved
customized profiles keep their visibility and order; Add Action offers Compose
Text without requiring Pro. Mode changes and reopening controls use the current
profile, and the video-free session can compose without receiving desktop pixels.

## iOS shared Login and Access, 2026-10-15

On iOS, one device-only Keychain profile per saved Mac is the credential authority.
Desktop and Trackpad & Keyboard use its default Mac account/password. Terminal
inherits that login unless an explicit SSH password or named-key override is
configured. Each private key remains in the existing shared key library; the
profile stores only a key reference and account. Differing legacy SSH logins
are preserved as overrides before old password items are cleaned up. An empty
canonical profile never falls back to stale legacy data.

Mac Settings has one Login & Access entry. Login, authentication method and key
selection are read-only while this Mac is connecting, connected, reconnecting or
closing. Disconnect & Edit warns about transfers and waits for teardown. Other
Macs stay editable. Global key management permits cosmetic renames and unrelated
new keys; a key in use cannot be deleted. Initial unsaved sign-in remains possible;
connection forms do not create independent saved login stores.

Files is an expandable companion sheet from Desktop, Trackpad and Terminal.
It opens SFTP on the originating session's authenticated SSH client, with no
second password prompt or password copy, including when Save Login is off.
Standalone Browse Files defaults to the Mac login, with an explicit SSH-override
choice; a key-only setup uses its SSH override. It starts no video or shell. Files shows its actual account and retains its folder and foreground
transfers when the sheet closes. Ending a parent session can interrupt its Files
channel after a transfer warning; completed downloads remain accessible through
Browse Files. New sessions never replay a transfer automatically. Transfers and
results remain bound to their original Mac/account. See the iOS revision in
[Direct Files](../spec/capability-protocol/v0/direct-files.md). macOS and visionOS
retain their existing access behavior.

### Persistent iOS pointer and automatic host following, 2026-10-15

Desktop shows one persistent pointer using the Mac's streamed cursor shape. Local
movement immediately updates its position and sends that target to the Mac;
lifting a finger leaves the cursor visible, and the next Trackpad tap clicks at
its displayed hotspot. Host following is always enabled without a menu option.
While local fingers/gestures are active, incoming positions cannot move it.
While idle, newly delivered host positions update the visible pointer and next
click target together. A bounded in-memory history rejects recognizable older
local targets. This cannot establish freshness: a genuine host move to an old
local target may be suppressed, and an unrecognized delayed report remains
ambiguous. No host execution acknowledgement or perfect handoff is claimed.
Shape-only updates never reposition it. The cursor stays visible independently
of Touch & Haptics indicators; input-only mode shows finger feedback without a
desktop pointer. Keep Pointer Visible only pans a zoomed viewport. No Mac helper,
new wire extension or automatic cursor probing is introduced.

### Connection naming, 2026-10-15

Screen Sharing is the visible connection name on iOS, macOS and visionOS.
Existing `desktop` record values, restoration IDs and credential accounts stay
unchanged. On iOS and visionOS it opens the in-app remote screen, described as
View and control this Mac. The isolated Mac prototype opens Apple Screen Sharing
in a separate application, with an external-app arrow and Opens Apple Screen
Sharing subtitle. Terminal remains an independent action. No combined launch
or workspace terminology is required in the interface.

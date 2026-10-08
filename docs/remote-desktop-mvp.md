# Remote-desktop MVP decision

Decision: 2026-10-04, explicitly requested by the product owner. This supersedes
the paired Mac-host product decision of 2026-10-03.

The first product is one iOS app connecting directly to built-in macOS Screen
Sharing. There is no required or optional Mac Companion host/helper installation.
The journey is enable Screen Sharing once, add a Mac in the phone, enter the Mac
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
ARD protects the login exchange but does not establish encrypted framebuffer or
input transport, or our former pinned host identity. The setup must disclose this
and must not label the desktop encrypted. Secure transport and public distribution
remain release gates. The app does not provide a public relay or direct public endpoint connection.

Observe/Act, custom session confirmations, alternate host engines, vendor relays,
accounts, helper installation, audio and file transfer are outside this MVP.
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

Follow Cursor defaults on per Mac and is configurable in the session’s mode-specific Controls settings.
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
App Settings groups Appearance, Security and Session options.

The floating session menu groups View & Display, Keyboard & Input and Session.
Customizable quick actions stay nearest the controls button and support tap and
press-and-slide. Extra Keys groups editing, navigation and special keys; gesture
help is separate. Mode-specific Controls uses a section-scoped Reorder control and
Save/Cancel for all preference drafts. Terminal offers its own keyboard and color
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

# Native direct macOS client v1

This platform extension uses the existing direct Screen Sharing and SSH profiles.
It does not instantiate the historical paired host protocol. The authoritative
native input/ownership cases are `spec/fixtures/native-macos-client-v1.json`,
indexed only by `spec/fixtures/manifest.json`.

macOS exposes Desktop (Screen Sharing) and Terminal (Remote Login). The shared
iPhone library retains Desktop, Terminal and Trackpad & Keyboard values. A
shared Trackpad default or a restored legacy Trackpad window resolves to Desktop
on macOS, preserving the window UUID and machine selection. Reading that default
or saving unrelated machine edits must not replace the shared iPhone preference.
An explicit change to the Mac default writes the selected Desktop/Terminal value.
Native Desktop always requests pixels; relative pointer input remains a Desktop
control preference, not a separate connection mode.

Each window has a unique session UUID and an immutable machine/mode selection.
Key, pointer, focus and teardown callbacks are routed to that owner. A callback
from a retired connection generation cannot present pixels, alter a replacement
session, or enqueue input. Closing releases input and retires only that owner.
Background windows continue receiving output. Input requires the corresponding
key window and first responder, local unlock and protocol readiness.

VNC coordinates are relative to the admitted framebuffer/display crop, with a
top-left origin. Fit letterboxing is excluded from input. Drag movement clamps
to the selected crop; an initial click outside it is rejected. Local zoom and
pan do not reconnect or change display resolution. Native key codes map to RFB
keysyms; every held physical key uses its admitted down keysym for release, even
if modifiers change. Focus loss releases held modifiers, keys and buttons.

SSH uses the existing host-key validator, password/Ed25519 authentication and
PTY channel. SwiftTerm's AppKit surface supplies terminal bytes and PTY resize.
Remote terminal titles/OSC clipboard/link requests cannot silently affect local
identity, clipboard or launch applications. Local copy/paste remains explicit.

Native Terminal local clipboard, selection/find and link actions recheck local
unlock at execution. Lock clears selection, composition and embedded Find text,
ends field editing and revokes the window responder. Each owner records only
admitted mouse presses and Kitty press/repeat reports that negotiated release
events. Focus loss releases that
owner's held reports once, using their original protocol and key identity.
Protocol query replies are not held input. Cleanup may finish while locked, but
cannot admit a new press, replay after reconnect, or exceed the existing bounded
SSH write budget. Teardown discards the retired ledger; another owner is untouched.

SGR and SGR-pixel releases retain the original button identity, including normal
AppKit button-up reports. Legacy X10/UTF-8/urxvt releases use their generic release
code. Kitty functional presses with implicit key number 1 or legacy SS3 encoding
require a matching CSI event-type-3 release when event reporting is enabled.

Cursor-only VNC notifications invalidate native drawing and cursor rectangles
without requiring a framebuffer update. Each new VNC window consumes at most one
saved-login attempt after unlock. Later unlock, cancellation and disconnect never
automatically dial. New machine saves recheck current local creation entitlement;
editing a still-existing record and accepting cloud records remain separate.

Development build provenance verifies every remote package checkout against the
admitted revision and clean source contents before and after compilation. A
dirty or changing checkout cannot produce a successful pinned build report.

Sync uses the unchanged direct-client cloud records and service. macOS selects
the data-protection Keychain and the existing iPhone application's authorized
access group. Missing signing/access-group configuration fails visibly; it never
falls back to a separate cloud library. Credential and key stores remain local.

If the existing bounded VNC input owner rejects a key group, retire only that
window connection. Release held input through the transport teardown, discard
pending local input and require an explicit reconnect. Never replay it in a new
connection. Retired display metadata cannot select a crop in a new connection.

The native client preserves the direct iPhone login policy: turning off VNC
login retention removes the previous local login before dialing; a removal
failure prevents the new attempt. Invalid fields do not modify saved data.
Each new SSH key login rechecks access to the actual key displayed in that
window against the current local key library and Pro/free-key policy. Expired
access does not stop an existing shell, but cannot authorize a new one.

Native VNC text input keeps marked text local until the input method commits it.
Commit uses the existing Unicode keyboard owner. Focus loss, lock and retirement
discard local preedit without sending it. Physical shortcuts retain balanced
keys/modifiers; committing composed text first releases those held keys. The
input method can query the local marked buffer, never remote document content.

Native presentation distinguishes the default connection mode from live window
state. The library lists each open connection window by its immutable session
UUID, mode and current phase; raising a listed window does not create or reconnect
a session. Closing removes only that window's status entry. Status is ephemeral,
device-local UI state and is never a cloud record or diagnostic payload.
Session chrome may show connection state and the configured addresses without
claiming which address won routing. iCloud status distinguishes opt-in, active
refresh and errors; local Keychain submission never claims confirmed delivery
to an iPhone. Native text size is a local presentation preference; changing it
may resize that window's SSH PTY but cannot reconnect or change another owner.

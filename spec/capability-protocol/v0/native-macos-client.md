# Native direct macOS client v1

This platform extension uses the existing direct Screen Sharing and SSH profiles.
It does not instantiate the historical paired host protocol. The authoritative
native input/ownership cases are `spec/fixtures/native-macos-client-v1.json`,
indexed only by `spec/fixtures/manifest.json`.

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

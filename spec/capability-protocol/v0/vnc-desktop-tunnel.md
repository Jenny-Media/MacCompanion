# Paired VNC desktop tunnel v0.1

Historical compatibility profile. The 2026-10-04 standalone-client decision in
`direct-screen-sharing.md` supersedes this composition for the normal VNC
development app. Keep existing messages and fixtures compatible.

Decision: 2026-10-04. The normal desktop client migrates to Apple Screen Sharing
through the existing TLS 1.3 pinned, application-authenticated primary connection.
The prototype remains isolated; viewer sources are independently promoted into
the normal development app. Permanent release admission remains gated.

## Authority and compatibility

Pairing and application authentication use the unchanged golden inputs in
`crypto/v0.1.json` and `crypto/interactive-v0.1.json`; the trusted
session-key profile in `trusted-device-session-consent-v0.1.json` is retained.
No new signing key, password-based Mac Companion authentication, or session prompt
is introduced. The Mac account login is solely inner Apple ARD authentication.

Before opening, require the exact active Control session on this primary, both
pointer and keyboard effects, current device/epoch/grant/policy, visible Mac app,
current runtime lease and monotonic expiry. Recheck before each read/write and
at least every 200 ms while idle. Stop, removal, revocation, runtime retirement,
primary loss and lease expiry close the loopback connection. No remote host or
port is accepted: the only destination is 127.0.0.1:5900. Credentials, framebuffer,
input and upstream errors are never recorded. There is no plaintext LAN fallback.

## Closed stream envelopes

Register `desktop.tunnel` on command, null correlation, and
`desktop.tunnel.event` on events, null correlation. Both bodies contain exactly
`tunnelID`, `interactiveSessionID`, `operation`, `sequence`, `bytes`.
IDs are canonical UUIDs. Sequence is 0...9007199254740991. Bytes are an array of at most six canonical base64 strings, each at most 4096
bytes of text. Each decoded segment is 3072 bytes except the final segment; the
combined maximum is 16384 decoded bytes. Open/opened/close/closed require an empty
array. Window query/geometry use the fixed payloads defined below.
Client operations: open, data, close, windowQuery. Server operations: opened,
data, closed, windowGeometry.
Open/opened use sequence 0; data increments per direction; close/closed use the
next sequence (closed may be 0 if opening fails before opened). Each direction has its own ordered sequence. Only one tunnel per
primary is active; replacement requires complete retirement and a new tunnelID.
Stale tunnel/session IDs, replay, skipped sequences and oversized data cannot
reach Screen Sharing. Ordinary primary traffic remains framed and correlated.
Server events have no authority to renew the Control lease.

Window queries carry exactly 16 decoded bytes: unsigned big-endian request
sequence (8 bytes), then framebuffer x, y, width and height (2 bytes each).
Sequence must match the envelope stream sequence, remain positive and at most
9007199254740991. Dimensions are positive and at most 16384; the point is inside
the framebuffer. Geometry replies carry those 16 bytes followed by x, y, width
and height (2 bytes each), inside the same framebuffer. An all-zero rectangle
means no window. This bounded metadata is not RFB data and never reaches the
loopback socket. The exact current desktop authority is checked before lookup
and before reply. Geometry supplies no input or renewal authority.

## Development host runtime

The normal VNC development host installs the existing validated execution lease
and visible indicator with a Screen Sharing runtime adapter. It checks the same
Desktop descriptor, current screen permission and matching allowed classes, and
adopts only exact lease renewals. Stop clears the installed binding. It starts no
ScreenCaptureKit stream, H.264 encoder, native host, or legacy media publication.
Legacy surface transitions and media/input preparation are unavailable in this
adapter; VNC input remains subject to the exact tunnel authority above.

The legacy local-XPC media publication deadline and error policy are unchanged.
Publishing unused legacy video without an attached legacy media role waits for
a consumer, then hits the three-second server publication deadline and retires
the local menu connection. VNC must avoid creating that publication entirely.
Permanent Release composition retains its existing admission gates; this normal
development engine selection does not admit a release artifact.

Framebuffer allocation permits positive dimensions through 16384 per axis,
with at most 96 MiB for RGBA pixels. Both limits must pass before allocation.
This admits a combined Retina desktop of 8144 by 2134, which exceeds the earlier
prototype's 64 MiB limit. The render queue still admits only one pending frame;
invalid, zero, oversized or over-budget dimensions fail before pixel allocation.

Display, zoom and pan changes operate within the existing framebuffer. Desktop
Spaces and window resize do not restart RFB. App/window viewing initially focuses
or crops the desktop, with no isolated capture claim. File transfer/audio and
clipboard integration are deferred. RFB client extension requests are disabled.

A selected display is a cropped canvas, not a zoom into the combined image.
Zoom and pan are confined to that canvas; only explicit All Displays selection
shows adjacent displays. Local pointer coordinates are translated through the
crop origin into framebuffer coordinates. Taps outside the crop are rejected;
an active drag clamps to its edges and releases before changing the crop.
An invalid or mismatched display layout supplies no crop and admits no pointer
input until an explicit All Displays choice or valid catalog restores geometry.
Framebuffer updates preserve zoom; canvas size changes refit the selected crop.

Two-finger double tap toggles zoom in and fit view. From any zoomed view,
including a manually pinched view, it returns to fit view. From fit view it
fits the topmost visible Mac window under the tap. If no smaller window is
available, it uses a bounded two-times-fit zoom centered at the tap,
without emitting remote clicks or delaying ordinary single/double clicks. More
also offers Smart Zoom and Fit View. Smart zoom stays inside the selected crop.
Window lookup reads only visible, ordinary window bounds and the current display
union. It sends no names, titles, processes, pixels or input. Layout mismatch or
no window returns no geometry. The client intersects the window with its active
display crop and ignores stale results after selection, resize, Stop or session
replacement. The host still sends the combined RFB framebuffer; selection
does not claim display-only transport, isolation or reduced bandwidth.

## Cursor presentation

The viewer requests the standard RFB XCursor, RichCursor and PointerPos
pseudo-encodings through LibVNCClient's remote-cursor option. These are opaque
RFB bytes on the existing authorized Desktop tunnel; they introduce no Mac
Companion envelope, authority or host endpoint. The viewer installs both
shape and position handlers, retaining at most one pending cursor presentation.
Cursor updates carry the same generation fence as framebuffer presentations.
Stop, backgrounding, disconnect and framebuffer resize clear cursor state.

Decoded cursor shapes admit positive dimensions through 256 per axis, four-byte
little-endian BGRX source pixels, an in-bounds hotspot and a byte-per-pixel mask.
Conversion produces bounded RGBA data with zeroed transparent pixels. An invalid
or unsupported shape uses a local outlined pointer rather than retiring video.
Server positions and immediate local pointer feedback translate through the
selected display crop. A cursor outside that crop or the visible canvas is
hidden. Native cursor presentation keeps its hotspot aligned and its longest
dimension between 24 and 64 screen points for visibility. The fallback pointer
has a fixed size. It never intercepts gestures or modifies framebuffer pixels.
Cursor pixels, hotspots and positions are not written to logs or persistent
storage; only shape/position update counts may be reported.

## Remote keyboard

Toolbar modifiers are one-shot selections, not persistent remote key-downs.
Tapping Shift, Control, Option or Command arms/disarms that modifier locally.
The next committed key sends selected modifiers down, the key down/up and
modifiers up in reverse order as one bounded, ordered queue admission. Selection
then clears. Only the first scalar in a multi-scalar text commit consumes the
selection. Escape, Tab, Return, Backspace and arrow keys follow the same rule.
Marked text is not sent until committed.

Holding a toolbar modifier sends that modifier alone as a balanced down/up pair
and clears pending selections. The More menu also exposes Shift only. Stop,
backgrounding, connection failure and disconnect clear local selections; no
modifier selection carries into another session. Overflow cannot enqueue half a
shortcut. Existing session retirement and release of actually sent held keys
remain enforced. These rules do not change pairing, tunnel authority or framing.

## Inner login retention

Mac login retention uses a separate per-paired-host Keychain item with
WhenUnlockedThisDeviceOnly, no user-presence flag or synchronisation. It is never
placed in the pairing record, defaults, logs, backup files or website. Removing a
Mac removes its saved inner login. This setup choice does not alter host identity,
keys or recorded grants. Public release remains subject to existing Apple gates.

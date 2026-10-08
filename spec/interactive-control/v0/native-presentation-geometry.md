# Native presentation content geometry v0.1

Status: normative local geometry boundary; no presentation wire record or input
admission is introduced by this document.

Native presentation must distinguish logical Mac points, capture-mode pixels,
encoded pixels and client viewport points. A future authenticated presentation
receipt must join the exact current Control/native/surface generations and a
trusted host capture geometry before either input gate opens. A connected or
first-frame callback, viewport, or geometry value alone is not input authority.

The first geometry primitive covers unrotated Desktop aspect-fit capture.
Encoded dimensions are 320…8192 by 240…8192; capture dimensions are 1…32768;
logical dimensions are positive UInt32 values. Rotation/cropping and geometry
changes require separate admission. Capture dimensions come from the menu's
selected display capture mode, never from client guesses or encoded dimensions.
Logical dimensions come from the acknowledged Desktop descriptor. The menu's
native backend owner joins those logical bounds and rotation to current selected
display measurements, retains immutable capture-mode geometry before the inert
factory, and revalidates it around suspensions and through its watchdog. Physical
display IDs and capture-mode measurements remain menu-local. Missing mode data,
changed logical bounds, changed capture pixels or unsupported rotation reject
preparation or retire the current backend. This remains a host measurement gate;
no clean-aperture or native presentation acknowledgement is admitted.

The encoded source content rectangle is centered aspect-fit capture:
`scale = min(encodedWidth / captureWidth, encodedHeight / captureHeight)`.
Its dimensions are capture dimensions multiplied by scale, bounded by the
encoded frame to canonicalize floating-point edge rounding. Padding is excluded.
This mathematical rectangle is not proof of a particular backend's clean
aperture; backend capture metadata must be joined before input enablement.

The client first aspect-fits the entire encoded frame into its viewport, then
projects the encoded source rectangle into that fitted frame. The existing
input mapper normalizes within this inner source rectangle. Points outside it,
including encoded padding or viewport padding, are rejected. Right and bottom
edges remain half open; outside points are not clamped into valid input.
Trackpad displacement uses the inner content dimensions. Host logical mapping
continues using the acknowledged logical Desktop bounds and existing input path.

The authoritative cases are in `valid/native-video-content-geometry.json`,
indexed only by `spec/fixtures/manifest.json`. They cover full-frame content,
encoded horizontal/vertical padding, nested viewport padding, Retina capture,
chroma rounding, offset viewports, rejected padding/half-open edges and malformed
dimensions. No signing, pairing or grant semantics change.

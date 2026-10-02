# Client viewport and input mapping v0

Status: normative bundle-independent mapping contract. UIKit recognizer wiring,
physical-device ergonomics, accessibility, keyboard-layout behavior, and render
latency remain platform evidence.

## Authority boundary

The client maps local gestures into the already closed reliable input union. It
does not infer host permissions, focus safety, or a wider interaction class.
Every resulting payload still passes through the acknowledged-descriptor input
producer, which supplies the exact session, epoch, surface, coordinate, and
focus fence.

Two local interaction modes are closed for the first alpha:

- `trackpad`: relative one-finger motion updates a client-owned normalized
  pointer initialized at the center; taps click at that current position.
- `directTouch`: a point inside the rendered content rectangle maps directly
  to normalized host coordinates; letterbox/pillarbox regions admit no input.

Mode choice is presentation state, not protocol state. Changing mode while a
drag is held emits `reset` before the new mode becomes active.

Automatic focus-follow is enabled at the start of every live-control
presentation. A verified focus event may select a Focused Region through the
ordinary replacement exchange. If its one-use target expires or is superseded
before any reset or selection request is emitted, the client must select a
fresh Desktop descriptor to clear the paused focus fence and preserve the
Control session. Errors after a selection request is emitted remain
fail-closed. A manual Desktop, Application, or Window selection disables
automatic focus-follow until the user enables it again.

Manual visual zoom is nonmodal: a two-finger pinch changes the local scale at
any time without requiring a separate adjustment state. At magnified scale, a
two-finger pan moves the local viewport; at fitted scale, the same pan remains
remote scrolling. One-finger pointer/touch input remains available before and
after the local gesture. Beginning local magnification or panning emits/reset
clears any held remote input before changing the presentation transform.

## Geometry

The mapper receives finite positive viewport and rendered-content rectangles in
client points. The complete content rectangle must lie inside the viewport.
Direct coordinates use the half-open content rectangle and map its first point
to 0 and its last representable point below the far edge toward 65,535. Results
are rounded to the nearest integer and clamped to 0 through 65,535.

Trackpad deltas are scaled by content width/height and a finite sensitivity from
0.25 through 4.0, then accumulated with saturation. Non-finite values are
rejected before state mutation. Pointer motion may be coalesced only before the
reliable input producer assigns a sequence.

## Gestures and balance

- A direct tap emits exact pointer motion, button down, then button up.
- A trackpad tap emits button down then button up at the current pointer.
- A recognized double tap emits one pointer motion when direct-touch mapping
  requires it, followed by two balanced down/up pairs without an intervening
  pointer move. The host reconstructs the platform double-click state; the
  client does not extend the closed v0 wire payload for this gesture.
- Drag begin emits at most one pointer move followed by one button down; drag
  updates emit only pointer moves; drag end emits the matching button up.
- Repeated begin, update/end without a held drag, an out-of-content direct
  point, or a gesture for the wrong mode is rejected without partial mutation.
- The UIKit surface consumes an out-of-content direct gesture locally. It
  emits no payload and does not close the authenticated input or media roles;
  malformed geometry, inconsistent drag state, and other gesture failures
  remain fail-closed.
- Visual zoom is local presentation state. A transient invalid pinch or pan
  transform resets to the fitted screen locally and emits no remote input; it
  must not close the authenticated input or media roles.
- A finite scroll translation that rounds to zero on both axes is a local
  no-op. UIKit emits no payload for it and must not close the authenticated
  input or media roles.
- Cancellation, backgrounding, surface replacement, rendering loss, or mode
  change while held emits `reset` and clears local drag state.
- Scroll components round to signed integers, clamp independently to -4,096
  through 4,096, and are omitted when both become zero.

## Keyboard

Keyboard and Text are distinct product paths. The remote-keyboard controls may
emit one-shot physical-key down/up pairs for supported USB HID keyboard usages,
including letters, digits, Delete Backward (0x2A), Return (0x28), Tab (0x2B),
Escape (0x29), and arrow keys (0x4F through 0x52). A chord applies its complete
modifier snapshot to the key pair and immediately emits an empty modifier
snapshot so no toolbar action leaves a remote modifier held. Physical keys and
shortcuts require Keyboard authority but do not require an input field or focus
token.

The separate software-keyboard path may emit bounded Unicode `text`. It never
uses the clipboard. The input producer remains responsible for denying text
unless the exact acknowledged focus is non-secure and authorized for text.

The compact keyboard bar may arm a local modifier snapshot for the next key.
With no armed modifiers, software-keyboard commits retain their Unicode text
semantics. With modifiers armed, one supported ASCII key may instead use the
existing balanced physical-key chord path; uppercase and shifted punctuation
include Shift. An unmappable or multi-character modified commit emits nothing,
and must never silently become unmodified text. The local selection clears after
the key, keyboard dismissal, surface replacement, input retirement, or Stop.
Modifier selection itself emits no remote held-key state. This changes neither
the wire payloads nor Keyboard/Text authority or secure-focus checks.

For an exact acknowledged Focused Region whose verified focus category is
`text`, `editable` is true, and `secure` is false, the iOS client may offer a
phone-local composer. The composer reads no Mac value and retains only the
uncommitted local draft. Sending emits one bounded `text` payload under the
surface, coordinate, focus-token, and focus-revision fence captured when the
composer opened. Any pending focus event or changed fence rejects the draft
locally. The user may switch to direct keystroke input without exposing a Mac
field value.

Opening the remote-keyboard controls is local UI and does not perform a focus
transition. Requesting text input first attempts the verified local composer,
including one automatic application of the latest admitted focus event. The
composer may appear only after the replacement is visibly rendered,
acknowledged, and input is active on that exact focus token and revision. If no
eligible composer binding exists, the client falls back to the direct iOS
keystroke bridge when the acknowledged surface still authorizes non-secure
Text input. Physical keys and shortcuts remain independently available under
Keyboard authority.

## Acceptance

Bundle-independent tests cover geometry bounds, letterbox denial, both modes,
drag balance, mode-switch reset, scroll saturation, non-finite rejection,
closed keyboard mappings, and balanced one-shot modifier chords. Release
acceptance additionally requires real UIKit
recognizers, keyboard/input-method testing, VoiceOver and Switch Control,
orientation/scale changes, render-coordinate synchronization, and physical
latency measurements.

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
- Cancellation, backgrounding, surface replacement, rendering loss, or mode
  change while held emits `reset` and clears local drag state.
- Scroll components round to signed integers, clamp independently to -4,096
  through 4,096, and are omitted when both become zero.

## Keyboard

The platform adapter may emit bounded Unicode `text` or one-shot physical-key
down/up pairs for Delete Backward (0x2A), Return (0x28), Tab (0x2B), Escape
(0x29), and arrow keys (0x4F through 0x52), plus explicit modifier snapshots.
It never uses the clipboard. The input producer remains responsible for denying
text unless the exact acknowledged focus is ordinary, editable, non-secure, and
authorized for text.

## Acceptance

Bundle-independent tests cover geometry bounds, letterbox denial, both modes,
drag balance, mode-switch reset, scroll saturation, non-finite rejection, and
closed keyboard mappings. Release acceptance additionally requires real UIKit
recognizers, keyboard/input-method testing, VoiceOver and Switch Control,
orientation/scale changes, render-coordinate synchronization, and physical
latency measurements.

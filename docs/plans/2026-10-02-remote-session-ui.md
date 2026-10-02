# Remote session usability

The user requests improvements before everyday physical testing, using Screens
screenshots as interaction references. The working Shared Display recovery is
committed separately as `2f118fe`.

## Current interface pass

1. Give the display diagram an explicit canvas, positioning tiles by their
   centers inside that canvas. Keep full names and resolutions in readable
   selection rows, including the current-display checkmark. Retain the sheet
   presentation that keeps the admitted renderer attached.
2. Put Keyboard, Escape, Tab, Shift, Control, Option, Command, and session options
   in one compact bar that remains above the native iOS keyboard. Armed modifiers
   apply to the next supported physical key, with balanced release. Ordinary
   Unicode input and existing secure-focus checks remain unchanged.
3. Keep one Close/Stop action, hide the redundant navigation Back, and put display,
   surface, pointer mode, zoom and extended shortcuts in the session menu. The
   single Stop action remains reachable while the keyboard is open.

Verification includes contained runtime tile frames, keyboard-bar placement,
one-shot software-keyboard chords, a single Stop control, fresh presentations
after both display replacements and Window selection, input delivery, Stop/start,
and cleanup. Screenshots and runtime evidence remain private.

## All Displays recommendation

Add a combined live desktop as an optional overview; retain individual display
selection and let the user zoom into one display. This is separate host work:
the current catalog, bootstrap geometry, native backend scope, ScreenCaptureKit
filter and input geometry resolve one opaque selected display to one physical
display. A picker item alone cannot produce a live combined desktop.

The implementation should:

- Represent an explicit aggregate choice with a current, exact set of member
  displays and the Mac's actual arrangement, including negative origins.
- Update the normative selection/capture contract and manifest-indexed fixtures
  before adding protocol or authority behavior. Preserve independent grants,
  exact session/lease/surface bindings, and the existing cryptographic vectors.
- Compose admitted member captures into one bounded frame, accounting for
  different backing scales and empty areas between displays. Retire changed
  topology before fresh admission and prohibit fallback to a broader capture.
- Map remote input back to the correct member display. Empty arrangement gaps
  emit no pointer effects, and local zoom must preserve the same verified mapping.
- Bind the changed host binary, source, native package and signed catalog before
  installation. Verify two-display playback, pointer routing, detach/rearrange,
  keyboard, Stop and host cleanup in Simulator and on the physical phone.

The current interface pass does not expose a nonfunctional All Displays item.

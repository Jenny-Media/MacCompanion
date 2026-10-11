# Native visionOS direct client

The native client uses the same built-in Remote Login and Screen Sharing
services and direct-client contracts as iOS. Desktop must first establish
verified SSH and forward only to the saved loopback Screen Sharing port. It
must not fall back to plaintext VNC. No historical host, Agent, pairing service,
Observe/Act grant, or relay is instantiated. Historical grants remain preserved.

Each Desktop or Terminal window owns a unique session UUID, immutable initial
Mac/mode selection, connection generation and transport. Focus loss releases
held input once through that owner. Closure and reconnect invalidate old
callbacks, trust replies and queued writes. Closing one window cannot stop or
send input through another. Scene interruption suspends input, clears local
composition and sensitive drafts, and leaves reconnection explicit if the
transport fails. Lock covers every scene and invalidates pending authentication.

Native system selection gestures and physical pointer/keyboard events map only
to the focused scene's current remote surface. Gaze hover is not remote pointer
authority. Local composition remains local until committed. Letterbox taps are
ignored; active dragging may clamp to the selected remote crop. Mapping uses
actual framebuffer/display geometry and never assumes a horizontal monitor
arrangement or changes the Mac's resolution.

Hand/direct-touch selection and physical pointer input have distinct public
input-source classification. Brief hand selection below 12 local view points
atomically clicks once at the initial selected location. Movement crossing that
threshold scrolls at the initial remote target, with no primary hold or final
click. A stationary 550 ms hold opens native target actions without remote input.
The first admitted branch wins; cancellation cannot fall through to a click.
Two brief selections within 350 ms and 24 local points use the first target;
each admits one click, never an extra third click. Explicit Double Click admits
two complete click groups. These comfort thresholds remain provisional pending
physical acceptance.

Right Click and Double Click require a current saved target. Drag Item arms that
target once; the next selection must cross the movement threshold before holding
primary. Short selection or cancellation consumes the arm without clicking.
Toolbar Desktop Actions and the configurable Right Click shortcut use the current cursor only when it lies in the visible
selected crop. Otherwise it selects the center of the visible remote area. Its
marker and menu anchor use that same target; no old display coordinate is reused.
Session, focus, display/crop and viewport changes invalidate targets, timers and
arms. An admitted drag releases through its owner on completion/interruption.
Normal gesture completion preserves held physical keyboard modifiers; complete
owner cleanup still releases keys/buttons and discards composition. A key release
whose HID identity was retired cannot reconstruct modifiers from its flags; only
new admitted presses can establish a new held-key owner.
Each connection's native scene owns its content and system toolbar ornament
windows. A key window in that same scene admits its controls; another connection
scene cannot supply admission. Key-window transitions within the owned scene
preserve input ownership. Keyboard requests restore the content window's native
responder explicitly. Scene deactivation and loss of the scene's key window retire
input through that owner.

Physical primary press/drag/release, secondary click, hover and wheel retain
conventional behavior independently of hand scrolling. Hover forwarding applies
only to physical pointer input. Primary and secondary presses capture the input
generation, crop, viewport and local presentation at actual UIKit touch admission,
before tap recognition or drag begin. Completion and delayed drag begin require
that binding and no conflicting selection, target action or view adjustment.
Owner/view changes, selection cancellation and handoff invalidate pending presses;
their later callbacks send nothing and cannot interrupt a newer hand selection.
A fresh admitted touch is required. Fit and local zoom/pan intent also retire
pending presses, including a presentation roundtrip. Cancelled/failed taps do not click.
Wheel fallback accumulates signed displacement
with a 12-point quantum and retained fractional remainder, independent of sample
count; pulse groups are atomic and do not enter the held-button ledger. Native
precise scrolling uses the existing bounded Screen Sharing extension when offered.
Admitted updates up to 16,384 points per axis split into at most eight updates of
2,048 points per axis. Splitting preserves each admitted displacement at the
extension's 16.16 precision, including its signed fractional remainder. Zero
movement starts no native gesture. Owner retirement cancels queued updates and
cannot replay the remainder into a new gesture or connection.
Physical wheel completion, cancellation and failure finish the admitted gesture
even when the final location is outside the rendered content. Translation at an
unmapped location is discarded; each later gesture starts with its own target and
empty fractional remainder.
Physical wheel intent starts only at an admitted recognizer begin, bound to that
owner's input generation, crop, viewport and local presentation, with its initial
remote target. Later updates require the same binding. Retirement, adjustment or
handoff to a selection invalidates it; remaining changed/ended callbacks cannot
start another scroll. A new begin is required. Late wheel completion cannot end
scrolling owned by a later hand selection.
Physical primary dragging also completes only its admitted selection. Owner
retirement and selection cancellation (including adjustment or Keyboard) clear
that recognizer's origin; remaining end/cancel/failure callbacks
cannot finish a later hand gesture or release its button.
Wheel cleanup retires scroll state only. A button held by an active physical
selection remains owned by that selection until its own completion or interruption.
Content follows the local displacement: positive vertical movement uses wheel-up
(8), negative uses wheel-down (16); positive horizontal movement uses wheel-left
(32), negative uses wheel-right (64). The native extension retains its existing
point-delta convention.
No inertial or delayed scroll survives interruption.

Adjust View is temporary and local: zoom is anchored at the intentional target,
stored pan is clamped, and Fit/Zoom/Pan/Done generate no new remote input.
Hand pan applies each movement increment to the already clamped stored position;
reversing after edge overshoot responds immediately without retracing excess
travel. A new selection starts a fresh displacement baseline.
Magnification captures its initial local anchor at begin and retains it when the
pinch centroid moves. Its binding includes owner generation, crop, viewport and
the last presentation produced by that gesture. Owner/view changes, adjustment
exit and end/cancel/failure invalidate it; late callbacks cannot alter the view.
Native text input responds to actual responder focus. Keyboard requests focus
again even when its bar already exists; Done dismisses it. Text-responder loss
releases held input and discards uncommitted composition without sending it.

Terminal emulator query replies may be sent without input focus only while
feeding received SSH output into the emulator. User input is checked for focus
both before enqueueing and before writing. Suspension, lock, closure and
connection replacement block both sources. Remote clipboard reads are denied;
local paste and opening a web link require an explicit action in that window.

Wide and ultrawide (including 21:9 and 32:9) framebuffer content is supported
within the existing bounded framebuffer policy. Standard windows preserve
aspect ratio and allow local fit/zoom/pan. Window size is under user/system
control. As of the public visionOS 27 API audit, system curved windows are not
available to third-party apps. No private curvature keys, selectors or Apple
High Performance/virtual-monitor claim is permitted. Curvature requires a new
public API audit and input/rendering acceptance before admission.

Quick Actions Settings presents only actions supported by the selected visionOS
connection. Desktop Mouse Mode and Copy Text from Screen are absent from the
draft preview, add catalogue and restored defaults. Loading or editing a supported action preserves stored
unsupported entries and their identities; presentation is not a profile migration.
Restore Defaults replaces only supported entries, subject to the existing total
profile limits. Draft editing sends no remote input and retains Pro and unlock gates.

Saved-machine service ports follow the existing direct-client defaults: blank
or whitespace-only Screen Sharing input resolves to 5900, and blank or
whitespace-only Remote Login input resolves to 22. Explicit ports must be from
1 to 65535; invalid input cannot change the persisted record.

Saved-machine metadata and supported connection preferences reuse the existing
opt-in synchronizable Keychain schema and group when a signed profile authorizes
it. Passwords, SSH private keys, trusted server keys, sensitive drafts and consent
stay device-local. Simulator merge tests do not establish device delivery.

Initial PTY output MUST reach the current Terminal emulator. Before the native
surface attaches and completes a usable native layout, output is buffered up to
the existing 1 MiB output bound. A zero-size or provisional two-column emulator
MUST NOT drain startup output;
overflow ends that shell explicitly. Attachment drains bytes exactly once in
order. Session generation changes discard old pending output, and stale surface
teardown cannot detach a newer receiver. Initial banners, prompts, mode-setting
sequences and emulator queries cannot be discarded during presentation.

Metadata sync uses the existing full disclosure and affirmative confirmation
before persisting opt-in. Cancellation and scene interruption leave sync off.
Settings exposes the existing separate Delete Mac Data from iCloud workflow,
including its warning to turn off sync on other devices, local-record retention,
and explicit confirmation. Only the current confirmation in an active, unlocked
owning scene may commit while cloud work is idle. Cancellation, disappearance,
inactivity, background and lock retire that confirmation without replay.
Sensitive SSH import/export drafts, picker requests and pending operations are
cleared or invalidated when their owning scene backgrounds or app unlock locks.
Temporary inactive authentication prompts do not cancel an admitted export.
Completion and picker callbacks require the same current operation generation,
an immutable identity for the initiating presentation, and an active, unlocked
owning scene. Retired success, cancellation and error callbacks cannot read a
file, consume a newer request, or clear newer export state. Each admitted
presentation completes at most once; a denied callback cannot replay after
reactivation. Unsaved quick-action text is also discarded on
background or lock.

Unreadable saved-Mac storage offers explicit Retry and disables creation/editing
until readable. Free users can select another retained Mac without deleting any
record. Save treats a snapshot as an edit only if its UUID still exists in the
current library; recreation rechecks the current creation limit.

The development floor is provisionally visionOS 26.0. Disposable feasibility
sources remain in Experiments and are never linked to the client. Development
identifiers do not authorize permanent identities, shared Keychain groups,
StoreKit storefront configuration or distribution. Existing exact source pins,
cryptographic vectors and release gates continue to apply unchanged.

The authoritative input corpus is native-visionos-client-v1.json, indexed only
by spec/fixtures/manifest.json. Native Simulator/device-SDK compilation, Simulator
behavior, signed hardware acceptance, actual metadata delivery, purchase/restore,
TestFlight and public release are independent evidence gates.

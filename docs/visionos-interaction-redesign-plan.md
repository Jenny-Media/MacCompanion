# visionOS interaction redesign plan

Drafted October 10, 2026, for issue #8 after the user's interaction review.
The user approved implementation on October 11, 2026. The normative contract
and runtime now implement this plan; the final verification and review binding
remain separate from physical acceptance. See the coverage ledger in
`docs/native-visionos-client.md` and external review evidence.

The goal is comfortable Desktop and Terminal use through standard visionOS
interactions, with the development and debugging loop on Simulator. Use the
first-generation Vision Pro running visionOS 27 only for final testing.

## Proposed interaction contract

Remove the persistent Pointer / Scroll / Pan View picker from the primary
Desktop UI. Hand interactions follow this proposed contract:

| Intent | Behavior | Required remote effect |
| --- | --- | --- |
| Click | Look at a target and pinch briefly; allow small movement | Exactly one ordered primary press/release at the initial target |
| Scroll | Pinch and move over the desktop | Wheel events at the initial target; no primary press or release-generated click |
| More actions | Pinch and hold while remaining within movement tolerance | A native menu at the selected target; no remote event merely from opening or dismissing it |
| Secondary click | Choose Right Click in that menu | Exactly one secondary press/release at its saved target |
| Double-click | Two quick pinches within target tolerance, or choose Double Click | Two primary press/release groups at one stable target; no third click |
| Drag a Mac item | Choose Drag Item; the next movement gesture uses that target once | One primary hold during movement, released on completion or interruption; no additional click |
| Adjust local view | Open Adjust View, then zoom/pan; finish with Done or Fit | No remote pointer, button, wheel, or key event caused by view adjustment |
| Type | Press Keyboard to focus/reopen native input; Done dismisses it | Only committed text or explicitly chosen keys reach the current Mac |

Once a selection becomes scroll, context-menu, local-adjustment, or drag
interaction, its release cannot become a normal click. Cancelling before remote
drag activation sends nothing; cancelling an already admitted drag must release
its button. That release does not promise to undo a change made on the Mac.

Drag Item is a visible, one-shot action, not a persistent mouse mode. Movement
must cross the drag tolerance before a hold is sent; a short or cancelled
selection consumes the armed action without falling through to a click. Offer
an explicit Cancel action and clear the arm after use or interruption.

Physical mouse/trackpad events keep conventional primary drag, secondary click,
hover, and wheel behavior independently of this hand mapping. A mouse press
must never be converted to hand scrolling merely because both use a drag event.
Normal click completion must preserve held physical keyboard modifiers.

Use feedback for the selected point after an intentional interaction, plus
standard hover effects on native controls. Screen Sharing supplies pixels, not
Mac button/text-field semantics. Do not infer raw gaze, automatically focus
remote text fields, or add guessed invisible targets over the desktop.

## Implementation order

### 1. Define and prove the event contract

Before changing the native client's input behavior, update
`spec/capability-protocol/v0/native-visionos-client.md` and the existing
`spec/fixtures/native-visionos-client-v1.json`, including its manifest hash.
`spec/fixtures/manifest.json` remains the only fixture index.

Add authoritative traces for click versus scroll versus hold, one-shot dragging,
double-click targeting, cancellation, modifier-click, local adjustment, and
invalidation of a menu/drag target after a session or geometry change. Thresholds
for movement and hold/double-click timing must be documented and independently
testable; initial values remain provisional until physical acceptance.

Reproduce the known failures before replacing their paths: Pan View clicks,
callback-dependent scrolling, modifiers released before click, Keyboard state
out of sync with its responder, and the unhandled Mouse Mode quick action.

Prototype recognition and input-source classification in the normal development
app on Simulator against the synthetic peer. Establish that brief selection,
hold, scrolling, cancellation, and physical pointer capture remain distinct.
If a public event/API cannot support the combination reliably, resolve that
specific case in Simulator and retain explicit native-button alternatives before
proceeding with the broader UI. Disposable API experiments, if needed, stay in
`Experiments/` and cannot enter the normal app target.

Exit condition: actual native-window interaction produces the intended event
sequences, with no overlapping recognition or accidental click after a hold or
scroll. Model tests alone do not close this milestone.

### 2. Separate hand recognition, local view changes, and input cleanup

Refactor `VisionNativeSurfaces.swift` around an explicit per-window interaction
state: idle, pending selection, scrolling, context actions, drag armed, remote
dragging, and local adjustment. The native recognizers use the same controller
exercised by the authoritative traces; tests do not use a separate recognizer
implementation or a direct transport bypass.

Capture the intentional gesture's initial remote coordinate and current session,
display/crop, and viewport generation. Context actions and armed dragging require
that binding to remain valid. Focus loss, reconnect, display selection, resize,
or incompatible view changes invalidate pending actions and timers. Continuous
frame updates alone do not supply new authority or guessed control semantics.

In `VisionDesktopSession.swift`, separate gesture-button completion from complete
owner cleanup. Normal selection completes its own button events while held
Shift/Command/Option/Control remain held. Focus loss, lock, suspension, closure,
and connection retirement still release all input through the correct owner.

Replace per-callback wheel pulses with signed distance accumulation and a retained
fractional remainder. Equivalent movement must produce equivalent wheel events
regardless of event sampling. Validate natural direction and horizontal input.
Start with deterministic distance-based scrolling; add bounded deceleration only
after cancellation and focus-loss tests pass, with no scrolling after retirement.

Exit condition: contract tests and native-window peer assertions pass for each
input source, including modified clicks and cancellation at every transition.

### 3. Implement the native controls and complete typing workflows

In `VisionSessionWindow.swift`, replace the small scrolling control row with a
native toolbar ornament. Keep Keyboard, Displays, Adjust View, and More
discoverable, with gaze-friendly spacing and accessible labels. Disconnect must
remain reachable while the system keyboard is visible. Filter unsupported
visionOS quick actions at presentation time without changing iPhone preferences.

Adjust View is temporary and visually distinct. Include Fit, Zoom In, Zoom Out,
Done, and an accessible pan alternative. Magnification uses the initial gesture
target as its anchor. Clamp stored pan as well as rendered pan so overshooting a
boundary does not create a dead interval when moving back. Keep system spatial
window movement separate from local content adjustment.

Make Keyboard respond to actual focus rather than only input-bar visibility.
Clicking the remote canvas, hiding the keyboard, or changing windows must leave
a coherent state; one press of Keyboard must focus/reopen input again. Show the
destination Mac and use native committed-text/IME input with an explicit Done.
Respect existing composition discard and owner cleanup on interruption.

For Terminal, retain SwiftTerm's native scrollback, text selection, copy/paste,
and text-input paths. Add accessible Tab, arrow, Esc, and modifier actions and
exercise terminal mouse-reporting applications separately. Make New Shell an
explicit new window action; label ending the current shell separately.

Present existing sessions and an explicit Open Another Window action in the Mac
library. Preserve independently owned concurrent Desktop/Terminal sessions.
Review connection forms, submit/focus behavior, trust-sheet cancellation, recovery,
Settings, and enabled/disabled action presentation as complete native workflows.

Audit direct-touch activation, keyboard navigation, VoiceOver labels/order,
larger text, and reduced-motion behavior for native controls. Test available
Simulator accessibility inputs and record unavailable modalities explicitly.
Keep essential actions reachable through native buttons so they do not depend
solely on a timed hold or custom gesture. This improves access to the client;
the pixel-only remote desktop still cannot expose individual Mac controls to
VoiceOver without a separate host-side accessibility design.

Exit condition: the normal app completes the click, menu, scroll, drag, typing,
and Terminal journeys with both correct UI state and correct peer events.

### 4. Expand Simulator evidence and run regressions

Extend the existing `VisionSSHTestServer.swift` interoperability workload with
generated target markers, draggable content, a scrollable area, and a visible
text destination. Update generated frames in response to received input so tests
can assert a visible result as well as packet counts. This remains a generated
test workload, not a second golden fixture corpus or a pretend macOS application.

Record bounded test-only event kind, ordering, coordinate, modifier state, and
timing information for assertions. Reports retain content-free summaries; use
only synthetic credentials/text. Continue using the real Citadel/SSH forwarding,
native renderer, input owner, and library/login/trust journey. The RFB workload
does not establish real macOS account authentication or every Mac application's
wheel/double-click semantics.

Use hosted tests for boundary traces, jitter, callback timing, output ordering,
IME, cancellation, focus changes, and owner cleanup. Use XCUI tests against the
normal app for visible controls, menus, resulting frames, and system keyboard.
Prefer native accessibility elements; recheck rendered geometry before any
coordinate-targeted gesture because projected Simulator coordinates can land in
letterboxing. Assert the keyboard in its owning `com.apple.RealityKeyboard` app,
as well as the client's focused text input.

Run the complete native visionOS suite on stable Xcode 27 with visionOS 27.
Repeat the new combined interaction journey three times on the final source to
check recognizer/timer/focus integration. Preserve each result independently.
Run `bash scripts/validate.sh`, source-bound Simulator and unsigned device-SDK
builds, and relevant iOS/macOS regressions for shared code changes. Resolve or
record the existing macOS hosted-test limitation separately; a pre-existing
failure cannot become a passing result by being omitted.

Exercise the provisional visionOS 26 floor if a runtime is available. Otherwise
record that gap before claiming the floor supported. Unsigned device-SDK
compilation does not contact or validate physical hardware.

### 5. Final physical acceptance

After the required Simulator scenarios pass, use the first-generation Vision Pro
running visionOS 27 for the final real-Mac checkpoint: gaze/pinch targeting,
stationary-pinch jitter, hold-versus-scroll comfort, item dragging, actual
double-click timing, natural scrolling, keyboard reopening, dictation/system IME,
physical peripherals, multiwindow focus, readable ultrawide content, and fatigue.

Any new failure returns to a Simulator reproduction and implementation correction
before another final hardware retest. Actual macOS built-in Screen Sharing input
semantics need this checkpoint even when the synthetic peer tests pass.

## How Simulator will mimic the interactions

Use Device Hub's **Select to interact with the visionOS content** mode for
simulated eyes/hands. Use **Capture Pointer** and **Keyboard Capture** separately
to validate physical-input behavior. These modes are documented in
[Apple's Device Hub interaction guide](https://developer.apple.com/documentation/xcode/interacting-with-your-visionos-app-in-device-hub).

| Intended input | Simulator exercise | What to verify |
| --- | --- | --- |
| Looking without acting | Move the pointer in content-interaction mode | Native control hover feedback; zero remote packets |
| Brief pinch | Click; XCUI native-element tap | One click at the selected point, with visible peer response |
| Hold | Click and hold; XCUI press | Native target menu and zero remote clicks before an action |
| Scroll | Drag or swipe in content-interaction mode | Scroll effect, correct target/direction, no item drag or final click |
| Drag Item | Hold, choose Drag Item, then drag | One continuous remote hold, movement, release, and cleared armed state |
| Double-click | Two native-element taps; explicit Double Click menu fallback | Exactly two complete clicks at the same target and no third event |
| Local pan/zoom | Use Adjust View controls and content gestures | Correct anchor/clamping and zero remote input |
| Physical pointer | Capture Pointer, then hover/click/drag/secondary-click/wheel | Conventional pointer behavior independent of the hand mapping |
| Physical keyboard | Keyboard Capture with modifiers and special keys | Correct key identity and modified click/drag; balanced cleanup |
| Virtual keyboard / IME | Focus native input; interact with the system keyboard | Reopening, composition, committed text, and correct destination |
| Spatial windows | Use the system window bar/corners and vary the simulated viewpoint | Resizing, layout, accessible controls, and independent window closure |

Do not confuse camera navigation with app gestures: Device Hub's trackpad
pinch/navigation controls can change viewpoint rather than content magnification.
First verify whether the installed toolchain can synthesize the app's two-hand
magnification gesture. If it cannot, use real UI zoom controls for integration
coverage and authoritative gesture traces for the model; mark actual two-hand
recognition as unverified until final hardware testing. Treat unavailable
dictation, direct-finger interaction, or accessibility automation the same way.

## Required Simulator acceptance matrix

| Scenario | Required assertion |
| --- | --- |
| Brief pinch with small jitter | Exactly one click at the initial target; cancellation produces none |
| Hold then cancel or choose an action | No unintended primary click on menu opening, selection, or dismissal; only the chosen action's events use its saved target |
| Movement versus hold threshold | Only one branch activates; crossing into scroll never activates a delayed menu |
| Equal scroll distance at different sample rates | Equal signed wheel totals and retained remainder; small deltas accumulate |
| Scroll completion, interruption, and reconnect | No final click, held primary button, or retired deceleration event |
| Armed drag and cancellation | Correct origin and one hold/release; no reused arm or extra click |
| Double-click | Exactly two complete press/release groups, one stable target, bounded timing |
| Shift/Command-click and modified dragging | Modifier remains active through the click/drag and releases at the correct later boundary |
| Adjust View, Fit, zoom, and pan | Zero remote events, stable zoom anchor, bounded pan, no click on leaving adjustment |
| Letterbox and stale context target | No input outside valid content; changed session/display/geometry invalidates old actions |
| Keyboard open, canvas selection, keyboard reopen | Actual system keyboard appears with one button press each time; no misleading stale bar |
| IME, dictation where available, and explicit paste | Composition stays local; committed text sends once; cancellation sends no uncommitted text |
| Terminal scrollback, selection, paste, links, mouse reporting | Correct visible state and SSH input, including explicit link confirmation and bracketed paste |
| Desktop plus Terminal plus second Desktop | Input goes only to its owner; focus loss releases holds; closing one preserves the others |
| Lock, background, resize, display switch, disconnect | Pending gestures/actions retire; input balances; privacy cover and recovery remain correct |
| Standard, wide, and ultrawide desktops | Known targets map correctly at 3440x1440 and 5120x1440 through resize/zoom/pan; Mac resolution stays unchanged |
| Toolbar, forms, Settings, and accessibility alternatives | Controls remain reachable at minimum window size and larger text; labels/focus order and reduced motion work; no enabled action silently does nothing |

Required automated cases must have assertions and cannot be counted as passed
when skipped, unavailable, or only exercised by a model. Each matrix row records
its layer and result: authoritative trace, hosted Simulator, native UI, manual
Simulator, or pending physical. This prevents one green bundle from implying
coverage of every modality.

## Scope and delivery

First delivery contains the interaction contract, hand/physical input separation,
target actions, local adjustment, native toolbar, reliable typing, essential
Terminal controls, and the Simulator matrix. Follow with session discoverability,
form polish, and remaining accessibility alternatives before physical acceptance.

Keep Observe, Act, and Control and their independent grants intact. This work
uses the existing direct-client SSH/Screen Sharing path and adds no custom
authentication, pairing, crypto, Agent, or host permission mechanism. It changes
neither the Mac's display resolution nor existing iPhone control preferences.

Continue flat wide/ultrawide support. Curved system windows require a supported
public API, which Apple currently says is unavailable to third-party apps:
[Apple engineer response](https://developer.apple.com/forums/thread/829696).
Recheck the installed SDK and Apple's guidance at implementation preflight. If
supported curvature becomes available, evaluate it behind a separate gate:
coordinate mapping, menu/drag targeting, local adjustment, and readability must
pass the same Simulator matrix before the feature reaches final hardware testing.
Do not substitute private APIs or a custom immersive surface for that support.
Full remote accessibility semantics, cross-platform file transfer, virtual-monitor
creation, continuous gaze forwarding, and an immersive replacement are separate
projects. Real purchase/restore, signed cloud delivery, permanent identities,
TestFlight, and release retain their existing independent gates.

Deliver a source-bound build report, exact `.xcresult` paths, a scenario/result
ledger, and short captures of the synthetic click/menu/scroll/drag/keyboard
journeys. Keep screenshots, videos, input captures, profiles, credentials, and
other generated evidence outside Git. Preserve unrelated changes and other
Simulator sessions; stop only resources owned by this test run.

The go decision for the final hardware checkpoint requires all required
automated scenarios passing, manual Simulator journeys completed, and all
remaining hardware-only items explicitly listed. Final acceptance additionally
requires comfortable, accurate operation on the first-generation headset.

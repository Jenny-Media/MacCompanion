# Client Primary Live Control Screen Evidence

Date: 2026-08-21

Environment: bundle-independent selected-primary state, iOS SwiftUI/UIKit
composition, and an iPhone 17 Pro Max Simulator on iOS 27.0 with Xcode 27 beta.
This is unsigned construction and synthetic interaction evidence. It is not
physical-device media/input, stable-toolchain, signed-candidate, or release
evidence.

## Boundary completed

The first-party selected-primary workspace now owns the Control product instead
of delegating “Open Remote Control” to an opaque application callback. Observe,
Approved Actions, and Control remain peer sections. The Control entry first
sends a separate full-effect request (`view`, `pointer`, `keyboard`, and `text`)
and exposes the live-screen navigation only after the exact role-channel-ready
state. Requesting authority is therefore not conflated with presenting media.

One main-actor coordinator owns the UIKit initial-Desktop product across SwiftUI
destination transitions. It starts decoder/render/input composition only from
the exact selected role binding, keeps input disabled until the renderer-backed
acknowledgement becomes active, and applies a UI-side 30-second pessimistic
bound matching the primary protocol deadline. Navigating back does not claim or
silently request a remote stop; the active product remains represented in the
Control section and can be reopened.

The live destination uses the actual UIKit video surface full-screen, offers
direct-touch and trackpad interaction modes, and presents an explicit Stop
button. Stop invokes the typed selected-primary end command. The screen disables
input while ending, dismisses only after the exact correlated host receipt
returns the workspace to ready, and retains an explicit retry state when the
Mac cannot confirm teardown. A failed preparation exposes a separate command to
stop the still-authorized session.

## Verification

A value-level workspace test proves that authority request, waiting,
role-channel-ready presentation, in-flight local-product reopening, ending,
and failed-session stop are distinct entry actions. The iOS Simulator target
cross-compiles and renders the concrete coordinator, full-screen view, UIKit
surface, interaction-mode picker, and typed Stop integration.

The active screen also exposes a manually invoked iOS software keyboard. Its
hidden `UIKeyInput` proxy retains no typed text or remote-field metadata. Each
UIKit insertion is validated through the existing bounded text payload path;
Delete becomes the existing balanced HID stroke. Disabling input, terminal
failure, or Stop resigns the responder before resetting and blanking the
surface. This is baseline Desktop input, not a claim that focus-aware Smart
Input is implemented.

The disposable no-network harness injects the production screen with a
synthetic Desktop descriptor and visible placeholder, without a socket,
credential, signer, decoder, or captured pixel. XCTest accessibility automation
reached the screen, confirmed the Touch pointer-mode value, opened the actual
software keyboard, tapped `hello` through the visible keys, observed the
production surface emit nonzero typed input payloads, invoked Stop, waited for
the workspace to return to ready, and confirmed that the keyboard disappeared.
The expanded complete harness run executed six tests with zero failures in
98.213 seconds. Its ephemeral result bundle is under
`/private/tmp/maccompanion-client-ui-harness-derived/Logs/Test/`.

The complete unsigned gate validates 63 indexed protocol/product fixtures,
760 repository files plus 34 historical blob paths and 14 repository-material
fixtures, four Swift package manifests and 12 dependency-policy fixtures,
three privacy manifests with 12 fixtures and six required-reason API source
records, 10 source-SBOM fixtures, 16 release-evidence fixtures, and 1,030 Swift
tests. All macOS/iOS package cross-compiles and all three no-prompt/no-network
construction probes pass. Only the expected read-only user SwiftPM cache
warnings appear.

## Remaining gates

- Prove physical decoding, gestures, Stop, blanking, backgrounding, and latency
  on a signed iPhone and Mac; the synthetic harness does not provide captured
  media or a physical input path.
- Re-run on stable Xcode 26.6 and preserve signed release evidence separately.

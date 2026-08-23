# Adaptive client surface switching

Date: 2026-08-23

## Outcome

The permanent iOS live Control product can now request the Agent's
privacy-limited application/window target inventory and present the existing
first-party surface picker. Desktop remains an unconditional escape hatch.
Selecting Desktop, an application, or a window drives the already-frozen
replacement-surface exchange rather than creating a second remote-control
path.

This checkpoint is bundle-independent construction evidence. It does not
claim a signed physical-iPhone exchange, real ScreenCaptureKit pixels, posted
input, latency, lock-session behavior, or focus-aware Smart Zoom.

## Closed ordering

One activation owner now coordinates both the primary and reliable-input
roles:

1. request and validate the current opaque target inventory;
2. pause input and send the exact sequenced reset on the input role;
3. only then send the correlated surface selection on the primary role;
4. keep all subsequent input inert while replacement media crosses the
   discontinuity, decoder-configuration, and clean-keyframe gates;
5. require concrete renderer proof for that exact clean frame;
6. send the replacement acknowledgement; and
7. resume input only after the exact host acknowledgement reply advances the
   replacement coordinator to active.

The client primary reply owner now routes target, selected, and acknowledged
responses into the same coordinator that owns media and input fencing.
Mutating failure paths retain the coordinator's fail-closed state instead of
leaving a stale pre-error value in the primary owner. Refreshing inventory
also clears the previous result before the new request, so an empty completed
inventory is distinguishable from a pending reply and stale tokens cannot be
returned optimistically.

## Visible product behavior

The live iOS toolbar adds **View**. It fetches a fresh inventory before opening
the picker, exposes only application names and generic window ordinals, and
retains the existing warning that window titles and document names never leave
the Mac. During a switch, keyboard and pointer input are disabled and the live
product returns to active only after the verified replacement frame handshake.

Application and Window Focus are therefore usable without turning Mac
Companion into a Desktop-only product. Focus-aware crop changes, native field
semantics, and host-pushed focus changes still require fixture-first protocol
work and remain outside this checkpoint.

## Verification

- `ClientSurfaceControlCoordinatorV0Tests`: replacement selection requires the
  exact target inventory where applicable, reset, clean-media boundary,
  concrete render proof, and correlated acknowledgement before input resumes.
- `replacementSurfaceOrdersResetBeforeSelectAndAckBeforeInput`: proves the
  cross-role order `reset -> select -> acknowledge -> input`.
- Complete affected test targets: 45 `CompanionInteractiveClientTests` and 46
  `CompanionClientNetworkPlatformTests` passed on the installed Xcode 27 beta.
- `CompanionClientUI` cross-built for `arm64-apple-ios17.0-simulator`.
- The unsigned disposable `ClientUIHarness` built for generic iOS Simulator in
  both simulator architectures, compiling the updated production protocol
  conformance and live-screen composition.
- The repository-wide gate passed 71 indexed fixtures, the 1,468-test Swift
  catalog, macOS/iOS cross-builds, the unsigned permanent application builds,
  and all eight platform probes.

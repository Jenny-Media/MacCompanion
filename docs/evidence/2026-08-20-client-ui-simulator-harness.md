# Client UI Simulator Harness Evidence

Date: 2026-08-20

Environment: unsigned disposable iOS target, iPhone 17 Pro Max Simulator on
iOS 27.0, Xcode 27 beta. This is compatibility and interaction evidence only;
it is not stable-toolchain, signed-product, physical-device, Keychain, network,
or release evidence.

## Scope

`Experiments/ClientUIHarness` is an intentionally disposable Xcode project
that links the local `MacCompanionKit` package. It has no network calls,
credentials, private keys, Keychain access, background modes, Apple-managed
capabilities, or permanent bundle identity. It uses one temporary durable route
store plus synthetic authenticated dial results; it never opens a socket. Its
values cover:

- the pairing entry surface without beginning pairing;
- ambiguous DNS/public-address route classification without publication;
- saved-route edits without durable or network effects;
- Ready, approval, controlling, locked, background, and no-network host states;
- privacy-limited Desktop, application, and numbered-window selection.
- application-global UIKit activity and injected reachability driving the real
  configured-route lifecycle binding.
- a complete granted-only Approved Actions catalog, schema-driven Boolean
  parameter editor, effect disclosure, and typed schema-verified synthetic
  result without a socket, credential, signer, or Control session.
- the production first-party live-Control screen injected with a synthetic
  Desktop descriptor and placeholder, but no socket, credential, signer,
  decoder, captured pixel, or physical input path.

The harness uses public conformance-fixture public keys only to decode an
immutable paired-host record accepted by the production bootstrap-plan API.
No corresponding private key is present or usable.

## Results

The app built with code signing disabled, installed, and launched on the booted
Simulator. Visual inspection confirmed that Observe/Act, private-route setup,
and optional Control remain separate top-level groups and that the root screen
explicitly states that the target has no networking or credentials.

Five UI tests then passed through XCTest's accessibility automation:

1. `testClosedSurfacesAreSemanticallyReachable` traversed the host summary,
   Approved Actions, pairing entry, first-pairing route choices, saved-route
   editor, and surface picker. It changed the schema-owned mute Boolean, waited
   for its accessibility value to become `1`, ran the typed action, observed a
   schema-verified `Muted, Yes` result, asserted that the Act flow contains no
   Remote Control entry, and kept bootstrap Continue disabled before every
   ambiguous route is classified.
2. `testHostStateMenuChangesClosedProjection` changed Ready to No Network and
   asserted `No Private Network`, a hittable Reconnect action, and the absence
   of an active-control status.
3. `testLifecycleUsesInjectedReachabilityAndRearmsAfterBackground` began with
   zero rounds and injected reachability disabled, enabled it to start one
   synthetic round, pressed Home, reactivated the app, and observed exactly one
   additional round from the UIKit application-active transition.
4. `testLifecycleTerminalFailureStopsFurtherReachability` injected an invalid
   round ID, observed one terminal failure and zero rounds, then proved a later
   reachability attempt produced neither another failure nor a dial.
5. `testLiveControlKeyboardAndStopAreSemanticallyReachable` rendered the
   production live-Control destination, asserted its Touch pointer-mode value,
   opened the real software keyboard, tapped `hello`, observed nonzero typed
   input payloads, invoked the typed Stop path, returned to the workspace, and
   confirmed that the keyboard was dismissed.

The final run executed 4 tests with 0 failures and produced an ephemeral result
bundle at
`/private/tmp/maccompanion-client-ui-owner-final-derived/Logs/Test/`.

The expanded 2026-08-21 run executed 5 tests with 0 failures in 83.147 seconds
using `/private/tmp/maccompanion-client-ui-harness-derived/Logs/Test/`. The iOS
27 beta accessibility driver required a coordinate tap on the actual switch
control; the test separately asserts the resulting value before invocation.
The keyboard proxy correctly became first responder and displayed the keyboard;
automation used the visible keys because the intentionally invisible,
non-accessibility proxy is not a valid `typeText` target.

## Platform-floor finding

The first Xcode build revealed that an undeclared Swift-package platform floor
made Xcode compile platform adapters as iOS 15 even though the client decoder
uses an iOS 17 API and the package UI is already annotated for iOS 17. The
manifest now declares package compile floors of iOS 17 and macOS 14. These are
library compile contracts, not a change to the documented macOS/iOS 26 shipping
target.

## Remaining gates

- `xcode-select` still points at Command Line Tools, so the Simulator integration
  cannot invoke its own accessibility snapshot command. XCTest with explicit
  `DEVELOPER_DIR` supplied equivalent semantic traversal without changing the
  machine-wide selection.
- The [composed application owner](2026-08-20-client-network-application-owner-construction.md)
  still needs permanent-target instantiation and physical proof. Its source
  remains scheduling input only and cannot classify routes.
- Stable Xcode 26.6, final identities, signing, physical-device UI/input/render,
  Keychain, live private-route, lock-session, latency, and accessibility-posting
  evidence remain separate external or later gates.

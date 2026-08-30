# Client UI Harness

This is a disposable, unsigned iOS Simulator harness for Mac Companion's
value-driven client views and application lifecycle binding. The default
closed mode owns no sockets, credentials, or captured pixels; its route
outcomes are synthetic. The separate `--network-control-lab` mode connects
to an isolated loopback host using temporary test keys. Neither mode reads
production Keychain, registers an Agent, or changes paired devices.

The harness exercises:

- pairing presentation without starting pairing;
- explicit classification of ambiguous private routes;
- provider-neutral no-relay setup and troubleshooting guidance;
- local route editing against an in-memory catalog;
- a temporary durable route catalog driving the real lifecycle owner;
- injected reachability plus UIKit background/foreground re-arming;
- the host summary across closed connection/control states; and
- a first-class Observe status and scoped-activity surface with explicit
  freshness and history-gap presentation;
- a schema-driven Approved Actions catalog and typed synthetic result that
  never opens Remote Control; and
- privacy-limited application/window surface selection.

Its seven closed-mode UI tests traverse every listed screen through the accessibility
hierarchy, changes the host projection from Ready to No Network, proves one
synthetic dial interval before and after a real Home/reactivation transition,
verifies terminal lifecycle failure is reported once without dialing, proves
validated Observe status and incomplete activity history are reachable without
Remote Control, and proves an Act action completes in the typed harness without
a Remote Control surface, socket, credential, or signer.

The Private Access scenario distinguishes local LAN setup from a user-managed
private network, names Tailscale only as one example, and states that routing
never replaces Mac Companion identity, authentication, grants, or separate
Remote Control approval.

The closed live-Control scenario injects the production screen with a synthetic
Desktop product. It owns no socket, credential, signer, decoder, or captured
pixels, but exercises the real full-screen composition, touch/trackpad menu,
remote-key sheet, native software-keyboard payload path, iPhone toolbar
overflow, and Stop-to-ready dismissal through the Simulator accessibility
tree. The native path uses the production sentinel-backed `UITextField`
delegate: UIKit sees a concrete text client, while every proposed edit is
forwarded and rejected so entered content never becomes the field's backing
value. The keyboard scenario requires an exact ordered synthetic word match
and then an exact word-plus-Space match. The harness exposes only event/scalar
counts and match booleans to accessibility; it does not expose captured input
content.

A complementary package test named
`clientTextInputTraversesFramingAdmissionPlanningAndConstruction` runs without
a Simulator. It composes the production client input producer, JSON codec,
length framing, Agent role-data pump, host admission authority, macOS input
planner, and no-post Core Graphics constructor. It proves ordered Unicode text
and Space reach constructed key-down/key-up events without posting input or
requiring Accessibility permission.

Run all fifteen UI tests, including the authenticated journey, live network scenarios, and pairing
regressions with a booted iOS Simulator:

```sh
bash scripts/verify_simulator_features.sh
```

The runner selects a booted iPhone preferentially, builds the test host and
Simulator app, installs only the disposable harness, transfers a temporary
bootstrap file, runs XCTest, and removes the bootstrap file and test host
on exit. Logs, video assertions, and the `.xcresult` remain in the printed
temporary evidence directory. No Face ID, QR scan, physical iPhone, or Mac
privacy prompt is involved. The ordinary signed apps remain untouched.

Optional environment settings:

- `MACCOMPANION_SIMULATOR_ID`: another booted iOS Simulator UDID.
- `MACCOMPANION_LAB_ONLY_LIVE=1`: run only the live scenario while iterating.
- `MACCOMPANION_LAB_SUITE=full|live|soak|reconnect|lifecycle|integration|journey|journey-observe`: select a test profile.
- `MACCOMPANION_LAB_ITERATIONS=3`: repeat the selected UI tests three times.
- `MACCOMPANION_DEVELOPER_DIR`: override the full Xcode installation.
- `MACCOMPANION_LAB_DERIVED_DATA`: override the temporary build directory.
- `MACCOMPANION_LAB_SOURCE=real-mac-window`: opt into actual ScreenCaptureKit
  capture of a disposable Mac window and own-process OS input delivery. See
  the [real Mac lab boundaries](../LiveControlLab/README.md). Missing permission
  returns exit 77, not a passing test or a generated-video fallback.

The live scenario checks software-signed Control approval, visible H.264
frames across lease renewal, tap/pinch, automatic focused-region zoom,
queued input admitted during a verified focus pause without session teardown,
deliberately delayed surface replies across independent sockets, returning
to Desktop, the bound native composer, direct iOS keyboard input, forced
disconnect/reconnect, and Stop. Pixel assertions distinguish visible video
from merely receiving/decoding frames. Host assertions compare only
synthetic input and expose booleans rather than typed text.

UIKit and SwiftUI animations are disabled only in live-test mode: the beta
Simulator intermittently withheld animation-complete notifications during
sheet/menu dismissal, causing XCTest to time out while video still advanced.
This lane validates behavior, not animation timing or visual performance.

See [Live Control Lab](../LiveControlLab/README.md) for the security and
evidence boundaries. Seeded pairing and role bootstrap are **not** a test of
real TLS, QR scanning, Secure Enclave, Face ID, TCC, or physical-network
behavior. Those remain separate package/platform/release checks.

Follow the [Simulator-first development gate](../../docs/simulator-first-testing.md)
before proposing a physical checkpoint. The expanded suite includes 90 seconds
of idle Desktop plus 90 seconds of focused video, five keyboard-open
Stop/drop/reconnect cycles with runtime/capture/queue cleanup, and five real
UIKit background/return cycles with a synthetic route dialer. The live host
and connection-lifecycle composition are still separate coverage lanes.

To run just the seven closed-mode tests directly:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild test \
  -project Experiments/ClientUIHarness/ClientUIHarness.xcodeproj \
  -scheme ClientUIHarness \
  -skip-testing:ClientUIHarnessUITests/ClientUIHarnessUITests/testNetworkControlLabStreamingZoomKeyboardReconnect \
  -skip-testing:ClientUIHarnessUITests/ClientUIHarnessUITests/testNetworkControlLabIdleSoak \
  -skip-testing:ClientUIHarnessUITests/ClientUIHarnessUITests/testNetworkControlLabRepeatedStopDropReconnect \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' \
  -derivedDataPath /private/tmp/maccompanion-client-ui-harness-derived \
  CODE_SIGNING_ALLOWED=NO
```

The bundle identifier `dev.maccompanion.clientuiharness` is disposable. This
target must not be used for signing, distribution, TCC evidence, or as the
starting point for a permanent iOS application target.

The authenticated `journey-renewal` profile uses the production Agent renewal
scheduler with the disposable runtime. It verifies healthy renewal across
focus changes and safe teardown/recovery after a lost receipt or lease expiry,
including keyboard dismissal and explicit-only Control restart. Use the
repository runner, not an unconfigured direct XCTest launch, for these live
profiles. `full` now expects sixteen tests; missing execution cannot pass.

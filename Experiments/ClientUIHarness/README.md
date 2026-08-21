# Client UI Harness

This is a disposable, unsigned iOS Simulator harness for Mac Companion's
value-driven client views and application lifecycle binding. It intentionally
owns no sockets, Keychain items, private keys, background modes, Apple
capabilities, or permanent identifiers. Its route outcomes are synthetic.

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

Its six-test UI target traverses every listed screen through the accessibility
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
stateless software keyboard payload path, and Stop-to-ready dismissal through
the Simulator accessibility tree.
Run it with a booted simulator and an explicit full-Xcode developer directory:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild test \
  -project Experiments/ClientUIHarness/ClientUIHarness.xcodeproj \
  -scheme ClientUIHarness \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' \
  -derivedDataPath /private/tmp/maccompanion-client-ui-harness-derived \
  CODE_SIGNING_ALLOWED=NO
```

The bundle identifier `dev.maccompanion.clientuiharness` is disposable. This
target must not be used for signing, distribution, TCC evidence, or as the
starting point for a permanent iOS application target.

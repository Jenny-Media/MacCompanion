# Integrated Simulator route-to-Control regression

## Scope

The isolated Simulator now composes the production configured-route factory,
reconnect controller/executor, selected-primary candidate and command router,
role-binding owner, UIKit lifecycle owner, workspace model/navigation, live
Control coordinator, decoder, renderer, and input producer together. The Mac
test host captures only its own disposable window and posts synthetic input
only to its own PID. No physical iPhone or installed production Mac app/Agent
is part of this run.

The fixture supplies an initially monitor-only pairing record; the simulated
authenticated session carries a separate granted state. Each connection uses
a fresh connection ID. The primary/role traffic traverses actual loopback
sockets. Seeded transport binding is package-scoped and compiled out of Release;
the shared composition factory remains the one used by production. Isolation
checks reject lab markers in the release graph and unguarded seeded binding.

## Finding and repair

The integrated test reproduced a failure the older separate lanes missed:
after background/return, the selected replacement primary and role channels
were healthy, and the workspace model reached `channelsReady`, but the live
destination did not open. Content-free tracing showed the rendered-value
`onChange` observer receiving requesting/awaiting-acceptance but missing the
later readiness publication. The workspace now consumes distinct mode
publications directly through `onReceive`; it still opens Control only after
an explicit request has produced ready channels, never merely on reconnect.
Temporary trace statements were removed.

Repetition then caught a stale `invalidPhase` error after successful recovery.
The render/input relays could complete queued work after closure and still
invoke their failure callbacks. The live coordinator also lacked a product
generation check, allowing retired callbacks to affect a replacement. Relays
now recheck their current activation, and the coordinator fences callbacks and
factory results by generation. A product returned after canceled construction
is explicitly closed. A deterministic Simulator regression verifies retired
callbacks are ignored, replacement products remain active, current failures
still surface, and late factory results are closed exactly once.

The new lab itself also needed corrections: a monitor-only initial durable
pairing fixture, runtime initialization before publishing the host session,
waiting for completed retirement before replacement, and failed-handshake
socket cleanup. These were harness defects, not claims about production
Agent failures.
The runner also holds a per-Simulator lock until all pairing checks and cleanup
finish; an overlapping run is rejected before it can modify the active fixture.

## Automated scenarios

- Three real UIKit Home/background/activate cycles, each with live video,
  replacement-primary selection, verified old-runtime cleanup, no automatic
  Control restart, then a fresh explicit request and visible pixels.
- Native composed text delivered to the owned Mac window; live streaming
  across the production selected-primary periodic status request.
- Offline/online with a direct keyboard open: dismiss video/keyboard, close
  capture/runtime authority, purge media, avoid offline dial churn, and recover.
- Abrupt primary drop followed by automatic reconnect and fresh Control.
- Cancel a delayed dial by going offline; reject any late primary publication,
  then reconnect and render again.
- Inject retired-product callbacks before and after replacement; preserve a
  legitimate current-product failure and close a delayed canceled product.

Reproduce with a booted iOS Simulator and existing lab permissions:

```sh
MACCOMPANION_LAB_SOURCE=real-mac-window \
MACCOMPANION_LAB_SUITE=integration \
bash scripts/verify_simulator_features.sh
```

Use `MACCOMPANION_LAB_ITERATIONS=3` for repetition and `full` for the complete
UI/soak/feature suite. Evidence directories are printed under `/private/tmp`;
the runner retires its fixture and host on exit. Captured test-window pixels
and ephemeral bootstrap material are not committed.

## Validation

Integrated runs retain normal navigation animations. Earlier failed iterations
are diagnostic evidence, not counted as successful repetitions.

- Final repeated integration: **9/9 passed**, 454.875 seconds. Three runs each
  of app-switch/live recovery, offline/drop/canceled-dial recovery, and the
  deterministic retired-callback regression. Pairing checks also passed;
  runner cleanup completed. Evidence: `/private/tmp/maccompanion-feature-tests.8TY9oS`.
- Full repository validation after the lifecycle repairs: **1,725 tests passed**
  across 42 test-run footers, plus policy, fixture, isolation, and platform-build
  checks; process exit 0. Log: `/private/tmp/maccompanion-integrated-complete-validation.log`.
- Production `MacCompanionIOS` Release build for generic iOS Simulator:
  **passed**, unsigned and unlaunched. This is build/isolation evidence, not
  distribution or physical-device evidence. Log:
  `/private/tmp/maccompanion-integrated-release-ios.log`.
- Exclusive runner probe: a second run was rejected with exit 2 before
  installing or replacing the active bootstrap. Shell syntax and diff checks
  passed.
- Full feature/soak suite: **13/13 passed**, 629.720 seconds, including the
  three-minute Desktop/focused-view soak, five Stop/drop/reconnect cycles,
  zoom and both keyboard paths, lifecycle cases, and deterministic callback
  checks. Pairing checks passed and runner exit was 0. Evidence:
  `/private/tmp/maccompanion-feature-tests.za8d9w`.

Xcode beta emitted its secondary diagnostic-collection warning about locating
`simctl`; XCTest results and runner exit still confirmed success. This warning
is not counted as a product failure or as missing test execution.

## Remaining limits

This is not full shipping-app E2E: paired inventory, approval/user presence,
reachability, and authenticated transport establishment are injected. TLS,
session authentication, Bonjour/LAN, Keychain/Face ID, final signing/TCC
attribution, and the outer release bootstrap/rebuild shell remain separate
evidence. Observe status data is synthetic; Act execution is unsupported in
this lane. The host renewal scheduler is lab-owned, and lab Stop closes the
primary as well as Control. Independent Agent, pairing, and real-network
regressions remain required. Simulator-first remains the development policy;
a later physical checkpoint requires a fresh explicit user request.

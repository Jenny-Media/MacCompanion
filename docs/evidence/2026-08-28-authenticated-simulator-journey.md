# Authenticated Simulator journey

## Scope and reproducible command

```sh
MACCOMPANION_LAB_SUITE=journey bash scripts/verify_simulator_features.sh
```

Use an already booted iOS Simulator. Add `MACCOMPANION_LAB_ITERATIONS=3` for
repetitions, or `MACCOMPANION_LAB_SOURCE=real-mac-window` for the separately
signed disposable host's own-window capture and own-PID input. `full` includes
the journey plus all earlier UI, live, soak, and recovery regressions.

This never installs or launches the physical iPhone app or installed Mac
Companion/Agent. No signing-account, Keychain, TCC, or production-pairing state
is changed. The real-window lane only checks existing permission and reports
exit 77 if unavailable; it never prompts or substitutes generated pixels.

## What is actually composed

- Production pinned TLS listener/client verifier and same-socket ingress;
  wrong-pin failure must come from the verifier, not an unreachable endpoint.
- Production pairing, exact host consent decision, recovery, and durable
  SQLite/paired-host/route stores. The client generates its own signing keys.
- Production primary authentication, route ownership, command router, workspace,
  Control approval authority, mutually authenticated role channels, and live
  media/input owners. Every new Control session requires an explicit request.
- Actual client process termination/relaunch and supervised host replacement,
  preserving only the run's durable identity and pairing state.
- Production Mac status sampling and client freshness/sequence admission;
  host send counters alone cannot satisfy the Observe assertion.

The complete journey exercises fresh pairing; both restarts; listener off/on;
Observe; explicit grant and Control; rendered video; pinch; focused composer;
native iOS keyboard; Stop; three Home/return cycles; abrupt primary loss;
host restart during active Control; reachability off/on; and durable revocation
followed by client restart. Stop must allow a new verified Observe response
without a new authentication. Every recovery removes stale video/keyboard and
must not restart Control automatically.

## Production defect found

The first combined run appeared to lose its primary after Stop. Content-free
diagnostics showed the actual failure was the next explicit status response:
`ClientObserveChannelErrorV0` caused primary protocol rejection. The host had
reused request-arrival wall time as response-send time, while asynchronous
sampling produced a later `observedAt`. The client correctly rejected an
observation apparently made after its response was sent.

`AuthenticatedPrimarySessionV0` now samples a host-owned response clock after
status sampling/sequence commit. A clock earlier than the observation or
outside wire bounds returns the existing correlated `provider.unavailable`
error and preserves the primary. Client freshness checks are unchanged. A
deterministic regression covers valid, backwards, negative, and unsafe clocks;
the live journey checks actual client acceptance and same-primary Stop.

The remaining intermittent Observe failure was reproduced with a successful
connection, no client error, `provider.unavailable`, and host diagnostic
`invalidCounterDelta`. The sampler had received identical CPU counters twice.
[Apple's XNU implementation](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/host.c)
rate-limits third-party `host_statistics` calls using a shared one-second cache.
This explains why even the production 100 ms interval can return unchanged
counters. The sampler now extends that sample once by 1.1 seconds, comparing
against the original baseline. It still fails if unchanged, propagates syscall
errors/cancellation, and never labels a missing measurement as idle. Five
deterministic tests cover recovery, no unnecessary backoff, retry exhaustion,
cancellation, and read failure. Client freshness rules remain unchanged.

Test-only animation disabling now covers every live harness mode. A
process sample showed the app responsive while XCTest explicitly reported a
missing animation-completion notification and waited 60 seconds. No shipping
animation behavior was changed.

The journey and older integration tests wait for the client's focused-surface
acknowledgement before expecting the native composer. They previously tapped Keyboard while the
focus transition was in flight, when direct keyboard fallback is valid.
Existing XPC-admission and scheduled-reconnect unit-test waits also now use
bounded elapsed time rather than a number of executor yields; the latter
could expire in tens of milliseconds under concurrent Simulator load.

Restart testing exposed an unbounded test status probe: dialing during the
restart gap left `NWConnection` in `waiting`, so telemetry stopped even after
the host was listening and the production client had reconnected. Test-probe
setup now rejects `waiting` and has an independent five-second deadline. A
nonreplying-loopback-peer regression verifies bounded setup. Separately, host
restart now waits for the old child to exit and launches a fresh supervised
process instead of calling `exec` from a Swift worker in an AppKit process.
Cleanup bounds normal termination and reaps its exact child, including failure.
The background supervisor uses a function body without a second subshell;
otherwise `$!` identified a wrapper and cleanup could orphan the inner host.
Earlier disposable instances were retired, and subsequent cleanup is checked
against the actual process list, not just the supervisor's exit status.

## Verification

- Generated-source complete journey: 1/1 passed, 143.968 seconds, run
  `/private/tmp/maccompanion-feature-tests.LEddJQ`.
- Final real-window journey repetition: **3/3 passed**, 565.865 seconds
  overall (170.425, 173.166, and 212.691 seconds per journey), run
  `/private/tmp/maccompanion-feature-tests.2dCqN3`. All five subsequent pairing
  regressions passed, the runner exited 0, and `report.json` records three
  completed executions despite xcresult aggregating them under one test name.
  Temporary host credentials were removed and no test host remained running.
- Focus-synchronized integration regressions: **3/3 passed**, 208.143 seconds,
  run `/private/tmp/maccompanion-feature-tests.Cm1ZyF`; pairing regressions and
  runner cleanup also passed. This covers background recovery, network loss
  and cancelled dial, and retired-Control callback isolation.
- Final complete real-window suite: **15/15 passed**, zero failures/skips,
  1,109.673 seconds, run `/private/tmp/maccompanion-feature-tests.QYS4GB`.
  This includes the six-reopen Observe regression, complete authenticated
  journey, independent UI paths, both integration tests, lifecycle tests,
  three-minute idle-stream soak, five keyboard-open Stop/drop/reconnect cycles,
  zoom/focus/keyboard feature flow, and native-composer/callback regressions.
  All five subsequent pairing regressions passed; runner exit and final
  `report.json` are green. Process inspection found no disposable test hosts.
  Host and current Simulator-container credentials and the run lock were
  confirmed absent after cleanup. Only logs/build products/test results remain.
- Final repository validation: exit 0, 1,736 Swift tests (1,722 main-package,
  6 live-lab safety, 8 platform-probe), policy/isolation checks, and platform
  builds, including the nonreplying-peer and CPU-cache regressions. Local log:
  `/private/tmp/maccompanion-journey-validation-final4.log`.
- Simulator report validator: 19 positive/negative cases, including missing
  tests and missing repetitions.
- Shipping iOS Release build: unsigned Simulator build succeeded.
- Production host networking Release build: succeeded after the CPU-cache fix;
  test loopback seam is
  Debug-only and internal, not a shipping construction path.

Xcode beta emitted its auxiliary `simctl` diagnostic-collection warning after
the tests. Test execution, result-bundle parsing, and cleanup still completed
successfully; this is not stable-toolchain or release certification.

Each runner emits `report.json` with content-free counts, source, result, and
limits. Missing/skipped/failed/malformed/non-Simulator evidence or unsuccessful
cleanup cannot pass. Software keys and pairing stores are confined to private
run directories and the disposable Simulator container and removed on exit.
Raw local `.xcresult` artifacts may contain screenshots of synthetic test UI;
they are not committed. A hard kill bypassing cleanup requires inspection.

## Limits

Subsequent work in the [Agent-renewal checkpoint](2026-08-28-agent-renewal-simulator.md)
replaces the authenticated lab's scheduler and adds active-stream failure
recovery tests. The limits below describe this earlier checkpoint.

Software custody and simulated local consent/presence are deliberate test
substitutions, not Secure Enclave, Keychain, Face ID, or Mac approval-UI proof.
The outer release bootstrap, Bonjour/LAN, final signing/TCC attribution,
installed Agent lifecycle, arbitrary-app focus discovery, and physical-device
behavior remain unproven here. The test host still supplies runtime composition,
renewal scheduling, focus recommendations, and status sequence persistence;
Act execution remains unsupported in this lane. Separate Act, Agent, and
golden cryptographic tests remain required. Local Xcode 27 beta results do not
replace the stable-toolchain release gate.

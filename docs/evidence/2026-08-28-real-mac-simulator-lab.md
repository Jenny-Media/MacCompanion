# Real Mac capture and isolated-input Simulator lab

Follow-up: the first physical test exposed a production Agent/XPC cleanup
deadlock absent from this isolated host. The
[physical reconnect repair](2026-08-28-physical-reconnect-cleanup-deadlock.md)
records its regression, signed installation, and actual-phone connection proof.

Date: 2026-08-28. Local Xcode 27 beta / iOS 27 Simulator evidence. This is not
stable-toolchain, production pairing, or Stage 3 release acceptance.

## Reproduce

```sh
MACCOMPANION_LAB_SOURCE=real-mac-window MACCOMPANION_LAB_ONLY_LIVE=1 \
  MACCOMPANION_LAB_ITERATIONS=3 bash scripts/verify_simulator_features.sh
```

Use an already-booted iPhone Simulator. The separately development-signed test
app must already have the required Screen Recording and event-posting access.
Denied preflight exits 77; no permission request or generated-source fallback
is performed. See the [lab guide](../../Experiments/LiveControlLab/README.md).

## What this proves

The real lane captures only the test process's own window using ScreenCaptureKit
and the production capture owner, then encodes, transports, decodes, and displays
that video in Simulator. Assertions require advancing media sequences and visible
tinted test-window pixels, including after crop transitions and reconnect.

The scenario exercises tap/pinch, repeated focused-region/Desktop transitions,
delayed selection replies, local composer text, native iOS keyboard keys, Return,
forced disconnect/reconnect, and Stop. The production input planner/constructor
feeds a test-only adapter that posts solely to its own PID. OS-received events,
the actual editor text, and an actual newline determine success.

The owned test application explicitly routes received key events into its
editor's NSTextInputClient methods while Simulator stays foreground. This does
not prove arbitrary-app responder routing, global HID posting, shortcuts in
other apps, real Accessibility focus discovery, or physical keyboard behavior.
Pairing, primary authentication, grants, focus recommendations, and presence
signing use isolated test setup. Production TLS, installed Agent/Keychain state,
real QR pairing, Face ID, network changes, and lock/unlock remain separate checks.

## Production races found and repaired

1. **Late old-surface reset.** Primary selection and input use independent
   sockets. Selection can finish before the old terminal reset arrives, producing
   a binding mismatch. After proven input release, the runtime now drains exactly
   one next-sequence reset for the immediately retired surface without posting
   any event or releasing replacement input. Old pointer/key/text, wrong fences,
   duplicate/gapped resets, expired authority, and resets after new input stay
   rejected. Deterministic tests cover before acknowledgement, after
   acknowledgement, and after renewal, as well as the ordinary path.
2. **Video publication across lease renewal.** A queued encoded frame could
   carry the prior lease even after the capture publisher adopted its renewal.
   Runtime admission correctly rejected it as stale, but the publisher treated
   that race as terminal. Runtime stale-lease rejection remains unchanged. The
   publisher retries once only after adopting an authoritative new lease with
   every non-lease binding/dimension unchanged. It uses a fresh clock sample
   through ordinary strict admission. Other errors, no adoption, changed source,
   or a second rejection remain terminal. This is not replay of a committed
   effect and introduces no new IPC method or runtime lease-rebinding API.

Normative rules are in
[menu runtime composition](../../spec/interactive-control/v0/menu-runtime-composition.md)
and [client admission](../../spec/interactive-control/v0/client-admission.md).

Test-only repairs were kept separate: complete AppKit text storage/layout setup,
owned-editor event dispatch, and serialization of the lab host's surface/lease
mutations. They do not change the production Agent's authority model.

The final default-mode UI pass also exposed an older lifecycle fixture race:
both saved synthetic routes returned immediate authentication while the test
expected Local Discovery. The failure artifact confirms the app was actually
connected through Private DNS, with zero terminal failures; it was not stuck
connecting. The test-only dialer now makes only its intended Bonjour route
succeed. Production route racing is unchanged. Red evidence:
`/private/tmp/maccompanion-feature-tests.bPNRG9/features.xcresult` and the
exported `/private/tmp/maccompanion-lifecycle-failed-label.txt`.

A repeated full validation found an existing cancellation assertion that
required the first caller to throw even when it completed before a cancelled
join installed its handler. The test now accepts the first caller's legitimate
success/cancellation/terminal orderings while still requiring CancellationError
for the cancelled caller, one factory/start, exactly one cleanup, and terminal
subsequent ownership. No production cancellation behavior changed. The failed
run is retained at `/private/tmp/maccompanion-real-mac-handoff-validation.log`.

## Recorded validation

- Real Mac end-to-end scenario passed initially in 64 seconds:
  `/private/tmp/maccompanion-feature-tests.OSGqI7/features.xcresult`.
- A 100 ms renewal stress run reproduced the terminal `staleLease` failure:
  `/private/tmp/maccompanion-feature-tests.TnOg1x/host.log`.
- After the bounded publisher retry, the same 100 ms stress scenario and its
  pairing regression checkpoint passed:
  `/private/tmp/maccompanion-feature-tests.P7cls2/`.
- Publisher tests passed, including adoption/no-adoption, second-rejection,
  and non-stale-error cases:
  `/private/tmp/maccompanion-renewal-retry-tests.log`.
- The reset timing regression first failed with bindingMismatch, then all four
  timing cases passed. Logs:
  `/private/tmp/maccompanion-late-reset-red.log`,
  `/private/tmp/maccompanion-late-reset-matrix.log`.
- Full repository validation passed after both production fixes: **1,719 Swift
  tests**, policy/fixture checks, and platform builds.
  `/private/tmp/maccompanion-real-mac-complete-validation.log`.
- Both updated development-signed apps built and passed deep/strict signature
  verification. Logs: `/private/tmp/maccompanion-real-mac-final-signed-build.log`
  and `/private/tmp/maccompanion-real-mac-final-ios-build.log`.

- Three consecutive real-Mac scenarios passed in **63.391, 63.210, and 62.961
  seconds**, followed by the pairing regression checkpoint:
  `/private/tmp/maccompanion-feature-tests.G1I4Qs/`.
  The host recorded a transient stale-lease rejection without terminal encoder
  failure; the scenario continued through input, reconnect, and Stop. Final
  reconnect screenshots were also visually inspected.
- Forced denied preflight returned exactly **77**, before bootstrap publication:
  `/private/tmp/maccompanion-real-mac-denied-preflight.log` and
  `/private/tmp/maccompanion-feature-tests.aom34a/`.
- After the deterministic route-fixture repair, the complete default-mode suite
  passed: **8 UI tests, 0 failures**, 190.4 seconds, followed by its pairing
  regression checkpoint: `/private/tmp/maccompanion-feature-tests.5wu0mz/`.
- The corrected lifecycle UI scenario also passed **five consecutive runs**:
  `/private/tmp/maccompanion-lifecycle-repeat.Qw8waM/lifecycle.xcresult`.
- The cancellation regression passed **30 consecutive runs** with exact cleanup
  assertions retained: `/private/tmp/maccompanion-cancel-repeat-1.log` through
  `/private/tmp/maccompanion-cancel-repeat-30.log`.
- Final full repository validation passed again after both test-harness repairs:
  **1,719 Swift tests**, policy/fixture checks, and platform builds. Log:
  `/private/tmp/maccompanion-real-mac-final-handoff-validation.log`.
- Post-run inspection confirmed no current Simulator bootstrap, no per-run
  credential fixture, and no running test host after the completed live lanes.

### Installed development builds

The updated signed Mac app replaced the installed app after orderly shutdown;
its existing enabled Agent registration was repaired and the new Agent is
running. Installed app/Agent debug binaries match the verified build byte for
byte. The previous app remains recoverable at
`/private/tmp/maccompanion-app-backup.UtfvDb/Mac Companion.app`.
The updated iOS app was installed over the existing app and launched on the
paired physical iPhone. No uninstall, pairing reset, grant approval, or TCC
change was performed. Successful launch is not a physical Control-session pass.

## Isolation and remaining acceptance

The lab is Debug-only and excluded from shipping dependency graphs. It binds
loopback, generates temporary software credentials, never reads production
pairing/Keychain data, and permits only bounded synthetic text and narrow
pointer/Return/reset actions to its own PID. Logs retain counts/match flags,
not typed text or video. Temporary XCTest screenshots contain synthetic content.
The runner stops its process/window and removes bootstrap fixtures on exit.

After signed installation, the focused physical-device check should connect
using the existing pairing, request Control with genuine Face ID, type through
both keyboard modes into a disposable document, pinch/change surfaces, stop,
reconnect, and confirm lock/unlock recovery. Do not use Simulator success to
waive that check or the stable-toolchain and release gates.

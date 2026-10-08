# Normal Simulator pairing, workspace and restart

## Scope

The normal `MacCompanionIOSApplication` now completes a real pairing against a
disposable signed Agent in the dedicated iOS Simulator, saves its normal public
paired-host record, configures a private route, opens the normal workspace and
reads live status. After terminating and relaunching the app, the same saved pair
and route reopen the workspace, authenticate again and read live status.

The test uses the admitted Debug Simulator bootstrap and real Security.framework
software key custody. A test-only Mac consent bridge approves the exact newly
generated client identity through signed local XPC. This substitutes human Mac
consent; it does not prove the installed Mac approval UI. Client operation
approval signing/user presence is not exercised or substituted. Observe remains
the only paired grant; the workspace explicitly requires separate Mac permission
for Remote Control. No native video session is started in this checkpoint.

## Changes

- `verify_normal_native_live_pairing.py --complete-pairing` drives the normal app
  through pairing, route setup and restart. Default comparison/cancellation mode
  remains available. The normal app receives no injected pairing code or test
  hooks: the separate UI test types a fresh code into its normal entry screen.
- The disposable consent bridge accepts the public fresh client UUID and waits
  up to 60 seconds for its pairing review; existing callers retain 12 seconds.
  Normal product pairing/security deadlines and signatures remain unchanged.
- A separate Debug Simulator hosted cleanup test reads the exact owned pair,
  verifies its host/client IDs and published key references, deletes only those
  two keys through normal custody, and proves re-registration fails afterward.
  Neither UI nor cleanup test source is linked into the normal app target.
- The runner locks the owned Simulator lane, preserves original isolated data
  and app bytes, verifies source/framework bindings, and restores the original
  app and exact data hashes after disposing of the test host and pairing keys.
  It refuses to replace existing paired state or configured routes.

## Verified result

Stable Xcode 27.0, iOS 27.0 Simulator
`8FF65ABB-572E-4EE4-9A9F-F61AA302A586`:

- Normal UI journey: one test passed, zero failures, 43.615 seconds.
- Exact owned pair-key cleanup: one test passed, zero failures, 0.048 seconds.
- Host cleanup and Simulator state restoration: verified.
- `bash scripts/validate.sh`: passed on stable Xcode, including 110 indexed JSON
  fixtures. `git diff --check`: passed.

Private evidence (contains transient pairing/test data; do not commit):

- `/private/tmp/maccompanion-normal-paired-workspace-20260927-v6/report.json`
  SHA-256 `69136073ac58f2bf3aee35c5a3cf1e61e5e81dd00087df41ac3694febc6216b9`.
- UI and cleanup results: `result.xcresult` and `cleanup.xcresult` in that directory.
- Disposable host evidence: `/private/tmp/maccompanion-agent-xpc-evidence.b1xcsjkl`.
- Validation: `/private/tmp/maccompanion-normal-paired-workspace-validation-v3-20260927.log`.

Exact normal source-input SHA-256:
`aab1110bf2ca88c8cec4a3679d6e661c0c40c0b99d325ef7e8bd686fb9c954bc`.
Tested normal executable SHA-256:
`fab768bfc769263c6ecdb4fd3645ca1a06acee2a168e86b27e5633e746f445cd`.
Disposable host source SHA-256:
`a98ec46735cbdd2812ac1320c9f6b7e0dedcb835b43c52b541504246a9a2f41f`.
The report pins both native framework hashes, the baseline build report and all
test input hashes. The test rebuilds the disposable Xcode project; afterward its
original cached normal executable is restored to
`d64c9eb3095b05080ff129630dc67fb6c6d77560330baa6e562bb0f2ee90c8d4`.

## Failed runs retained

Versions v1-v5 remain private diagnostics. The initial preflight incorrectly
rejected the normal route-store lock; the first timed approval wait expired
before code typing finished. Later UI runs completed pairing and exact-key cleanup
but used the wrong picker selector, then looked for Refresh Status at the workspace
root. The v5 UI hierarchy proved the authenticated workspace was present:
Refresh Status is inside its Mac Status destination. The final v6 test opens that
destination explicitly both before and after restart. No workspace navigation
product fix was required.

## Next acceptance

Follow-up: [normal native Control in Simulator](2026-09-27-normal-native-control-simulator.md)
now verifies two explicit normal-app native sessions with keyboard, pointer,
modifiers, shortcuts and Stop/restart against a disposable Mac host. Recovery and
installed Mac/physical acceptance remain separately tracked.

Exercise the normal app's separately granted Control path, native enrollment,
visible frame, controls, Stop and recovery against the disposable host. Existing
harness video/control evidence remains separate. Installed normal Mac GUI/TCC
continuity, paired LAN and physical iPhone tests remain open. Native focused
App/Window capture, visible-area bitrate and current corresponding-source
assembly also remain open. This checkpoint changes no installed Mac state and
uses no physical device.

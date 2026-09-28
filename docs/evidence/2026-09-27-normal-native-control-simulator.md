# Normal iOS app native Control in Simulator

## Scope and verified journey

The admitted Debug Simulator build of the normal `MacCompanionIOSApplication`
completes pairing, saves its normal pair/route, reconnects after relaunch, receives
a separately authorized Control grant and exercises two native Desktop sessions
against an isolated signed Agent/menu and verified archive-rebuilt Sunshine host.
The client uses its normal Security.framework custody and approval signature path;
no client identity, approval signer, route reader or native adapter is substituted.

Each session verifies:

1. Request Remote Control from the normal workspace and enter its normal live UI.
2. A native presentation receipt with host input admission. The receipt requires
   current managed capture evidence and the normal client owner's displayed
   native frame/presentation readiness; bootstrap media alone cannot qualify.
3. A typed `a` through the iOS software keyboard and visible keyboard dismissal.
4. A center-screen pointer tap, Shift+Tab, and Copy through the normal controls.
   Every action must increase the signed host's final input counter.
5. Stop, return to the normal workspace, verify capture inactive, runtime idle and
   media queue empty, retain an authenticated Observe workspace, and open its
   live status screen. The next session starts through a fresh explicit request.

This is normal **iOS app** acceptance against a disposable **Mac test host**.
Human Mac consent is substituted by a separate test process driving signed local
XPC. Capture uses real Desktop pixels, while final input posting uses the existing
synthetic sink behind the real current native input permit. It does not prove
physical system input, biometric/hardware custody, installed Mac GUI/TCC
continuity, LAN behavior, background recovery or connection-loss recovery.
The status UI remains live across Stop; the test does not compare a new Observe
reply's correlation ID after each Stop. No screenshot/pixel-distribution claim is
made in this checkpoint.

## Test-only changes

- `verify_normal_native_live_pairing.py` accepts explicit native root/package
  inputs in completed-pairing mode. It verifies the package before/after the run,
  uses a native continuous disposable menu and pins test/host/framework inputs.
- A private, bounded loopback consent channel remains entirely in the separate
  UI-test process. The normal app does not receive its bearer token or hooks.
- `journey-grant-control-observe` requires the exact empty current grant set and
  verifies that only Control is stored. It does not grant an unrelated Act
  capability. Existing Act-plus-Control harness callers retain their checks.
- Disposable menu telemetry counts only successful `.present` replies with
  `inputAdmitted == true`; the test waits for one new native presentation per
  session, and the runner requires exactly two corresponding admission markers.
  No production protocol, deadline, key requirements or wire behavior changes.
- The existing exact-key cleanup test and original app/data restoration run
  after native host retirement. These bundles are never normal app target sources.

## Exact evidence

Stable Xcode 27.0; iOS 27.0 Simulator
`8FF65ABB-572E-4EE4-9A9F-F61AA302A586`.

- Normal UI journey: one passed test, zero failures, 88.066 seconds.
- Exact owned pair-key cleanup: one passed test, zero failures, 0.050 seconds.
- Two successful native presentation/input-admission receipts; input delivery
  verified separately for keyboard, pointer, modifier key and shortcut actions.
- Disposable host cleanup and original Simulator app/data restoration verified.
- Stable `bash scripts/validate.sh` passed at both the native presentation/keyboard
  checkpoint and the final expanded-control checkpoint, including 110 indexed
  JSON fixtures. `git diff --check` passes.

Private local records, which must not be committed:

- `/private/tmp/maccompanion-normal-native-control-20260927-v3/report.json`,
  SHA-256 `4b28784844d7c6db3a939ec74884ee1a56898c7b4f480d9af994d52675c2852e`.
- `result.xcresult`, `cleanup.xcresult`, `test.log` and `key-cleanup.log` in that
  directory; `/private/tmp/maccompanion-agent-xpc-evidence.up4wog7w` for host evidence.
- `/private/tmp/maccompanion-normal-native-control-validation-20260927.log`
  and `/private/tmp/maccompanion-normal-native-control-final-validation-20260927.log`.

Normal source-input SHA-256:
`aab1110bf2ca88c8cec4a3679d6e661c0c40c0b99d325ef7e8bd686fb9c954bc`.
Tested normal executable SHA-256:
`fab768bfc769263c6ecdb4fd3645ca1a06acee2a168e86b27e5633e746f445cd`.
Disposable host source SHA-256:
`ea7a4420493538b5bd1c584ae8258becbfa1bb7e728886ecf2b6af04fb6a8993`.
Verified archive-rebuilt host manifest SHA-256:
`1ee79a835e04c12b3c6a4a3a64e5b07d99455f3122a65ec28f96e2435bc55492`.
The report binds both native frameworks and every UI/cleanup/runner input.
The production Mac host catalog and installed apps were not changed.

Earlier v1 established request/Stop/restart but did not assert native receipt
completion or input delivery. V2 added two native receipts and keyboard delivery;
V3 is the stronger pointer/modifier/shortcut result above. The earlier private
results remain retained with their original input hashes.

## Remaining work

Normal app background/reachability recovery and fail-safe input fencing; then
installed normal Mac GUI/TCC and full paired LAN/physical acceptance. Native
focused App/Window capture, visible-area bitrate and current corresponding-source
assembly remain open. The historical harness's four-cycle recovery evidence
remains separate from this normal-app two-cycle result.

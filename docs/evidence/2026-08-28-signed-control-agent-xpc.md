# Signed Control through the isolated production Agent — 2026-08-28

## Result and scope

The [pre-physical goal](../pre-physical-execution-plan.md) remains active.
The matrix extends the [40-case pairing checkpoint](2026-08-28-real-pairing-agent-xpc.md)
with three signed Control cases. Three consecutive final **43/43** runs passed
with cleanup; final validation and current-source repetitions are below.
This is a lease/authority checkpoint, not full media/input or Simulator proof.

The existing real paired client, TLS primary, Agent enabled composition,
SQLite grant state and signed menu connection now exercise:

- Decline a real Control-grant review, obtain a distinct fresh review, approve
  its exact device/grant state, and reject another grant review once granted.
- Publish signed display admission; request Control through the production
  client approval/signature path; install the Agent-issued execution lease
  through the production XPC route and menu runtime owner/adapter.
- Authenticate both Interactive role connections, wait for two scheduled
  production renewals, then client Stop. Verify runtime cleanup and a fresh
  Observe reply on the same authenticated primary connection.
- Pause the test Desktop preparer, withdraw display admission over signed
  XPC, resume preparation, and require rejection with no capture installation.
  Signed status and Observe continue working.
- Lose the signed menu connection during active Control. Require the real
  menu runtime to return to idle and invoke capture stop, input release, frame
  blank and indicator clear, while the same Observe primary remains usable.

## Product defect found and fixed

The admission-race case failed consistently before it could verify final
admission. Swift's synthesized encoder omitted `selectedDisplayID` when nil;
the closed decoder required that key. Both the publication and receipt had
this mismatch. Sending a valid no-display state therefore closed the signed
XPC generation as malformed traffic.

Both encoders now include explicit JSON `null`. Missing/unknown fields remain
rejected; no authentication or grant check was relaxed. The normative local
IPC specification and existing indexed admission fixture were updated before
implementation. The fixture now contains exact null-publication/receipt codec
vectors. Two new tests cover these vectors/round trips and missing-key
rejection for both message types. No cryptographic signing input changed.

Reproduction evidence remains available:

- `/private/tmp/maccompanion-agent-xpc-evidence.5d9apaqu/report.json`: 41 cases
  passed, then signed null-publication failed; cleanup verified. Earlier
  `.yxy1rkdr` and `._tusknj_` reports show the same failure.
- `/private/tmp/maccompanion-admission-null-before.log`: new regression fails
  against the unfixed code (both encodings differ; null round trip rejected).
- `/private/tmp/maccompanion-admission-null-after.log`: four codec tests plus
  the independent admission transaction-gate test pass after repair.
- `/private/tmp/maccompanion-agent-xpc-evidence.2w1oyrd4/report.json`: first
  repaired 43/43 signed run passes with cleanup, before final formatting.

An earlier test-only capture substitute incorrectly required a renewal to keep
the same lease ID. Production renewals intentionally issue new IDs. The
substitute now calls the actual renewal validator; the corrected lifecycle
passed in `.fhvj5yfv` before adding the two fault cases. That failed test was
not a production renewal defect.

## Final verification

- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash scripts/validate.sh`:
  passed, **1,750 Swift tests across 42 runners**, plus fixture/policy/isolation
  validators and platform builds. Log:
  `/private/tmp/maccompanion-control-xpc-validation.log`.
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --package-path Packages/MacCompanionKit -c release --target CompanionAgentApplicationPlatform`:
  passed. Log: `/private/tmp/maccompanion-control-xpc-release.log`.
- Defined-symbol inspection with `xcrun nm -U` across the seven affected
  transport/startup/product/network objects: **393 matching Debug test symbols,
  zero Release test symbols**. Source guards also reject linking the experiment
  into permanent targets and prohibit real privacy/capture/input effects in
  its substitutes.
- Three consecutive final runs of
  `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3 scripts/verify_agent_xpc.py`:
  **43/43 passed with cleanup verified** in each report:
  `/private/tmp/maccompanion-agent-xpc-evidence.s5zk_wry/report.json`,
  `/private/tmp/maccompanion-agent-xpc-evidence.tivf4ers/report.json`, and
  `/private/tmp/maccompanion-agent-xpc-evidence.0ej_iou4/report.json`.
  Durations: 36.519, 38.892 and 37.998 seconds. These are repeat checks, not
  long-duration soak evidence. The loop stops on the first failure.
- Shared final matrix source SHA-256, independently recomputed after testing:
  `3a2a2a7eadb49098dcb8ae243d937b204301cdc07a71f7c316166b3ce763b64b`.
- Independently confirmed all three UUID launchd jobs absent, all three private
  state directories/helper binaries/plists removed, and zero matching helper
  processes. `git diff --check`, both experiment isolation validators and all
  77 indexed JSON fixtures also pass.

## Boundaries and next work

The Debug startup seam explicitly substitutes an active console fact. Host
and client custody remain private disposable software keys; local human
approval is simulated. The Agent retains production Security.framework random
material generation, grants, durable admission reader, runtime/renewal owners,
signed XPC and TLS role authentication. No release custody bypass was added.

`ProbeInteractiveEffects` substitutes an opaque display, prepared descriptor,
capture/indicator readiness and cleanup effects. The real menu runtime and
lease adapter enforce lease binding and expiry, but the substitute does not
capture or render pixels, post input, display a real indicator, or provide
focus/surface transitions. Display withdrawal proves a final visible-admission
reread; it does not independently prove concurrent durable-grant revocation.
Providers remain empty and Bonjour is replaced by confirmed loopback readiness.
No installed products, production Keychain, privacy settings, Simulator or
physical iPhone were operated during this checkpoint.

P1/P2/P3/P6 remain active. Required work includes signed administrative Stop/
revoke/history/diagnostics, bounded Act, durable-grant race and broader process/
pending-operation faults, surface/focus/input/media integration, combined
Simulator journeys, UX/performance/actual seven-day soak, Release preparation
and the consolidated physical handoff. Earlier launch/handshake stalls remain
open; later passing runs do not erase them. No physical-device action is
needed for the next work.

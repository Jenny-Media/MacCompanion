# Managed native backend input executor

## Implementation

The managed-host specification and its sole manifest-indexed admission fixture
were extended before the backend posting API. Pairing, authentication, approval,
operation signatures and remote input message shapes are unchanged.

The menu now binds the exact physical display resolution and approved capture
geometry into its local revocable permit before the inert backend factory runs.
A bounded synchronous input batch re-resolves that display and measures capture
geometry while holding the permit. It checks both the original Control bound and
the current short lease deadline, including a second clock check after geometry
inspection. Failed geometry inspection permanently revokes the permit: restoring
the old mode cannot revive it before drain. Retirement revokes before awaiting
backend cleanup.

The backend protocol has a local posting API whose default refuses the operation.
The managed Sunshine adapter requires an explicitly injected atomic permit,
then checks the exact running operation, fresh actual sample metadata, admitted
geometry, original expiry and short lease bound before the synchronous batch.
There is no suspension between these final checks and posting. The sample reader
is synchronous and does not reenter the permit's separate status getter while
its lock is held. The production-owner experiment injects the menu permit and
its diagnostic backend wrapper forwards the new method explicitly.

Sunshine keyboard/mouse/controller routes remain disabled. The normal release
composition still has no experimental adapter. No presentation grant or runtime
installation is created merely by having this executor. Connecting the correlated
receipt to the serialized runtime permit and enabling visible UIKit controls
remain next.

## Verification

Candidate source input SHA-256:
`cf34819f3ad3a4f9b29482ccf564c08a37170da1521151f923625ccdc8b8e66e`.

Two added Mac tests cover a current bounded batch, expired short lease, changed
or missing geometry, retirement, restored geometry after revocation, and default
backend refusal. They use synthetic geometry and a counter; no system input is
posted. The existing native backend scope, actual-sample, watchdog and retirement
regressions pass in full `bash scripts/validate.sh` on stable Xcode 27.0,
including all 109 indexed fixtures and existing package/platform/policy checks.

The isolated managed-host probe passes at this candidate SHA. It compiles the
actual updated adapter and verifies certificate admission, listener/route sealing,
HTTPS Desktop launch, invalid proof, port conflict, revocation and menu Stop with
private-state cleanup. Platform effects are explicitly substituted. It does not
decode a frame or invoke the new native posting batch, and is not authenticated
primary/local-XPC or physical-phone evidence.

Both SDK builds bind this candidate. Fifteen Simulator component tests pass
(four native video, three launch and eight UIKit owner tests). The refreshed
inventory covers six framework binaries with release admission false.
Private evidence:

- `/private/tmp/maccompanion-native-backend-executor-validation.log`
- `/private/tmp/maccompanion-native-backend-executor-managed-host.log`
- `/private/tmp/maccompanion-sunshine-moonlight-20260926/managed-host-probe-report.json`
- `/private/tmp/maccompanion-sunshine-moonlight-20260926/logs/embedded-lifecycle-tests.log`

The prior [runtime permit checkpoint](2026-09-27-native-runtime-input-permit.md)
proves the serialized installation seam with injected executors. The live native
presentation-to-runtime connection is still pending. Native input, permanent
process/dependency/TCC admission, normal app packaging and physical installation
remain open. No new end-to-end remote input acceptance is claimed here.

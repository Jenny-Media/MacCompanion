# Stage 3 local enrollment and initial product capture

Date: 2026-08-23

## Outcome

The permanent iOS product now has an explicit, local-only dogfood enrollment
and study-session gate over the existing Stage 3 report owner. Enrollment is
optional, creates no account, starts no network request, and does not change
pairing, Observe, Act, or Control authority. Mac Companion remains usable
without enrollment and after report deletion.

An enrolled tester must explicitly choose a study day and begin a session each
time the app process is used for evidence. No study fact is captured before
that gate. Ending the session serializes behind already-admitted durable writes
and prevents later work from crossing into a different session.

## Enrollment boundary

The permanent Study Report screen now collects only:

- a 16-character externally coordinated opaque study code;
- the candidate app/build and current iOS major version from the signed app;
- the tester-confirmed Mac OS major version;
- one closed current-workaround category; and
- whether an adaptive app, window, or focused-region job applies.

The screen explains that the report is content-free, local, optional,
deletable, and never uploaded automatically. It offers local dogfood only.
Calibration and confirmatory enrollment remain visibly unavailable until the
external participant disclosure and retention policy are approved.

The report contains no enrollment date, wall-clock event timestamp, contact
mapping, stable product identifier, host/device identifier, screen/input
content, address, or diagnostic log. The selected day is an ephemeral session
gate and only its zero-based 14-day index enters closed report facts.

## Initial product-owned capture

`Stage3StudyLocalCaptureV1` exposes closed mutation methods over the one
canonical report. It currently binds these real product transitions:

- the first accepted or failed pairing scan marks setup attempted;
- verified durable pairing completion records `completed` plus monotonic time
  from the first in-session scan;
- pairing rejection, validation/connection failure, and ambiguous local
  storage outcome map to distinct closed results without raw errors; and
- the selected-primary workspace records authenticated connection completion
  and the first validated live Observe result, with elapsed time from explicit
  study-session start.

Pairing retry may converge from an earlier failed/denied/unknown result to a
verified completion. A completed pairing or first fresh Observe result never
downgrades. Repeated publication of the same completed product fact is
idempotent and does not replace its original timing.

The capture authority also provides closed APIs for operational events, route
class, Observe/Act/Control jobs, aggregate per-mode Control duration, route and
surface timing, physical return, comprehension, safety incidents, and recovery
confusion. Those APIs enforce report invariants and exact active-session
fences, but this checkpoint does not claim that every corresponding permanent
product transition is bound yet.

## Persistence and failure behavior

Every mutation rereads the durable report, rebuilds it through the strict
schema, and commits through the atomic exact-current report owner. An explicit
FIFO mutation barrier spans persistence awaits. This is required because Swift
actors are reentrant: without it, simultaneous connection and Observe facts
could both read the same revision and race to replace one another.

Session start, stop, enrollment, and report mutations share that barrier.
Each mutation carries a private random session fence and revalidates it after
waiting. An admitted write completes before End Study Session returns; a stale
write cannot resume in a later day or session.

Study failure never blocks the underlying pairing or workspace transition.
Expected no-enrollment/no-active-session results are inert. Any other capture
failure latches a visible warning telling the tester not to export until the
study report is reviewed.

## Verification

Five capture tests and one workspace-binding test cover:

- explicit enrollment and explicit day-session admission;
- complete closed pairing, Observe, operational, route, job, Control-duration,
  timing, physical-return, comprehension, and safety-review facts;
- invalid authority transitions with no durable mutation;
- retry convergence, post-review immutability, report deletion, and session
  retirement;
- bounded Control-duration overflow without partial persistence; and
- concurrent authenticated-connection plus first-live-Observe capture without
  lost updates or a false failure latch.

The focused study and workspace tests pass on Xcode 27 beta. The iOS client UI
cross-build and the permanent `MacCompanionIOS` generic-Simulator target also
build successfully with signing disabled.

The complete repository gate passes 1,635 MacCompanionKit Swift tests, eight
platform-probe tests, all policy/release fixtures and supported cross-builds,
1,218 current repository files, and 2,253 historical blob paths.

## Non-claims and next gate

This checkpoint does not prove the UI on a physical device, participant
understanding, Data Protection across lock/restart, real paired transport,
pairing timing accuracy in the field, or exported evidence. It does not yet
bind authenticated route class, Act job completion, Control mode/duration,
fallback, Stop, revoke, recovery, physical-return, comprehension, or safety
review UI to every permanent product transition. It does not enable external
cohorts and makes no market-MVP claim.

The next product-evidence slice is to bind the remaining closed Act and Control
outcomes without inferring job intent or screen content, then add explicit
tester review for facts the product cannot establish itself. Internal dogfood
must compare every generated fact with visible product truth before the
calibration cohort can begin.

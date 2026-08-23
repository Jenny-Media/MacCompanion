# Stage 3 explicit Act and Control job capture

Date: 2026-08-23

## Outcome

The permanent iOS product can now add the first qualifying Act and Control
jobs to an explicitly active local Stage 3 study session. Neither path treats
ordinary product use as study evidence. After the product establishes a closed
result, the tester must separately confirm that the attempt was a real job as
defined by ADR-0002.

This preserves the three-path product boundary: Act evidence is recorded from
Approved Actions without opening Remote Control, while Control evidence is
recorded from the separately authorized live-Control destination.

## Act boundary

Only the exact built-in capability
`maccompanion.system.setAudioMuted` is eligible. Its terminal product state is
mapped to one closed report result:

- verified success becomes `completed`;
- denied becomes `denied`;
- expired or cancelled becomes `notCompleted`;
- provider failure or remote rejection becomes `failed`; and
- unresolved delivery becomes `outcomeUnknown`.

Pending and unrelated capability states cannot be recorded. The detail view
offers the study action only after an eligible terminal result and asks the
tester to confirm that the attempt represented a real mute/unmute job. The
report stores neither the requested value nor the prior or current audio value.

## Control boundary

One pure monotonic accumulator begins only after the client has a verified
active Control surface. It records aggregate active milliseconds for the
closed surface kinds `desktop`, `application`, `window`, and `focusedRegion`.
It pauses while a surface replacement is in flight, after Control leaves its
active phase, while the study confirmation sheet is open, on Stop, and when
the destination disappears. Failed surface selection does not resume timing.

The tester must select one of the three predeclared Control job categories and
press **Add Completed Job**. This checkpoint accepts only completed Control
jobs because the live surface cannot establish the intended real-world outcome
on its own. Saving the job atomically adds its closed mode set and duration
delta, then starts a fresh accumulator for a later explicitly reviewed job.
A failed save retains the accumulator so evidence is not silently discarded.

No frame, screenshot, input event, pointer coordinate, typed text, title, app
identity, target token, surface contents, or wall-clock event time enters the
study report.

## Verification

Focused tests cover:

- exact capability and terminal-outcome admission for Act;
- rejection of non-Control job categories by the Control binding;
- monotonic aggregation across Desktop and Application surfaces;
- double-resume, clock-regression, and empty-snapshot rejection; and
- durable workspace-to-report composition for an explicitly submitted
  completed adaptive Control job.

The focused tests and iOS client-UI cross-build pass on Xcode 27 beta. The
permanent `MacCompanionIOS` generic-Simulator target also builds successfully
with signing disabled. The complete repository gate passes 1,639
MacCompanionKit Swift tests, eight platform-probe tests, all policy/release
fixtures and supported cross-builds, 1,221 current repository files, and 2,268
historical blob paths.

## Non-claims and next gate

This checkpoint does not prove a real physical Act or Control job, participant
understanding, timing accuracy in the field, active route provenance, physical
return, fallback, Stop/revoke recovery, safety review, signed-device behavior,
or exported cohort evidence. It does not infer job intent from a command or
screen session and does not enable calibration or confirmatory enrollment.

The next local evidence slice is explicit tester review for route-independent
facts the product cannot establish, plus authenticated route-class binding only
where the exact winning product authority provides it. Physical dogfood must
then compare every generated fact with visible product truth before any
external cohort begins.

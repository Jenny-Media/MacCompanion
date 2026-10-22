# Stale session activity — issue #33

The reported physical iPhone sequence has not been independently reproduced in
this task. Source inspection found that orphan retirement depended on creating
a session activity controller. Terminal creates that controller only after a
shell opens, so opening the app and canceling sign-in could leave an old system
activity untouched. Desktop activity links also enabled automatic connection,
and the native Desktop view did not carry the session selection's auto-connect
choice into its saved-login startup action.

The library now retires unowned activities on app entry, foreground return and
valid activity-link delivery. A main-actor registry weakly tracks current
activity owners by their unique ActivityKit IDs. Cleanup snapshots unowned IDs
before awaiting ActivityKit; it preserves live, paused and reconnecting owners,
and cannot collect a later session's activity. Controller startup uses the same
ownership filter. Existing immediate session retirement and its independence
from stalled status updates are retained.

With no mounted session, both Desktop and Terminal activity links open sign-in
without automatically connecting. Desktop now passes that choice through its
SwiftUI/native bridge. Existing mounted viewers keep their normal retained
resume path, and ordinary Mac-list entry keeps automatic saved-login startup.
The link format, activity attributes, authentication and wire protocol are
unchanged. The normative lifecycle text and the sole indexed fixture were
updated with orphan-owner and explicit-connect cases.

Regression coverage includes stop → activity entry → canceled reconnect for
both activity kinds, native explicit stop and connection-loss delivery,
attempt cancellation, cleanup with no controller, live/paused/reconnecting
ownership, another controller's startup, delayed old cleanup after replacement,
retained native resume, saved-login automatic-start admission, and actual
ActivityKit orphan cleanup while preserving a current activity. Existing
blocked-update retirement and activity-intent tests remain in the focused gate.

Stable Xcode 27.0 (27A266a) passes the normal iOS Simulator build and all 76
focused hosted tests in one final run, with zero failures. Real ActivityKit
start/update/end and orphan cleanup run successfully, without skips. The required
`bash scripts/validate.sh` passes, including all 138 indexed JSON fixtures and
the package/platform/policy checks. An initial combined run timed out in an
unchanged Terminal login/recovery test; its isolated retry and the unchanged
final combined run both pass.

Private evidence remains outside Git:

- `/private/tmp/maccompanion-issue33-simulator/build-report.json`
- `/private/tmp/maccompanion-issue33-simulator/QA/Lifecycle-final-1792676420343858000.xcresult`
- `/private/tmp/maccompanion-issue33-validation/runs/20261022T133048Z-1a109e26abf5/`

Physical acceptance remains pending: on the reported iPhone/iOS build, exercise
Disconnect → any remaining island entry → Cancel; check foreground and
background connection loss, cancel an initial connection attempt, resume a
valid paused connection, and repeat an old Disconnect action after starting a
new session. Confirm the stopped activity disappears and the new session stays
connected. Simulator lifecycle results do not establish physical Dynamic Island
delivery or presentation acceptance.

## Merge validation

Before merging PR #35, main advanced through `901869c` (Terminal changes in
PRs #30, #31 and #34). Integration commit `084606a` preserves both fixture
updates and recomputes their combined canonical hash in the existing manifest;
there are no additional runtime edits. A follow-up subagent integration review
finds no issues. Stable Xcode 27.0 again passes the normal iOS Simulator build,
all 76 focused hosted tests with zero failures, and required repository
validation with 139 indexed fixtures. Evidence is retained under
`/private/tmp/maccompanion-issue33-merge-simulator/` and
`/private/tmp/maccompanion-issue33-merge-validation/runs/20261022T134651Z-144e9403bcef/`.
Physical acceptance remains pending.

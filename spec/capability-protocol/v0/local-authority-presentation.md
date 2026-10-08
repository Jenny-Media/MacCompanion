# Local authority presentation v0.1

Status: normative bundle-independent Mac administration presentation. This profile defines the facts and correlations a future menu-app UI consumes; it does not define SwiftUI, localized copy, authenticated XPC, durable grant mutation, or capture execution.

## Agent status dashboard

The menu app may present only a successfully revalidated
`LocalAgentStatusSnapshot` obtained through the already-authorized
`readAgentStatus` local capability. Loading and unavailable states contain no
retained Agent facts. A decoded snapshot is validated again before projection;
the dashboard accepts no arbitrary message, endpoint, address, path, device
name, provider identity, or content-bearing field.

The status projection preserves enabled intent, console lock/logout, Agent and
visible-menu process state, listener state, closed route kinds, security
posture, bounded device/session/provider counts, and every sanitized warning.
It also carries one closed `interactiveControlGranted` fact which is true only
when at least one device is paired and every active paired device has the
durable Interactive Control grant. This aggregate fact may suppress redundant
grant review and show that Remote Control is allowed for all paired devices,
but it never authorizes a live session or substitutes for fresh device
approval and visible Mac admission.
It must not claim ready until both processes and the listener report ready. A
locked session states that Observe may remain available while Control is
limited to the genuine lock surface when supported; it never implies desktop
access behind the lock.

Enable, disable, pair, administer devices, view local activity, export
diagnostics, and retry are separate typed intents. Rendering a button or
receiving status does not authorize or complete any of them. Pairing is
available only when the Agent, visible menu app, listener, and security storage
are ready and fewer than eight active devices are paired. Only one QR
presentation and one pairing decision may be active at a time. Pairing remains
distinct from opening device administration, activity history, or diagnostics.

One closed action-admission policy is normative for both projection and
execution. Loading admits no action; unavailable admits only status retry. A
validated status admits enable only while disabled and logged in, disable only
while enabled, pairing only at the complete readiness/below-capacity boundary,
device administration with one or more paired devices, local activity only
while administration is ready, and sanitized diagnostics only while the Agent is
ready. SwiftUI and the application owner must consume this same policy so a
rendered disabled state cannot drift from execution admission.
This policy is presentation/application admission, not security authority. Each
injected lifecycle or Agent capability revalidates current authoritative state
after admission and may still deny the action.

The menu application owns one serialized action coordinator. Before invoking
an injected capability, it re-reads the current dashboard source, revalidates
status, and reapplies admission. A second action cannot enter while any effect
is suspended. Navigation produces only the closed local destinations `devices`
or `activityHistory`; it invokes no remote or lifecycle capability. Diagnostic
completion contains only a revalidated `LocalDiagnosticExport`; file writing
is not part of this coordinator.

Lifecycle, status-retry, and pairing adapters return exactly `completed`,
`notCompleted`, or `outcomeUnknown`. Lifecycle may return `completed` only
after the complete transition and every required platform postcondition
converge. Status retry may return it only after the current connection owner
accepts a fresh status response. Pairing may return it only after the existing
pairing owner holds a visible validated Agent-issued receipt. A closed
`notCompleted` becomes failure; ambiguity remains `outcomeUnknown` and is never
collapsed into success or definitive failure.

Local-authority replacement or loss clears the visible action state and fences
the exact suspended revision. A later completion from that revision returns
only `outcomeUnknown` to its original caller and cannot republish finished
state over the replacement. Application invalidation is terminal for the
coordinator. These revision fences are not peer authentication; signed XPC
adapters must authenticate and authorize each injected capability separately.

The menu application owns a local connection-generation token. A new Agent/XPC
candidate retires the prior token before status is requested. Within one token,
diagnostic sequence must strictly increase and generation time cannot regress.
Connection loss or application invalidation publishes unavailable and retires
the token; delayed status from that connection cannot restore old facts. The
token is only a stale-callback fence and is never evidence that the peer passed
audit-token or designated-requirement authentication.

## Capability grant expansion

The remote-desktop MVP includes the fixed Control grant in the explicit local
pairing approval. The pairing sheet must disclose screen viewing, pointer,
keyboard and eligible text access before its approval button, and explain
that the device remains trusted until removed. New pairings do not present a
second grant-expansion step. Observe and Act are deferred product paths and
are not presented as MVP setup choices. The existing Control expansion UI is
retained solely for legacy pairings which lack Control; an update cannot
silently expand those devices. The following expansion contract remains
applicable to that upgrade and future separately scoped capabilities.

One grant-expansion review is bound to exactly one random review ID, device ID, and its locally confirmed `DeviceDisplayName`. The request contains a nonempty, duplicate-free set of validated local registry descriptors not already in the device's current grants, plus current authorization epoch, grant revision, and policy revision.

Each requested capability retains its bounded English title and summary for identification and all declared effect facts individually:

- data access;
- local-state change;
- user disruption;
- external-service invocation;
- credential access/use;
- destructiveness;
- foreground and lock eligibility; and
- cancellation semantics.

The UI must render host-generated labels for these facts. A provider title or summary is supplemental identification and cannot hide, lower, merge, or replace an effect warning. There is no universal risk score and no wildcard approval for future capabilities.

Reviewing or merely opening the UI creates no intent. Explicit local approval produces one decision-ID-correlated intent containing the review, exact device and shown name, expected revisions, requested capability facts, complete current set, and complete proposed canonical grant set. That intent maps without loss to `LocalGrantDecisionCommandV0`. Success is shown only when its exact receipt advances authorization epoch and grant revision once and stores the proposed set. Decline emits the same exact review binding with a closed decline decision and cannot later become approval; a stale or mismatched receipt cannot claim success.

Interactive Control uses the same durable expansion semantics through a
dedicated, non-provider review contract. The visible menu app may request a
review only while at least one active paired device lacks Control. The Agent
selects the newest active device that lacks Control, reads its locally
confirmed name and complete current grant set in one storage turn, and returns
a five-minute `LocalInteractiveControlGrantReviewV0` bound to
the exact Control capability identifier, authorization epoch, grant revision,
and policy revision. The Control descriptor is fixed product authority and is
never published in the Act provider registry.

The deterministic newest-eligible selection lets a newly paired device receive
its independent grant without allowing remote input to select a target. If the
local user skipped earlier reviews, repeated locally initiated reviews advance
through the remaining eligible devices one at a time. The menu app cannot
choose a device identifier, author the review, change the Control effects, or
approve by requesting the review. It may only present the
Agent-issued review and send the existing exact `LocalGrantDecisionCommandV0`.
Approval stores `maccompanion.interactive.control`, advances both
authorization and grant revisions, and closes current primary-session ingress
until durable convergence and the closed local status fact are complete. An
all-granted status must not be represented as review failure. A newly granted
device must reconnect
and still complete the profile-selected signed, one-session Interactive
approval before capture or input can start.

## Interactive Control warning

The visible Mac warning is separately bound to the locally named device, request ID, approval ID, selected display, approval expiry, and exact closed effects: view screen, move pointer, press keyboard keys, and insert eligible text. View is mandatory and text requires keyboard.

This warning does not create or expand a durable grant. It does not substitute for the phone's profile-selected session-start signature. It identifies an awaiting, starting, active, paused, ending, or ended one-session request and always provides a local stop intent. The stop intent carries the device and shown name, request/approval IDs, and session ID when one exists and maps without loss to `LocalInteractiveStopCommandV0`; only an exact receipt proving both remote-authority end and runtime teardown can close the warning.

`CompanionMacUI` must continue distinguishing the durable Interactive Control grant, the fresh phone approval for one session, the visible local warning, and the active capture/input indicator. None implies shell, files, clipboard, audio, provider execution, or autonomous authority.

## Host identity recovery

The Mac recovery presentation consumes only an Agent-issued
`LocalHostIdentityRecoveryReviewV0`. It shows the exact current host UUID and
fingerprint as identification and separately discloses every fixed destructive
consequence: remote access stops, all paired phones become invalid, all grants
are removed, queued and active remote work is fenced, and re-pairing is
required. Review display alone creates no intent.

Explicit destructive confirmation maps without loss to one
`LocalHostIdentityRecoveryCommandV0` bound to the complete unexpired review and
one recovery UUID. While submission is in flight, the user cannot edit the
cause, scope, expected identity, or recovery UUID. Failure retains the exact
command for retry. Only a correlated receipt naming a different new host UUID
and fingerprint may become completed; invalidation or a delayed mismatched
receipt cannot claim success.

## Acceptance boundary

Bundle-independent tests cover closed status projection, status revalidation,
shared action admission, serialized action effects, closed completion/failure/
unknown outcomes, authority- and application-invalidation fencing, typed local
navigation, sanitized-export revalidation, existing pairing-owner composition,
connection-generation fencing, sequence/time regression, local device-name
binding, deterministic capability ordering, every effect fact, explicit
approval, exact revision/grant receipt, decline, closed Interactive effect
mapping, invalid effect/lifetime rejection, lifecycle presentation, correlated
stop, exact host-identity recovery review/command/receipt correlation,
destructive-consequence completeness, retry fencing, and pure Mac UI
projections. The compile-checked SwiftUI surfaces receive immutable
presentation values and emit only explicit callbacks; they do not own IPC or
authority. Release acceptance still requires authenticated local IPC, reviewed
localization, accessibility review, live lifecycle/grant/recovery mutation,
menu-app crash/recovery, and physical capture/input indicator and stop evidence.

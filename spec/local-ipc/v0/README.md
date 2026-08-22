# Local IPC shared payload profile v0.1

Status: normative for bundle-independent role policy, leases, status, sanitized
diagnostic payloads, and the macOS 26 peer-identity boundary. The signed
peer-requirement mechanism is provisionally proven on Xcode 27 beta. The
production hello, menu-lifecycle-ready, and content-free status-read transport
are constructed; permanent Agent bootstrap composition and signed runtime
evidence remain pending.

Local IPC is never authenticated by a caller-supplied role, PID, path, service
label, or claimed audit token. The macOS adapter installs an XPC peer
requirement derived from transport-owned process credentials, the exact signing
identifier, and the caller's own Apple-issued signing team. Only after that
requirement and version negotiation succeed may it assign one of the closed
roles `agent`, `menuApp`, or `diagnosticCLI` and apply the method matrix in
`CompanionIPC`.

## macOS peer-identity boundary

The Agent listener requires the same signing team and exact
`media.jenny.maccompanion` identifier. The menu-app session requires the same
team and exact `media.jenny.maccompanion.agent` identifier. Both use
`xpc_peer_requirement_create_team_identity`; the private Team ID is not stored
in source, configuration, messages, or evidence. The diagnostic CLI remains
unadmitted until its permanent identifier and reciprocal requirements are
separately signed and proven.

The listener and client session are created inactive. The Agent installs its
requirement on the listener and repeats it on every incoming peer session before
activation. The menu app installs its Agent requirement before activating its
session. A mismatch invalidates or rejects the platform connection before any
role capability is issued.

XPC checks received messages, so a substituted server may receive the first
outgoing request before its reply is rejected. Exactly one pre-authentication
request is allowed: the constant closed value
`{"kind":"hello","version":1}`. Its reply must be exactly
`{"kind":"hello.ack","version":1}` and arrive through the requirement-bound
session. Neither message contains a role, identifier, token, credential,
endpoint, path, capability, device data, user data, or authority.

The JSON-like notation above is descriptive only. On the wire, each handshake
dictionary has exactly two keys: `kind` is `XPC_TYPE_STRING`, and `version` is
the signed scalar `XPC_TYPE_INT64` with value `1`. Missing or additional keys,
and unsigned-integer, floating-point, Boolean, or other alternate scalar types,
are malformed even when their displayed value resembles `1`.

After that reply succeeds, the menu app may send exactly one closed
`{"kind":"lifecycle.menu-ready","version":1}` request. The Agent acknowledges
it only with exact `{"kind":"lifecycle.menu-ready.ack","version":1}` and
publishes readiness only after the acknowledgement is sent successfully. This
message is the transport mapping of menu-only `publishMenuReady`; hello itself
never publishes lifecycle readiness or authorizes another method.

No status, pairing, diagnostic, recovery, lease, media, input, surface, or
other lifecycle message may be sent before that readiness exchange. A malformed,
premature, duplicate, or rejected readiness message cancels the exact peer.
Lifecycle admission failure is returned to the transport owner so it can cancel
only the still-current generation.
Once readiness is acknowledged, an explicitly composed
`menuLifecycleReadinessAndStatus` profile may accept sequential exact
`{"kind":"status.read","version":1}` requests. It calls
`LocalIPCAuthorizationPolicy` for the authenticated `menuApp`-to-`agent`
`readAgentStatus` method and requires a typed reader issued from the complete
Agent local-service root. The permanent target remains `authenticationOnly`;
passing a reader to any narrower profile or constructing the status profile
without one fails before listener construction.

A successful response is exactly
`{"kind":"status.read.ack","version":1,"payload":<data>}`, where `payload`
is `XPC_TYPE_DATA` containing at most 4,096 bytes of canonical closed JSON for
one validated `LocalAgentStatusSnapshot`. A source failure is exactly
`{"code":"sourceUnavailable","kind":"status.read.error","version":1}` and
carries no payload. Unknown members, alternate scalar types, open or
noncanonical JSON, invalid closed values, missing data, or oversized data
cancel the current generation; the menu client publishes only a decoded typed
snapshot, never raw transport bytes.

Only one status read may be in flight per peer and per client. Operation IDs,
listener generations, peer generations, and client session generations fence
late completion, timeout, cancellation, and replacement callbacks. The Agent
cancels a read that exceeds two seconds; the menu client cancels its generation
if no terminal reply arrives within three seconds. A source-unavailable reply
does not invalidate an otherwise current connection, so a later sequential
read may recover.


Client transport callbacks are bound to monotonically increasing session
generations. A cancelled session's delayed cancel, hello, readiness, or status
reply is ignored and cannot authenticate, acknowledge,
release, or cancel a restarted session. Each server listener run has its own
monotonic generation, and every accepted callback requires both that active run
and exact retained-peer membership. The Agent admits at most eight pre-hello
candidates and cancels each after a generation-bound ten-second deadline.
Listener shutdown fences the run before initiating cancellation of all retained
peers and the listener; delayed callbacks from that run cannot enter a restart.

Opening a candidate connection does not displace the current authenticated
peer. Only a successfully acknowledged exact hello installs a replacement;
that replacement immediately fences and cancels the old transport without
publishing a false lifecycle-loss event. Old cancellation and late messages
cannot clear or restore the newer generation. Interruption, invalidation,
requirement mismatch, malformed hello, version mismatch, or current-connection
replacement revokes the issued role and every connection-scoped capability.
The signed probe evidence is recorded in
`docs/evidence/2026-08-21-signed-local-xpc-peer-identity-probe.md`.

The menu app may publish `publishMenuReady` and call the Agent methods
`createPairingSession`,
`dismissPairingSession`, `decideGrantExpansion`, and `stopInteractiveSession`,
may submit `recoverHostIdentity` only from an Agent-issued local review, and may
read bounded local status, activity history, and sanitized diagnostics.
`readAgentStatus` returns only the closed content-free
`LocalAgentStatusSnapshot`; the menu application binds each response to its
current connection generation before presentation. None of the mutating or
detailed-history methods is available to the
diagnostic CLI, the Agent-to-menu runtime endpoint, or a same-role connection.
Agent-to-menu `publishHostIdentityRecoveryReview`,
`publishHostIdentityRecoveryResume`, `withdrawHostIdentityRecovery`,
`withdrawPairingReview`, and `revokeInteractiveLease` remain separate
delivery, presentation-revocation, and execution-teardown
methods and cannot themselves mutate durable identity or grants.

All receivers validate the v0.1 payload while decoding and again against current local authority before method admission. Version mismatch fails before method admission. Interactive execution additionally requires an unexpired agent-issued lease bound to the host, device, Interactive Control session, authorization epoch, selected display, surface, surface revision, and coordinate revision.

## Local pairing presentation

`createPairingSession` is a secret-bearing menu-app-to-Agent method. Its command
contains only the local-IPC version and a random command ID. The Agent, never
the menu app, supplies the current listener-bound host fingerprint, canonical
endpoint candidates, wall and monotonic clocks, pairing ID, and one-time secret.
Success returns one canonical bounded QR string bound to the command, pairing
ID, exact five-minute wall expiry, and creation time. The response is excluded
from diagnostics, audit, CLI methods, logs, clipboard export, and generic local
event payloads.

Only one pairing QR may be visible at a time. An exact retry of its create
command returns the same receipt; a different create command is denied until
the current presentation is dismissed or expires. A create command whose code
was dismissed, expired, or consumed is stale and can never redisplay its old
secret. If QR encoding or receipt construction fails after authority creation,
the Agent must tombstone that session before returning failure.

`dismissPairingSession` binds a new command ID to the exact visible pairing ID.
The Agent reports success only after the pairing authority has consumed the
session and retained its tombstone. A wrong pairing ID changes nothing. A
session already expired, consumed remotely, missing, or durably committing is
never described as successfully dismissed. Exact successful dismissal retries
return the same secret-free receipt. Actor reentrancy cannot admit a second
create or dismiss while an authority mutation is in flight.

The signed XPC adapter must expose these methods only after menu-app peer
verification, invalidate the connection on role/version failure, and discard
the QR response when the local presentation closes. It must never make the
encoded QR available to diagnostic or crash-reporting surfaces.

The Agent network owner exposes pairing context only while both the exact
sealed listener and its Bonjour registration are ready. Their callbacks use
independent increasing generations; stale callbacks cannot restore
availability. Bonjour withdrawal consumes any visible session before a later
code may be created. Listener failure, cancellation, or start failure
permanently disables that handler instance and consumes its active or
in-flight session; a replacement listener requires a new context authority and
handler. Teardown remains authoritative even if status or route publication
fails.

The bundle-independent listener composition consumes one sealed TLS
configuration to create both the unstarted listener and pairing-context
authority. It derives the sole Bonjour candidate from that configuration's
instance, service type, domain, fingerprint, and the same nonzero listener
port. Caller-supplied additional candidates cannot be Bonjour records and must
use that exact port; invalid candidates fail before the one-use listener
configuration is consumed. This construction prevents QR identity, service,
or port substitution, while final private-route inclusion policy remains a
separate platform responsibility.

The menu app retains pairing request state in a pure presentation reducer, not
in SwiftUI callbacks or its transport adapter. If an XPC response is lost, a
create or dismiss retry reuses the exact prior command ID; it never silently
creates a second code or dismisses a different pairing ID. Created and
dismissed receipts must correlate exactly, and dismissal completion cannot
predate QR creation. Agent/listener loss, logout, expiry notification, or local
presentation teardown immediately erases the secret-bearing receipt from the
reducer. The reducer emits typed commands but cannot authenticate XPC, create a
secret, or mutate pairing authority.

### Local pairing review and decision

After remote transcript proof succeeds, the Agent sends
`publishPairingReview` only to the authenticated visible menu-app endpoint.
`LocalPairingReviewV0` binds a random review ID, pairing and client IDs,
SHA-256 fingerprints of both validated client public keys, the transcript
digest, derived authentication string, current policy revision, and exact QR
expiry. It contains no QR
secret, public-key bytes, address, remote name, or mutable authority. The menu
app never synthesizes or edits this review.

The remote protocol deliberately carries no device display name. To approve,
the Mac user must enter a locally chosen `DeviceDisplayName` while comparing
the displayed authentication string; decline requires no name.
`LocalPairingDecisionCommandV0` binds a new command ID, the complete review
identity, approve/decline, and a safe wall-clock decision time. Its name field
is required for approval and must be explicit JSON `null` for decline. A
menu-app retry reuses the exact command. The Agent
re-reads the current review and pairing authority; a mismatch consumes no
broader authority and returns no success.

Approval atomically stores the locally chosen name with the new device keys,
Monitor Only state, authorization epoch 1, grant revision 1, policy revision,
pairing consumption, and minimal security event. Decline consumes the pairing
session and stores neither device nor name. The exactly correlated
`LocalPairingDecisionReceiptV0` carries a device ID and stored name only for an
approved decision; decline requires both fields to be JSON `null`. Missing
fields, false approval, partial commit, absent menu UI, expired review, or a
response that predates the decision fail closed. Review and decision payloads
are excluded from diagnostic/CLI/log/crash-report surfaces.

The bundle-independent delivery boundary is connection-scoped and receives no
caller-supplied role, audit token, endpoint name, or authorization flag. A
platform adapter may obtain it from the Agent local-service root only after it
has authenticated the visible menu-app peer and authorized
`publishPairingReview`, `withdrawPairingReview`, and
`resolveLocalApproval` through the closed method matrix. Production XPC
composition remains outside this bundle-independent delivery profile; its
peer-identity boundary is normative above.

Exactly one review may be publishing, visible, or resolving on that boundary.
The service accepts a review only when it exactly equals the pending review in
the Agent decision authority. It acknowledges publication only after the menu
surface has retained and published the exact immutable value. Reentrancy,
surface rejection, authority cancellation, or replacement with a different
review cannot turn a partial delivery into an acknowledgement. An exact
duplicate publication is idempotent only after the same review is visible.

The menu presentation starts with an empty local name draft and never derives
one from the client ID, network metadata, or either key fingerprint. Approval
validates the draft as `DeviceDisplayName`; decline emits an explicit null
name. Once either action starts, a delivery failure retains the exact command
and command ID for retry and does not permit editing it into the opposite
decision. Only an exactly correlated receipt clears the decision operation.

Withdrawal is bound to the exact review ID and is idempotent. Remote
disconnect, listener teardown, expiry, publication failure, or authenticated
menu-endpoint loss removes the review from presentation. Endpoint loss also
cancels the still-pending decision authority; it never interrupts an already
in-flight durable decision. A host wire owner treats an unavailable registered
review as terminal rather than waiting for its original expiry. Delayed
publication, decision, receipt, expiry, and withdrawal callbacks are fenced by
the exact review plus an increasing local generation, so none can resurrect a
removed review or erase a later one.

The Agent decision authority remains the only source of receipt replay. After
successful mutation, a lost local response may be retried only with the exact
prior command and receives the retained exact receipt. A nonmatching command
cannot use replay to inspect or mutate another pending review. The delivery
service stores no device keys, grants, pairing secret, durable approval, or
independent outcome.

### Authenticated menu presentation wire

After exact menu readiness, the Agent may map only the following five
authorized presentation operations onto its current authenticated menu XPC
generation:

| Request kind | Authorized method | Exact request members |
| --- | --- | --- |
| `presentation.pairing-review.publish` | `publishPairingReview` | `kind:string`, `version:int64=1`, `payload:data` |
| `presentation.pairing-review.withdraw` | `withdrawPairingReview` | `kind:string`, `version:int64=1`, `reviewID:uuid` |
| `presentation.host-recovery-review.publish` | `publishHostIdentityRecoveryReview` | `kind:string`, `version:int64=1`, `payload:data` |
| `presentation.host-recovery-resume.publish` | `publishHostIdentityRecoveryResume` | `kind:string`, `version:int64=1`, `payload:data` |
| `presentation.host-recovery.withdraw` | `withdrawHostIdentityRecovery` | `kind:string`, `version:int64=1`, `reviewID:uuid` |

Every successful reply contains exactly `kind:string` and
`version:int64=1`; its kind is the request kind plus `.ack`. Only the three
publish requests may have an application-rejection reply, containing exactly
those members plus `code:string="presentationRejected"` and using the request
kind plus `.error`. Withdrawal has no error reply: anything other than its
exact acknowledgement terminally invalidates the generation. No reply contains
diagnostic text, roles, process identifiers, transport generations, endpoint
names, authorization flags, or payload data. XPC request/reply association plus
generation-bound local operation state is the sole transport correlation;
router tokens and generations are never sent on the wire.

Each publish payload is nonempty canonical JSON, carried as `XPC_TYPE_DATA`,
and is limited to 4,096 bytes. The receiver first rejects duplicate JSON
members and noncanonical encodings, then decodes the one expected closed
`CompanionIPC` value, validates its constructor invariants, and requires exact
canonical re-encoding equality. Pairing review, recovery review, and recovery
resume payloads cannot substitute for one another. Withdrawal carries no JSON
payload and accepts only a nonzero exact review UUID. Fresh recovery-review
publication also requires receiver-clock proof that current wall time is before
the review expiry; durable recovery-resume delivery may occur after that
original confirmation window.

A publish acknowledgement is sent only after the menu presentation owner has
retained the exact immutable value. Exact visible replay is idempotent; the
same identifier with changed bytes or review/resume mode substitution fails
closed. Withdrawal is exact-ID-bound and idempotent: a wrong or already absent
identifier removes nothing but may acknowledge. Malformed or unknown messages,
wrong scalar types or version, an unrecognized reply, operation mismatch,
timeout, send failure, or ambiguous withdrawal failure terminally invalidates
that XPC generation. A publish `presentationRejected` response is recoverable
only when the menu owner proves it retained no state; a thrown presentation
call without that proof sends no recoverable error and terminally invalidates
the generation.

These messages are unavailable before authenticated menu readiness and are
not admitted to a menu-to-Agent, same-role, or diagnostic-CLI caller. A
concrete transport endpoint must repeat exact-current peer and generation
checks on its serialized XPC queue before every send; it cannot expose a raw
session, arbitrary kind string, raw payload, role, or authentication flag.

### Pairing product composition

The release path constructs pairing as one sealed product composition. One
`PairingSessionAuthority`, backed by the required security store and pairing
audit writer, is shared by QR creation and dismissal, remote transcript proof,
local approval or decline, cancellation, and tombstone replay. The local
session handler, decision handler, and connection-scoped review service are
created together; callers cannot independently inject those authorities into
the production network factory or listener service.

That composition also owns the exact listener and pairing-context authority
derived from one sealed TLS listener configuration. The same context authority
both supplies QR identity and endpoint facts and receives listener and Bonjour
readiness. A production listener therefore cannot advertise one context while
its QR handler reads another, or bind a host pairing session to a different
security store, audit writer, decision owner, or review surface.

The production factory accepts the complete startup-reconciled
`AgentPrimaryServicesV1`, not separately supplied host ID, primary-session
authority, local status/route publishers, local-service root, or audit
composition. Pairing services are issued from that aggregate's originating
required-audit composition and exact local root. This prevents pairing ingress
and ordinary authenticated ingress from being assembled from different durable
stores, lifecycle generations, host identities, or startup reconciliations.

Construction requires an already authenticated and authorized visible
menu-app surface. If that endpoint is lost, the connection-scoped review
service is invalidated, the listener and context are torn down, and the sealed
composition is not reused. A later authenticated endpoint receives a newly
constructed listener-lifetime composition. Package-only split initializers may
exist for deterministic tests and disposable platform probes, but they are not
a conforming release construction path.

## Interactive execution contract

The Agent issues an `InteractiveExecutionLease` for at most 10 seconds. The lease contains a unique lease ID, every binding above, a safe-integer renewal counter, monotonic issue/expiry times, and a canonical sorted unique list of allowed interaction classes. `view` is mandatory. `text` is legal only when `keyboard` is also allowed. Invalid, duplicate, or non-canonical interaction classes and invalid lifetimes fail during decoding; a local caller cannot repair them after decoding.

The Agent sends `InteractiveRuntimeInstallCommandV0` only after final admission. It includes the lease, a locally confirmed presentation-only device name, Desktop as the initial surface, and the enclosing session deadline. The menu app may acknowledge installation only with an exactly correlated receipt, a positive current menu-app revision, a visible status indicator, and readiness for every class granted by the lease. A receipt is not proof that TCC or runtime authority remains available; each operation still revalidates the lease and current platform authority.

A renewal replaces the lease ID, increments the renewal counter exactly once, preserves every host/device/session/authorization/display/surface/revision/class binding, and is issued before the old lease expires. It cannot widen authority or resurrect an expired lease.

Revocation is exactly correlated to the current lease and session. Success is acknowledged only after input is released, capture is stopped, the last frame is blanked, and the visible indicator is cleared. Disconnect, timeout, version mismatch, or an incomplete receipt is treated as teardown failure and keeps remote Control denied.

The device display name is confirmed through authenticated local administration and stored by the Agent. It is NFC UTF-8, 1–64 bytes, has no surrounding whitespace, controls, illegal scalars, or directional formatting controls, and is never accepted as remote authority or copied from unauthenticated discovery metadata.

The menu app's `administerDevices` method sets that name with `SetDeviceDisplayNameCommandV0`: exact local-IPC version, random command ID, retained device ID, validated name, and non-negative safe-integer wall time. Success returns an exactly correlated device/name receipt at or after the command time. Both types re-run validation during decoding. The presentation model publishes no new confirmed name until that receipt matches; stale, mismatched, revoked-device, and storage-failure outcomes preserve the prior confirmed identity. A failed retry may preserve the local draft but never changes authority.

The same authenticated menu-only method performs destructive single-device
revocation through a separate review/command/receipt exchange. The Agent issues
`LocalDeviceRevocationReviewV0` for exactly five minutes from current durable
facts: random review ID, device ID, locally confirmed display name, current
non-revoked state, authorization epoch, grant revision, and closed wall-clock
window. It contains no client key, grant list, route, address, remote name,
screen/input content, or arbitrary consequence text. Receiving a review does
not revoke or suspend anything.

Explicit confirmation creates `LocalDeviceRevocationCommandV0` with a distinct
random command ID, the complete immutable review, and a confirmation time in
the half-open review window. Before awaiting any teardown or storage work, the
Agent installs an independent security-administration ingress fence. It closes
the live primary transport and semantic session, which withdraws route
observation and ends all pending approvals, role channels, and Interactive
authority. A lifecycle-ready callback cannot clear this fence.

With ingress still denied, the Agent first persists the complete accepted
command as one schema-v8 pending intent, without changing authorization. It
then activates the preallocated revocation deny latch and atomically compares
the exact reviewed device state, epoch, grant revision, and local display name
before transitioning to `revoked`. The same SQLite transaction advances
authorization epoch and grant revision exactly once, removes every grant,
fails queued operations, requests cancellation for running work, writes one
minimal security event, and changes the pending intent into a terminal receipt.
While an intent is pending, display-name, grant, suspend/resume, generic revoke,
tombstone, and host-recovery mutations touching that device fail closed.

The latch remains active after the SQLite commit. The Agent refreshes the
content-free paired-device inventory, clears only the matching latch, publishes
nominal security posture, and only then releases the security-administration
fence and returns `LocalDeviceRevokedReceiptV0`, exactly correlated to command,
review, device, terminal state, both successor revisions, and completion time.
Detailed audit failure cannot prevent or roll back this security transaction.

An exact command replay reads and returns the same durable receipt without
repeating effects; reuse of its command ID with different content fails closed.
The intent and receipt survive Agent restart for exactly the revoked-device
tombstone lifetime and are deleted by that tombstone's cascade. After that
retention boundary, exact replay is unavailable and the removed device identity
cannot authorize a new review. Startup reconciles a pending row, a matching
active latch, or the legacy device-only latch before primary ingress can be
issued. A timely persisted confirmation remains executable after its review
window expires. A stale unpersisted review mutates no security state and may
reopen ingress only after the handler proves its own latch is clear and the
local security posture is nominal. Latch, transaction, teardown, or uncertain
status failure returns no success and keeps security ingress denied for local
repair.

## Local host-identity recovery confirmation

Host-identity recovery is a destructive menu-app-to-Agent action and is never
available to a remote session or diagnostic CLI. Before the menu app can form a
command, the authenticated Agent endpoint supplies one immutable
`LocalHostIdentityRecoveryReviewV0`. The review binds a random review ID, the
exact current host UUID and public-key fingerprint, one closed cause, the fixed
scope `invalidateAllPairingsGrantsAndWork`, and an exact five-minute wall-clock
window. It carries no private-key reference, Keychain tag, certificate bytes,
device identity, route, secret, or generic reset parameters.

The menu presentation renders every fixed consequence separately: remote
access stops immediately; every paired phone becomes invalid; every capability
grant is removed; queued and active remote work is fenced; and every phone must
pair again. Merely receiving or opening the review creates no recovery intent.
Only the explicit destructive confirmation action may create
`LocalHostIdentityRecoveryCommandV0`, which embeds the complete review, a new
command ID, a nonzero recovery UUID, and a confirmation time inside the review
window. Failure retains that exact command for retry; changing its review,
recovery UUID, cause, scope, or expected identity requires discarding it and
obtaining a new Agent review.

The Agent accepts the command only while the authenticated menu endpoint and
exact review remain current. In the same transaction that compares the
review's expected host UUID and fingerprint and fences authority, it persists
one bounded reviewed recovery intent: command, recovery, and review UUIDs; the
old host UUID and fingerprint; the closed cause; and the review-created,
review-expiry, and confirmation times. The fixed scope and protocol version
are implicit. This row contains no encoded payload, display copy, private-key
reference, key tag, certificate, device, route, grant, or work content. A
stale review cannot rotate a repaired or replaced identity. The command cannot
select a new host UUID, fingerprint, key tag, certificate, devices, grants, or
work.

Success returns `LocalHostIdentityRecoveredReceiptV0`, exactly correlated to
the command and recovery UUID, naming the replaced host UUID plus a different
new host UUID and fingerprint. Completion cannot predate confirmation. A lost
success response is retried with the exact command and converges through the
durable reviewed intent. While fenced, a restarted Agent may reconstruct and
re-publish only that exact immutable review, and accepts only the exact command
bound to the retained intent; it never manufactures a new review or accepts a
different command for the same recovery UUID. After completion the intent is
retained with the last receipt so a lost success response remains exactly
replayable. A mismatch, expired review before its first durable fence,
Agent/menu endpoint loss, storage or Keychain failure, partial deletion, or an
incomplete receipt remains
failed or in-progress and never claims recovery. The presentation clears an
unsubmitted review on invalidation, but retains a submitted exact command only
for an authenticated retry after the Agent re-publishes the same durable
recovery context. If the menu process also restarted, the Agent uses the
distinct `publishHostIdentityRecoveryResume` delivery to supply the exact
durably retained command; ordinary review publication can never imply that a
command was submitted. The menu may expose only exact retry from this resume
payload and cannot edit or reconfirm it.

The bundle-independent payload, reducer, and application-owner boundaries do
not authenticate XPC or perform recovery. Final transport binding requires the
proven same-team exact-identifier peer requirements and must issue the Agent
review from current durable state rather than caller-supplied identity facts or
roles.

The permanent macOS 26 adapter now constructs that transport boundary. Both
sides install reciprocal same-team exact-signing-identifier requirements while
inactive; the Agent repeats its requirement per peer. It accepts only the
closed hello, publishes a generation-bound authenticated lifetime only after
the exact acknowledgement is sent, and publishes invalidation only for a
previously published lifetime. This handshake grants no method capability.
The production construction evidence is recorded in
`docs/evidence/2026-08-21-production-local-xpc-handshake-construction.md`.
Status, recovery, and other method adapters must consume a capability bound to
that exact generation and must lose it before any replacement can publish.

The bundle-independent recovery delivery boundary is connection-scoped and is
issued only after the platform adapter has authenticated and authorized the
menu-app endpoint. It receives no caller-supplied role, audit token, endpoint
name, or authorization flag. Exactly one fresh review, durable resume command,
or resolution may be visible or in flight. Fresh publication succeeds only
after the surface retains the exact review. Resume publication succeeds only
after the surface adopts the exact command read from durable intent; the
surface cannot turn a fresh review into a resume or vice versa.

`recoverHostIdentity` is admitted through this boundary only for a command
whose complete review equals the visible fresh review, or whose complete bytes
equal the visible durable resume command. A response-loss failure after the
fence changes retry authority to the durable command; a pre-fence failure keeps
only the same fresh review. Reentrancy, replacement publication, or endpoint
loss cannot acknowledge a stale delivery. Endpoint loss withdraws the exact
review from presentation and invalidates only unsubmitted in-memory review
authority. It cannot erase a durable intent or interrupt already-running
Keychain/store convergence; a later authenticated connection must request the
exact durable resume. Successful recovery may leave the completed local result
visible, but the connection-scoped admission returns to idle.

## Local grant decision

`LocalGrantDecisionCommandV0` is emitted only from an explicit local decision on an Agent-issued review. It binds command and review IDs, retained device ID, the locally confirmed device name shown during review, approve/decline, current authorization/grant/policy revisions, the exact canonical current and proposed grant sets, and a non-negative safe-integer decision time. The proposed set must be a strict superset of the current set even for decline, so the Agent can match the exact review that was rejected rather than accepting an unbound denial.

The Agent re-reads the review, device/name, descriptor/effect facts, registry generation, grants, and revisions before acting; the menu payload cannot lower an effect declaration. Approval success returns the exact proposed set, unchanged policy revision, and authorization and grant revisions advanced exactly once. Decline returns the exact current set and unchanged revisions. `LocalGrantDecisionReceiptV0` must correlate command/review/device/decision and complete no earlier than the command time. A stale, mismatched, noncanonical, unknown-field, or revision-inconsistent payload fails closed.

The bundle-independent Agent handler accepts decisions only for an Agent-owned pending review, consumes a mismatched or failed review, and retains a bounded exact-command idempotency window for a response lost after commit. Each pending record retains the exact provider-registry generation and full reviewed descriptors, including every effect fact; the difference between proposed and current grants must equal those descriptor IDs. Registration and decision both require exact equality with the Agent-owned current registry. Registry replacement shares the handler's serialized boundary, invalidates every pending review, and is rejected while a durable decision is in flight, so an effect change cannot interleave with approval. Its SQLite adapter compares the local name, current grants, all three revisions, and active device state inside the same immediate transaction that writes an approval, advances both authorization fences, fences queued work, and appends the security event. Injected failures roll back every part. A decline performs the same exact comparison without changing grants, revisions, or the audit stream.

## Local Interactive stop

`LocalInteractiveStopCommandV0` binds the local action, retained device and displayed local name, remote request and approval IDs, closed reason, time, and either the active Interactive session ID or explicit JSON `null` while approval is still pending. Missing the session field is invalid and cannot be interpreted as pending.

The Agent first prevents new remote admission, ends the pending or active Interactive authority and channels, then drives the existing Agent-to-menu lease revocation when a runtime exists. `LocalInteractiveStoppedReceiptV0` reports success only when remote authority has ended and runtime teardown is complete; it exactly repeats the action/device/request/approval/session/reason binding and completes no earlier than the command. The Mac presentation remains `ending` after any incomplete or mismatched receipt.

The Agent handler enforces that order behind two distinct interfaces. The concrete remote adapter removes only an exactly bound pending approval, approval-to-runtime transition, or active dispatcher session, clears remote state before awaiting termination, and makes exact retries idempotent. The runtime adapter accepts either an explicit no-runtime-installed result for a pending approval or an exactly correlated lease-revoke receipt proving input released, capture stopped, retained frame blanked, and indicator cleared. A false, partial, stale, or cross-session proof never becomes a local stopped receipt.

## Local audit history

`readAuditHistory` is menu-app-to-Agent only after platform peer
authentication. `LocalAuditPageRequestV0` carries the exact protocol version,
random request ID, optional exclusive descending cursor, and a limit of 1
through 100. The Agent ignores any notion of scope from the caller and always
reads `.localAdministration` from the bounded detailed store.

The response exactly correlates the request and carries at most 100 newest-first
closed events, an optional exclusive continuation cursor equal to the last
returned sequence, complete retained bounds, and explicit prune/drop gaps.
Events contain only the stored event UUID/time, closed actor/visibility/code,
optional subject-device ID, capability ID, route class, surface kind, and closed
outcome. Correlation, operation, Interactive-session, and revision identifiers
are deliberately omitted from the menu payload because the v0 activity UI does
not render them. Parameters, results, remote text, addresses, titles, paths,
input, media, and content remain unrepresentable.

The Mac projection receives this IPC response, resolves a device label only
from Agent-owned locally confirmed names, and preserves gaps and continuation.
It never consumes a SQLite record directly. Store errors become one closed
local handler failure and do not expose SQLite or record detail.

Diagnostic payloads are deliberately content-free:

- Status contains closed lifecycle, network, security, route-kind, warning-code, and bounded-count fields.
- Route kinds never contain addresses, hostnames, interface names, or credentials.
- Events contain only a sequence, time, closed component/severity/code, and bounded occurrence count.
- Events are strictly increasing and exports contain at most 256 events.
- Export asserts that private route details and all content-bearing data were omitted; either assertion being false invalidates the export.
- There is no arbitrary message, path, title, value, address, key, screen, input, focus, or application-content field.

The Agent owns one boot-scoped in-memory diagnostic event authority. It assigns
positive, strictly increasing safe-integer sequences and retains only the
newest 256 events; when full, it removes the oldest event before admitting the
newest. The v0.1 producer facet records one occurrence per event, so
`occurrenceCount` is always one for Agent-created events. Invalid or unsafe
times and sequence exhaustion fail before mutation. No producer can supply a
sequence number, arbitrary detail, or retention decision.

Both the authenticated menu app and authenticated diagnostic CLI may call
`exportDiagnostics`; other role directions and same-role connections remain
denied. The bundle-independent export service accepts no caller-supplied role,
token, identifier, or authorization flag. A platform adapter receives it only
after same-team exact-identifier XPC authentication, closed hello negotiation,
and authorization through the closed method matrix. One export obtains a
freshly validated status snapshot
and the current ordered event ring. If either source or final export validation
fails, it returns only `sourceUnavailable` and no partial value.

This export is not detailed audit history, a crash report, a telemetry stream,
or a durable record. The authority is empty after each Agent launch and does
not write a file, upload data, or promise a transactionally atomic physical-time
snapshot across status and events. A future user-selected file save remains a
menu/CLI target concern and must write only the already-validated export.

The Agent owns one coherent cached status version. Lifecycle, listener state,
emergency-latch health, route-class inventory, active paired-device count, live
provider count, and detailed-audit health publish only their closed facts after
their source transition completes. A read never races those authorities and
assembles a mixed payload itself. This is coherence of the published Agent
version, not a claim that independent OS sources were sampled at one physical
instant.

For the one-Mac/one-phone v0.1 product, paired-device count and active primary
session count are each bounded to zero or one; provider count is bounded to
128. Route classes are supplied by a platform route monitor and are never
inferred from listener addresses, peer identities, or provider metadata. A
failed paired-device inventory read preserves the last inventory and publishes
only `storageUnavailable`. A clear emergency latch maps to `nominal`, an active
latch maps to `denyLatched`, and a corrupt or unreadable latch maps fail-closed
to `storageUnavailable` without exposing its path, pending device, reason, or
POSIX error.

Each successful status read receives the next unique positive diagnostic
sequence. Invalid source updates and invalid read times change neither the
cached facts nor that sequence. Warning codes are derived from the accepted
version: unavailable required processes, the closed listener warnings,
deny-latch/storage posture, and degraded audit history. Callers cannot inject a
warning outside the network adapter's exact `localNetworkDenied` and
`routeUnavailable` set.

## Route observation contract

The bundle-independent route authority starts at generation zero in `stopped`
with no route kinds. Each accepted closed source event advances the shared
projection generation exactly once. Event and freshness-read times are
non-negative safe-integer monotonic milliseconds and may not regress behind
any already accepted source event or freshness read.

Route source ownership is disjoint. `lan` is event-owned by the exact listener
plus Bonjour-registration authority. `privateDNS` and `privateNetwork` are a single
replaceable contribution owned by the current authenticated primary
connection. A configured-route contribution is fresh for 30,000 milliseconds
through its inclusive deadline. The first read after that deadline advances
exactly once and removes only that scoped contribution; it may not remove LAN.
Likewise, a configured-route heartbeat may not extend LAN evidence, and a LAN
callback may not extend configured-route freshness.

An accepted empty aggregate route set publishes `routeUnavailable`; a later
nonempty aggregate clears that warning. Explicit aggregate `unavailable`
behaves the same without a freshness deadline. Intentional `stopped` removes
all route kinds but clears the route-source warning because disabled
monitoring is not a route failure.

The status authority accepts only a route generation newer than the last one
it published. Source-specific authorities add their own listener,
advertisement, and primary-owner generations. These fences are required
because an actor call awaiting the status sink may be re-entered by a later
platform callback. A delayed earlier callback may complete, but it cannot roll
back the route set or warning or mutate a replacement connection's evidence.

The platform adapter, not this authority, must define evidence for classifying
`lan`, `privateDNS`, and `privateNetwork`. It may publish only that set. It must not
pass through interface names or indices, addresses, DNS names, Bonjour labels,
peer or tailnet identity, credentials, path descriptions, or platform errors.

## Local status read service

The bundle-independent status read service accepts no caller role, audit token,
identifier, method name, or protocol version. A platform adapter may receive
that read capability only after it authenticates the XPC peer and authorizes
`readAgentStatus` through the closed method matrix. This prevents an informal
service call from treating a caller-supplied role as identity evidence.

One read samples wall time exactly once and asks the coherent status authority
for one version. A successful read consumes one unique diagnostic sequence. An
invalid/unsafe clock value, exhausted sequence, or other internal source error
returns only `sourceUnavailable`, emits no payload, and does not consume the
next sequence. Concurrent reads remain serialized only at the status authority;
they may share a wall-clock millisecond but cannot share a sequence.

## Agent local-service construction root

The Agent bootstrap constructs one local-service root only after provider
publication validates and durable operation restart reconciliation succeeds.
Before returning any local read or update capability, the root creates its
status authority, reads emergency-latch posture, folds current detailed-audit
health, and refreshes active paired-device and live-provider counts. The initial
network and route sources are stopped with zero active remote sessions. It also
creates one boot-scoped sanitized-event authority, gives Agent coordinators only
its write-only publisher facet, and issues one validated export capability that
shares the root's status reader.

An unreadable paired-device inventory or corrupt/unreadable security latch does
not suppress local repair status. The root returns with `storageUnavailable`
and a closed sorted bootstrap degradation report. Audit degradation likewise
returns a readable root with `auditHistoryDegraded`. A paired-device or provider
count outside the v0.1 bounds is an invariant failure: bootstrap returns no
root or reader.

The raw multi-field status authority, its initializer, snapshot function, and
mutation methods are package-only and are never returned by product bootstrap.
The public root exposes only the already-authorized reader, a network-only
publisher, the generation-fenced route authority, inventory refresh, security
refresh, and a narrow transient-source stop. Lifecycle and audit-health facets
are package-owned by their exact Agent coordinators. One source therefore
cannot replace another source's fields.

Transient stop clears route and listener facts and the active-session count,
but preserves lifecycle, paired/provider inventory, security posture, audit
health, and diagnostic readability for shutdown presentation.

## Lifecycle observation source binding

Agent process readiness is not an IPC method. After the complete required-audit
`AgentPrimaryServicesV1` graph returns, the signed Agent target creates the
sealed lifecycle-observation root. That exact construction activates a random
Agent generation and publishes ready; no earlier provider-loading, storage,
identity, reconciliation, local-service, or primary-session failure can publish
Agent ready.

Menu process readiness is connection-scoped metadata, not a caller-supplied
request or role. Only after the platform adapter enforces the menu's same-team
exact-identifier requirement and authorizes protocol negotiation may it ask the
sealed root for one exact-generation menu connection capability. Issuance alone
leaves menu state `starting`. The capability publishes ready only when the
authenticated connection and required visible-menu runtime are ready, and its
invalidation callback owns exact-generation termination. It accepts no caller
role, PID, path, service label, or signing claim.

Duplicate generation issuance is rejected. Replacing a prior ready generation
performs lifecycle exit/Control safety before a new connection may publish
ready. Ready and invalidation calls serialize across suspension; repeated
invalidation replays its exact terminal receipt, while ready after invalidation
is stale. A stale old connection cannot publish readiness, terminate the
replacement, or request recovery. The final XPC adapter must invoke invalidation
for interruption, invalidation, authenticated-peer loss, or process loss and
must retain a failed/ambiguous recovery result for the separately bounded
recovery policy rather than converting it to success.

That recovery policy is exact and closed. A failed or ambiguous request to
start the already-registered menu role retains only its lifecycle revision,
menu observation epoch, and the fixed `requestMenuRecovery` effect. It may make
at most three additional attempts after 250 milliseconds, 1 second, and 4
seconds. The start request is idempotent platform recovery, not a semantic
remote operation; an ambiguous outcome therefore permits this bounded replay
but never claims the menu process is present or ready. Each attempt rechecks
the exact retained revision and role epoch while the role remains `starting`,
enabled, logged in, and without an authenticated replacement observation. A
new connection, disable/logout, any lifecycle revision or role-epoch change,
successful request, or cancellation ends the loop. Exhaustion leaves the
original terminal receipt and degraded `starting` state truthful and schedules
no further automatic work.

The required Agent audit composition folds its closed producer-health snapshot
into the existing `readAgentStatus` payload as the single warning code
`auditHistoryDegraded`. It does not change `securityPosture`, because detailed
history is not security authority, and it does not expose the database error,
producer name, path, quota, or dropped content. The authenticated local menu UI
may use that warning to offer repair guidance; the diagnostic CLI receives the
same content-free fact through its already-authorized status method.

The JSON fixtures exercise the platform-neutral model only. They do not define
an XPC serialization or permit using JSON over a local socket. The signed probe
proves system-bound same-team and exact-identifier enforcement in both
directions, including wrong-identifier and wrong-signer rejection, and rejects
unsupported or structurally broadened hello messages. The production adapter
must carry those exact checks forward and still prove connection replacement,
invalidation, late-message fencing, role-capability revocation, and Interactive
lease teardown before it is accepted.

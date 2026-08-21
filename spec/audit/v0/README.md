# Bounded audit profile v0

Status: normative bundle-independent profile for the first local user-visible
audit store. It is separate from `security_events`, whose minimal records remain
transactionally coupled to security-state mutations in the security database.
This profile stores no media, input, semantic, provider-private, or arbitrary
text.

## 1. Authority and database boundary

The Agent is the sole writer. The detailed audit database is a separate SQLite
file so its 16 MiB logical quota, 50,000-row quota, retention, compaction, and
repair cannot consume the security database quota. It is not a second authority
for grants, operations, devices, policy, or session state.

The release Agent composition must construct operation execution and lifecycle
observation through one root that requires the security store and this detailed
store. Lower-level optional writers are test seams, not a permitted release
configuration. Every best-effort producer must inspect the append result: a
durably recorded rate/quota drop degrades audit health just like a thrown store
failure, while the primary committed fact or completed safety action remains
unchanged.

Consequential state mutation still requires its minimal `security_events` row
in the same security-database transaction. A caller may additionally mark a
detailed event `requiredBeforeEffect`; failure or throttling then denies the new
effect. Safety teardown is never delayed to write audit: teardown proceeds, the
store records a gap if possible, and current health remains degraded until
local recovery.

## 2. Closed record

The store allocates a monotonically increasing positive sequence and accepts:

- random event UUID;
- non-negative host wall time;
- closed actor: `localUser`, `agent`, `menuApp`, `diagnosticCLI`,
  `pairedDevice`, or `system`;
- closed visibility: `localOnly`, `subjectDevice`, or `allPairedDevices`;
- optional subject-device, correlation, operation, and Interactive-session
  UUIDs;
- one closed event code from the implementation enum;
- optional capability ID, limited by the core capability-identifier grammar;
- optional policy, authorization-epoch, and grant revisions;
- optional coarse route class: `localDiscovery`, `directPrivateAddress`, or
  `privateHostname`;
- optional surface kind: `desktop`, `application`, `window`, or
  `focusedRegion`;
- optional closed outcome; and
- `bestEffort` or `requiredBeforeEffect` importance.

`pairedDevice` requires the same non-null subject device. `subjectDevice`
requires a subject device. `allPairedDevices` forbids device, correlation,
capability, operation, session, authorization/grant revision, route, and surface
fields and is reserved for coarse host availability/security state. Arbitrary
maps and strings are absent.

The store rejects duplicate event UUIDs, noncanonical capability IDs, invalid
revision/timestamp ranges, contradictory actor/visibility, and records whose
deterministic logical size exceeds 1,024 bytes.

## 3. Privacy and self scope

Local administration may page every retained record. `audit.readSelf` may page
only `subjectDevice` rows matching the authenticated requesting device and
`allPairedDevices` rows. It never returns another device ID or activity. Global
rows contain no device, correlation, capability, provider, operation, session,
device revision, route, or surface detail. The requester device ID comes from
the authenticated principal, never the message body.

The schema cannot represent QR secrets, keys, addresses, app/window titles,
paths, parameters, results, provider error text, stack traces, video, images,
audio, pointer coordinates, key identities, typed text, clipboard, focus or
Accessibility content. Byte/frame counters are deliberately omitted from v0;
future aggregation requires a new closed schema and privacy review.

## 4. Bounds, compaction, and gaps

- Logical retained bytes: 16 MiB by default.
- Retained rows: 50,000 by default.
- Maximum single record: 1,024 logical bytes.
- Retention: 30 days.
- Page size: 1 through 100.
- Per actor plus subject-device bucket: 120 append attempts per rolling
  60-second wall-clock window.

Before an append, the writer removes expired rows and then the oldest retained
`bestEffort` rows until the new row fits. It never quota-evicts an unexpired
`requiredBeforeEffect` row. Purging advances a durable `prunedThroughSequence`.
A dropped best-effort append durably increments `droppedEventCount`; if even
that transaction cannot commit, the caller receives a storage error and must
surface degraded audit health.

Required events fail closed on rate, row, logical-byte, transaction, or disk
failure. Best-effort events may return a typed dropped result only after the
gap counter commits. Pages always include newest/oldest retained sequences,
the pruned-through sequence, and dropped count. Therefore an empty page never
means that no event occurred.

### 4.1 Operation producer boundary

An operation producer writes `operation.admitted` with
`requiredBeforeEffect` after the security store has atomically claimed the
durable operation and before calling the provider. If that detailed write
fails, the provider is not called and the durable running operation transitions
to failed with the host-owned code `audit.requiredUnavailable` plus its normal
minimal `security_events` record.

Terminal operation rows are `bestEffort` because their described effect or
safety outcome has already occurred. A detailed-store error degrades audit
health but cannot rewrite that durable outcome. Operation audit event UUIDs are
stable over operation UUID plus closed event code, so observing a terminal
record again repairs a missed append without duplicating it. The detailed
record contains only the subject device, operation, capability, exact authority
revisions, closed code, and closed outcome; parameters, results, and terminal
provider text remain absent.

### 4.2 Pairing producer boundary

The security database's atomic pairing-consumption, device, and minimal
`security_events` transaction is the pairing authority. The separate detailed
database cannot participate in that transaction, so `pairing.approved` is
written `bestEffort` immediately after the security commit. Its event UUID is
the durable pairing UUID, making exact observation retries idempotent.

A detailed-write failure marks audit health degraded but never rolls back or
hides a pairing that already committed. The record exposes only the local-user
actor, subject device, policy/authorization/grant revisions, closed allowed
outcome, and event time. It contains no one-time secret, public key, transcript,
authentication string, client ID, or remote-provided identity text.

### 4.3 Interactive Control producer boundary

An authenticated Interactive request writes `interactive.requested`
`bestEffort`. After fresh-presence proof has been consumed and a complete
bootstrap/accepted response has been constructed, the dispatcher writes
`interactive.approved` with `requiredBeforeEffect` before reserving active
authority or asking the visible menu runtime to install capture/input effects.
Failure returns the closed `storage.securityUnavailable` local-repair response;
the runtime is never installed.

`interactive.started` is best-effort and is emitted only after runtime install
succeeds. A runtime-install failure emits best-effort `interactive.failed`
without a started event. Primary-session disconnect first terminates runtime
authority and then emits best-effort `interactive.stopped` using an injected
host wall clock. A local `interactive.stopped` event is best-effort and is attempted
only after remote authority has ended and the exact receipt proves input
released, capture stopped, retained frame blanked, and indicator cleared. Audit
failure can never delay that safety teardown. Request, approval, session, and
local-stop event IDs are deterministic or durable command IDs, so retries do
not duplicate history. Events expose only closed capability/surface/outcome and
authority bindings; credentials, frame/input content, target tokens, display
IDs, and device display names remain absent.

### 4.4 Product-lifecycle producer boundary

The pure lifecycle reducer remains the authority for process/session state and
recovery effects. After a caller has applied a valid reducer transition, a
separate Agent writer may observe a completion that exactly reproduces the
same before state, event, after state, and ordered effects. A mismatched or
forged completion is rejected before audit storage.

The writer emits privacy-safe `allPairedDevices` rows only when the completed
transition changes one of two coarse projections. A change to explicit enabled
intent emits `host.securityStateChanged`; a change to Observe availability
emits `host.availabilityChanged`. `succeeded` means that the projected state is
enabled or available, and `unavailable` means that it is disabled or
unavailable. Rows use the `system` actor, contain no correlation, device,
capability, operation, session, authority-revision, route, or surface fields,
and are always `bestEffort`. Menu-app-only transitions do not misreport the
whole host as unavailable; Interactive termination has its own detailed event.

The lifecycle state and ordered recovery/safety effects exist before the
writer is called. Storage failure, throttling, or quota drop degrades audit
health but cannot change, delay, or suppress teardown, session closure, or
process recovery. Event UUIDs are stable over the caller's durable transition
UUID plus closed event code, so replay repairs a missed observation without
duplicating history.

### 4.5 Primary application-session producer boundary

After proof verification publishes an authenticated principal, the primary
session writes subject-device `auth.succeeded` and `connection.opened` rows as
best effort. Both bind the current policy, authorization epoch, and grant
revision but omit the opaque connection credential, nonces, signature, route,
addresses, and request content. Stable event IDs derive from the 16-byte
connection credential plus closed event code without storing that credential.

A rejected cryptographic proof writes only a local `auth.rejected` row from the
Agent with the proof-message correlation UUID. It does not assign a subject
device or become visible through `audit.readSelf`; invalid framing or
correlation belongs to the separate protocol-rejection producer. Strict wire
decoding, replay, wrong-phase, and authentication-correlation violations emit
local-only `protocol.rejected` from the Agent with no request content, subject,
or correlation. The host-generated response UUID supplies a stable namespaced
event ID without storing it as remote-visible correlation. Authentication
denial, liveness expiry, adapter-clock failure, and server-side status failure
do not masquerade as protocol rejection.

Closing an authenticated primary session first clears session authority and
awaits Interactive authority teardown, then attempts subject-device
`connection.closed` with an injected host wall clock. A failed or durably
dropped close row degrades audit health but cannot delay or reopen either
authority. Re-observation is idempotent. The Agent required-audit composition
constructs this writer from the same separately bounded detailed store.

## 5. Pagination and ordering

Pages are newest-first. An optional exclusive `beforeSequence` cursor selects
older records. A page returns another cursor only when an additional visible
row exists. Sequence allocation, insertion, rate-window update, compaction, and
gap metadata are one immediate transaction. Restart preserves ordering and gap
state. Sequence exhaustion fails closed.

## 6. Evidence boundary

Bundle-independent tests must cover validation, exact self filtering, global
privacy, cursor behavior, age/row/byte compaction, required-row preservation,
durable rate drops, injected rollback, duplicate IDs, restart ordering, and
sequence exhaustion. Real WAL/checkpoint/disk-full/permissions loops, repair UX,
authenticated remote and local adapters, and seven-day size/rate measurements
remain release-shaped evidence.

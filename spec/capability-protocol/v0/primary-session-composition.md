# Authenticated primary-session composition v0.1

Status: normative bundle-independent host composition. This profile binds one
accepted Network.framework application connection to authentication, replay,
status, and operation authorities. It does not define listener construction,
socket I/O, certificate custody, or a permanent Apple target.

## Host-side TLS binding

The client-side pin authority and host-side listener evidence are distinct.
The client verifies the Mac's pinned certificate. The host does not infer
client identity from TLS and does not claim mutual TLS. Before constructing a
primary session, the host adapter proves that the accepted connection:

- negotiated exactly TLS 1.3;
- accepted no early data; and
- was served with SubjectPublicKeyInfo whose SHA-256 fingerprint equals the
  current durable host identity.

Failure creates no primary session. Application authentication remains the
only remote-client identity proof.

## Ownership and phases

One session owner has exactly four phases:

```text
awaitingHello -> awaitingProof -> ready -> closed
```

The owner holds the connection replay window, authentication challenge
correlation, random 16-byte primary connection ID returned by the authentication
authority, and authenticated principal. None of these values is accepted from
an operation or status request body. Closing destroys all boot-scoped session
state. A closed owner cannot reopen.

Only `auth.hello` is accepted in `awaitingHello`. Only an `auth.proof` whose
`correlationID` exactly equals this owner's `auth.challenge` message ID is
accepted in `awaitingProof`. Successful proof produces the correlated
`session.describe.response` and enters `ready`. Wrong-phase traffic, malformed
traffic, failed proof, bad correlation, replay, unsupported direction, or an
authentication deadline failure closes the owner.

## Agent bootstrap and MVP connection ownership

The release composition does not construct this owner directly. One Agent
bootstrap first loads the complete provider set, validates one immutable
registry/provider publication, and atomically reconciles every durable queued
or in-flight operation after restart. Provider-load failure, publication
validation failure, or reconciliation failure returns no capability mutation
authority and no primary-session authority.

Before that fence, the release Agent reads the singleton durable host-identity
record from the same private security store. The record must exist and be in
`ready` state. Its host ID, 32-byte SPKI fingerprint, and certificate DER are
the only release identity binding; the product target does not supply a free
host ID. Missing or recovery-fenced identity returns no service root.

The public Agent-network startup factory owns the ordering before that read. It
uses the required-audit root's exact private security store to run the normative
host-identity startup coordinator. First-unlock waiting, established-key loss,
or a durable recovery fence returns a closed non-ready product result and
constructs no TLS configuration, primary-service root, pairing graph, or
listener. One release wall-time sample binds identity issuance/inspection, TLS
configuration validation, and Agent bootstrap. A ready result constructs the sealed TLS configuration only from that
exact issued identity and fingerprint, then bootstraps the provider/status/
Interactive root, and finally asks the existing pairing product factory to
consume the configuration. The latter's certificate/fingerprint comparison
against the newly re-read ready row is the final stale or cross-wired identity
fence. Failure at any intermediate gate opens no listener or QR authority.

Only after those identity and reconciliation fences does the Agent bind the
durable device store to the application-authentication authority, the bounded
detailed store to the `audit.readSelf` dispatcher, and the root-owned status
and Interactive authorities to the private operation and capability
dispatchers. A listener may supply only connection-specific validated TLS
evidence and its monotonic acceptance time; it cannot substitute a registry,
provider catalog, authentication reader, audit store, status authority, or
Interactive authority per connection.

The public listener/pairing product factory must compare both the sealed TLS
configuration's fingerprint and certificate DER to that exact durable
identity binding before it consumes the one-use listener configuration. A
different certificate or fingerprint creates no listener, pairing context, QR
authority, or primary ingress. Same-key certificate renewal therefore requires
the durable record and listener configuration to converge on the same current
certificate before restart.

The platform bridge consumes only the one-shot verified-ready connection
authority produced for the exact accepted `NWConnection`. It asks the fixed
Agent authority for a session using that authority's TLS binding, constructs
the frame pump from the same one-shot connection, and attaches the pump as the
session's transport before returning either value. Exact transport termination
removes only that session; global lifecycle and security fences cancel every
attached pump before completing semantic teardown. Construction or attachment
failure closes only the exact candidate session; stale cleanup cannot close an
unrelated retained session.

The shared-listener first-frame classifier and independent pairing ownership are
normative in `host-listener-ingress.md`. A pairing-classified connection is not
a primary candidate and cannot close, replace, or mutate the retained primary
set.

One listener-handoff authority owns the asynchronous transfer from accepted TLS
candidate through verified readiness, Agent binding, frame-pump activation, and
terminal cleanup. It runs one classifier/binder at a time and retains at most
three additional accepted candidates in a bounded FIFO so the application,
input, and media dials cannot starve one another. Every readiness, binding, and
terminal callback carries an unforgeable local generation token; a callback may
mutate state only while that exact generation is still pending, binding, or
active. Cancelled candidates close their exact connection and session without
touching any retained owner.

Pump activation has a synchronous termination latch. A terminal event that
wins the race with activation prevents publication and closes the candidate; a
terminal event after activation retires only the matching active generation.
An application-primary generation joins the bounded retained set only after it
has bound and its preserved first frame has been accepted by the semantic
owner. It never cancels another device's application-primary connection. A
TLS-ready connection or syntactically valid `auth.hello` is not an activated
primary and cannot evict an authenticated owner. Listener-handoff cancellation
clears pending and every active publication before awaiting teardown, is
idempotent, and causes any in-flight binding result to self-retire when it
resumes.

The outer Agent network service has one start and one terminal transition. Its
release constructor accepts only the sealed host listener owner and the
startup-reconciled Agent primary-session authority; listener callbacks cannot
inject a different binder or semantic dependency. It samples the acceptance
timestamp exactly once before handoff admission. Listener start failure,
listener terminal state, or explicit service cancellation first makes the
service terminal, then cancels the handoff, and only after teardown publishes a
sanitized local terminal reason. Late accepted callbacks are cancelled without
starting TLS evaluation. Accepted-connection start failures are reported only
as the closed local `acceptedConnectionStartFailed` category; underlying error
text is not diagnostic data.

The sealed listener emits one local ready transition, distinct from start. The
service therefore projects `idle`, `starting`, `listening`, locally stopped,
and degraded outcomes without guessing from construction or acceptance. The
projection exposes only `LocalAgentNetworkState`, a content-free
`hasActivePrimary` Boolean, and the existing `routeUnavailable` warning code.
It contains no count, route, address, peer, TLS, traffic, or underlying-error
detail. A per-connection start failure may add that warning while the listener
remains listening; listener failure makes the network state degraded; explicit
local cancellation makes it stopped.

The Stage 2 product retains at most eight application-primary sessions, matching
the paired-device capacity. Opens and global teardown serialize; a ninth open
fails closed. Observe and Act dispatch remain bound to each session's
server-issued connection ID. Exact transport termination removes only its own
session and releases its capacity slot, so reconnect churn cannot exhaust the
set. Interactive teardown is connection-aware: closing an unrelated primary
does not clear another device's pending or active Control authority. The shared
Interactive dispatcher still admits at most one active Control session across
all retained primaries.

The same returned service root owns the pure product lifecycle reducer. Menu
process loss invokes only Interactive teardown and leaves otherwise eligible
Observe/Act primary sessions open. Disable, logout, or Agent loss closes every
primary owner, with connection-aware exactly-once Interactive teardown.
Only after those remote-authority effects complete may the coordinator publish
the completed transition and attempt best-effort lifecycle audit. Registration,
unregistration, and process-recovery effects remain explicit output for the
future signed platform owner.

Dashboard lifecycle commands persist the user's desired enabled state before
changing login registration or live remote authority. The final containing app
supplies one owner-controlled Application Support directory. Its single-record
store contains only schema version, positive safe-integer revision, desired
enabled Boolean, random command UUID, and non-negative safe-integer wall time.
The record is strict canonical JSON bounded to 1,024 bytes. Replacement uses a
process-shared lock, expected-revision compare-and-set, a 0600 no-follow
temporary file, file `fsync`, same-directory atomic rename, and directory
`fsync`. The directory is a non-symlink 0700 directory and unknown entries fail
closed. A failure after rename is accepted only by exact read-back; readiness,
process state, routes, peer data, credentials, and remote content are never
stored in this record.

Dashboard enablement then uses a compare-and-commit lifecycle saga. After
durable enabled intent exists, the Agent prepares the exact reducer transition
from its current state without mutating or reserving it. The containing-app
owner converges Agent registration followed by visible-menu registration. Only
after both succeed may the Agent commit that exact prepared transition, and the
commit fails if any lock, logout, crash, or other lifecycle event changed the
before state. While live desired state remains disabled, a failed/stale commit
unregisters both roles as compensation. The durable enabled intent remains for
an explicit retry or restart reconciliation. If another accepted enable already
owns enabled state, the stale caller must not unregister those roles and
returns `outcomeUnknown`.

After an exact enable commit, the platform owner requests Agent then menu
process starts. A start-request failure does not rewrite the committed enabled
intent; it returns not completed and a same-desired-state retry reconverges both
registrations and both start requests. `completed` means those platform calls
reached their verified postconditions, not that either process has reported
ready. Readiness remains an independent lifecycle/status transition.

Disable durably records disabled intent before committing the reducer and
completing Interactive/primary remote teardown. Only after that live safety
boundary does it attempt either unregistration. Both login roles are always
attempted. Unregistration failure therefore leaves a known remote-safe disabled
state and returns not completed for local cleanup; it cannot restore remote
ingress. Same-desired-state disable retries converge both roles absent. All
transition times are non-negative safe integers, and lifecycle command
execution is serialized independently of dashboard serialization.

On restart, the durable record is loaded before constructing the lifecycle and
before any listener can become ready. A missing record means disabled. The
initial reducer restores only desired enabled intent and the freshly observed
console state. Agent and menu states begin `starting` for an enabled eligible
session and stopped otherwise; they never restore `ready`. Startup then
reconverges registration and live state to that exact durable Boolean. An
enabled logged-out state registers both recovery roles but requests no process
starts until a genuine login transition. Corrupt, unreadable, or conflicting
storage prevents readiness rather than guessing an enabled state.

Every committed lifecycle transition advances a boot-scoped revision. A
prepared transition binds that revision as well as its complete before state;
commit requires both. Returning through an ABA sequence to an equal state does
not make an old preparation current. Each process role also has a boot-scoped
observation epoch. Enable, disable, eligible login, logout, and the matching
role's exit advance that role's epoch; ready and lock/unlock do not. Epoch or
revision exhaustion fails closed.

Process readiness is accepted only through one generation-fenced observation
owner. The final signed target may activate an Agent generation only after that
exact Agent completes its required bootstrap, and a visible-menu generation
only from its authenticated local process/IPC authority. Login registration,
`SMAppService` status, a successful start request, PID presence, or an
untrusted self-asserted role is insufficient. Activation alone leaves the role
`starting`; an exact current-generation ready observation applies the matching
`agentReady` or `menuAppReady` transition.

Replacing an already-ready generation first applies the matching exit and
remote-safety effects, binds the replacement to the resulting role epoch, and
requires fresh ready; it does not request a redundant process start because the
replacement candidate already exists. Exact active-generation termination
applies exit before requesting exactly one matching Agent or menu recovery
effect. Recovery completion, not-completion, and outcome-unknown remain
distinct. Stale generations cannot make a role ready, terminate current
authority, or request recovery. Observation operations serialize across every
suspended lifecycle and process-start call.

Primary ingress is enabled exactly when the reducer says Observe is available.
Disable, logout, and Agent loss therefore deny newly accepted connections after
closing the current one; a listener callback cannot reopen service until a
valid lifecycle transition restores Agent readiness.

## Timing

The host adapter supplies monotonic time. Authentication must complete before
the exact 10-second deadline measured from accepted-connection creation. Once
ready, 45 seconds without valid authenticated inbound traffic closes the
session at the exact boundary. Wall time is diagnostic only and must stay in
the protocol safe-integer range. A decreasing monotonic observation is an
invalid clock and closes the owner.

### Authenticated keepalive

After authentication, the client sends `keepalive.ping` when the primary
connection has carried no authenticated inbound or outbound application frame
for 15 seconds. The body is the closed empty object. The host revalidates the
authenticated principal, admits the ping message ID through the connection
replay window, records authenticated inbound traffic, and returns exactly one
`keepalive.pong` with an empty body correlated to that ping. Keepalive does not
enter an Observe, Act, or Control lane and grants no authority.

The client permits at most one outstanding ping. A pong is accepted only on
the same primary connection, with a fresh message ID and correlation equal to
that outstanding ping. Other authenticated traffic may postpone a ping but
does not satisfy an already-outstanding ping. A missing pong after 15 seconds,
an unexpected pong, a duplicate, a wrong correlation, or a malformed body
closes only that primary connection. The existing reconnect owner may then
construct a fresh authenticated primary; no command, approval, Interactive
role credential, input event, or media record is replayed across replacement.

## Ready command admission

Before every ready command, the authentication authority re-reads durable
device state. Device ID, client ID, active state, authorization epoch, grant
revision, and policy revision must still equal the established principal.
Suspend, revoke, grant replacement, reviewed resume, or policy revision change
therefore closes the session before status disclosure or operation dispatch.

The release Agent does not accept a preconstructed status provider. Its
startup root fixes the status authority to the durable ready host ID used by
the listener, authentication, pairing, and session description, and lazily
bootstraps the revision sequence from the same private `SQLiteSecurityStore`.
The product target supplies only the macOS system sampler, wall clock, initial
generation seed, and bounded freshness. Raw status injection remains a
package/test seam. A status snapshot with another host identity therefore
cannot enter a release primary session.

The owner admits only these original request kinds:

- `status.snapshot.request` to the host status authority and wire mapper;
- `capability.registry.request` to the privacy-limited granted-capability dispatcher;
- `operation.invoke`, `operation.approve`, `operation.status.request`, and
  `operation.cancel` to the authenticated operation dispatcher.

Every admitted message ID enters the connection replay window before authority
work. The operation context is constructed only by the owner from its durable
principal, authentication-issued connection ID, current host state, and host
clocks. The operation startup-reconciliation gate remains inside the operation
coordinator and cannot be bypassed by session composition.

`session.describe.features` is not the message-kind registry and does not grant
operations. v0.1 continues to advertise only `status.snapshot`; operation
availability is determined by the authenticated capability-registry
response plus the device's durable grants. Supporting the closed operation
messages in this owner does not advertise or grant any capability by itself.

## Server failures

### Bounded Act execution without blocking the primary

The platform frame pump serializes authentication and ordinary command handling.
After authentication, `operation.invoke` and `operation.approve` response work
may overlap, because their provider execution can remain pending. At most 31
such handlers are retained; one additional ordinary handler can process status,
cancellation, heartbeat, or other traffic. A further execution request closes
the connection rather than allocating an unbounded queue. Each handler still
passes the same semantic authentication, replay, admission, and durable claim
checks. This scheduling rule changes no wire or cryptographic inputs.

Responses correlate to requests and need not complete in request order. A client
must observe an operation as admitted/running before relying on a later cancel
to target it; transport send order alone does not prove durable admission.
Concurrent exact invokes still use the single durable execution claim. Repeated
cancellation does not run the provider cancellation hook again.

Only one socket read or frame-chunk admission loop is active at a time. Writes
remain serialized. A closed pump cancels its retained response tasks and drops
late results; it never writes a success response after teardown. Task cancellation
is not proof of provider cancellation or of absence of an effect. Semantic
revalidation must recheck the current ready phase/connection after suspension,
and liveness observations must not regress when handlers finish revalidation
out of order. Authentication remains sequential and wrong-phase traffic closes.

The indexed `host-primary-act-concurrency-v0.1.json` fixture records this contract.

Status response timestamps are sampled after asynchronous status collection and
sequence commit finish, not from the request-arrival context. The response must
not predate its observation. A backwards or invalid response clock follows the
same provider-unavailable path below; client freshness checks remain unchanged.
This preserves the existing status-snapshot fixture and freshness contract.

A host status sampling or durable sequence-commit failure emits no fabricated
snapshot and does not classify the authenticated peer as a protocol violator.
It returns the correlated registered `provider.unavailable` error with
`retry: backoff`; the primary session stays ready and any independently active
Act or Control authority remains intact. Operation domain failures are converted
by the operation dispatcher to the closed safe error body. Protocol,
authentication, authorization, timing, and replay failures are terminal for
this primary session.

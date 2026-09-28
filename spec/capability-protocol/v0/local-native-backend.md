# Local managed native backend v0.1

The authenticated Agent-to-menu connection accepts
`runtime.interactive.native.backend` and replies with
`runtime.interactive.native.backend.ack`. Both use canonical bounded JSON
(4096 bytes), applyInteractiveSurface and the existing generation/endpoint token,
single-flight gate, deadlines and malformed-traffic cleanup. Permanent identity,
Keychain, signing and capture/TCC admission gates are unchanged.

The closed operations are prepare, activate, health, present and retire. Every command
has its own correlation ID, an inert backend instance ID, enrollment operation ID
and immutable scope. Scope binds the trusted primary host/pin/client/connection,
epoch/grant/policy, original Control install generation/deadline, opaque selected
display, acknowledged surface/revisions/dimensions, visible menu generation/revision
and registered session public key. It carries no physical display ID, private key,
path, arbitrary URL, content, input, audio or diagnostic. Only prepare carries
canonical padded base64 complete public client DER (1..4096 bytes); the local
4096-byte envelope can reject larger otherwise remote-valid material.

Scope requires `logicalWidthPoints`, `logicalHeightPoints` and `rotation` copied
from the acknowledged local runtime snapshot. Logical dimensions are positive
UInt32 values; rotation is closed to 0, 90, 180 or 270. Missing/malformed fields
fail closed. Every menu snapshot match includes these fields; encoded pixels
cannot replace logical Mac points. This does not alter the native enrollment
signature transcript or registered-key proof.

Before constructing the inert backend, the menu measures the selected physical
display locally. For the initial unrotated Desktop path, its current logical
bounds must match scope, rotation must be zero, and capture-mode pixel dimensions
must be valid (1..32768) and come from the current display mode. There is no
logical-size or encoded-size fallback for missing capture-mode metadata. The
menu retains the resulting source-content geometry with the exact backend and
passes it to the inert factory. It rechecks physical mapping and that geometry
around preparation/activation suspensions and during its existing watchdog.
Changed or unavailable capture geometry revokes the permit and drains the
backend; a late factory result is retired before any credential preparation.
Capture geometry remains menu-local; it is neither a client guess nor clean
aperture proof and does not release the native input pause.

Prepare reserves the sole operation before awaiting runtime, display resolution,
inert factory or public certificate preparation. The menu independently joins
scope to its atomic acknowledged Desktop snapshot and resolves the opaque
selected display locally before and after suspensions. Short lease renewal can
change only lease expiry; it cannot extend the original session deadline. The
menu runtime also latches a native-presentation input pause under that exact
acknowledged Desktop fence before resolving the display or awaiting the inert
factory. It releases held input before preparation proceeds. Release failure
invokes full safety teardown; no backend may be created on that path. Exact
replay of the same fence does not repeat input release. While paused, no input
payload is posted, including reset. Short lease renewal preserves the pause.
Native preparation, activation, health, certificate receipt, legacy frame
acknowledgement and backend retirement cannot clear it or restore legacy input.
Only fresh Control installation currently clears it: native presentation
acknowledgement is not yet admitted by this profile.

The factory receives a menu-local physical ID and a revocable local process permit.
Preparation may generate private owned host credentials but cannot start listeners,
register a client or capture. A late inert factory result is retired and joined.

The Agent coordinator performs the existing golden-vector attestation verification
against both complete DER hashes and the registered primary session key. Only its
successful proof transition requests activate. The menu accepts activate once for
the exact prepared operation/scope and rechecks current acknowledged Control
before and after startup. No new signing, approval or pairing mechanism is added.
Success returns only the enrolled port base. Health returns only current boolean
health. Prepared reply returns only the complete public host DER.

Stop, surface/display change, lease/session expiry, Agent loss, generation loss
or failure revokes the local permit before suspending, cancels pending work,
joins preparation/startup and backend retirement, then admits a replacement.
A 50 ms menu watchdog rechecks runtime and physical display while an operation
exists. The original-deadline/parent-death process supervisor remains required.
Retire is idempotent and exact; stale retire cannot touch a replacement backend.
Retired instance IDs are bounded tombstones; unknown or reused operations fail
closed. A retirement reply acknowledges joined cleanup, never grants authority.
Malformed/cross-operation receipts cannot publish a certificate or port.

The managed profile disables native pairing, resume, application assets, Web UI,
plaintext HTTP, input/audio/UPnP and retains sole Desktop. Development host adapters
remain under Experiments and are not linked into permanent release targets.
The manifest-indexed transport/admission fixture is the sole authoritative index.

Active health receipts may include `captureEvidence` only after the menu joins a
fresh actual sample observation to the exact active backend/operation and its
retained capture geometry. The receipt remains bound to command/backend/operation
IDs. The Agent also checks operation ID, encoded dimensions, report shape and
freshness. Missing sample evidence is permitted during startup; it never grants
input. Capture evidence is absent for prepare, activate and retire or inactive
health. No physical display identifier crosses XPC. The authoritative evidence
shape and rejection cases are indexed in `valid/native-backend-capture-evidence.json`.

Concurrent read-only health observations for the same exact prepared operation
may join one in-flight authenticated local health command. Each caller rechecks
retirement, operation and scope after the shared result. Health must not overlap
preparation/activation commands or reuse a completed receipt as a cache. Retirement
fences callers before cancelling/joining the shared read and its underlying command;
a late active/sample result cannot escape the retired proxy. This prevents a
watchdog health read from interpreting another current health read as backend loss.

## Correlated presentation installation

Only present carries a positive JSON-safe nativeGeneration and a presentationID
(the enrolled primary challenge message ID). Both fields are required for present
and forbidden on other operations. Its receipt echoes both and requires active
true, inputAdmitted true and fresh operation/geometry-bound capture evidence.
Non-present receipts forbid these admission fields. The existing correlation,
backend, operation and scope checks still apply. No input payload crosses this API.

The menu requires its exact active backend, current runtime snapshot and scope,
fresh actual sample and a backend explicitly supporting atomic posting. It binds
one renderer generation/challenge ID per backend. The first admitted presentation
installs the backend's local posting authorization into the exact paused runtime
fence. Repeated admission for the same generation/challenge rechecks current state
and sample without replacing the primitive. A revoked installed primitive cannot
be revived. Retirement revokes the primitive and process permit before drain.

The Agent joins any in-flight read-only health operation before presentation.
Health readers during installation wait for that transition and then make a fresh
health read; they must not report false activity merely because installation holds
the single-flight local-command slot. Cancellation and retirement fence all joins.

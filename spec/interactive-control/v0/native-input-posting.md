# Native input posting boundary v0.1

Status: normative local posting primitive. No input admission or new remote
message is enabled by constructing this primitive.

A trusted native runtime composition can retain a posting authorization tied to
its exact existing Control binding and immutable native surface. An input
payload must match the session, authorization epoch, surface and coordinate
revisions. The original Control deadline and the shorter current runtime lease
deadline remain independent bounds in the host's monotonic clock domain.

The platform adapter completes any asynchronous selected-window activation before
invoking this authorization. Its trusted backend executor must revalidate the
current backend, original operation, capture geometry and revocable process/input
permit, then execute one bounded synchronous input batch while that permit is
held. Neither a prior watchdog check nor a check before activation suffices.

The primitive rechecks exact payload scope and both deadlines at the synchronous
posting callback, fences cancellation before a batch starts, and admits that
callback only once. The callback cannot escape after the executor returns.
An executor returning without posting or suppressing a posting failure cannot
report success. A batch already synchronously admitted before cancellation may
finish; teardown must release held input after it. No callback overlap or deferred
posting is allowed.

Default/unsupported input adapters refuse this primitive. Legacy posting remains
under its existing Control authority. The native runtime pause stays latched until
a separate, specified presentation admission installs the exact current backend
executor. Native input remains disabled at this primitive-only checkpoint.

The sole fixture manifest indexes `valid/native-input-posting.json`. Application
authentication, pairing, approvals, operation signatures and their golden vectors
are unchanged. This primitive is local platform execution, not a new grant.

## Serialized runtime installation

A trusted local composition may install the posting primitive only into its exact
paused Desktop runtime fence, after presentation admission. Installation joins the
current acknowledged snapshot, host, original Control generation and deadline,
session/epoch, surface/revisions and encoded dimensions. It is single use for that
pause: replacing an installed primitive is refused. This is an internal API, not a
new remote request or grant. No current release composition calls it.

Input preserves existing class, sequence, focus and lease checks. Native input
always calls the native adapter API with the current short lease deadline and
never falls back to legacy posting. Renewal retains the same primitive and original
Control bound. Re-pause, focus/surface transition and termination revoke the shared
primitive before releasing held input or starting cleanup. Revocation also fences
copies retained by an in-flight executor; a synchronously admitted bounded batch
may finish before revocation returns.

An exact current-surface reset while native input is paused and the posting
primitive is absent or revoked consumes only ordered release state. It must
validate the current lease, epoch, surface, coordinate, focus and sequence, release
held input, and preserve the native pause. Duplicate exact reset is idempotent;
other input or a stale fence cannot post or restore admission. This permits a
second surface choice during native preparation without terminating Control.

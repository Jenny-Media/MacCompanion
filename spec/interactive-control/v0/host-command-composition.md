# Interactive Control host command composition v0.1

Status: normative for the bundle-independent primary-command dispatcher. Durable-store, visible-menu-app IPC, runtime, and OS cryptographic-randomness implementations remain platform composition.

## Inputs and ownership

The authenticated primary-session owner routes only `interactive.session.request` and `interactive.session.approve` and supplies host-owned device/client identity, current device state and revisions, primary connection ID, host ID/fingerprint, host state, and wall/monotonic time. No field in request JSON may replace those facts.

The lower-level dispatcher receives three injected authorities:

- an admission reader that conservatively joins the current durable device/grant/approval-key record with visible-menu-app availability and its selected display;
- a material generator backed by an OS cryptographic RNG in production;
- a runtime owner that atomically installs or terminates the session state machine and both one-time role-channel authorities.

The release Agent does not accept a preconstructed dispatcher or admission
reader. Its startup-reconciled product root constructs the admission reader
from the exact `SQLiteSecurityStore` that backs application authentication,
pairing, grants, operations, and audit-self, and supplies the same root's
required `BoundedInteractiveAuditWriterV0`. The product target may inject only
the authenticated visible-menu-app snapshot source, OS-random material
generator, runtime owner, and optional surface executor. Lower injectable
dispatcher construction remains a package/test seam and is not a release
composition path.

Consequently, a release primary session cannot combine one durable device or
grant authority with another Interactive admission store, and it cannot omit
required Interactive approval audit. The runtime owner remains a platform seam
because atomic XPC installation and final state revalidation are not yet
bundle-independent; signed-target evidence must still prove that it revalidates
against the same durable/visible authorities before publishing runtime state.

The production material generator uses Security.framework system randomness for approval IDs, challenges, session/channel IDs, and distinct role credentials. The production pre-admission reader brackets one atomic SQLite device/grant snapshot with identical visible-menu-app generation/revision snapshots; a changing IPC-visible state yields no admission. Neither replaces the runtime installer's final revalidation.

The successful admission snapshot retains that exact nonzero visible-menu-app
generation and publication revision. Runtime installation accepts no receipt
unless it comes from the same generation, has a positive activity revision and
matches the exact current install command, lease, session and display. Activity
and publication revisions are independent counters; numeric comparison between
them cannot establish freshness. The complete admission publication is still
revalidated unchanged around installation, and a different process generation
or stale command binding remains denied.

The v0.1 Interactive Control capability ID is exactly `maccompanion.interactive.control`. A request is eligible only for an `activeGranted` device with that exact grant, exact authorization/grant/policy revisions, an active console session, a visible available menu app, and a selected display. Failure returns only the closed `policy.denied` error.

## Request and proof flow

At most one transition, pending approval, or active session exists for the dispatcher. A valid Desktop request creates a random approval ID and 32-byte challenge, binds all authenticated and admission facts into `InteractiveApprovalAuthority`, stores the challenge response ID, and returns one correlated `interactive.session.approvalRequired` response with an independently authoritative 60-second monotonic deadline.

Approval accepts only the exact challenge correlation, approval ID, primary connection, identity, host pin, revisions, and a second eligible admission snapshot with the same selected display. The raw approval signature is then consumed once by `InteractiveSessionBootstrapAuthority`, which creates the starting session and distinct input/media credential authorities as one in-memory transition.

The bootstrap retains the exact `InteractiveApprovalEffects` that were bound
into the verified phone signature. Initial runtime-lease construction must map
only those retained effects to interaction classes; it may neither infer a
default Control set nor reconstruct authority from an unverified request.

Before any `interactive.session.accepted` bytes are disclosed, the runtime installer receives the complete bootstrap plus the required command/admission snapshot. Inside the same serialized boundary that publishes the starting session, it must re-read durable device, exact grant, approval key, revisions, visible-menu-app availability, and selected display and require exact equality. The earlier dispatcher snapshot is not final authority. A failed installation publishes no accepted response and must install no partial runtime.

## Concurrency and teardown

Every asynchronous admission, material, and runtime call is guarded by a transition reservation. Actor reentrancy cannot admit a second request or proof. After each suspension point, the dispatcher verifies that the same primary transition still owns the result.

Primary disconnect clears pending approval immediately. If disconnect races runtime installation, the dispatcher reserves the active identity before installation, orders idempotent runtime termination, and performs a compensating termination after installation returns if ownership was lost. The primary-session owner awaits exactly one dispatcher teardown notification before releasing the connection. The runtime termination operation itself is idempotent and closes channels, destroys unused credentials, releases input, stops capture, blanks retained video, and publishes the terminal session transition.

Correlation, approval-ID, signature, replay, or primary-binding failures create no session and return only a closed authentication error. Concurrent-session pressure returns a bounded backoff error. Internal runtime failure returns a closed provider-unavailable error without disclosing platform details.

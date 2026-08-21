# Authenticated operation command orchestration v0.1

Status: normative bundle-independent host composition. It binds the closed
operation messages to the existing admission, approval, persistence, and
provider-execution authorities; it does not open a socket or grant a native
capability by itself.

## Pre-ingress gate

The host runs `provider-execution.md` startup reconciliation successfully
before accepting any operation command. Every command handler checks the same
completed gate. A missing or failed reconciliation returns a host-owned
storage/unavailable error and performs no admission, provider lookup, status
disclosure, or cancellation.

## Authenticated context

Each command is accompanied by host-owned connection context, never client
body fields: the authenticated device principal, exact 16-byte primary
connection ID, current host state, wall time, monotonic time, and negotiated
version. Status and cancellation lookups require both the durable device ID and
client ID to match the principal. A missing or foreign operation is reported
through the same opaque not-found path.

## Invoke

The coordinator canonicalizes the native parameter object and calls the
operation admission authority. Elevated effects return the exact existing or
new `operation.approvalRequired` challenge. A durable terminal replay returns
its status without provider invocation. A queued admission resolves only the
descriptor-bound provider identity and enters the execution authority. A
missing provider terminally fails the queued record as
`provider.unavailable`; arbitrary resolver text is not retained.

Concurrent identical invokes cannot execute twice. The first committed
execution claim wins. A later handler observing `running` or
`cancelRequested` returns current durable status rather than treating the race
as a protocol fault. A conflicting operation digest remains
`protocol.operationIDConflict`.

## Approval completion

Pending approval memory retains the already validated canonical parameter bytes
alongside the digest-bound durable candidate. This is boot-scoped and bounded;
it is destroyed on every completion attempt, expiry, invalidation, or restart.
After a valid proof and atomic durable admission, the coordinator resolves the
same descriptor-bound provider and executes with those exact canonical bytes.
The client does not resend or reinterpret parameters after user presence.

## Status and cancellation

`operation.status.request` returns a closed status body for an owned durable
record. `operation.cancel` delegates queued/running transitions to the execution
authority using the exact bound provider. A missing provider can cancel queued
work without invoking anything; running work without its bound provider cannot
claim cancellation success and returns a stable unavailable error.

Every status response contains all nullable fields. Live canonical result bytes
are included only in the immediate successful execution response. Durable
replay never reconstructs or fabricates a result and therefore returns
`result: null`.

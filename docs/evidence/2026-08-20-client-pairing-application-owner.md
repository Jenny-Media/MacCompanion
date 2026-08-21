# Client pairing application owner evidence

Date: 2026-08-20

## Claim

`CompanionClientApp` now composes the accepted QR handoff through prepared
session/approval keys, one immutable connection request, QR-pinned TLS evidence,
the normative transcript proof, verified SAS presentation, final monitor-only
completion, and atomic durable publication. UI receives only
`PairingClientPresentation` snapshots; the owner retains the QR secret,
connection, session, opaque key references, and unpublished host state.

The connection request fixes the pairing ID, QR fingerprint, route candidates,
and QR wall expiry. One returned connection object owns TCP, TLS evidence,
framed traffic, and closure. All two sends and three receives carry the exact
single monotonic pairing deadline, so a future platform adapter must enforce a
byte-independent timeout rather than refreshing it on traffic.

Every asynchronous return is revision fenced. Cancellation while waiting for
local Mac approval closes the exact connection and session, discards prepared
keys, and prevents a delayed completion from publishing. Once the atomic client
record commit begins, cancellation is deliberately deferred: the operation
converges to `paired` after success or a closed storage failure, avoiding a UI
reset that contradicts a durable commit. Raw provider errors map only to the
closed presentation failure taxonomy.

## Verification

Six tests drive the real client pairing/session, security transcript, SAS,
presentation, identity-publication, and durable-record types through an
in-memory server connection. They prove durable-before-paired success, exact
pin/route/expiry request binding, one unchanged deadline on all framed I/O,
pending-completion cancellation, pin mismatch, sanitized connection failure,
storage failure with prepared-key discard, and cancellation deferral during a
suspended atomic commit. The hardened unsigned gate passes 824 Swift tests.

## Boundary

The connection, clock, randomness, custody, and persistence implementations are
injected. This is not live Network.framework routing, a physical deadline,
Keychain/Secure Enclave execution, Data Protection inspection, camera UI,
background behavior, local Mac approval UI, or physical QR exchange. The final
iOS target must supply those adapters without weakening this owner or moving
authority into SwiftUI.

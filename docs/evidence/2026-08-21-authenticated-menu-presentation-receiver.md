# Authenticated menu presentation receiver

Date: 2026-08-21

Status: package construction complete; permanent runtime remains inert

## Result

`MacLocalXPCClientV1` now installs an incoming-message handler before activating
its XPC session. The public initializer supplies no presentation surfaces and
therefore remains fail-closed. A package-only initializer may inject only the
pairing-review and host-identity-recovery surfaces plus a wall clock; it does
not accept a raw session, caller role, authorization flag, arbitrary method, or
untyped payload.

After the exact Agent hello and menu-readiness acknowledgement, the client
synchronously copies one of the five closed request values and repeats the
Agent-to-menu method authorization check. The production
`MacLocalXPCMenuPresentationReceiverGenerationV1` then retains the borrowed XPC
request exactly once, admits it to the shared one-active-plus-seven-queued FIFO,
and serializes pairing and recovery mutations in exact arrival order.

At the FIFO head, canonical typed decoding rejects malformed, open,
noncanonical, oversized, or cross-kind payloads. A new recovery review must
satisfy `createdAt <= now < expiresAt`; exact already-visible replay is
idempotent even after expiry, while durable resume deliberately has no new wall
clock gate. Same-ID changed bytes, recovery review/resume substitution, and a
different visible presentation in the same family are terminal. Exact
withdrawal is idempotent and cannot remove another identifier.

The receiver fixes its absolute two-second monotonic deadline before launching
the asynchronous surface effect. It sends the operation-specific
acknowledgement only after the exact immutable state has been retained and the
exact client generation, authentication, readiness, receiver owner, and live
session have been revalidated. The initial implementation intentionally emits
no recoverable presentation rejection: surface throw, cancellation, timeout,
queue overflow, reply failure, malformed traffic, or ambiguous withdrawal all
terminally invalidate the generation without an application-error reply.

Invalidation first fences the receiver, cancels deadlines and tasks, and
releases every retained request. Its awaitable retirement barrier waits for any
surface operation that may ignore cancellation and then withdraws the union of
the generation's retained and possibly retained exact IDs. Queued mutations
never reach a surface. The same client cannot restart presentation delivery
until this cleanup task completes, and late callbacks cannot reply through a
retired or replacement receiver generation.

## Verification

The focused `CompanionLocalXPCPlatform` suite passes 78 tests. Fourteen receiver
tests cover all five mutations, canonical decoding, exact replay, same-ID byte
changes, mode substitution, fresh recovery bounds, expired exact replay,
durable resume after expiry, absent withdrawal, exact retirement planning, and
the awaitable cleanup barrier. They also directly drive the exact generic owner
used by production through premature, unauthorized, and malformed admission;
retain-present-acknowledge-release ordering; cross-family FIFO order; eight
admitted plus terminal ninth overflow; queued-work suppression; deterministic
timeout; cancellation-ignoring late completion; ambiguous throw after possible
retention; reply failure; exactly-once request release; and exact-ID cleanup.

The final repository-wide gate passes across 911 repository files, 1,066
historical blob paths, 298 Swift source files, 64 indexed fixtures, 14 privacy
source records, every supported cross-build, and all platform probes. A fresh
`swift test list` reports 1,284 unique package tests with zero duplicate names.
A fresh unsigned Xcode 27 beta build reports `BUILD SUCCEEDED` and contains the
Mac app executable, embedded Agent executable, LaunchAgent plist, and privacy
manifest. Independent protocol, Apple-platform, and delivery re-audits report
no remaining P1 or P2 findings.

## Explicit non-claims

This slice does not compose the menu receiver with the Agent sender, surface
router, or prepared Agent product. It does not change the permanent Agent's
authentication-only profile, start a permanent target, register or sign an App
ID, use a managed entitlement, or prove a signed live two-process exchange.
`Apps/`, `project.yml`, `Package.swift`, signing settings, entitlements, and
release identities are unchanged.

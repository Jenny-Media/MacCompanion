# Exact authenticated menu-presentation envelopes

Date: 2026-08-21

Status: package construction complete; runtime composition not claimed

## Scope

The macOS 26 C bridge now has five operation-specific request senders and
parsers for pairing-review publish/withdraw and host-recovery review,
resume, and withdraw. Each request requires the exact committed kind, signed
Int64 version 1, closed members, and either 1...4,096 bytes of XPC data or one
exact 16-byte nonzero XPC UUID. There is no generic kind-string sender.

Every operation has one exact acknowledgement. Only the three publishes admit
their matching `presentationRejected` response. The closed reply classifier
maps acknowledgement, recoverable rejection, and malformed-or-transport
failure without returning a raw reply or diagnostic text. Its C self-test
covers all five acknowledgement mappings, all three rejection mappings,
cross-kind substitution, open dictionaries, alternate scalar types, null
replies, forbidden withdrawal errors, payload bounds, and 15/16/17-byte plus
zero UUID cases.

`MacLocalXPCMenuPresentationWireV1` immediately copies the C parser's borrowed
payload or UUID bytes into a closed Swift request value. Focused tests mutate
the source buffers after return and preserve the copied value for all five
request kinds. The authorization method is derived only from the closed enum.

## Contract decisions

The normative profile now fixes one active plus seven queued requests in one
cross-family FIFO, a two-second receiver-operation deadline, a three-second
sender-reply deadline, typed `rejectedWithoutRetainedState` proof, exact
ready-generation endpoint issuance, cancellation-before-send fencing, and the
fresh-recovery clock interval `createdAt <= now < expiresAt`. These decisions
precede the stateful endpoint and receiver implementation.

## Verification

The focused `CompanionIPC` suite passes 57 tests. The focused
`CompanionLocalXPCPlatform` suite passes 48 tests, including the expanded C
self-test and four Swift wire-boundary tests. The fixture validator accepts
all 64 indexed fixtures. The final repository-wide gate for this checkpoint is
green across 904 repository files, 295 Swift source files, 1,254 uniquely
listed package tests with no duplicate names, all 8 platform probes, 14 privacy
source records, and every cross-build. A fresh unsigned Xcode build also
constructs the app and embedded Agent successfully. The independent protocol,
platform, and delivery reviews are recorded separately from these local gates.

## Explicit non-claims

This checkpoint does not issue a sender endpoint from an authenticated ready
peer, enqueue or transmit a production presentation request, install a menu
receiver, retain an asynchronous incoming request, activate a presentation
server profile, compose either permanent target, or prove a signed two-process
round trip. Those remain the next package-only slices and the later external
runtime gate.

## Later checkpoint

The subsequent [authenticated current-ready sender checkpoint](2026-08-21-authenticated-menu-presentation-sender.md)
implements the sender endpoint and production FIFO while preserving this
checkpoint's menu-receiver, product-composition, permanent-target, and signed
runtime non-claims.

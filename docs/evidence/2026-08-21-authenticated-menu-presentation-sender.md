# Authenticated current-ready menu-presentation sender

Date: 2026-08-21

Status: package construction complete; permanent runtime remains inert

## Result

`MacLocalXPCServerV1` now has one explicit presentation profile used only by package construction.
Only the exact current authenticated peer can publish readiness into its
issuance gate, and only that gate can create and cache one private nonzero
endpoint token. The resulting actor is an opaque pairing/recovery presentation
capability: it weakly references a narrow sender authority and never owns or
returns the raw XPC session.

All five surface calls encode through the committed bounded canonical codec and
enter one production cross-family FIFO. The same extracted state machine used
by the server fixes the limit at one active plus seven queued requests, strict
arrival order, monotonic local operation IDs, queued cancellation without send,
terminal active cancellation, terminal ninth-request overflow, and terminal
operation-ID exhaustion. Operation IDs, generation values, and endpoint tokens
remain local and never enter a message.

Immediately before every C send, the serialized server rechecks listener run,
retained peer identity, exact current generation, readiness, explicit profile,
private endpoint token, method authorization, FIFO head, and task-cancellation
state. The cancellation marker is locked across the asynchronous-send call, so
no send can begin after its pre-send cancellation marker. Exact
acknowledgements advance the FIFO; publish-only
`rejectedWithoutRetainedState` is recoverable. Send failure, malformed reply,
withdrawal rejection, active cancellation, and the three-second monotonic
reply deadline terminally drain the exact generation. Late callbacks cannot
match a fenced or replacement state machine.

The peer owner now has a separate idempotent post-authentication traffic fence.
It synchronously blocks later menu messages, status admission/replies, and
presentation sends, cancels an active status read, drains presentation
continuations exactly once, and only then claims the single XPC-session cancel.
This closes the unsafe interval in which queued work could otherwise reply on a
cancelled session.

The endpoint latches terminal transport failure before its router fence may
exist, requests that fence exactly once after installation, and treats loss of
its weak sender as a new terminal failure. Owner-driven retirement is
idempotent and never recursively requests the router fence.

## Verification

The focused `CompanionLocalXPCPlatform` suite passes 64 tests. Sixteen sender
tests cover exact readiness and cached opaque issuance, the explicit inert
versus presentation profiles, all five encoded requests, recoverable publish
rejection, pre-send cancellation, weak-sender loss before and after fence
installation, transport failure and timeout latching, idempotent owner
retirement, production FIFO order, eight-plus-ninth overflow, queued versus
active cancellation, operation exhaustion, stale/late callback rejection, and
the peer-wide fence-before-one-cancel invariant. The prior C self-test and
production-builder traversal continue to exercise all five exact C builders,
acknowledgements, publish rejections, malformed replies, bounds, and UUID
shapes.

The final repository-wide gate passes across 908 repository files, 1,057
historical blob paths, 297 Swift source files, 64 indexed fixtures, 14 privacy
source records, all cross-builds and platform probes, and 1,270 uniquely listed
package tests with zero duplicate names. A fresh unsigned Xcode 27 beta build
also completes with `BUILD SUCCEEDED` and contains the Mac app plus its embedded
Agent executable and LaunchAgent plist. The independent protocol, platform,
and delivery re-audits report no remaining P1 or P2 findings.

## Explicit non-claims

This slice does not install the menu incoming-message receiver, retain or reply
to an incoming asynchronous presentation request, bind the sender/router into
the prepared Agent product, change the permanent Agent profile, start a
permanent target, or prove a signed two-process exchange. `Apps/`,
`project.yml`, `Package.swift`, signing settings, entitlements, and release
identities are unchanged. The next package-only slice is the bounded menu
receiver and its awaitable retirement barrier.

## Later checkpoint

The subsequent [authenticated menu presentation receiver](2026-08-21-authenticated-menu-presentation-receiver.md)
now completes that package-only receiving and retirement slice. The historical
non-claims above remain accurate for this sender checkpoint; sender/receiver
product composition and signed runtime evidence still follow.

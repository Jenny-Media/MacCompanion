# Multi-device application-primary isolation checkpoint

Date: 2026-08-29

## Physical finding

The first physical acceptance attempt for development candidate source
`69767e73e8b228675c27d069d702e804cc8fedb8` retained the existing iPhone and
iPad pairings and launched the exact signed iOS candidate on both devices. The
iPhone initially authenticated normally. After the iPad also requested
Reconnect, both clients alternated rapidly between ready and reconnect UI.

Content-free Agent unified logs established the failure mechanism. Each
verified `applicationPrimary` classification immediately started a primary
replacement with a prior transport present. Replacement locally cancelled the
other client's primary connection; that client reconnected and replaced the
new owner in turn. This repeated many times per second. No Wi-Fi, pin,
signature, pairing, grant, or Interactive-role failure preceded the loop.

Physical acceptance stopped at this point. No Control session was started and
the flapping result is not acceptance evidence.

## Root cause

The product decision and Stage 2 checklist permit up to eight retained paired
clients and require a second client to remain independently connected while a
single global Control session is arbitrated. Two older construction boundaries
still implemented the historical one-Mac/one-phone assumption:

1. `AgentPrimarySessionAuthorityV1` stored one semantic primary session and
   transport and closed them whenever another primary opened.
2. `AgentNetworkListenerIngressHandoffV2` stored one active primary connection
   and cancelled it after activating a later primary.

`AuthenticatedInteractiveWireDispatchingV0.primarySessionClosed()` was also a
global teardown notification. Simply retaining multiple transports would
therefore have allowed an unrelated client disconnect to terminate another
device's pending or active Control session.

## Repair

- The Agent semantic authority now retains at most eight exact primary
  session/transport entries. A ninth open fails closed. Exact connection
  termination removes and closes only its own entry; lifecycle and security
  fences still close the complete set.
- The listener handoff now retains multiple active primary generations and
  resolves unsolicited authenticated events by exact server-issued primary
  connection ID. Pairing and the single input/media role pair remain
  independently owned.
- Transport terminal callbacks retire the matching semantic entry, including
  its capacity slot, so repeated reconnects cannot accumulate closed sessions.
- Authenticated primary closure carries its exact connection ID into the
  Interactive dispatcher. Unrelated closure leaves peer pending/active Control
  authority unchanged. Global local/lifecycle teardown remains explicit and
  still ends Control.
- The normative primary-session, listener-ingress, and local-status profiles
  now describe the retained-client model. Local status continues to expose one
  active Remote Control count, not application-primary connection inventory.

## Verification

Focused Swift suites pass for listener handoff, Agent primary authority,
authenticated primary sessions, Interactive dispatch, and network pump
teardown. New regressions prove:

- two valid application-primary connections remain active without either
  cancelling the other;
- authenticated events select either retained connection by exact ID;
- ending one primary leaves the peer event sink active;
- an unrelated primary close leaves another device's pending and active
  Control authority unchanged;
- eight semantic primary sessions are admitted, the ninth is rejected, and
  exact teardown frees one reusable slot; and
- a pre-authentication transport failure cannot tear down Interactive authority
  it never owned.

The complete repository validation passes under the installed Xcode 27 beta,
including 78 indexed fixtures, 1,334 repository files, every Swift package and
test target, the signed Agent/XPC and Live Control labs, Simulator checks, and
platform probes.

## Remaining boundary

This checkpoint repairs and validates source; it does not inherit the failed
candidate's physical result. A new exact signed Mac/Agent/iOS candidate must be
built from the commit containing this checkpoint, installed on both retained
devices, and demonstrate stable simultaneous readiness plus one-active-Control
denial before physical acceptance can resume. Stable Xcode, distribution,
notarization, seven-day soak, and Stage 3 gates remain unchanged.

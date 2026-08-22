# Disabled-Agent bootstrap protocol

Date: 2026-08-22

## Claim

Mac Companion now has a frozen, bundle-independent local-IPC contract for the
otherwise unreachable first-enable transition. An explicitly initiated setup
may register only the inert Agent before durable enabled intent exists, solely
to reach its same-team exact-identifier `authenticationOnly` endpoint.
Registration is not readiness and grants no remote authority.

After the closed hello, that profile admits only two menu-to-Agent methods:

1. `readRemoteAccessBootstrap` returns one content-free, five-minute offer
   bound to the current disabled durable-intent revision; and
2. `enableRemoteAccess` accepts one command containing the complete offer, a
   fresh command ID, the closed `agentRemoteAccessV1` consent profile, and a
   confirmation time inside the offer window.

The success receipt binds the command, offer, exact successor intent revision,
and completion time. It proves only durable enabled intent. The Agent must
retire the authentication-only service and restart through the complete
required-audit readiness/status product before the UI may claim availability.

## Closed safety boundary

- Revision zero means an absent durable record; stored revisions are positive
  safe integers.
- Offers expire after exactly five minutes and are invalidated by revision or
  peer-generation changes.
- The command contains no generic desired-state Boolean and cannot grant
  Observe, Act, Control, pairing, presentation, networking, or a capability.
- Recovery mode rejects both methods without disclosing recovery details.
- The diagnostic CLI, Agent-to-menu endpoint, and same-role connections are
  denied by the closed role/method matrix.
- The visible menu login role remains unregistered until the Agent durably
  acknowledges enabled intent.
- A receipt is not process start, authentication, readiness, status, or remote
  ingress evidence.

## Automated evidence

Five focused message tests prove exact round trips, safe revisions, exact offer
lifetime, half-open confirmation admission, strict successor-revision binding,
command/offer correlation, and unknown/missing-field rejection. The exhaustive
role-matrix test permits both new methods only from authenticated `menuApp` to
`agent`; all other caller/endpoint combinations remain denied.

The focused `CompanionIPCTests` target passes all 63 tests. The complete
repository gate passes with 64 indexed protocol/product fixtures, 938
repository files, 1,180 historical blob paths, 305 production Swift source
files, 1,353 package tests, every supported cross-build, and all 8 platform
probe tests.

## Deliberate limits and next gate

This checkpoint defines messages and authorization only. It does not implement
the XPC envelopes, authentication-only handler, durable offer/command owner,
Agent-only setup registration, menu-role convergence, Agent restart, dashboard
consent UI, or signed runtime exchange. Those pieces must consume this exact
contract and preserve the profile separation before signed acceptance can
proceed.

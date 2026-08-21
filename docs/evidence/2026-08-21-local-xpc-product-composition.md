# Local XPC Agent and dashboard product composition evidence

Date: 2026-08-21

## Outcome

The previously separate complete Agent service root, lifecycle observation
authority, authenticated local-XPC transport, typed status reader, and Mac
dashboard owner now have sealed product compositions. Observe status remains
independent of Remote Control and never carries screen, input, document, or
window-title content.

This is bundle-independent construction evidence. The permanent Agent remains
explicitly `authenticationOnly`, and the permanent Mac app still presents its
truthful unavailable shell. Neither target opts into the new products until the
complete release bootstrap and signed runtime lane can supply their required
authorities.

`CompanionAgentPlatform` remains a macOS-only host-administration product. The
aggregate Swift package also advertises iOS solely for its supported client
products; this evidence does not claim an iOS AgentPlatform build.

## Agent-side product root

`MacLocalXPCAgentProductV1.afterAgentBootstrap` accepts only
`AgentPrimaryServicesV1`. It derives the lifecycle observation root from that
same startup-reconciled service graph and adapts only its issued local-status
read capability. The resulting server always selects the explicit
`menuLifecycleReadinessAndStatus` profile.

The product owns the server and lifecycle event pump together. Authentication,
readiness, invalidation, failure, and shutdown remain ordered. A failed
lifecycle publication cancels only the exact current transport generation.
Shutdown fences event admission, cancels the server, and awaits retirement of
the exact menu lifecycle capability. Weak callback storage prevents the server,
pump, and product from retaining one another indefinitely.

## Menu dashboard product root

`MacLocalXPCDashboardProductV1` owns the menu client and a bounded ordered event
pump. It prepares one dashboard connection token before starting transport,
then drives only the exact authenticated, readiness-acknowledged, typed-status
sequence. A malformed order or changed transport generation cancels the client
and retires the dashboard token.

A valid `sourceUnavailable` response publishes temporary unavailability while
retaining the authenticated generation. Manual retry marks the dashboard
loading and issues one sequential read; a later snapshot must still advance the
diagnostic sequence and preserve wall-clock monotonicity. Transport invalidation
retires the token, so a late response cannot restore availability.

## Verification

Fifteen injected product tests cover:

- exact full-profile Agent construction, ordered readiness, and shutdown;
- current-generation peer cancellation after lifecycle rejection;
- terminal Agent finish fencing before start and across an admitted blocking start;
- typed dashboard status publication and same-generation source recovery;
- retry rejection while a read is outstanding plus reservation before async owner publication;
- premature event and changed-generation fail-closed behavior;
- transport-start failure and terminal restart rejection;
- suspended dashboard start versus finish without post-terminal client activation;
- synchronous overflow admission fencing without processing across a dropped event;
- terminal invalidation retiring retry admission before async owner notification; and
- one replayed finish barrier plus fail-closed owner retirement on product deinitialization.

The existing transport, lifecycle binding, status codec/adapter, and dashboard
owner suites remain the lower-level authority for parser, ownership, timeout,
canonical payload, status monotonicity, and stale-token behavior. The final
repository gate passes across 889 files, 290 Swift source files, 1,207 unique
Swift tests, 8 platform-probe tests, every supported cross-build, and the
permanent-target validators. An unsigned Xcode 27 beta Mac application build
also succeeds. Independent protocol, platform-lifetime, and delivery reviewers
each returned GO after the start/finish, retry, overflow, deinitialization, and
invalidation races were remediated and re-audited. This remains construction
evidence, not a live signed-XPC or release-bootstrap claim.

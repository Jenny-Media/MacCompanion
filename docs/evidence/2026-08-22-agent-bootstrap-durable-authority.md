# Agent bootstrap durable authority

Date: 2026-08-22

## Claim

Mac Companion now has one Agent-owned, bundle-independent authority that turns
the frozen disabled-Agent offer and consent command into an exact durable
enabled-intent receipt. It uses the existing cross-process-locked atomic intent
store and exposes no listener, login-role, process-start, readiness, pairing,
presentation, network, Observe, Act, or Control authority.

## Durable transition

- An absent record is revision zero; an existing record must be disabled and
  below the maximum safe revision before an offer is issued.
- One validated offer is reused for the exact peer generation and expires on
  its half-open five-minute boundary.
- Enablement accepts only the exact embedded offer and a confirmation that is
  not in the future at Agent evaluation time.
- The committed record is exactly the successor revision, enabled state,
  command UUID, and Agent completion time.
- Every write, including one that reports an error after rename, is followed by
  an exact durable read-back. Only byte-equivalent semantic state becomes a
  receipt; conflict or ambiguity is terminal.
- The receipt is reconstructed only from that exact snapshot and validates its
  command ID, offer ID, successor revision, version, and completion time against
  the command. Exact command replay returns the same receipt without a second
  write; changed-command reuse fails closed.

## Reentrancy and generation fence

The authority maintains both a peer-generation high-water mark and monotonic
operation IDs. Every suspension on durable storage is followed by an exact
generation/operation check. A replacement generation clears the old offer and
operation; delayed reads or writes from the retired generation cannot publish
state or terminalize the replacement. Cancellation invalidates only the exact
current generation.

## Deterministic verification

Six focused tests cover absent and existing disabled revisions, one offer per
generation, exact successor persistence, exact replay without a second write,
post-rename error recovery, conflicting read-back rejection, expiry, stale
generation denial, changed-command denial, and a suspended storage read that
returns only after a replacement generation has completed.

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --package-path Packages/MacCompanionKit \
  --filter CompanionAgentPlatformTests
```

Result: all 100 Agent-platform tests passed on Xcode 27 beta.

The complete repository gate also passes with 64 indexed protocol/product
fixtures, 946 repository files, 1,199 historical blob paths, 308 production
Swift source files, 1,367 package tests, every supported cross-build, and all 8
platform-probe tests.

## Non-claims and next gate

This authority is not yet injected into the authentication-only local-XPC
server, retained by the permanent Agent preparation owner, or consumed by the
foreground menu client. It does not register either login role, restart the
Agent, or prove signed readiness. The next checkpoint must bind this authority
to the exact transport handler and retire the authenticated bootstrap service
only after its receipt is sent successfully.

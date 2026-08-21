# Registry publication construction evidence

Date: 2026-08-20

## Claim

The bundle-independent Operations and Agent packages now provide one immutable,
validated capability registry plus live-provider publication. A single actor
atomically replaces that value, rejects incomplete provider sets and generation
collisions, and retains old provider references for commands that already hold
an old snapshot.

Discovery and operation admission read immutable registry snapshots from this
authority instead of owning replaceable copies. The release-path command
composition retains one publication across admission and provider effect and
resolves execution and cancellation providers from it. The required Agent
construction binds local grant review/commit, discovery, operation admission,
execution, required operation audit, and registry-change audit to that shared
mutation authority.

Registry-change detail is attempted only after the authoritative swap and
pending-review invalidation complete. It is a
local-only, Agent-authored, closed succeeded fact whose event UUID is the new
registry generation. A detailed-store fault or acknowledged durable drop does
not roll the publication back and marks the registry audit producer degraded
for local repair status.

## Evidence

- Candidate construction rejects duplicate, missing, extra, and
  identity-mismatched providers before publication.
- Replacement accepts only exact same-generation replay; changed content with
  the same generation is rejected.
- Concurrent readers observe only complete old or complete new publications.
- A retained old snapshot continues to call its old provider while a new
  snapshot resolves the replacement provider.
- One cross-consumer test retires a capability and proves discovery hides it,
  new admission rejects it, queued execution cannot call the retired provider,
  and the durable queued record is not silently retargeted.
- One sequenced-reader test proves a full invoke reads one publication and
  retains it through the provider effect.
- Pending approval cannot cross provider removal, while a running operation
  retains its exact old provider only long enough to route cancellation and
  finish its durable terminal transition.
- Agent tests prove review invalidation and replacement-versus-grant-commit
  exclusion under the same mutation gate, one idempotent post-commit audit row,
  swap preservation under injected insert failure, and swap preservation plus degraded health
  under a durable rate-limit drop.
- `AgentRequiredAuditCompositionV0` exposes one complete Agent bootstrap that
  requires both operation and registry audit writers, loads providers,
  validates the publication, and reconciles durable operations before
  returning anything.
- Provider-loader and missing-provider failures return no product bootstrap.
  An injected atomic startup-reconciliation failure also returns nothing and
  leaves queued, running, and cancellation-requested rows unchanged.
- The returned primary-session authority fixes authentication, status,
  `audit.readSelf`, Interactive, operation, capability, and detailed-audit
  dependencies once. The private operation/capability dispatchers cannot be
  substituted per connection.
- The one-phone MVP session authority closes the prior primary owner before a
  reconnect becomes current and rejects overlapping replacement transitions.
- Exact post-start provider failure removes only that provider's descriptors,
  retains unrelated descriptors and provider references, rejects mismatched or
  stale removal, invalidates pending reviews, and audits one idempotent commit.
- The product lifecycle coordinator ends only Interactive on menu loss, closes
  the primary owner on Agent loss, disable, or logout, waits through any
  reconnect transition, and returns only the remaining signed-platform effects.
- The public validation gate passes 54 indexed fixtures and 687 Swift tests,
  iOS client-platform and client-UI compilation, macOS local-authority UI
  compilation, all three no-prompt/no-network probes, and `git diff --check`.

## Boundary not claimed

The fully bound, startup-reconciled Agent root is package construction rather
than a signed product target; lower-level fixed-registry initializers remain
for focused tests. Its single-current-primary rule is the explicit
one-Mac/one-phone MVP topology, not many-device evidence. No signed provider
process, MacTools adapter, XPC invalidation, physical native provider
replacement, or release-shaped registry evidence is claimed.

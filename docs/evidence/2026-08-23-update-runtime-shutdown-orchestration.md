# Update runtime shutdown orchestration

Date: 2026-08-23

Status: package-owned orchestration passed. All dependencies were injected test
doubles; no live updater, network listener, operation, Agent, or relaunch action
ran.

## Outcome

`MacUpdateRuntimeShutdownCoordinatorV0` is now the only public production path
from an exact admitted candidate to the lower-level installation authority. The
validated candidate, binding, and authority constructors are internal, and the
admission value does not expose its authority to consumers.

The coordinator reserves confirmation ownership before its first suspension,
then samples monotonic time, menu-app foreground state, and Control state at
every authority transition. It runs only the exact issued effect, in this
order:

1. close network admission;
2. drain bounded work;
3. stop the Agent and require an exact version match; and
4. hand off once to the updater.

Any effect failure, foreground loss, expiry, Control conflict, version
mismatch, updater rejection, cancellation, duplicate confirmation, or duplicate
installation fails closed. Before returning a failure, the coordinator reads
the authority's recorded recovery scope and invokes exactly no recovery,
network-admission recovery, or Agent-plus-network-admission recovery. Recovery
failure is one distinct sanitized terminal result.

## Verification

Five new tests cover exact successful order, duplicate confirmation and
handoff denial, each effect failure, minimum recovery selection, version
mismatch, foreground loss, background confirmation, cancellation, updater
rejection, and recovery failure. All 31 focused `MacUpdate` tests pass.

The complete repository gate passes 73 authoritative fixtures, every
supply-chain, privacy, SBOM, signing, packaging, and release-evidence validator,
1,530 MacCompanionKit tests, 8 platform-probe tests, and all permanent target
and cross-platform compiles on Xcode 27 beta.

## Deliberate non-claims

The injected closures prove orchestration and fencing, not integration with the
real runtime owners. The containing app still has no protected feed or key and
still permits only an informational Sparkle probe. It does not map Sparkle's
validation and postponed-install lifecycle to candidate admission, present the
foreground install confirmation, close the real Agent listener, drain the real
dispatcher, stop or reconcile the real Agent, or invoke an installation block.

Those containing-app and runtime-owner bindings, followed by a signed
two-version upgrade/failure matrix, remain the next update gates.

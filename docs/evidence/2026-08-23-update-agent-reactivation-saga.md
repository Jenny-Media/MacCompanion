# Update Agent reactivation saga

Date: 2026-08-23

Status: bundle-independent construction and focused tests pass. All registration,
receipt, Agent-version, and failure effects were injected; no live
ServiceManagement, Agent, updater, listener, or application action ran.

## Problem closed by this checkpoint

The permanent Agent is a registered LaunchAgent with `KeepAlive=true`. Asking
the process to exit is not a safe update stop: launchd can immediately restart
the old embedded executable while Sparkle replaces the containing app.

The locally installed macOS 27 ServiceManagement header gives the required
platform boundary. `unregisterWithCompletionHandler` kills a running LoginItem,
LaunchAgent, or LaunchDaemon, invokes completion only after the process has
been killed, and states that re-registration is safe after completion. The
existing `AgentLoginRoleConvergingServiceV1` already waits for this completion
and verifies the registration postcondition.

## Outcome

`MacUpdateAgentStopOwnerV0` defines the single-use update transition without
impersonating ServiceManagement:

1. observe whether the Agent is registered;
2. for an enabled Agent, require its authenticated build to equal the source
   app build;
3. atomically persist a source/candidate-bound `prepared` reactivation receipt;
4. unregister and wait for the Agent process to be killed;
5. atomically advance the same receipt to `agentStopped`; and
6. return the exact-version fact required by the outer update authority.

An already unregistered Agent is safely stopped and creates no receipt.
Requires-approval, unavailable registration, preexisting receipt, persistence
conflict, effect failure, build mismatch, reordering, or reuse fails closed.
Receipt compare-and-swap prevents a concurrent or substituted update from
being overwritten.

If updater handoff or an earlier stop step fails, `recoverSourceBuild()`
idempotently registers the source Agent, requires exact authenticated source
build readiness, and only then clears the exact retained receipt. A prepared
receipt is sufficient recovery evidence even if the process died between
unregister completion and the second receipt write.

`MacUpdateAgentStartupReactivatorV0` is the corresponding crash/relaunch seam.
Only the receipt's exact source build or exact candidate build may consume it.
The reactivator registers the Agent from the running app bundle, verifies that
same build through the injected readiness owner, and clears the receipt last.
An unrelated app build, registration failure, version mismatch, or clear
conflict retains the receipt for explicit recovery.

## Verification

Eight focused tests cover the closed receipt schema, disabled no-op, exact
write/unregister/write order, version mismatch without mutation, unregister
failure with prepared-receipt recovery, source/candidate startup repair,
unrelated-build rejection, registration/build/clear failures, retained receipt,
and concurrent stop reservation.

The complete repository gate passes 73 authoritative fixtures, 35 update-policy
fixtures, 1,139 repository files and 1,929 historical blob paths, every
supply-chain, privacy, SBOM, signing, packaging, and release-evidence validator,
1,552 MacCompanionKit tests, 8 platform-probe tests, and every permanent target
and supported cross-platform compile on Xcode 27 beta.

## Deliberate non-claims

This checkpoint does not encode or write the receipt on disk, bind
`AgentLoginRoleConvergingServiceV1`, wait on the real authenticated readiness
surface, install startup repair in the containing app, or connect the owner to
`MacUpdateRuntimeShutdownCoordinatorV0`. Those platform bindings remain
required before the Sparkle proxy may forward `.install`. Full update checks
remain denied.

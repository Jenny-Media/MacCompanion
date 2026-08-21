# Login-role effect executor construction evidence

Date: 2026-08-20

## Claim

The bundle-independent Agent composition now has one explicit boundary for the
containing Mac app's two login roles. It consumes only reducer-validated
lifecycle transitions and never infers registration from process state.

For enablement, before the new enabled state may be committed, it:

1. registers the per-user Agent role;
2. registers the visible menu-app role;
3. returns process start/readiness work only after both calls succeed; and
4. attempts reverse-order unregistration of every possibly affected role when
   either registration call fails, including effect-then-error failures.

For disablement its API accepts only the transition returned by
`AgentRemoteLifecycleCoordinatorV1` after remote sessions and Interactive
Control have been stopped. It then attempts Agent unregistration and menu-app
unregistration even when the first call fails. The caller receives a closed,
content-free list of failed roles and cannot claim the transition fully applied.

The executor serializes transitions and rejects actor reentrancy while a
platform call is suspended. It leaves process-start effects explicit because
registration does not prove process readiness.

The raw-service convergence wrapper makes each individual role idempotent. It
does not call registration when already enabled or unregistration when already
absent. It distinguishes approval-required, missing-service, platform-failure,
and failed-postcondition outcomes without retaining framework error text. Every
mutation re-reads status, and an effect-then-error race is accepted only when
the requested postcondition is already true. Approval-blocked roles remain
eligible for unregistration so explicit disable can still remove them.

`CompanionAgentPlatform` now supplies the label-free Apple-framework seam. Its
main-actor adapter accepts an already-constructed `SMAppService`, projects all
four known statuses into the closed convergence model, maps future statuses to
an unsupported state, invokes registration, and waits for the asynchronous
unregistration completion before returning. The target contains no plist name,
bundle identifier, service factory, or process-readiness inference.

## Verification

Twenty-one focused Swift tests prove:

- exact Agent-then-menu enable order;
- start effects withheld until both registrations complete;
- compensation after an Agent registration error;
- reverse menu-then-Agent compensation after a menu registration error;
- explicit rollback-failure reporting;
- both disable unregistrations attempted after a first failure;
- reentrant transition rejection while a platform adapter is suspended; and
- rejection of a non-enable registration or non-disable unregistration path;
- idempotent already-enabled and already-absent handling;
- approval-required and missing-service separation;
- fail-closed future-status handling for both mutations;
- effect-then-error convergence for both mutations;
- rejection of false-success postconditions; and
- preservation of the typed approval reason through the transaction boundary.

One platform test proves exact projection of all four current `SMAppService`
statuses; compiling the target also proves the register and completion-handler
unregister signatures against the installed macOS SDK.

The complete package run passed 777 Swift tests. The hardened repository gate
also passed with 60 indexed fixtures, macOS and iOS package compiles, and the
three non-authorizing platform probes.

## Remaining signed-platform gate

This does not claim a live `SMAppService` registration. After final identifiers
freeze, the permanent containing app must construct its exact
`SMAppService.agent` and visible menu-app login objects and pass them into the
adapter. Clean-user approval, login, lock, crash, explicit disable, logout,
update, uninstall, and mandatory process-observation evidence remains required.

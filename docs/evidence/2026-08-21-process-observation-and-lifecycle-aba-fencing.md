# Process observation and lifecycle ABA fencing evidence — 2026-08-21

## Claim

Mac Companion now has a bundle-independent mandatory process-observation owner
that cannot turn login registration, start-request success, service status, or
PID presence into readiness.

`AgentRemoteLifecycleCoordinatorV1` advances one boot-scoped revision on every
committed transition. Prepared transitions bind the revision plus exact before
state, so lock/unlock or any other ABA sequence cannot make an old preparation
current. Independent Agent and visible-menu observation epochs advance across
the lifecycle boundaries that require fresh process authority while remaining
stable across lock/unlock.

`MacLifecycleProcessObservationOwnerV1` accepts only final-source-issued role
generations. Activation leaves a role starting. Fresh exact-generation ready
applies the matching reducer event. Replacing a ready generation applies exit
and remote safety before the replacement may become ready. Exact termination
applies exit before requesting only the matching recovery effect. Stale
generations cannot publish readiness, terminate current authority, or request a
restart. Recovery not-completed and outcome-unknown are preserved distinctly,
and every suspended call is independently serialized.

## Automated evidence

Eleven new Agent-platform tests prove:

- activation alone never claims Agent or menu readiness;
- exact current-generation ready and duplicate-ready handling;
- replacement fencing of old ready observations;
- ready-generation teardown before replacement readiness;
- exact Agent-only and menu-only recovery requests after termination;
- stale termination produces neither lifecycle mutation nor recovery;
- closed recovery failure and ambiguity;
- disable/re-enable invalidation of a pre-disable generation;
- lock/unlock preservation of a still-current pending generation;
- disabled/logged-out and unsafe-time rejection; and
- serialization while recovery start is suspended.

The existing real Agent-root integration now drives a complete lock/unlock ABA
sequence, proves the state returns equal, proves the lifecycle revision advances
twice while both process epochs remain stable, rejects the old preparation,
then proves menu and Agent exits advance only their matching epochs.

The focused `CompanionAgentPlatformTests` target passes all 37 tests. The final
hardened unsigned gate passed with 63 indexed JSON fixtures, 788 repository
files, 34 historical blob paths, 14 repository-material fixtures, 4 package
manifests, 12 dependency-policy fixtures, 3 privacy manifests, 12 privacy
fixtures, 11 required-reason API source records, 10 SBOM fixtures, 16 release-
evidence fixtures, 1,109 listed Swift tests, both platform cross-compiles, and
all three construction probes. Only the expected read-only user SwiftPM cache
warnings appeared.

## Deliberate limits

The owner deliberately does not choose how a generation is authenticated. The
final Agent target must issue its generation only after complete bootstrap, and
the final visible-menu source must bind generation to authenticated local
process/IPC identity and real loss/termination callbacks. Final labels,
designated requirements, audit-token checks, launch observation, signed XPC,
and physical crash/login/update/uninstall behavior remain release gates.

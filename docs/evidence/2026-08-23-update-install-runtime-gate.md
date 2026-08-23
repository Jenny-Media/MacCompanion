# Update installation runtime gate

Date: 2026-08-23

## Outcome

`CompanionLifecycle` now owns a bundle-independent, single-use update
installation authority. An updater adapter cannot receive its start callback
until the candidate and runtime converge through the complete direct-update
policy. No permanent target imports an updater or invokes this authority yet.

## Candidate admission

`MacUpdateValidatedCandidateV0` constructs only when:

- the installed and candidate channels are exactly equal;
- the candidate build is strictly greater;
- signed-feed verification passed;
- the archive signature passed;
- verification occurred before extraction;
- Developer ID validation passed;
- the replacement is notarized; and
- the archive represents the complete application ZIP.

The value carries no URL, key, archive bytes, path, process handle, or updater
object.

## Ordered runtime shutdown

`MacUpdateInstallAuthorityV0` accepts one local confirmation only while the
menu app is foreground and the monotonic clock can represent the exact
five-minute deadline. Every subsequent transition rechecks that foreground and
deadline fence.

The authority refuses both active Control and uncertain Control cleanup. Once
Control is exactly inactive, it issues only this ordered effect sequence:

1. close network admission;
2. drain bounded work;
3. stop the Agent; and
4. after exact app/Agent compatibility, hand off once to the updater callback.

Out-of-order, duplicate, expired, background, unsafe-clock, mismatched-version,
or failed transitions cannot skip a step. Updater errors are reduced to one
sanitized failure and cannot be retried through the consumed authority.

The authority records the minimum recovery scope when shutdown does not reach
handoff: none, network-admission reconciliation, or Agent-plus-network
reconciliation. A suspended updater handoff owns the consumed transition;
reentrant finish, failure, or foreground notifications cannot relabel a
successful handoff as safely rolled back.

There is deliberately no exact lock-state input. Foreground confirmation and
cancel-on-foreground-loss implement the documented public-API boundary without
inventing a private session discriminator.

## Verification

Twelve focused Swift tests cover every missing trust fact, channel/build
rejection, exact effect order, active and cleanup-uncertain Control, clock
overflow, foreground denial, inclusive expiry, ready-state foreground loss,
out-of-order calls, version mismatch, runtime failure, updater failure,
single-use handoff, reconciliation scope, and reentrancy across suspension.

The complete validation gate passes 73 indexed JSON fixtures, 21 update-policy
fixtures, the 1,511-test Swift catalog, every cross-build, unsigned permanent
target validation, and eight platform-probe tests on Xcode 27 beta.

## Non-claims and next gate

This authority does not fetch, parse, verify, download, extract, install,
restart, or roll back an update. It does not close a real listener, drain a real
operation, stop a real Agent, reconcile `SMAppService`, or bind Sparkle. No
remote dependency, feed, key, appcast, or permanent UI was added.

The next update slice is exact Sparkle dependency provenance and target
topology review, followed by a release-injected, unusable-by-default adapter
that maps the authority's effects to the existing lifecycle owners. Real
upgrade evidence still requires two notarized versions and explicit release
credentials.


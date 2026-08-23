# Update dashboard reconciliation

Date: 2026-08-23

Status: package and permanent-target composition pass on Xcode 27 beta. No app,
Agent, listener, local-XPC service, login role, TCC surface, network connection,
Sparkle download, or installer was started.

## Outcome

The containing-app dashboard now forwards the exact update-only network close,
drain, and recovery reopen commands only while its retained authenticated
product generation is active. It directly satisfies the runtime coordinator's
typed Agent-command boundary; inactive, finishing, and finished dashboard
lifetimes fail closed.

The process-level product router now owns network-admission reconciliation. It
first uses the retained authenticated dashboard. Explicit command failure may
retry on that same generation. Unavailable, malformed, timed-out, or
cancellation-after-send transport state retires the current generation
immediately. The router then rechecks that the Agent login role is enabled and
permits exactly one fresh authenticated dashboard generation.

The replacement generation may take at most 40 reopen attempts, spaced by the
injected production cadence of 250 milliseconds, to become command-ready.
Replacement transport ambiguity, exhaustion, registration loss, cancellation,
unknown effect failure, dashboard substitution, or product lifecycle loss
stays closed. Reconciliation is single-flight and temporarily fences setup
route publication, dashboard setup-start, and ordinary route retry.

`makeUpdateNetworkAdmissionRecovery()` produces only the coordinator closure.
Constructing it starts no dashboard, Agent, listener, updater, or other effect.
The permanent app still supplies no prepared-installer adapter, so the Sparkle
hold point remains `.skip` and this checkpoint cannot install an update.

## Verification

Six focused tests cover inactive/active/finished close-drain-reopen forwarding,
recovery-factory binding, repeated explicit command failure on the retained
generation, immediate replacement after ambiguous transport, replacement
readiness delay, registration loss, single-flight exclusion, and bounded
one-replacement exhaustion. The complete repository gate and exact package and
platform-probe inventory pass: 73 authoritative fixtures, 35 update-policy
fixtures, every supply-chain, privacy, SBOM, signing, packaging, release-
evidence, permanent-target, and cross-platform validator, 1,596
MacCompanionKit tests, and 8 platform-probe tests pass on Xcode 27 beta.

## Deliberate non-claims

No real command crossed XPC, no listener changed state, and no Agent was
stopped, recovered, registered, or unregistered. No prepared installer was
created or invoked. Live signed two-version success and failure execution,
forced process loss at each transition, stable Xcode 26.6 repetition, and final
Sparkle prepared-installer binding remain release gates.

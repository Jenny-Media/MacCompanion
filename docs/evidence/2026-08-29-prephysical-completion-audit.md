# Pre-physical completion audit

Date: 2026-08-29
Status: superseded historical checkpoint; the exact-source elapsed soak remains
incomplete and is not evidence for the current Stage 2 candidate worktree

## Outcome

This checkpoint recorded the state of source fingerprint
`2c19bbba9659d510a4ceab5eda57b4812ce05955c2d9948b034387fd4807f0c0`.
That source completed one of seven required UTC soak dates before the scheduler
was paused. Later Stage 2 implementation changed the source fingerprint, so the
campaign is now historical evidence only. It does not establish readiness for
the current worktree and must never be rebound to new code.

The machine-readable
[`prephysical-completion-audit.json`](prephysical-completion-audit.json) is the
closed inventory. `scripts/validate_prephysical_completion_audit.py` rejects a
source mismatch unless the audit is explicitly `supersededSource`, a weakened
soak threshold, missing/duplicate P-row, missing evidence file, unclassified
remainder, a false current-source soak status, or any nonempty
`automatableRequiredPathFailures` list. A superseded audit must still bind a
real retained ledger campaign and makes no current-readiness claim. The
validator remains part of `scripts/validate.sh`.

## Current-source reliability reconciliation

The older two Agent launch stalls and one signed menu timeout remain retained
as failed historical reports with unknown cause. The
[current-source stress checkpoint](2026-08-29-agent-startup-handshake-stress.md)
now completes 200 consecutive signed launches under the same ten-second
deadline. Fifty production-presentation cycles also complete the signed menu
handshake, generated presentation flow and graceful shutdown. Exact jobs and
state are absent after both runs. This closes the current P6/P8 reliability
gate without claiming a causal explanation for an older-source failure.

The retained historical soak fingerprint is
`2c19bbba9659d510a4ceab5eda57b4812ce05955c2d9948b034387fd4807f0c0`.
Its one recorded run remains attached only to that fingerprint. The current
source deliberately does not match, so Day 1 is not carried across a product or
Simulator-source change.

## Only unfinished in-scope automation

The historical ledger contains one valid run on one UTC date. That incomplete
campaign will not be resumed for changed source. After the Stage 2 candidate is
stable and source-frozen, a new campaign must start at Day 1 and span seven
distinct dates plus at least 518,400 seconds. Short repetitions and the paused
historical state are not treated as equivalent evidence.

## Why everything else is later

Four groups genuinely require physical hardware and OS behavior:

- physical iPhone custody, Face ID/Secure Enclave, device lifecycle,
  orientation and hardware-keyboard behavior;
- real screen capture, visible indicator, posted input, system audio mutation,
  lock/sleep/logout and user-owned app focus;
- real Bonjour/LAN/Local Network permission, IPv4/IPv6/private-DNS/Tailscale
  routes; and
- release performance, energy, thermal, battery, accessibility and unassisted
  usability measurements.

Two groups require fresh user authority rather than more unattended code:

- operating or modifying the installed app/Agent, production Keychain/TCC,
  privacy grants, user apps or system state is explicitly outside this goal;
  this is not mislabeled as a physical necessity; and
- the user explicitly deferred an independent subagent/review-skill audit until
  a separate request before public beta.

Four groups depend on external resources or decisions:

- stable Xcode 26.6 and controlled distribution profiles, custody,
  notarization and stapling;
- Apple's persistent-capture entitlement disposition;
- legal/privacy/retention/Apache-2.0/trademark approval; and
- TestFlight/App Review/publication plus calibration and confirmatory cohorts.

Every physical and release action is consolidated in
[`physical-acceptance-checklist.md`](../physical-acceptance-checklist.md). The
eight unresolved numeric performance decisions remain explicitly
`requiresPhysicalMeasurementAndApproval`; the Simulator baseline cannot close
them.

## Final stop rule

Do not claim the current Stage 2 candidate accepted until its candidate-bound
physical checks and new exact-source soak pass. Candidate-stabilization physical
testing may precede the new soak, but any resulting source change starts the new
campaign from Day 1. On the final valid date, rerun the complete repository
gate, signed Agent + Simulator journey, full Simulator suite, Release isolation,
startup/handshake stress validation and cleanup checks. Any newly reproduced
required-path failure reopens its requirement instead of being deferred.

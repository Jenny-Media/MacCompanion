# Outer codesign prerequisite correlation

Date: 2026-08-22

Status: deterministic non-acceptance construction evidence on Xcode 27 beta.

## Claim

The Mac-only outer `codesign --verify --deep` consistency check can no longer
be used by the correlated executor without every graph object and architecture
having already produced a passed, unchanged, exact-policy result. The executor
revalidates those prerequisites immediately before the outer invocation and
again after it.

This proves execution order and evidence continuity. It does not make
`--deep` a discovery mechanism, repair operation, or substitute for nested
verification.

## Construction

`platform_codesign_inspection.py` now exposes a read-only completed-record
revalidator. It independently rederives complete architecture plans and then:

- revalidates every whole-object prerequisite and retained raw stream;
- rehashes the complete reconstructed subject;
- independently reinspects each embedded architecture signature;
- reopens the contiguous mode-0600 certificate chain by exact path, size, and
  SHA-256 without following links;
- reopens and reparses both fixed-tool display invocations;
- recomputes embedded/display/entitlement correlation and signing-policy
  comparison; and
- requires byte-structural record equality, exact graph/policy coverage, and
  `platformAcceptanceEligible: false`.

`platform_codesign_outer.py` adds a correlated executor. It runs that complete
reinspection before invoking the existing exact outer plan, repeats it after
the invocation, requires identical closed prerequisite summaries, and embeds
the Mac artifact's ordered architecture summaries in the outer result.

An iOS-only graph still produces no Mac outer plan. A combined graph cannot
make its iOS construction subject part of the Mac outer check.

## Verification

The focused validators pass:

```text
python3 scripts/validate_platform_codesign_inspection_execution.py
python3 scripts/validate_platform_codesign_outer.py
```

The adversarial cases reject:

- architecture record omission;
- a changed passed/failed state or policy comparison;
- retained certificate substitution;
- whole-object raw-output or subject mutation;
- outer-plan and reconstructed-composition substitution; and
- a certificate mutation performed during the outer invocation, detected by
  the mandatory postflight reinspection.

The real fixed Apple tool continues to fail closed on the unsigned synthetic
subject. Exact success output is injected only to exercise the correlation
grammar and never contributes acceptance evidence.

## Remaining boundary

Every correlated result still records `platformAcceptanceEligible: false`.
The canonical 8 MiB evidence record, final signed-candidate execution,
Gatekeeper assessment, notarization and stapling correlation, packaging
equivalence, stable Xcode 26.6, release credential custody, exported IPA, and
physical/promotion gates remain open.

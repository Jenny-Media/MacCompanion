# Stage 3 study-evidence kernel

Date: 2026-08-23

## Outcome

The product-evidence decisions in [ADR-0002](../adr/0002-stage-3-product-evidence.md)
now have a bundle-independent implementation in the new `CompanionStudy`
module. It creates one bounded, canonical, content-free Stage 3 report and
reproduces the preregistered cohort decision without a network, account,
diagnostic-log import, or hidden denominator change.

The report binds:

- dogfood, calibration, or confirmatory phase;
- the opaque 16-character cohort study code;
- exact app version, build number, protocol version, and OS major versions;
- closed pairing, first-fresh-Observe, workaround, job, route-class, timing,
  physical-return, comprehension, safety, and recovery facts; and
- Control-mode durations and applicability needed to evaluate adaptive value.

The codec admits exactly one schema and ADR revision, rejects unknown members,
duplicate or noncanonical JSON, unbounded arrays/durations, invalid enum values,
and inconsistent states such as a fresh Observe result without completed
pairing. Encoding is capped at 256 KiB. One optional terminal newline is
accepted for POSIX fixture files; emitted reports remain byte-canonical JSON.

## Deterministic cohort decision

`Stage3StudyAggregatorV1` keeps enrolled, eligible, activated, withdrawn, and
received-report counts distinct. Ineligible enrollment is limited to the three
predeclared reasons and cannot carry a report. Eligible withdrawal or a missing
report remains in every eligible denominator and cannot become a success.

The evaluator implements the exact ADR rules:

- clean pairing is at least 80% of eligible testers;
- repeated real value is at least 60% of activated testers on three days;
- repeated Control and nonvisual value require five and three distinct testers;
- comprehension is at least 80% of all eligible testers;
- adaptive use requires three repeat testers and Desktop duration strictly
  below 80% of aggregate Control-active duration;
- no applicable adaptive job makes a confirmatory cohort inconclusive;
- one hard safety incident fails the result regardless of engagement; and
- the same confirmed recovery-confusion pattern in two distinct reports fails
  the result.

Dogfood and calibration can never return a market-MVP pass. Confirmatory
evidence below 15 eligible testers, missing an eligible report, missing a
safety review, or lacking adaptive applicability is inconclusive. Reports from
a different phase, app build, or protocol revision are rejected rather than
pooled. Percentage gates use integer cross-multiplication without display
rounding.

## Fixture and test evidence

The `CompanionStudyTests` resource corpus contains one valid content-free
report and four denied cases covering a screen title, typed text, IP address,
and duplicate schema key. Programmatic adversarial tests additionally cover
unknown members, identity and duration bounds, category/path and authority
inconsistency, missing reports, exact 80% and 60% boundaries, sub-threshold
failure, strict Desktop share, absent adaptive applicability, safety override,
recurring recovery confusion, calibration isolation, build mismatch, and
duplicate enrollment.

The focused command passed 12 tests on Xcode 27 beta:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift test --package-path Packages/MacCompanionKit \
  --filter CompanionStudyTests
```

## Authority and privacy boundary

This module stores no Apple Account, person, device, host, pairing, key,
certificate, address, DNS, application, window, document, screen, input,
clipboard, file, operation-parameter, or diagnostic-log content. It contains no
transport, uploader, analytics SDK, file writer, identity mapper, or optional
free-form notes field. Cohort contact-to-study-code mapping remains outside the
product evidence.

The evaluator is a decision aid over explicitly supplied enrollments and
reports. It does not establish that a report is truthful, that a tester was
eligible, that consent was obtained, or that an external cohort occurred.

## Non-claims and next gate

This kernel checkpoint does not itself implement product event capture, local
bounded persistence, preview, delete, share/export UI, participant disclosure,
retention operations, signed-app integration, physical dogfood, calibration,
or confirmatory testing. The later
[local report owner](2026-08-23-stage-3-local-report-owner.md) supplies the
bounded persistence and permanent-iOS preview/delete/export construction. It
does not change this kernel's evidence or make a market-MVP claim.

The later
[local enrollment and initial capture](2026-08-23-stage-3-local-enrollment-capture.md)
adds dogfood-only enrollment, explicit day sessions, and initial closed
pairing/connection/Observe bindings. Before any external cohort, the product
must complete the remaining Act/Control/tester-review bindings, prove that
recorded denial, failure, `outcomeUnknown`, fallback, Stop, and revocation facts
agree with visible product truth, and complete the disclosure/legal and signed
physical release gates.

# Exact Mac outer codesign verification construction

Date: 2026-08-22

## Claim

The protected signing foundation now derives and executes one fixed outer
`codesign --verify --deep --strict --all-architectures --verbose=4` consistency
check for the exact reconstructed Mac application. It rederives the plan,
rehashes the complete artifact composition before and after the fixed tool,
retains both bounded raw streams privately, and accepts only a closed
path-bound success grammar.

This result is deliberately `platformAcceptanceEligible: false`. The outer
check neither discovers nor repairs nested code and does not replace any
whole-subject, per-object, per-architecture, explicit-requirement,
certificate, entitlement, or policy result. The future canonical record must
prove all of those prerequisites and order this consistency result after them.

Only a `macApplication` graph binding whose reconstructed subject is one owned,
non-symlink `.app` receives a plan. A combined Mac/iOS graph produces exactly
one Mac plan; an iOS-only construction produces none. More than one Mac
application, missing reconstruction, platform/kind substitution, unsafe path,
unpinned tool, or changed plan fails before execution.

The fixed success grammar has empty stdout and exactly these two UTF-8,
LF-terminated stderr lines for the exact owned application path:

```text
SUBJECT: valid on disk
SUBJECT: satisfies its Designated Requirement
```

Nonzero exit, timeout, signal, tool mutation, output overflow, stdout,
additional diagnostics, missing or reordered lines, wrong path, CRLF, subject
mutation, and retained-output mutation cannot produce success.

## Apple-tool compatibility evidence

A disposable nested `.app` was constructed under `/private/tmp` with a main
Mach-O and independently signed nested helper. The helper was ad-hoc signed
first and the outer app last using the fixed system `/usr/bin/codesign`; no
repository or installed application was modified. Under the collector's exact
`LANG=C`, `LC_ALL=C`, private `HOME`, and private `TMPDIR`, the fixed outer argv
returned exit zero, empty stdout, and exactly the two lines above.

Several installed apps on this macOS 27 beta host failed strict outer
verification before grammar parsing, so they were not treated as positive
oracles and the parser did not broaden its grammar to tolerate their failures.

## Adversarial validation

`scripts/validate_platform_codesign_outer.py` covers:

- exact Mac-only and combined-target plan derivation plus iOS exclusion;
- real fixed-tool failure on the unsigned synthetic subject while retaining
  immutable non-acceptance evidence;
- injected exact success and closed failure interpretation;
- unexpected stdout, additional or missing stderr, changed argv, and open
  invocation results;
- plan/artifact substitution before execution; and
- reconstructed subject and composition mutation before any tool call.

The validator is part of `scripts/validate.sh`.

## Remaining boundary

The next checkpoint must add fixed Gatekeeper and stapled-ticket validation,
correlate the accepted notary record and exact app/DMG hashes, and assemble the
canonical platform-signing record. Until that record revalidates every prior
execution result and raw reference, `signedCodePlatformVerificationRequired`
remains mandatory.

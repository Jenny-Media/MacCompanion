# Platform signing fixed-tool runner

Date: 2026-08-22

## Claim

The first protected-collector foundation now executes one already approved
absolute tool and exact argument array without a shell. It revalidates the
pinned tool identity before and after execution, supplies a closed environment,
uses a caller-created mode-0700 private root, closes stdin, bounds both output
streams independently, applies a bounded timeout, isolates the child process
group, and retains mode-0600 raw stdout and stderr with exact byte counts and
SHA-256 references.

The result distinguishes ordinary exit, signal termination, timeout, and
output-limit termination. Only exit zero with an unchanged tool and every
required output present reports `passed`. A process launch never inherits the
release runner's `PATH`, shell startup files, `HOME`, temporary directory, or
other environment values.

## Adversarial validation

`scripts/validate_platform_signing_fixed_tools.py` exercises:

- a valid fixed tool with required stdout and stderr;
- relative and symlinked tool paths;
- group/world-writable tools;
- a non-private working root;
- a tool changed after its inventory was pinned;
- timeout and process-group termination;
- independently bounded output with retained prefix hashing;
- oversized argument input;
- signal and nonzero termination;
- missing required output; and
- refusal to overwrite an earlier invocation's raw evidence.

The validator is part of `scripts/validate.sh`.

The complete validation entry point passes on Xcode 27 beta. It scans 966
current repository files and 1,262 historical blob paths, runs every fixture,
target, privacy, signing-policy, packaging and release-evidence check, passes
the 1,389-test Swift package suite, builds every required cross-platform
surface, and passes the eight no-prompt/no-network platform-probe tests.

## Non-claims and next gate

This is not an acceptance-capable platform-signing collector and cannot clear
`signedCodePlatformVerificationRequired`. It does not reconstruct an artifact,
approve a candidate-derived argument, invoke `codesign`, parse a CodeDirectory,
inspect certificates or entitlements, compare a signing policy, correlate
notarization, validate stapling or Gatekeeper, or publish the canonical 8 MiB
evidence record.

The subsequent [subject-reconstruction and plan-derivation
slice](2026-08-22-platform-signing-subject-reconstruction.md) now rehashes exact
artifact-SBOM subjects inside an owned private root and builds only the
profile's fixed deepest-first verification plans over graph-selected subjects.
Those plans remain inert. The next slice must execute them through this runner,
parse the bounded raw evidence, and compare every reported platform fact to the
independently pinned signing policy.

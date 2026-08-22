# Platform signing subject reconstruction and fixed plan derivation

Date: 2026-08-22

## Claim

The protected platform-signing collector now has a descriptor-bound subject
reconstruction boundary and an inert deepest-first `codesign` plan boundary.
It accepts the already validated artifact-SBOM index, exact composition, and
signed-code construction graph; independently requires matching release/source
facts and complete Mac/iOS primary-artifact coverage; opens every archive with
`O_NOFOLLOW`; and verifies its descriptor identity, SHA-256, and byte count
before and after reconstruction.

Every regular file is streamed into a no-overwrite private root and rechecked
for exact SHA-1, SHA-256, byte count, and mode. Directories are created with a
private intermediate mode before their recorded final mode is applied.
Symlink bytes, targets, archive mode, and resolved in-root topology are checked
after regular files exist. Darwin's fixed filesystem representation of a ZIP
`0777` symlink is explicitly verified as `0755`; the canonical composition
continues to retain the archive's `0777` mode rather than silently rewriting
the evidence.

macOS may attach `com.apple.provenance` to newly created private files and can
make that attribute non-removable in a controlled execution environment. The
collector treats it as platform metadata, not candidate composition: the
private work root may contain no attributes or exactly that one attribute;
every reconstructed path may contain no attribute or the byte-identical root
value. The collector records the root value's SHA-256 and the number of marked
paths. Every other attribute name, a mismatched value, an empty root value, or
a changing attribute set fails closed without deleting the contamination.

The plan derivation consumes only graph objects marked inside the distribution
subject, retains the graph's deepest-first source order, resolves every subject
inside its owned reconstruction, and emits only the profile's exact
`/usr/bin/codesign --verify --strict --all-architectures --verbose=4
--test-requirement ...` argument array. It requires the independently inspected
absolute `apple.codesign` tool identity and does not execute it.

## Adversarial validation

`scripts/validate_platform_signing_subjects.py` covers combined Mac and iOS
reconstruction, implicit framework directories, exact plan arguments, owned
subject paths, deepest-first order, and absence of tool outputs. Its 19
negative cases reject:

- archive symlinks, mutations, and composition-digest substitution;
- unsafe subject roots, writable entries, and special permission bits;
- malformed composition entries and duplicate, incomplete, release-mismatched,
  or source-mismatched graphs;
- pre-existing output roots;
- private-root or reconstructed-path extended-attribute contamination while
  proving that unknown attributes are not deleted;
- invalid Team IDs and non-`codesign` fixed tools;
- malformed graph objects, changed `notRun` status, and reordered plans.

The validator is part of `scripts/validate.sh`.

The complete validation entry point passes on Xcode 27 beta. It scans 969
current repository files and 1,268 historical blob paths, runs every indexed
fixture and release-evidence boundary, passes the 1,389-test Swift package
suite, builds every required cross-platform surface, and passes the eight
no-prompt/no-network platform-probe tests.

## Non-claims and next gate

This slice still executes no candidate-derived platform command and cannot
clear `signedCodePlatformVerificationRequired`. It does not parse `codesign`
output, inspect per-architecture CodeDirectories, certificates, requirements,
or entitlements, compare the independent signing policy, validate the outer
bundle, correlate notarization/stapling/Gatekeeper, or publish the canonical
platform-signing evidence record.

The subsequent [fixed verification execution and parsing
slice](2026-08-22-platform-codesign-verification-execution.md) now passes only
these already-owned plans to the runner, reinspects subjects around each
invocation, and accepts only the profile's closed verification-success grammar.
The next collector slice must inspect each architecture, bind every reported
identity and entitlement fact, compare every policy field, and keep platform
acceptance closed on any missing, ambiguous, or unrecognized output.

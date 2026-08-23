# Source dependency SBOM profile v0

Mac Companion emits a deterministic SPDX 2.3 JSON document for the exact
first-party source dependency graph used by a release revision. SPDX 2.3 is
used for its established JSON ecosystem and can be converted to SPDX 3 by
release tooling later; this is not a claim that 2.3 is the newest SPDX model.

## Scope

The document describes `Mac Companion` containing `MacCompanionKit`, asserts
that `MacCompanionKit` has no package dependency, and records the containing
application's exact Sparkle 2.9.6 binary Swift-package dependency. The Sparkle
record binds its full resolved revision plus audited upstream-manifest,
archive, and license digests in the package comment while retaining
`filesAnalyzed: false`. This assertion is valid only after the repository's
closed dependency policy passes. Disposable experiments are repository
packages but are not release components and are not included in the release
source graph.

The document records product version, build, targets, full Git revision, dirty
state, generation time, supplier, and tool identity. Generation time is an
explicit UTC input so identical inputs produce identical bytes. The namespace
uses a deterministic UUIDv5 over every input plus the dependency-policy digest.

## Deliberate limitations

All packages use `filesAnalyzed: false`, `downloadLocation: NOASSERTION`, and
license/copyright `NOASSERTION`. No source or artifact checksum is invented.
The document comment states that it is a source dependency inventory, not
artifact composition or license evidence.

Therefore this document alone cannot satisfy the signed-candidate SBOM gate.
The release job must extend or replace it with exact built-artifact composition
and separately retained dependency-license evidence. A dirty-source document
is useful for construction evidence but cannot support a signed candidate.

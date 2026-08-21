# Exact-candidate artifact SBOM construction

Date: 2026-08-21

## Claim

The repository now has a bundle-independent, credential-free construction for
binding release evidence to the exact executable-bearing ZIP archives that
would be distributed. It closes the archive-inventory substitution gap. The
separate Mac packaging-equivalence construction now binds those trees to a DMG,
while a real signed-candidate claim remains closed until final release artifacts
pass both paths under the trusted stable lane.

The construction is not a signed-candidate claim. No release application,
archive, disk image, signing identity, notarization record, or reviewed license
set was produced.

## Construction

- `spec/artifact-sbom/v0/profile.md` defines the closed three-file evidence set,
  exact ZIP scope, deterministic encoding, reciprocal SPDX rules, archive
  safety/bounds, and the deliberately opaque DMG boundary.
- `scripts/artifact_sbom.py` provides duplicate-key-safe parsing, streaming
  SHA-256, bounded ZIP inspection, exact composition/SPDX cross-validation,
  release binding, and whole-directory fsync/rename publication at mode 0600.
- `scripts/create_artifact_sbom.py` accepts only a closed clean-source candidate
  input, explicit evidence root, and new output directory. It derives artifact
  hashes and member facts itself and refuses overwrite.
- `scripts/validate_artifact_sbom.py` validates the adversarial corpus, proves
  repeated generation is byte-identical, and exercises the signed-candidate
  verifier against a synthesized exact bundle.
- `scripts/validate_release_evidence.py --verify-files` now validates the index,
  both transitively hashed documents, the exact archives, release metadata,
  source revision, target coverage, artifact bindings, and executable paths.

The covered v0.1 artifact kinds are `macApplication`, `sparkleArchive`, and
`iosArchive`. A macOS set requires both ZIP kinds and an iOS set requires its
archive ZIP. The companion packaging-equivalence profile owns the separately
checksummed DMG and requires all three Mac containers to carry the same tree.

## Automated evidence

The focused validators passed:

```text
validated 26 artifact-SBOM fixture(s)
validated 14 exact-candidate release-integration case(s)
validated 4 iOS/combined signed-code graph release-integration case(s)
validated 16 release evidence fixture(s)
```

The corpus includes valid macOS, iOS, and combined sets with a framework-style
symlink chain plus dirty source, unsafe traversal, case collision, escaping or
cyclic symlinks, special files, encrypted/unsupported/polyglot archives,
ambiguous and non-NFC paths, valid and corrupted ZIP data descriptors,
duplicate keys, noncanonical JSON, mutated
archives, SPDX mismatch, release-version/artifact-hash substitution, and
missing or non-executable executable paths. The integration cases prove
source-SBOM substitution and post-generation archive mutation fail, and prove
the missing macOS packaging-equivalence gate fails closed. Generated output is
mode 0600, published as a no-overwrite directory, and a second publish is
rejected.

## Remaining evidence

- Generate the set from real signed application/Sparkle/iOS archives under the
  stable release toolchain.
- Run the now-implemented Mac packaging-equivalence path against the final
  signed/notarized ZIPs and DMG under the stable release lane.
- Pin and run an independent SPDX 2.3 conformance implementation in the trusted
  release lane; the repository validator currently enforces the normative
  fields directly but is not independent.
- Bind signed-code verification evidence to each exact executable-member digest.
- Retain reviewed dependency-license evidence separately; `NOASSERTION` in the
  composition SPDX is intentional and makes no legal conclusion.
- Complete signing, notarization, physical scenarios, and explicit human
  promotion under the release evidence profile.

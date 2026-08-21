# Exact candidate artifact SBOM profile v0.1

Status: normative for repository release tooling.

Mac Companion records the composition of the executable-bearing ZIP archives
that form a signed release candidate. This profile is separate from the source
dependency SBOM: the source document has `filesAnalyzed: false` and cannot be
substituted for exact-candidate evidence.

## Three-file evidence set

`artifact-sbom-index.json` is the release-evidence entry point. It binds the
product, version, build, target set, clean Git revision, generation time, and
every covered archive's release artifact ID, kind, platform, relative path,
packaged SHA-256, and byte count. It contains hashed references to exactly:

- `artifact-composition.json`, the closed exact ZIP-member inventory; and
- `artifact-sbom.spdx.json`, the reciprocal SPDX 2.3 representation.

All JSON is UTF-8, sorted-key compact canonical JSON with one trailing newline.
Generation time is an explicit whole-second UTC input. Identical archives and
metadata therefore produce byte-identical evidence.

The composition contains every ZIP directory, regular file, and symbolic link
in UTF-8 path order. Each entry records its relative POSIX path, type, four-digit
octal permission mode, uncompressed byte count, SHA-1, SHA-256, and symlink
target. Directories have zero bytes and null digests/target. Regular files hash
their uncompressed bytes. Symlinks hash the UTF-8 target bytes.

The SPDX document uses `filesAnalyzed: true`, one package per covered archive,
and one file per regular file or symlink. Each file carries the SPDX-required
SHA-1 plus SHA-256, and each package carries the SPDX 2.3 package verification
code computed from its sorted file SHA-1 values. `DESCRIBES` and `CONTAINS`
relationships and checksums must be exactly reciprocal with the index and
composition. License and copyright fields remain `NOASSERTION`; this is
composition evidence, not a legal conclusion.

## Coverage boundary

The profile covers `macApplication`, `sparkleArchive`, and `iosArchive` ZIPs.
A macOS candidate requires both the application ZIP and Sparkle ZIP. An iOS
candidate requires the archive ZIP. A disk image is retained and checksummed by
release evidence but remains an opaque distribution wrapper in v0.1. A later
packaging-equivalence gate must prove its contained application matches the
covered application payload; this profile makes no such claim.

Every signed executable path declared by release evidence must exist as an
executable-bit regular file in the composition for its referenced artifact.

## Archive safety and bounds

Inspection is of the exact packaged archive, never an expanded build folder.
The validator rejects absolute, dot-segment, backslash, control-character, and
non-NFC paths; duplicate paths; case-fold/NFC collisions; encrypted members;
unsupported special files or compression; malformed Unix types or modes;
escaping, missing, or cyclic symlink targets while permitting bounded standard
framework chains; unaccounted prefix/suffix/inter-member bytes; ambiguous path
separators; data descriptors whose signature, CRC, or sizes disagree with the
central directory; more than 20,000 entries; more than 4 GiB expanded data; and a
greater-than-1000:1 ratio for members larger than 1 MiB. Content hashes are
streamed. All three documents must be byte-canonical. Archive substitution,
member addition/removal/change, mode change, and symlink-target change all fail
exact-file verification.

## Release integration

Release-evidence v0.1 retains its closed `sbom.document`/`sbom.licenses` shape.
For a signed candidate, `sbom.document` points to
`artifact-sbom-index.json`. `--verify-files` validates the complete three-file
set against release metadata, artifact hashes and sizes, target coverage,
source revision, and executable paths. Unsigned construction evidence continues
to forbid SBOM attachment.

`scripts/create_artifact_sbom.py` generates the set from a closed candidate
input and an explicit evidence root. It computes archive facts itself, requires
clean source metadata, writes mode 0600 with fsync and atomic rename, and refuses
overwrite. `scripts/validate_artifact_sbom.py` is the conformance authority.

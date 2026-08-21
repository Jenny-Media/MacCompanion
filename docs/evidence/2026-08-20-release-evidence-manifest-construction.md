# Release evidence manifest construction

Date: 2026-08-20

## Claim

The repository now has a strict, non-secret v0.1 release evidence profile and
an executable validator. It separates three claims:

- `unsignedConstruction` records source, compatibility, toolchain, and
  validation only and cannot be promoted;
- `signedCandidate` additionally requires a clean revision, passed validation,
  checksummed target artifacts, exact signed executable evidence, accepted
  macOS notarization where applicable, and a checksummed SBOM; and
- `promotionReady` additionally requires target-bound passed physical
  scenarios, a separate human approval record, and exact Sparkle and/or App
  Store publication evidence.

The closed manifest binds release targets to protocol/minimum-OS
compatibility, artifact kinds, executable roles, platforms, bundle identifiers,
notarization/stapling, scenario platforms, and publication targets. A failed
extra validation or physical scenario cannot be hidden beside the required
passing set. Every artifact and evidence reference carries an exact relative
path, SHA-256 digest, and positive byte count; executable inspection is retained
as one hashed verification bundle per executable.

The validator rejects duplicate JSON keys, unknown or missing fields, unsafe
and dot-segment paths, duplicate identifiers, dangling references, platform
substitution, bad or obvious placeholder hashes, dirty signed candidates,
incomplete target artifacts, unsigned executables, failed postconditions,
premature promotion, invalid approval time, and secret-like fields or material.
It can validate the repository corpus with no arguments or one or more
generated manifests by path. `--verify-files` resolves every reference relative
to the manifest and rejects missing content, symlink/path escape, size mismatch,
or digest mismatch.

The unsigned generator captures the current Git revision/dirty state and active
Xcode, Swift, host OS, and target SDK versions. It accepts only a nonempty
validation log inside the chosen evidence root, hashes that log, validates the
result, writes mode `0600` through fsync and an atomic no-clobber hard-link
publication, fsyncs the directory, and refuses overwrite or output escape even
across a concurrent-creation race. A locally generated dual-target example
validated with file verification; mutating its retained log afterward produced
both size- and digest-mismatch failures.

## Verification

Sixteen indexed release-evidence fixtures pass their expected disposition:

- three valid manifests cover unsigned construction, a signed macOS candidate,
  and a dual-target promotion-ready release;
- thirteen invalid manifests cover closure, secrets, absolute and dot-segment
  paths, digest and placeholder rejection, incomplete signing evidence,
  missing and misbound physical evidence, duplicate IDs and JSON keys,
  compatibility leakage, executable platform substitution, and obvious
  placeholder revisions and digests.

The valid CLI path accepts all three valid levels. The invalid CLI path returns
nonzero with stable error codes. The public repository gate now validates this
corpus before Swift compilation alongside 60 protocol/product fixtures, 14 repository-material fixtures, 12
dependency-policy fixtures, 12 privacy-manifest fixtures, 10 source-SBOM
fixtures, 16 release-evidence fixtures, and 806 Swift tests.

## Remaining release gates

No fixture is a real release claim. A real signed candidate still requires
final Apple identities, stable Xcode 26.6, signing custody, actual artifacts,
notarization, SBOM generation, and signed executable inspection. Promotion
still requires the recorded physical matrix, Sparkle/App Store evidence, and a
separate human approval. The validator neither holds credentials nor performs
publication.

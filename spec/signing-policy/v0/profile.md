# Mac Companion release signing-policy profile v0.1

Status: normative for an independently pinned construction contract. No
production policy or production digest is pinned, and this profile cannot open
Apple-platform acceptance.

This profile binds reviewed signing expectations to one exact release, clean
source revision, artifact SBOM, signed-code construction graph, declared
executables, every distribution Mach-O object, and every architecture slice.
It prevents candidate evidence from authorizing its own signer, entitlements,
third-party code, or completeness claim.

## Independent authority

The canonical UTF-8 JSON file uses schema
`maccompanion.signing-policy.v0.1`, is no larger than 4 MiB, and ends with one
line feed. The loader opens one regular single-link file through `O_NOFOLLOW`,
reads it once, proves its descriptor facts did not change, hashes the exact
bytes before parsing, and compares them to a lowercase SHA-256 pin supplied by
protected release-runner configuration.

The expected pin cannot come from the candidate checkout, release manifest,
artifact SBOM, construction graph, retained evidence, build output,
build-controlled environment, or policy itself. Candidate evidence may retain
a policy reference for correlation, but that reference is never authority.
The production release runner must independently pin the exact policy SHA-256;
that digest cryptographically commits the approved policy ID, revision, byte
count, and every rule. Synthetic fixture pins are test inputs only.

## Closed root and exact bindings

Every root field is required:

- `schemaVersion`, `policyID`, positive `policyRevision`, and product exactly
  `Mac Companion`;
- exact `release` version, build number, channel, and sorted targets;
- exact clean `source` revision;
- exact `artifactSBOM` and `signedCodeGraph` evidence references;
- an exact platform/trust-profile-sorted `officialSigners` set, with one Team
  ID and leaf-certificate SHA-256 for each release target;
- `declaredExecutables`, the sorted set of the manifest executable fields that
  are not claims or evidence references; and
- `artifacts`, exactly the construction graph's primary artifact set.

The policy-to-candidate validator requires every repeated release, source,
reference, artifact, member, topology, declaration, architecture, and slice
digest fact to equal the independently validated manifest, SBOM, and graph.
The graph never references the policy, avoiding a digest cycle.

Each artifact policy contains the exact six artifact identity fields,
`subjectRoot`, a closed verification profile, an exact third-party allowlist,
and all distribution-subject Mach-O objects. `macOSDeveloperID` is the direct
Mac construction profile. `iosArchiveConstructionOnly` records expectations
for the current xcarchive product but is categorically ineligible for platform
acceptance: Xcode's independently hashed exported IPA must become a distinct
artifact in a later profile before iOS acceptance.

Each object repeats its exact member, owner bundle, bundle-main relation, and
declared-executable IDs. Objects are uniquely keyed by artifact and member
path, are sorted, and equal every and only graph Mach-O object whose
`inDistributionSubject` is true. dSYMs and other outside-subject objects remain
inventoried by the graph but cannot be included by policy choice.

Each architecture repeats the numeric CPU type/subtype and exact slice
SHA-256. Architecture tuples equal every and only independently parsed graph
slices. It also pins expected signing identifier, Team ID, one modern SHA-256
CodeDirectory's full digest and its exact first-20-byte CDHash, leaf certificate, raw
designated-requirement data digest, trust profile,
hardened-runtime and secure-timestamp requirements, and exact entitlements.
The v0.1 macOS 26/iOS 26 baseline requires exactly one SHA-256 CodeDirectory
record per architecture; alternate or legacy CodeDirectories require a policy
profile revision rather than being silently ignored. First-party architectures
equal the unique `officialSigners` entry for their platform and trust profile;
Mac Developer ID and iOS distribution identities therefore cannot share a
synthetic leaf merely because their Team ID is the same. Third-party architectures
remain individually pinned.

`thirdPartyAllowlist` is the exact sorted set of `{path, memberSHA256}` for
objects marked `thirdParty`. Team-only, prefix, bundle-ID, regex, glob, or
caller-predicate authorization is forbidden. Missing, extra, duplicated,
reparented, reclassified, or multiply matched objects fail.

## Exact entitlements

Absent and present-empty entitlements are distinct:

- `{ "mode": "absent" }`; or
- `{ "mode": "exact", "entries": [...] }` with sorted unique ASCII keys.

Values are closed tagged nodes: Boolean, safe integer, NFC string, ordered
array, or sorted-key dictionary. Untagged JSON, null, floating point, data,
date, duplicate keys, unknown types, substitution, regex, and matching
semantics are rejected. An asterisk inside a value is an exact byte, never a
wildcard. The complete sanitized signed entitlement value must compare equal;
extra keys fail.

The policy is capped at 1,024 objects, 2,048 architectures, 128 top-level
entitlement keys per architecture, 4,096 aggregate dictionary keys, 8,192
aggregate tagged nodes, depth four, 64 children per container, 128 ASCII bytes
per key, 1,024 UTF-8 bytes per string, and 512 KiB aggregate entitlement string
bytes. Integers are limited to the interoperable JSON safe range and Booleans
are never integers.

## Acceptance boundary

This parser proves only canonical, independently pinned policy construction and
exact correlation with construction evidence. It does not establish an Apple
trust chain, certificate validity, requirement evaluation, CDHash, hardened
runtime, timestamp, entitlement, provisioning, notarization, stapling,
Gatekeeper, App Store, TestFlight, or physical-device result.

A future release-only collector must safely reconstruct each graph-derived
bundle-root or standalone subject, execute fixed absolute Apple tools without a
shell or ambient `PATH`, retain bounded raw output and exact tool/OS identity,
evaluate the independently pinned requirement, inspect every architecture
deepest-first, use `codesign --deep` only as an outer cross-check, rehash every
candidate/policy/input/output before and after execution, and clean up its
private staging area. Valid construction remains
`signedCodePlatformVerificationRequired` until that separate contract and its
stable-toolchain, final-identity, exported-IPA, notarization, and physical gates
pass.

## Validator and fixtures

`scripts/signing_policy.py` owns the bounded pinned loader, closed parser, and
exact construction-binding validator. `scripts/validate_signing_policy.py`
owns the synthetic indexed corpus under `Tests/System/SigningPolicy`. No
fixture digest, policy ID, identity, or certificate is a production default.

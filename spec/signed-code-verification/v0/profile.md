# Signed-code construction correlation profile v0.1

Status: normative for bundle-independent construction evidence. It is not a
signed-candidate acceptance profile.

This profile proves that one canonical signed-code record names the exact
release, clean source revision, artifact-SBOM index, release artifact, declared
executable, and regular-file member independently observed in the candidate
archive. It retains four hash/size-bound raw outputs. It does not trust or
interpret those outputs or prove an Apple signature. Complete construction
discovery is a separate required signed-level validation record defined by the
[signed-code graph profile](../../signed-code-graph/v0/profile.md).

## Canonical bundle

Each `release.executables[].verificationBundle` points to one bounded canonical
UTF-8 JSON file with schema
`maccompanion.signed-code-verification.v0.1` and evidence level
`constructionCorrelation`. The file is read once through `O_NOFOLLOW`, is at
most 1 MiB, rejects duplicate/noncanonical JSON, and is hashed from the exact
bytes that are parsed.

The closed record binds:

- product, full release version/build/target set, clean source revision, and
  generation time;
- the exact artifact-SBOM index reference;
- the complete covered artifact identity: ID, kind, platform, path, SHA-256,
  and byte count;
- every release executable identity field except the outer `signed` assertion
  and verification-bundle reference;
- all seven composition fields for the exact executable member: path, type,
  mode, bytes, SHA-1, SHA-256, and null symlink target;
- reported signing identifier, Team ID, CDHash, and leaf-certificate SHA-256;
- reported code-sign and target-specific assessment results; and
- four distinct retained references for designated requirement, expanded
  entitlements, code-sign verification, and platform assessment output.

The member must be a nonempty executable-bit regular file and must equal the
entry selected by `artifactID + relativePath` in the validated exact-candidate
composition. The artifact, executable, release, source, and SBOM references
must each match independently validated release evidence. Every transitive raw
reference is relative, non-symlink, bounded by its positive byte count, and
bounded to 16 MiB, then SHA-256 verified from one descriptor.

The reported platform value is `gatekeeperAccepted` only for the outer macOS
app, `embeddedNotApplicable` for embedded Mac agent/CLI records, and
`iosProvisioningReported` for iOS. These are retained reports, not trusted
results.

## Acceptance boundary

Attach-free `--verify-files` performs only canonical parsing and exact
correlation. Signed-level file verification also requires exactly one passed
`signed-code-graph-construction` record and independently recomputes its full
Mach-O inventory. A missing, stale, substituted, symlinked, incomplete, or
invented graph fails before this profile's platform gate. An otherwise valid
signed candidate returns `signedCodePlatformVerificationRequired`. No flag
bypasses that result in v0.1.

A future release-only platform profile must safely reconstruct the exact code
subject from the already validated archive, rehash it before and after tool
execution, run hardcoded Apple verification commands, parse their results,
apply the final signing/entitlement/identity policy, verify the outer seal and
the construction graph, and rehash the archive, SBOM, bundle, graph, and raw
evidence before acceptance. macOS Gatekeeper applies to the outer app;
embedded code is covered by the outer assessment but still requires independent
signature/requirement checks. iOS requires sanitized provisioning and signed
entitlement policy; App Store/TestFlight and physical installation remain
separate evidence.

Until final Team ID, bundle identifiers, target topology, entitlement policy,
stable macOS 26/Xcode 26.6, and protected signing custody exist, this profile
cannot open the real `signedCandidate` gate.

## Validator and fixtures

`scripts/signed_code_verification.py` owns the closed parser and correlation
rules. `scripts/validate_signed_code_verification.py` owns the indexed
attach-free corpus. The release verifier parses every declared executable
bundle only after exact artifact-SBOM validation succeeds and returns
`invalidSignedCodeVerification` for any malformed, stale, substituted, or
unverifiable construction record.

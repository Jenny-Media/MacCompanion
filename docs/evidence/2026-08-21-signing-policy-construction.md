# Signing-policy construction boundary

Date: 2026-08-21

Status: construction contract implemented; Apple-platform acceptance remains closed.

Mac Companion now requires one canonical, independently SHA-256-pinned signing
policy for every signed-candidate or promotion-ready evidence bundle. Candidate
files retain the policy reference for correlation, but only the protected
release-runner pin is authority.

The policy binds the exact release, clean source revision, artifact SBOM,
signed-code graph, artifacts, distribution Mach-O objects, architecture slices,
declared executables, discovered bundle identifiers, platform-specific official
signers, third-party allowlist, CodeDirectory/CDHash relation, requirements,
runtime/timestamp expectations, and exact tagged entitlements. Mac Developer ID
and iOS distribution signers are distinct per-platform trust profiles.

The bounded loader requires a single-link regular file opened with
`O_NOFOLLOW`, hashes exact canonical bytes before parsing, fails closed when
that primitive is unavailable, and normalizes malformed Unicode and resource
errors into policy rejection. Unsigned construction rejects both a policy
record and an externally supplied policy pin.

Evidence run on the repository:

- 64 structural signing-policy fixtures, including exact-limit and one-past
  entitlement resource bounds plus cross-platform signer separation;
- 30 exact policy-to-release/SBOM/graph binding fixtures;
- 10 CLI authority-boundary cases, including complete signed-candidate
  subprocess runs for correct, wrong, and omitted protected pins;
- 26 artifact-SBOM fixtures;
- 14 exact-candidate release integrations;
- 4 iOS/combined graph integrations; and
- the complete Mac packaging-equivalence fixture, recovery, and substitution
  suite.

Passing this contract still returns
`signedCodePlatformVerificationRequired`. The next protected implementation is
governed by the platform signing evidence profile; stable Xcode, production
identities, exported IPA evidence, notarization, physical matrices, and human
promotion remain separate gates.

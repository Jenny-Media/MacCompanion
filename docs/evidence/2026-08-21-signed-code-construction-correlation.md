# Signed-code construction correlation

Date: 2026-08-21

## Claim

Every declared release executable can now carry one canonical construction
record that is exactly cross-bound to the validated release, source revision,
artifact-SBOM index, artifact, and executable archive member. The retained raw
outputs are hash/size checked but deliberately remain untrusted.

This is not signed-candidate evidence. No final target, identity, protected
signature, Apple-tool verification, complete nested-code inventory,
entitlement-policy result, Gatekeeper acceptance, iOS provisioning acceptance,
or physical install was produced.

## Construction

- `spec/signed-code-verification/v0/profile.md` freezes the construction-only
  boundary and future platform gate.
- `scripts/signed_code_verification.py` performs bounded no-follow canonical
  loading, exact release/source/SBOM/artifact/executable/member correlation,
  and transitive raw-reference verification.
- `scripts/validate_release_evidence.py` parses every record only after the
  exact-candidate artifact bundle passes. A fabricated, stale, exchanged, or
  malformed record yields `invalidSignedCodeVerification`; a structurally
  correct record still yields `signedCodePlatformVerificationRequired`.
- Artifact-SBOM and Mac packaging integrations now construct distinct app and
  Agent records rather than accepting one-byte opaque placeholders. Signed
  file verification also requires the separate [complete construction graph](2026-08-21-signed-code-construction-discovery.md).

## Automated evidence

```text
validated 17 signed-code verification fixture(s)
validated 26 artifact-SBOM fixture(s)
validated 14 exact-candidate release-integration case(s)
validated 4 iOS/combined signed-code graph release-integration case(s)
validated 5 mac-packaging release-integration case(s)
```

The focused corpus covers exact binding, executable/member substitution,
member digest and mode, signing/team/CDHash shape, reported-check failure,
target-assessment mismatch, duplicate raw paths, mutated raw evidence,
raw-evidence symlinks, unknown fields, noncanonical and duplicate-key JSON,
Mac/iOS target branches, and the 1 MiB bound. Release integration also proves
that oversized or symlinked outer verification bundles are rejected before an
unbounded generic read.

## Remaining acceptance work

- Apply an independently pinned final identity/entitlement/third-party policy
  to the now-required complete construction-discovery graph.
- Extract the exact validated candidate safely, run and parse strict
  all-architecture `codesign`/requirement/entitlement checks, apply the final
  signing policy, and rehash every subject and evidence root afterward.
- Prove outer-app Gatekeeper/quarantine behavior on stable macOS 26/Xcode 26.6;
  prove sanitized iOS provisioning/entitlement compatibility and physical
  installation through the appropriate distribution lane.

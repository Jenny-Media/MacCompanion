# Canonical platform-signing construction record

Date: 2026-08-22

Status: deterministic non-acceptance construction evidence on Xcode 27 beta.

## Claim

Completed signing-construction facts can now be assembled into one canonical,
bounded, exact-input record without allowing that assembly to clear the Apple
platform gate.

The schema is `maccompanion.platform-signing-evidence.v0.1`. This checkpoint
admits only `constructionOnly` and
`platformAcceptanceEligible: false`.

## Exact composition

`platform_signing_evidence.py` binds:

- canonical SHA-256 and byte references for the release manifest, exact-candidate
  artifact-SBOM index, signed-code graph, and independently pinned policy;
- mutually equal release, target, clean-source, and transitive graph/policy
  references;
- a closed host OS, Xcode, SDK, and stable-toolchain fact set;
- the one pinned `/usr/bin/codesign` public tool identity;
- every reconstructed artifact subject and its fresh composition hash;
- complete whole-object, per-architecture, and correlated Mac outer records;
- closed per-target construction results; and
- every still-unresolved stable-toolchain, final-candidate, credential,
  Gatekeeper, notarization, stapling, packaging, exported-IPA, provisioning,
  physical, and human-promotion gate that applies.

Generation revalidates the artifact index and composition, release binding,
signed-code graph against the exact archives, signing policy, architecture
records, retained output and certificates, reconstructed subjects, and
correlated outer record. Parsing requires canonical UTF-8 JSON and an 8 MiB
maximum. Validation recomposes the entire record from those freshly reopened
inputs and requires byte-canonical equality.

## Verification

```text
python3 scripts/validate_platform_signing_evidence.py
```

The validator proves deterministic byte generation and canonical round-trip.
It rejects:

- an unknown root field;
- any attempt to set platform acceptance true;
- altered signing-policy input digest;
- omitted architecture evidence;
- changed policy-comparison facts;
- deletion of one unresolved gate;
- noncanonical JSON; and
- a record larger than 8 MiB.

It also verifies that combined target gate projection retains both Mac
Gatekeeper and iOS exported-IPA requirements even when the supplied toolchain
fact is stable.

The validator is part of `scripts/validate.sh`.

## Remaining boundary

This is not an acceptance-capable collector. Synthetic success output and
fixture certificate facts remain isolated test inputs. No final signed
candidate, production policy digest, Developer ID custody event, Gatekeeper
assessment, notarization ticket, staple, packaging-equivalence correlation,
exported IPA, stable Xcode 26.6 run, physical scenario, or promotion approval
was produced.

The release-evidence validator must continue to emit
`signedCodePlatformVerificationRequired`.

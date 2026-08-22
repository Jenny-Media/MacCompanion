# Per-architecture embedded-signature inspection construction

Date: 2026-08-22

Execution status: the plan and parser construction claims below remain
current. Their execution-time non-claims are superseded by the
[protected execution checkpoint](2026-08-22-per-architecture-signature-inspection-execution.md).

## Claim

The protected signing collector now has a graph-derived, shell-free inspection
plan for every distribution Mach-O architecture and an independent parser for
the embedded signature bytes selected by that exact graph slice. This closes
the construction boundary between all-architecture `codesign` verification and
the independently pinned per-architecture signing policy; it does not yet make
a signed candidate acceptance-eligible.

For each graph object and numeric CPU type/subtype, the plan binds the exact
reconstructed Mach-O source, bundle or standalone display subject, private
certificate-output prefix, and two fixed `/usr/bin/codesign` invocations. The
first requests verbose identity, explicit internal requirements, and the
certificate chain. The second requests XML entitlements. Plan construction
replays the graph's inert `reportIdentityAndRequirements` and
`reportEntitlements` steps exactly; substitution, omission, reordering, an
unsafe path, symbolic architecture alias, or a non-pinned tool fails before
execution.

The embedded parser reopens the exact single-link Mach-O without following its
final path, rederives the full graph architecture and slice SHA-256, reads only
the graph-bound `LC_CODE_SIGNATURE` range, and applies bounded big-endian
SuperBlob parsing. It requires exactly one modern SHA-256 primary
CodeDirectory, one explicit designated requirement, one nonempty CMS wrapper,
and only known v0.1 slots. It independently derives:

- the full CodeDirectory SHA-256 and first-20-byte CDHash;
- signing identifier, Team ID, CodeDirectory flags, and hardened-runtime bit;
- SHA-256 of the exact complete designated-requirement blob;
- exact absent-versus-present XML entitlements as the signing-policy tagged
  value; and
- the CMS, entitlement-blob, and complete embedded-signature digests.

The entitlement parser rejects duplicate XML or binary plist keys, overlapping
binary objects, unsupported plist types, non-ASCII or duplicate keys,
non-normalized or control text, unsafe integers, and every policy resource-bound
escape. Modern DER entitlement blobs deliberately fail closed in this
checkpoint. They cannot be ignored or authorized from the XML sibling; a
future semantic DER parser must prove the exact same tagged policy value before
such a signature can match.

The bounded Apple-display parser treats tool text only as an independent
cross-check. A positive synthetic grammar requires one graph-source-bound
`Executable`, identifier, Team ID, full SHA-256 CodeDirectory digest and
matching CDHash, non-ad-hoc signature size, certificate authorities, zero or
one timestamp, one explicit designated-requirement report, and a bounded
certificate-digest inventory. Entitlements are independently normalized and
must equal the embedded facts. Unknown non-authoritative verbose lines are
retained in the raw output but cannot create an authorization fact.

The final per-architecture comparator requires exact equality for the CPU
tuple, slice, identifier, Team ID, CodeDirectory, designated requirement,
leaf-certificate SHA-256, hardened runtime, timestamp requirement, and
entitlements, plus successful Apple verification and explicit-requirement
evaluation. A matching result remains `platformAcceptanceEligible: false` so
this component cannot bypass outer-bundle, notarization, Gatekeeper, stable
toolchain, exported-IPA, physical, or promotion gates.

## Adversarial validation

`scripts/validate_platform_code_signature.py` constructs bounded synthetic
Mach-O and embedded-signature bytes and covers graph substitution, final-path
symlinks, missing or additional requirements, missing CMS, alternate
CodeDirectories, unsupported slots, DER-only and XML-plus-DER entitlements,
unsupported values, duplicate plist keys, identity/policy substitution,
certificate mismatch, timestamp mismatch, runtime mismatch, and absent Apple
verification.

`scripts/validate_platform_codesign_inspection.py` validates the positive
identity/requirement/entitlement grammar and rejects implicit requirements,
ad-hoc signatures, missing certificates, changed argv, extra entitlement
diagnostics, failed invocations, and disagreement with the embedded parser.
`scripts/validate_platform_signing_subjects.py` additionally proves complete
numeric-architecture plan coverage and graph-order binding. All three are part
of `scripts/validate.sh`.

## Non-claims and next gate

The protected executor now performs before/after subject rehashing, exact
certificate-file retention, and policy correlation. Its positive execution
fixture injects bounded Apple-tool output, so no real signed candidate is
asserted to match policy. DER entitlement semantics, outer recursive
verification, notarization, stapling, Gatekeeper, and canonical evidence
publication remain open. Synthetic fixture values are not production policy or
identity authority.

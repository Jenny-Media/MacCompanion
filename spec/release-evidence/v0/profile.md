# Mac Companion release evidence manifest v0.2

Status: normative for repository release tooling.

This profile records evidence; it never performs signing, notarization,
publication, or promotion. A valid manifest is not proof that referenced files
exist or that their contents are truthful. The release job must assemble the
evidence bundle, compute its hashes, validate the manifest, and retain both.

## Claim levels

- `unsignedConstruction` records source, toolchain, and unsigned validation.
  Artifacts, executables, notarization, SBOM, physical scenarios, and promotion
  must be absent or empty. It cannot be promoted.
- `signedCandidate` additionally requires a clean source revision, passed
  validation, checksummed target artifacts, signed executable evidence, an
  SBOM, and target-specific notarization evidence. Promotion remains absent.
- `promotionReady` includes every signed-candidate requirement plus the exact
  target-specific physical scenario set and a separate human approval record.
  Only `beta` or `stable` channels may make this claim.

The level is monotonic. Missing evidence cannot be represented by a successful
status, placeholder digest, empty path, or a lower-level object embedded in a
higher-level manifest.

## Closed root

Every root key is required:

- `schemaVersion`: exactly `0.2`.
- `evidenceLevel`: one claim level above.
- `product`: exactly `Mac Companion`.
- `release`: version, build number, channel, and nonempty target list.
- `compatibility`: exact capability, Interactive Control, and local-IPC profile
  versions; the target-scoped Mac user-initiated update-check profile; plus
  target-scoped minimum operating-system versions. The update-check profile is
  either `null` (information-only checks) or exactly
  `maccompanion.user-initiated-full-update-check.v1`; it must be `null` when
  macOS is not a target.
- `source`: full lowercase Git commit SHA and dirty-worktree Boolean.
- `toolchain`: bounded Xcode, Swift, host OS, and unique SDK strings.
- `validation`: nonempty, uniquely identified passed/failed evidence records
  with hashed evidence references.
- `artifacts`: uniquely identified paths, kinds, byte sizes, and SHA-256 hashes.
- `executables`: signed-code evidence referring to declared artifacts plus one
  hashed verification bundle containing the designated requirement, expanded
  entitlements, code-sign verification, and platform assessment.
- `notarization`: one hashed canonical two-phase platform-notarization record,
  its two distinct accepted submission IDs, and final app/DMG stapling claims,
  or `null`.
- `sbom`: checksummed SBOM plus dependency-license evidence, or `null`.
- `physicalScenarios`: uniquely identified passed/failed evidence records.
- `promotion`: explicit human approval and publication evidence, or `null`.

Every evidence reference contains a relative path, SHA-256 digest, and positive
byte count. All nested objects are closed. Arrays are bounded. Signed executable records
include a syntactically valid bundle identifier and may reference only an
artifact and platform declared by the release. Identifiers use lowercase
ASCII letters, digits, dots, and hyphens. Evidence paths are relative POSIX
paths inside the retained evidence bundle; absolute paths, backslashes, empty
segments, and `..` are forbidden.

## Target requirements

A signed macOS candidate requires `macApplication`, `macDiskImage`, and
`sparkleArchive` artifacts; signed `macApp` and `agent` executable roles; a
canonical [two-phase notarization record](../../platform-notarization-evidence/v0/profile.md)
covering distinct accepted app-archive and disk-image submissions; and stapling
evidence for the application and disk image. A signed iOS candidate requires an `iosArchive` artifact and a
signed `iosApp` executable role. Every signed candidate requires an SBOM and
dependency-license evidence.

The repository's source dependency SPDX document is useful input but is not,
by itself, signed-candidate SBOM evidence: it explicitly does not assert actual
artifact composition or license conclusions. The release job must retain the
artifact-complete SBOM derived from the exact candidate plus separate reviewed
dependency-license evidence.

A promotion-ready macOS manifest additionally requires passed
`clean-install`, `upgrade`, `rollback`, `permission-revocation`,
`complete-uninstall`, and `quarantine-launch` scenarios plus Sparkle appcast and
signature evidence. A promotion-ready iOS manifest additionally requires
passed `physical-pairing`, `local-network-denial`, and `background-reconnect`
scenarios plus an App Store/TestFlight record. The promotion publication
targets must exactly match the release targets. Required scenario identifiers
are bound to their exact platform, and every recorded promotion scenario must
pass; a failed extra scenario cannot be hidden beside the required set.
The macOS `upgrade` and `rollback` scenarios must share the same canonical
[Mac update physical-evidence record](../../mac-update-physical-evidence/v0/profile.md).
File verification validates every transitive observation and exact candidate
binding; opaque or divergent scenario files cannot satisfy those two gates.
The other four macOS scenarios must likewise share one canonical
[Mac lifecycle physical-evidence record](../../mac-lifecycle-physical-evidence/v0/profile.md),
which binds quarantine, clean-install, permission-revocation, and complete-
uninstall assertions plus exact terminal candidate or removal state.
All three iOS scenarios must share one canonical
[iOS physical-evidence record](../../ios-physical-evidence/v0/profile.md),
binding physical pairing plus Observe/`setAudioMuted`, Local Network denial and
recovery, and foreground-safe background reconnect to the exact iOS archive.

## Secret exclusion

Manifests contain references and public verification results, never secret
material. Secret-like field names, PEM private keys, `.p8`, `.p12`,
`.mobileprovision`, or `.provisionprofile` values are rejected. Developer ID,
Sparkle, notarization, App Store, provisioning, pairing, and host private
material remain in protected external systems.

## Validator

`scripts/validate_release_evidence.py` is the executable v0.2 conformance
authority. `Tests/System/ReleaseEvidence/manifest.json` indexes valid and
invalid examples. The public repository gate validates the corpus but does not
claim a signed candidate or a promotion-ready release.

Passing an unsigned-construction manifest path validates its schema and gates.
For `signedCandidate` and `promotionReady`, the path-based CLI requires
`--verify-files`; omission returns `signedCandidateFileVerificationRequired`
rather than printing a valid manifest. Explicit `--schema-only` remains
available for structural inspection, is incompatible with file/platform flags,
and labels success `schema-valid only` so it cannot be consumed as acceptance.
File verification resolves every artifact and evidence reference relative to the manifest,
rejects symlink/path escape, and compares exact byte count and SHA-256 content.
For a signed Mac candidate it also parses the bounded canonical application
archive's `Info.plist`, normalizes an absent or empty
`MacCompanionUpdateUserInitiatedCheckProfile` to `null`, rejects every unknown
value or type, and requires the observed value to match the manifest exactly.
For signed candidates it additionally requires `sbom.document` to be an
[exact-candidate artifact SBOM](../../artifact-sbom/v0/profile.md), validates
its two transitively hashed documents and exact ZIP contents, and binds its
release/source/target/artifact/executable facts to this manifest. A source-only
SPDX document or schema-valid placeholder is rejected at this boundary.
Every executable verification reference must additionally be a canonical
[signed-code construction-correlation bundle](../../signed-code-verification/v0/profile.md)
whose release, source, artifact-SBOM, artifact, executable, member digests, and
four transitive raw references match exactly. Signed-level file verification
also requires exactly one passed `signed-code-graph-construction` validation
record whose evidence is a canonical
[construction-discovery graph](../../signed-code-graph/v0/profile.md). Its
dedicated bounded no-follow loader independently rediscovers every supported
Mach-O member, bundle, architecture, and LaunchAgent edge from the exact
archives; missing evidence returns `missingSignedCodeGraph`, while malformed,
stale, symlinked, incomplete, or invented evidence returns
`invalidSignedCodeGraph`. Signed-level file verification also requires exactly
one passed `signing-policy-contract` record whose evidence is a canonical
[release signing policy](../../signing-policy/v0/profile.md). The CLI accepts
the policy authority only through
`--expected-signing-policy-sha256`, combined with `--verify-files` and exactly
one manifest. The lowercase non-placeholder digest must come from protected
release-runner configuration; the candidate's own policy reference never
authorizes itself. Missing, malformed, stale, symlinked, incompletely bound, or
wrongly pinned policy evidence returns a signing-policy error and suppresses
the platform gate. Supplying a policy pin for `unsignedConstruction` returns
`unexpectedSigningPolicyPin`.

Attach-free correlation never trusts retained Apple-tool reports or the
graph's symbolic `notRun` plan. Only when both construction evidence forms and
the independently pinned policy pass does an otherwise valid signed candidate
return `signedCodePlatformVerificationRequired`. Clearing that result requires
the separate protected collector described by the
[platform signing evidence profile](../../platform-signing-evidence/v0/profile.md),
plus its stable-toolchain and target-specific external gates.
macOS `signedCandidate` and `promotionReady` file verification additionally
requires one passed `mac-packaging-equivalence` validation record whose evidence
is the canonical [Mac packaging-equivalence receipt](../../mac-packaging-equivalence/v0/profile.md).
Absence returns `missingMacPackagingEquivalence`; malformed or mismatched
evidence returns `invalidMacPackagingEquivalence`. Attach-free verification of
an otherwise valid receipt returns
`macPackagingEquivalencePlatformVerificationRequired`. The release job must
explicitly add `--verify-platform-packaging`, which authorizes a read-only DMG
mount, exact payload reinspection, device cleanup, and final rehash of the
receipt, SBOM bundle, ZIPs, and DMG. Release jobs must use both file and platform
verification before retaining or promoting a Mac bundle.

`scripts/create_unsigned_release_evidence.py` creates only
`unsignedConstruction`. It records the current Git revision and dirty state,
active Xcode/Swift/host/SDK versions, fixed compatibility profiles, and a
caller-supplied validation status. The referenced validation log must be a
nonempty file inside a caller-selected evidence root. The generator hashes it,
validates the complete manifest, writes mode `0600` through fsync plus atomic
rename, fsyncs the directory, and refuses overwrite or path escape.

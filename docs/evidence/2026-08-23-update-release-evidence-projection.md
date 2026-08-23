# Update release-evidence projection

Date: 2026-08-23

Status: complete repository gate and the unsigned permanent macOS target pass.
No protected appcast, download, extraction, installation, relaunch, or Agent
lifecycle action ran.

## Outcome

`MacUpdateReleaseEvidenceV0` is the typed bridge between release construction
and runtime candidate admission. It accepts only a closed set of 17 string
attributes from the signed Sparkle enclosure. The exact schema binds:

- profile `maccompanion.update-release-evidence.v1` and level
  `signedCandidate`;
- channel, candidate build, display version, archive URL, archive length, and
  archive Ed25519 signature duplicated exactly from the reviewed item;
- canonical non-placeholder SHA-256 digests for the archive, release manifest,
  platform-signing record, two-phase notarization record, and
  packaging-equivalence receipt; and
- `passed` claims for the complete Developer ID graph, notarization,
  application stapling, and whole-application ZIP.

Missing or extra custom attributes, non-string values, malformed decimal
fields, profile/level substitution, any candidate mismatch, failed claims,
uppercase or placeholder digests, and the empty-content digest all fail closed.
The lower-level validated candidate and admission APIs now accept this typed
value instead of three independent Developer ID, notarization, and whole-ZIP
Booleans.

The permanent Sparkle adapter projects only enclosure keys with the exact
`maccompanion:` prefix and delegates the closed-schema and semantic checks to
the package. An informational result without the complete evidence projection
is not shown as an available update. It retains the exact offer and can consume
it once into an inert admission seed containing the single-use candidate owner
and the typed evidence value. Taking that seed starts no check, download,
runtime shutdown, or installation. Automatic, background, download, and
installation checks remain denied.

## Namespace and cycle audit

The exact Sparkle 2.9.6 parser preserves a non-Sparkle qualified attribute name
from `NSXMLNode.name`. A local Xcode 27 beta Foundation probe confirmed that an
attribute declared under
`https://jenny.media/maccompanion/update-evidence/1` appears as
`maccompanion:evidenceProfile`, with local name `evidenceProfile` and the exact
namespace URI. The release generator must therefore declare that URI and use
the frozen prefix; alternate prefixes are not this v1 wire representation.

The projection binds `signedCandidate`, not `promotionReady`. A promotion-ready
manifest records Sparkle publication evidence, while the final appcast embeds
this projection; hashing each into the other would be impossible. The external
release lane remains responsible for human approval, physical scenarios, and
publication authorization before signing and serving the appcast.

## Verification

Five new tests cover exact acceptance, missing and unknown attributes,
profile/level substitution, invalid candidate encoding, every candidate-field
substitution, each failed release claim, and invalid or placeholder digests.
All 38 focused `MacUpdate` tests pass. The checked-in Xcode project also builds
the code-signing-disabled Debug `MacCompanion` scheme successfully on Xcode 27
beta.

The complete repository gate passes 73 authoritative fixtures, 35 update-policy
fixtures, 1,131 repository files and 1,879 historical blob paths, every
supply-chain, privacy, SBOM, signing, packaging, and release-evidence validator,
1,537 MacCompanionKit tests, 8 platform-probe tests, and every permanent target
and supported cross-platform compile on Xcode 27 beta.

## Deliberate non-claims

This checkpoint defines and consumes the signed publication projection; it
does not create the protected release-job generator, inspect real retained
records, generate or sign an appcast, download or hash an update at runtime, or
invoke Sparkle's extraction, validation, or installation lifecycle. The
protected publisher, callback correlation, foreground confirmation UI, and
concrete runtime-effect bindings remain open.

The later
[validation-correlation checkpoint](2026-08-23-update-validation-correlation.md)
closes the package-owned callback state-machine portion of this non-claim.
The live Sparkle callback bridge and all update actions remain absent.

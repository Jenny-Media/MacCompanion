# Signed update publication binding

Date: 2026-08-23

Status: complete repository gate and the unsigned permanent macOS target pass.
No live feed, download, extraction, installation, relaunch, or Agent lifecycle
action ran.

## Outcome

`MacUpdateFeedCandidateV0` now rejects an informational Sparkle item unless its
appcast signing status succeeded and its enclosure carries both a nonzero
archive length no greater than 4 GiB and one canonical Base64 64-byte Ed25519
signature. Those values join channel, installed build, candidate build, display
version, and canonical archive URL in the immutable reviewed observation.

`MacUpdateInstallCandidateBindingV0` independently requires the later
validation observation to reproduce both the exact archive length and exact
signature. A substituted archive description therefore consumes and closes the
single-use candidate instead of reaching the foreground-confirmed runtime
gate.

The containing-app Sparkle adapter reads these facts only from the admitted
2.9.6 public API and signed enclosure dictionary. Community and development
builds remain inert because they still have no protected feed or Ed25519 key.
All download and installation checks remain denied.

## Exact upstream lifecycle audit

The locally resolved source checkout is exact Sparkle `2.9.6`, revision
`ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a`. Its updater requires
`SUVerifyUpdateBeforeExtraction` when signed feeds are required. The exact
driver ordering shows that `didExtractUpdate` is misleadingly named: it fires
after the installer process accepts its data, before that process
asynchronously prevalidates the archive signature, extracts the application,
validates it, and completes stage-one preparation. The later
`showReadyToInstallAndRelaunch` user-driver callback is the available
post-validation, pre-install hold point.

`didExtractUpdate` cannot mint Mac Companion installation authority at all.
Even the later readiness callback is not platform-signing evidence: Sparkle's
validator explicitly permits an old-key-valid Ed25519 archive to change Apple
code-signing identity, and neither callback nor the appcast item attests Apple
notarization. Mac Companion therefore must not translate either callback into
unconditional `developerIDValidated` or `notarizedReplacement` facts. A
protected release-evidence bridge must bind the exact archive to the required
Jenny Media Developer ID graph, notarized and stapled replacement, and
whole-application ZIP before the readiness hold point can open admission.

## Verification

All 33 focused `MacUpdate` tests pass, including new coverage for missing
signed-feed validation, zero and oversized archives, noncanonical or wrong-size
Ed25519 signatures, and exact length/signature substitution. The checked-in
Xcode project also builds the code-signing-disabled Debug `MacCompanion` scheme
successfully on Xcode 27 beta.

The complete repository gate passes 73 authoritative fixtures, 35 update-policy
fixtures, 1,127 repository files and 1,867 historical blob paths, every
supply-chain, privacy, SBOM, signing, packaging, and release-evidence validator,
1,532 MacCompanionKit tests, 8 platform-probe tests, and every permanent target
and supported cross-platform compile on Xcode 27 beta.

## Deliberate non-claims

No release attestation format, protected appcast, Ed25519 private key, runtime
callback bridge, updater download check, foreground confirmation UI, concrete
shutdown effect, or installation handoff exists at this checkpoint. It proves
signed-publication admission and preserves the distinction between Sparkle
validation and Mac Companion release policy; it does not prove a usable update.

The later
[release-evidence projection](2026-08-23-update-release-evidence-projection.md)
closes the format and typed-binding portion of this non-claim. Protected
appcast generation and every live update action remain absent.

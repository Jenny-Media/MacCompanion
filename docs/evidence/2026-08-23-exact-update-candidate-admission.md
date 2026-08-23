# Exact update candidate admission

Date: 2026-08-23

Status: full repository gate passed. No live feed, download, extraction,
installation, relaunch, or Agent lifecycle action occurred.

## Outcome

The later [runtime shutdown orchestration](2026-08-23-update-runtime-shutdown-orchestration.md)
seals this admission value into the only public production path to the
lower-level authority; this file retains the candidate-correlation checkpoint.

`CompanionLifecycle` now owns the missing anti-substitution bridge between an
informational signed-feed observation and the existing update installation
authority. An informational `MacUpdateFeedCandidateV0` cannot directly create
installation authority, and the lower-level validated-candidate constructor is
no longer public to production consumers.

`MacUpdateInstallCandidateBindingV0` requires a later, independent
post-validation observation to match the reviewed candidate's channel, current
build, candidate build, display version, canonical archive URL, archive length,
and Ed25519 signature exactly. At this checkpoint it also required six frozen
trust facts: signed feed, archive signature, verification before extraction,
Developer ID validation, notarized replacement, and whole-application ZIP. The
later
[signed-publication binding](2026-08-23-signed-update-publication-binding.md)
added the length and signature fields after auditing the exact Sparkle 2.9.6
lifecycle, and the subsequent
[release-evidence projection](2026-08-23-update-release-evidence-projection.md)
replaced the final three free Booleans with one closed typed evidence value.

`MacUpdateInstallCandidateAdmissionV0` owns one feed candidate and can mint at
most one `MacUpdateInstallAuthorityV0`. Success, mismatch, missing trust,
cancellation, and attempted reuse all consume the observation. A later updater
callback therefore cannot be confused with an item that the user did not
review.

## Verification

Five focused tests cover exact admission, every substituted candidate field,
every missing trust fact, single-use authority creation, mismatch consumption,
cancellation, and retry denial. All 26 focused `MacUpdate` tests pass.

The complete repository gate passes 73 authoritative fixtures, all supply-chain,
privacy, SBOM, signing, packaging, and release-evidence validators, 1,525
MacCompanionKit tests, 8 platform-probe tests, and every permanent target and
cross-platform compile on Xcode 27 beta.

## Deliberate non-claims

This checkpoint provides a bundle-independent value and authority boundary. It
does not claim that an informational appcast item proves a downloaded archive
or replacement bundle. The containing-app adapter must obtain the Sparkle-owned
facts from the exact validation/install lifecycle and bind protected release
evidence for the Developer ID and notarization facts. It must then map the
runtime authority's effects to real network, bounded-work, Agent, and recovery
owners.

No protected feed or Ed25519 key exists in the tracked build. No updater check,
download, extraction, installation handler, runtime shutdown, Agent action, or
relaunch ran. The Sparkle callback bridge, foreground confirmation UI, concrete
lifecycle orchestration, two-version signed upgrade matrix, and failure
recovery evidence remain open.

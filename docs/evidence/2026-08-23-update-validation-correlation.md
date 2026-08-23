# Update validation correlation

Date: 2026-08-23

Status: complete repository gate and the unsigned permanent macOS target pass.
No protected appcast, download, extraction, installation, relaunch, or Agent
lifecycle action ran.

## Outcome

`MacUpdatePublishedCandidateV0` keeps one informational candidate and its
closed signed release-evidence projection inseparable. Construction requires
the evidence to bind the candidate's exact channel, candidate build, display
version, canonical archive URL, content length, and Ed25519 signature.

`MacUpdateValidationCorrelationV0` retains that full publication and accepts
only one ordered sequence:

1. one exact `willExtract` publication observation; then
2. one exact `didExtract` publication observation.

Both observations must equal the retained publication, including current build
and all five evidence digests and release claims. Mismatch, evidence
substitution, callback reordering, repeated callbacks, cancellation, concurrent
reuse, or a failed lower-level admission closes the actor and its admission
owner permanently. The actor closes before its awaited admission call, so Swift
actor reentrancy cannot mint a second admission.

The lower-level `MacUpdateInstallCandidateAdmissionV0` is now package-internal.
It retains the complete publication, accepts only the post-extraction call from
the correlation actor, and no longer exposes release evidence or three runtime
trust Booleans to the containing app. The permanent Sparkle adapter consumes a
reviewed offer once into the correlation actor rather than exposing those
lower-level pieces separately.

## Trust boundary

This state machine assigns meaning to the exact Sparkle 2.9.6 delegate order
audited in the preceding signed-publication checkpoint. With the frozen signed
feed and verify-before-extraction configuration, a matching
`didExtractUpdate` follows successful archive extraction and Sparkle validation.
It still does not attest Jenny Media Developer ID identity or Apple
notarization; those remain signed protected release-evidence claims.

The containing-app adapter must construct each publication observation directly
from the matching `SUAppcastItem`. An arbitrary caller-created value is not
independent platform evidence. The signed release publisher, signed appcast,
Sparkle delegate bridge, foreground confirmation UI, and physical update test
remain separate gates.

## Verification

Seven tests cover exact publication construction, one successful ordered
sequence, missing and repeated callbacks, candidate and evidence substitution,
cancellation before and during extraction, terminal reuse, and two concurrent
`didExtract` calls producing exactly one admission. All 45 focused `MacUpdate`
tests pass. The checked-in Xcode project also builds the code-signing-disabled
Debug `MacCompanion` scheme successfully on Xcode 27 beta.

The complete repository gate passes 73 authoritative fixtures, 35 update-policy
fixtures, 1,134 repository files and 1,895 historical blob paths, every
supply-chain, privacy, SBOM, signing, packaging, and release-evidence validator,
1,544 MacCompanionKit tests, 8 platform-probe tests, and every permanent target
and supported cross-platform compile on Xcode 27 beta.

## Deliberate non-claims

This checkpoint does not wire Sparkle's `willExtractUpdate` or
`didExtractUpdate` delegate callbacks and does not add a full update check,
download, extraction, shutdown effect, installation handoff, relaunch, or live
feed. It proves the inert package boundary that a later foreground-confirmed
runtime integration must use.

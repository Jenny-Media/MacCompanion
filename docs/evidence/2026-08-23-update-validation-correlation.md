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
2. one exact installer-start observation translated from Sparkle's
   `didExtractUpdate`; then
3. one installation-readiness event translated only from
   `showReadyToInstallAndRelaunch`.

Both item-bearing observations must equal the retained publication, including
current build and all five evidence digests and release claims. Mismatch, evidence
substitution, callback reordering, repeated callbacks, cancellation, concurrent
reuse, or a failed lower-level admission closes the actor and its admission
owner permanently. `didExtractUpdate` cannot mint admission. The actor closes
before its awaited ready-to-install admission call, so Swift actor reentrancy
cannot mint a second admission.

The lower-level `MacUpdateInstallCandidateAdmissionV0` is now package-internal.
It retains the complete publication, accepts only the prepared-update call from
the correlation actor, and no longer exposes release evidence or three runtime
trust Booleans to the containing app. The permanent Sparkle adapter consumes a
reviewed offer once into the correlation actor rather than exposing those
lower-level pieces separately.

## Trust boundary

The exact Sparkle 2.9.6 source audit corrects the callback meaning used by the
initial checkpoint. `SPUCoreBasedUpdateDriver` invokes `willExtractUpdate`,
starts `SPUInstallerDriver`, and invokes `didExtractUpdate` as soon as that
driver accepts the installation data. `AppInstaller` performs archive
prevalidation, extraction, validation, and stage-one preparation
asynchronously after that acknowledgement. Only after stage one succeeds does
`SPUUIBasedUpdateDriver` invoke
`showReadyToInstallAndRelaunch(reply:)`; forwarding `.install` from that reply
is the actual pre-install hold point available to Mac Companion.

Neither event attests Jenny Media Developer ID identity or Apple notarization;
those remain signed protected release-evidence claims.

The containing-app adapter must construct each item-bearing publication
observation directly from the matching `SUAppcastItem`. It must subclass or
proxy `SPUStandardUserDriver`, route
`showReadyToInstallAndRelaunch(reply:)` through the foreground-confirmed
runtime coordinator, and forward `.install` only after that coordinator
succeeds. An arbitrary caller-created value is not independent platform
evidence. The signed release publisher, signed appcast, Sparkle delegate and
user-driver bridge, foreground confirmation UI, and physical update test remain
separate gates.

## Verification

Seven tests cover exact publication construction, one successful three-stage
sequence, missing, reordered, and repeated callbacks, candidate and evidence
substitution, cancellation at every phase, terminal reuse, and two concurrent
ready-to-install calls producing exactly one admission. All 45 focused
`MacUpdate` tests pass. The checked-in Xcode project also builds the
code-signing-disabled Debug `MacCompanion` scheme successfully on Xcode 27
beta.

The complete repository gate passes 73 authoritative fixtures, 35 update-policy
fixtures, 1,134 repository files and 1,908 historical blob paths, every
supply-chain, privacy, SBOM, signing, packaging, and release-evidence validator,
1,544 MacCompanionKit tests, 8 platform-probe tests, and every permanent target
and supported cross-platform compile on Xcode 27 beta.

## Deliberate non-claims

This checkpoint does not wire Sparkle's `willExtractUpdate` or
`didExtractUpdate` delegate callbacks, subclass or proxy its standard user
driver, or add a full update check, download, extraction, shutdown effect,
installation handoff, relaunch, or live feed. It proves the inert package
boundary that a later foreground-confirmed runtime integration must use.

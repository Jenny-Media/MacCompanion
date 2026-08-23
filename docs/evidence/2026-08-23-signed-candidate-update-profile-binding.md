# Signed-Candidate Update-Profile Binding

Date: 2026-08-23
Toolchain: Xcode 27 beta (`27A5218g`), provisional pending stable Xcode 26.6
Runtime effects: none

## Outcome

Release evidence advances from v0.1 to v0.2 because the closed manifest gains
one required compatibility fact:
`macUserInitiatedUpdateCheckProfile`. It is `null` for information-only Mac
checks or exactly
`maccompanion.user-initiated-full-update-check.v1` for the reviewed visible,
foreground full-check route. It must be `null` when macOS is not a target.

Signed-candidate file verification no longer trusts that declaration alone.
After exact artifact-SBOM archive validation, it reads the single bounded
`Mac Companion.app/Contents/Info.plist` member from the hash-bound canonical
application ZIP. An absent or empty property is normalized to `null`. Unknown
values, non-string values, ambiguous or invalid property lists, archive
mutation, and declaration/payload mismatch reject the candidate before the
platform packaging and promotion gates.

The local Developer ID packaging lane applies the same normalization, rejects
unknown profiles before producing artifacts, and records the normalized value
in `local-package-summary.json`. Adding that field advances the closed local
summary schema to `maccompanion.local-mac-package.v0.2`; the summary remains
explicitly non-promotional.

## Verification

- 18 release-evidence fixtures pass, including unknown-profile rejection.
- 14 local Mac packaging cases pass, covering information-only, exact full
  foreground, unknown-profile rejection, and non-string rejection.
- 26 artifact-SBOM fixtures, 14 exact-candidate release integration cases, and
  4 iOS/combined graph cases pass. A manifest that claims unshipped full-check
  authority is rejected.
- 24 packaging-equivalence fixtures, 8 mounted-tree model cases, 5 release
  integrations, and the recovery/concurrency cases pass without a real mount.

No app, Agent, login role, listener, XPC session, update check, feed request,
download, extraction, updater, installer, network action, signing action,
notarization action, or disk-image mount ran.

The complete repository gate exits zero with 1,605 package tests plus 8
platform probes.

## Remaining gate

This proves candidate configuration integrity, not update safety. The protected
lane still must retain signed old-to-new evidence for `Not Now`, foreground
loss, Control-active and cleanup-uncertain denial, listener and Agent recovery,
successful handoff/relaunch, forced process loss, rollback, and clean-machine
behavior before an external beta carries the full-check profile.

# Closed Mac Update Physical-Evidence Matrix

Date: 2026-08-23
Toolchain: Xcode 27 beta (`27A5218g`), provisional pending stable Xcode 26.6
Runtime effects: none

## Outcome

Mac Companion now has a canonical
`maccompanion.mac-update-physical-evidence.v0.1` record for the protected
signed old-to-new lane. The record binds the exact beta/stable candidate,
clean source revision, reviewed full foreground update-check profile, and the
release's canonical app ZIP, DMG, and Sparkle archive. It also identifies a
lower source build under the official bundle identifier and one signing Team
ID.

The matrix has exactly twelve ordered cases: `Not Now`, foreground loss,
Control-active denial, cleanup-uncertain denial, forced loss before quiescence,
after quiescence, after Agent stop, successful upgrade, forced loss after
installer handoff, rollback, clean-user upgrade, and no background network.
Every case fixes its terminal outcome and exact observed source or candidate
version/build. Only clean-user upgrade may claim a fresh user.

The source installation and all twelve cases use distinct relative evidence
paths with bounded non-placeholder hashes and sizes. Verification performs
descriptor-bound, no-follow, bounded reads, rejects hard links and mutation,
and checks every transitive file. For a promotion-ready Mac release, `upgrade`
and `rollback` must reference the same canonical matrix; a divergent, opaque,
stale, information-only, or candidate-substituted record returns
`invalidMacUpdatePhysicalEvidence`.

## Verification

Sixteen focused cases cover canonical round trip and release integration plus
unknown fields, missing/reordered cases, outcome/build/fresh-user
substitution, candidate/profile/source substitution, duplicate observations,
content mutation, noncanonical JSON, symlinks, and release-level candidate
substitution.

No app, Agent, login role, listener, XPC session, update check, feed request,
download, extraction, updater, installer, network action, rollback, signing,
notarization, disk-image mount, or publication ran.

## Remaining gate

The schema proves correlation and completeness, not truth. The protected lane
must still build two signed/notarized versions with stable Xcode 26.6, execute
all twelve cases on physical Macs, retain reviewable observations, satisfy the
separate clean-install/permission/uninstall/quarantine gates, and obtain human
promotion approval.

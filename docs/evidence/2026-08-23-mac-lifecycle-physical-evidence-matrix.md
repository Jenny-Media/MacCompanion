# Closed Mac Lifecycle Physical-Evidence Matrix

Date: 2026-08-23
Toolchain: Xcode 27 beta (`27A5218g`), provisional pending stable Xcode 26.6
Runtime effects: none

## Outcome

Mac Companion now requires one canonical
`maccompanion.mac-lifecycle-physical-evidence.v0.1` record for the four
non-update macOS promotion scenarios. It binds the exact clean beta/stable
candidate, official identity, reviewed full-check profile, and canonical app
ZIP, DMG, and Sparkle archive.

The record fixes four ordered cases and their terminal state: quarantined
Gatekeeper launch without bypass, genuinely clean explicit enablement through
authenticated Agent readiness, safe remote denial with local administration
after Screen Recording and Accessibility revocation, and complete removal with
no version/build remaining. The uninstall assertions cover remote disablement,
login-role unregistration, listener absence, pairing revocation, product-data
removal, no privileged helper, and no silent authority restoration on
reinstall.

All four cases retain distinct bounded observations. Descriptor-bound,
no-follow verification rejects hard links, symlinks, path escape, mutation,
unknown fields, case/assertion reorder or substitution, duplicate evidence,
noncanonical JSON, and release-candidate mismatch. Release verification
requires all four scenario references to name the same canonical record.

## Verification

Sixteen focused cases cover canonical round trip, release integration,
structural and semantic substitutions, content mutation, noncanonical JSON,
symlink rejection, and divergent release-scenario references.

No app, Agent, login role, listener, permission, pairing, product data,
installer, network, signing, notarization, mount, or publication action ran.

## Remaining gate

The profile proves correlation and completeness, not truthful observation.
The protected lane must still execute all four cases on signed physical Macs,
retain reviewable evidence, and obtain human promotion approval.

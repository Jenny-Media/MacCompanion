# Closed iOS Physical-Evidence Record

Date: 2026-08-23
Toolchain: Xcode 27 beta (`27A5218g`), provisional pending stable Xcode 26.6
Runtime effects: none

## Outcome

Mac Companion now requires one canonical
`maccompanion.ios-physical-evidence.v0.1` record across all three iOS promotion
scenarios. It binds a fresh passcode-protected arm64 device, exact clean
beta/stable source, official iOS identity, and exact iOS archive.

Physical pairing must retain QR expiry, host-pin, two-device SAS, local-name,
session/approval-key custody, durable-before-visible publication, one Observe
status, and one explicitly approved and observed `setAudioMuted`. Local Network
denial must publish neither a route nor broader authority and later recover
under the same pin after a Settings grant. Background reconnect must close
Interactive Control, retire lost routes, respect first unlock, revalidate the
pin, avoid operation replay, and require fresh presence for Control.

All three observations are distinct bounded files. Descriptor-bound,
no-follow verification rejects hard links, symlinks, path escape, mutation,
unknown fields, missing/reordered assertions, device/candidate substitution,
duplicate evidence, noncanonical JSON, and divergent scenario references.

## Verification

Sixteen focused cases cover canonical round trip, release integration,
structural and semantic substitutions, device-posture denial, content mutation,
noncanonical JSON, symlink rejection, and divergent release references.

No app installation or launch, camera or Local Network prompt, QR scan,
pairing, Observe/Act request, network route, background transition, reconnect,
signing, TestFlight, App Store, or publication action ran.

## Remaining gate

The record proves correlation and completeness, not truthful device behavior.
The protected lane must still execute all three cases on signed physical
iPhone/iPad hardware, retain accessibility and Data Protection observations,
bind TestFlight/App Store evidence, and obtain human promotion approval.

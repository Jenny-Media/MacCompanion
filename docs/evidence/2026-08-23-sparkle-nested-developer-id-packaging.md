# Sparkle nested Developer ID packaging checkpoint

Date: 2026-08-23

Status: local construction evidence passed on Xcode 27 beta. No artifact was
installed, launched, notarized, uploaded, or published.

## Outcome

A clean Release archive built from revision
`f4e87aa576c9bdf61ad1af12e3cc4266aedcbe30` exposed an important defect in the
first Sparkle-enabled Developer ID archive: the containing app, embedded Agent,
and outer Sparkle framework used the expected Developer ID identity, but the
retained `Autoupdate` executable and `Updater.app` were still ad-hoc signed.
Outer `codesign --deep --strict` verification accepted that mixed topology, so
it was not sufficient evidence for the retained nested-code graph.

The archive sanitizer now signs the retained Sparkle subjects deepest-first
with the release identity, hardened runtime, and secure timestamp, then
strictly verifies each subject. The local packager independently requires all
five exact subjects, their identifiers, executable paths, Developer ID
authority, timestamps, hardened runtime, and one common team. It also proves
that both unused XPC-service paths and all release tools are absent.

The 11-case packaging validator rejects missing or substituted nested helpers,
ad-hoc signatures, team mismatch, unsafe archive layout, invalid identity or
version inputs, partial failure, overwrite, and publication races. The full
repository gate passed with 1,520 MacCompanionKit tests and 8 platform-probe
tests.

## Exact signed topology

Independent inspection of the clean archive accepted these universal
arm64/x86_64 subjects:

| Subject | Required identifier | Result |
| --- | --- | --- |
| `Mac Companion.app` | `media.jenny.maccompanion` | Developer ID, secure timestamp, hardened runtime |
| embedded Agent | `media.jenny.maccompanion.agent` | Developer ID, secure timestamp, hardened runtime |
| `Sparkle.framework` | `org.sparkle-project.Sparkle` | Developer ID, secure timestamp, hardened runtime |
| `Autoupdate` | `Autoupdate-5555494467dcbc6056da3300b22db5f67fff8b2d` | Developer ID, secure timestamp, hardened runtime |
| `Updater.app` | `org.sparkle-project.Sparkle.Updater` | Developer ID, secure timestamp, hardened runtime |

The private signing team and identity were supplied only to the build and
packaging invocations and are not recorded in tracked evidence.

## Local package evidence

The clean archive was packaged in the private temporary root
`/private/tmp/maccompanion-sparkle-resign.PtVpcj`. The output summary retained
all promotion claims as false and recorded:

```text
Mac Companion.app.zip
  bytes: 13301944
  sha256: ed903db0ee811afe9d14b96870cd26e3d71fb20520e8862094969988e9fb7b11

MacCompanion-0.1.0.zip
  bytes: 13301944
  sha256: ed903db0ee811afe9d14b96870cd26e3d71fb20520e8862094969988e9fb7b11

MacCompanion-0.1.0.dmg
  bytes: 13397277
  sha256: 18626afe58853231cbb96650d5444fa138bc80da3588db48f6ef0e7d87254c10
```

The two ZIPs are byte-identical. Explicit read-only APFS inspection proved that
both ZIPs and the DMG contain the same 117-entry, 35,313,420-byte application
tree with canonical entry hash
`e6a0267210b458cfab5259da26839f30e1041ec9573c7997d535a8faedd42b92`.
The DMG root contains exactly `Mac Companion.app` and
`Applications -> /Applications`; the private mount detached cleanly.

The built property list keeps the release-authority profile, channel, feed URL,
and public key empty. Automatic checks, downloads, update installation, runtime
profiling, and profile submission are false; signed feeds and verification
before extraction remain required.

## Deliberate non-claims

Gatekeeper rejects both the app and DMG with
`source=Unnotarized Developer ID`, and stapler reports no ticket. The update ZIP
has no Ed25519 signature or appcast entry. The package summary therefore keeps
`notarized`, `stapled`, `sparkleArchiveSigned`, and `promotionReady` false.

This is a local construction checkpoint, not a signed candidate or release.
Stable Xcode reproduction, both authorized notarization phases, app and DMG
stapling, post-staple byte correlation, final Gatekeeper acceptance, Sparkle
archive/appcast signing, reviewed licenses, physical clean-install and upgrade
evidence, and human promotion approval remain required.

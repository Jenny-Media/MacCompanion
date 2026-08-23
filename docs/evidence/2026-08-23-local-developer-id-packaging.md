# Local Developer ID packaging checkpoint

Date: 2026-08-23

## Outcome

A fresh Release `.xcarchive` built with Xcode 27 beta from clean revision
`81b71377072f578083a56ab63954879222fde9a2`. The signing team and identity were
supplied only to the build invocation. Strict recursive verification accepted
the universal containing app and embedded Agent. Both use the canonical
identifiers, the same Developer ID team, secure timestamps, and hardened
runtime.

`scripts/package_mac_release.py` now turns an already signed archive into a
local construction candidate without notarizing, installing, launching, or
publishing it. The command:

- verifies the exact app and Agent identifiers, Developer ID authority,
  timestamps, hardened runtime, and same-team relationship before packaging;
- creates one canonical application ZIP and a byte-identical unsigned Sparkle
  update ZIP;
- stages only `Mac Companion.app` plus the `/Applications` link;
- creates a compressed APFS disk image through macOS 27's supported
  `diskutil image create from` interface;
- signs and re-verifies the DMG against the app's signing team;
- publishes the completed directory with `RENAME_EXCL`; and
- emits a machine-readable local summary that explicitly keeps notarization,
  stapling, Sparkle signing, and promotion false.

Eight injected cases prove the fixed creation/signing command shapes, exact
archive layout, unsafe version and identity rejection, no-overwrite behavior,
partial-failure cleanup, and a publication race that preserves the competing
directory. The validator is part of `scripts/validate.sh`.

## Real candidate evidence

The production command completed against the real archive in an isolated
private temporary directory. Independent inspection recorded:

```text
Mac Companion.app.zip
  bytes: 12305472
  sha256: 2b6d67d631477fef80ec870b7a46e9ac2f52b3e395b15d7e5f293711269be792

MacCompanion-0.1.0.zip
  bytes: 12305472
  sha256: 2b6d67d631477fef80ec870b7a46e9ac2f52b3e395b15d7e5f293711269be792

MacCompanion-0.1.0.dmg
  bytes: 12459805
  sha256: 285881e4b8a4728b552832eb3c7c5b3d0f0752e6d47197e5928177bc0223a4c5
```

The exact-candidate artifact-SBOM generator accepted both ZIPs. The guarded
read-only DMG inspector then proved all three containers carry the same
14-entry, 32,720,664-byte application tree with tree SHA-256
`94822126d7129f00ab891248eeaff15f802b51caa02498e4621e3de024844e1a`.
The DMG root is one read-only APFS volume containing exactly
`Mac Companion.app` and `Applications -> /Applications`. Cleanup detached the
private inspection mount without force.

The DMG itself passes strict Developer ID signature verification with a secure
timestamp and the same private team as the app. A restricted-sandbox
`codesign` invocation transiently reported an invalid signature, but the
trusted signing lane immediately re-inspected the unchanged digest and
accepted it. Only the trusted-lane result is counted.

## Deliberate non-claims

Gatekeeper rejects both the extracted app and the signed DMG with
`source=Unnotarized Developer ID`. Stapler reports that neither carries a
ticket. The Sparkle ZIP has no Ed25519 signature or appcast entry. This is not
a signed-candidate or promotion-ready release, was not copied into
Applications, and was not distributed.

The final release path still requires stable Xcode 26.6 reproduction, two
explicitly authorized notarization submissions, app and DMG stapling,
post-staple byte correlation, final Gatekeeper acceptance, Sparkle integration
and signature evidence, reviewed licenses, physical clean-install scenarios,
and human promotion approval.

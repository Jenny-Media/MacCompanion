# Sparkle 2.9.6 provenance and topology audit

Date: 2026-08-23

Status: local dependency-admission evidence. This checkpoint does not add a
Swift package, framework, feed, public key, updater adapter, download, signing
key, or update action.

## Exact authority inspected

The audit used an isolated clean checkout of
`https://github.com/sparkle-project/Sparkle` at full revision
`ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a`, the commit referenced by the
upstream 2.9.6 release. Its `Package.swift` is a binary-only Swift package: one
product and one binary target named `Sparkle`, with an official
`Sparkle-for-Swift-Package-Manager.zip` checksum.

The independently downloaded release asset and checkout produced these exact
facts:

- upstream `Package.swift` SHA-256:
  `076e7810d9a463f3d7f034f9429bd5dcb3ed72203d06e1636f221668ec327962`;
- SwiftPM archive SHA-256 and upstream-declared checksum:
  `8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606`;
- source and archive `LICENSE` SHA-256:
  `389a4e4e9a32f059775b13a06e25a591445ba229d2838d26dd3e7c0c45127cfe`;
- 226 archive entries and 30,161,894 total uncompressed bytes;
- nine exact relative framework symlinks, with no absolute or escaping target;
- nine Mach-O members: five framework/runtime objects and four release tools;
  the legacy signing script is executable text, and `SampleAppcast.xml` has an
  executable mode but is not code; and
- no `PrivacyInfo.xcprivacy` in either the exact source tree or archive.

The license is MIT-style for Sparkle and retains the bundled notices for its
bsdiff/bspatch, sais-lite, and Ed25519 components. It is suitable input to the
final third-party notices and artifact SBOM review; this engineering audit is
not legal approval.

`scripts/audit_sparkle_provenance.py` now rechecks the clean revision, all
three digests, bounded ZIP shape, duplicate/path/type/CRC safety, complete
symlink inventory, exact executable-mode and Mach-O inventories, equal license
bytes, and the recorded absence of a privacy manifest. It consumes only
already acquired paths and performs no network operation or extraction.

## Signed-code and privacy findings

The archive contains universal arm64/x86_64 builds of the framework,
`Autoupdate`, `Updater.app`, `Installer.xpc`, and `Downloader.xpc`. The supplied
ad-hoc Hardened Runtime signatures pass strict whole-framework verification.
They have no Team ID; the framework identifier is
`org.sparkle-project.Sparkle`, Updater is
`org.sparkle-project.Sparkle.Updater`, Installer is
`org.sparkle-project.InstallerLauncher`, and Downloader is
`org.sparkle-project.DownloaderService`. Updater and both XPC services have
empty entitlement dictionaries. Autoupdate has only the upstream
`com.apple.application-identifier` value. These are acquisition facts, not the
final Jenny Media signing state.

Sparkle can add system profile facts and delegate-provided parameters to feed
requests. The audited implementation reads `SUSendProfileInfo` for the former
and calls `feedParametersForUpdater:sendingSystemProfile:` for the latter.
Mac Companion therefore explicitly denies both paths: it will keep
`SUEnableSystemProfiling` and `SUSendProfileInfo` false, set
`sendsSystemProfile` false in the runtime adapter, and return no custom feed
parameters. This is stronger than relying on the current absent-value default.

Apple's current [required third-party SDK list](https://developer.apple.com/support/third-party-SDK-requirements/)
does not name Sparkle, but Apple still makes the app developer responsible for
all included third-party code and its data behavior. The containing app's
privacy manifest and release privacy report remain required; the missing
upstream manifest is a recorded fact to re-review on every dependency change,
not an exemption.

## Topology decision

Mac Companion is a non-sandboxed direct-distribution app. Sparkle's official
[sandboxing guide](https://sparkle-project.org/documentation/sandboxing/)
states that its Installer and Downloader XPC services serve sandboxed apps and
may be removed when they are not enabled. It also states that archive/export
re-signs nested helpers, while manual signing must proceed inside-out and must
not use `--deep` as a signing shortcut.

The admitted final app topology is therefore:

- `Sparkle.framework/Versions/B/Sparkle`;
- `Sparkle.framework/Versions/B/Autoupdate`; and
- `Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater`.

The copied framework excludes `Installer.xpc` and `Downloader.xpc`. Release
tools such as `generate_appcast`, `sign_update`, `generate_keys`,
`BinaryDelta`, and the legacy signing script never enter the application.
Archive/export must re-sign every retained nested object with the release
identity. The final signed-code graph, entitlements, architectures, Developer
ID, notarization, app ZIP, and DMG remain subject to the existing exact-artifact
release gates.

## Dependency integration decision

The current repository policy still correctly rejects all remote packages,
binary targets, `Package.resolved`, and Xcode remote references. Adding Sparkle
must change that policy atomically with the real graph. The narrow exception
will require all of the following together:

1. XcodeGen declares only the official repository at exact version `2.9.6`;
2. the generated/resolved graph binds that version to the full audited
   revision;
3. the upstream manifest, archive checksum, binary-target name, and license
   match this v0.2 update policy;
4. no other remote dependency, binary target, registry package, or build-tool
   plugin becomes admissible; and
5. archive builds strip the two XPC services and validate the exact retained
   graph before signing and promotion.

This resolves the admission design without weakening the live dependency
boundary before the actual dependency and its build enforcement exist.

## Verification

The local audit passed:

```text
Validated Sparkle 2.9.6 provenance: revision ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a, 226 archive entries, 30161894 uncompressed bytes, exact license and executable topology.
Validated 35 update-policy fixtures and exclusive writer behavior.
```

The upstream 2.9.6 release records additional installer and symlink hardening;
the broader [Sparkle security history](https://sparkle-project.org/documentation/security-and-reliability/)
also shows why the exact modern pin and XPC minimization matter. Integration,
live feed behavior, final nested re-signing, notarization, and a signed
two-version upgrade remain open and must be proved rather than inferred from
this artifact audit.

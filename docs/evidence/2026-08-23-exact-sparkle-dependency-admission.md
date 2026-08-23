# Exact Sparkle dependency admission

Date: 2026-08-23

Status: passed for exact package resolution, unsigned archive construction,
privacy declarations, and minimized embedded topology. No updater object, feed,
key, appcast, download, installation, signing, notarization, or app launch was
performed by this checkpoint.

## Dependency graph

XcodeGen 2.46.0 now declares the sole remote package as the official
`https://github.com/sparkle-project/Sparkle` repository with
`exactVersion: 2.9.6`. Only the `MacCompanion` containing-app target consumes
the `Sparkle` product. Xcode resolution wrote the shared lockfile at
`MacCompanion.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
with exactly one pin:

- identity `sparkle`;
- kind `remoteSourceControl`;
- version `2.9.6`; and
- full revision `ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a`.

The dependency policy is now v1. Its four repository `Package.swift` manifests
remain an all-local closed graph. Separately, its sole Xcode-package exception
binds the repository, exact version, resolved revision, binary target/product,
consumer target, upstream manifest digest, binary archive digest, license
digest, lockfile path, and archive-build sanitizer path and digest. Twelve
existing package-manifest fixtures and twelve new Xcode dependency fixtures
reject a range, repository/revision substitution, extra package or lockfile,
consumer change, sanitizer drift/omission, profiling, sandbox-topology change,
and extra generated remote reference. Every unlisted remote package, binary
target, registry dependency, and every build-tool plugin remains denied.

## Privacy and Local Network declaration

The Mac target now uses a tracked XcodeGen-authored `Info.plist` rather than a
generated property list that silently omitted unrecognized Sparkle keys. The
source and built application declare:

- `SUEnableSystemProfiling = false`;
- `SUSendProfileInfo = false`;
- the sole Bonjour type `_maccompanion._tcp`; and
- a truthful Local Network description explaining direct, no-relay access.

The permanent Mac-target validator requires the complete closed property-list
shape, while the dependency validator independently rechecks the four values
that matter to the admitted package. The future runtime adapter must also set
Sparkle's `sendsSystemProfile` property false and provide no custom feed
parameters before any check is allowed.

## Archive sanitizer and measured result

`scripts/strip_sparkle_xpc_services.sh`, SHA-256
`34b057baff1b245f807650b1ab183fd51ce71616e1fae64ef857458f83b01261`,
runs only for Xcode's `install` action after dependency embedding. It resolves
one guarded path inside the target build directory, removes both the versioned
XPC directory and its root alias, proves their absence, proves all three
required executables remain regular and executable, rejects bundled release
tools, and signs `Updater.app`, `Autoupdate`, and then the outer framework
deepest-first for signed install builds without using `--deep` for repair. It
strictly verifies each retained nested subject before the containing app is
signed. Normal non-archive builds do not mutate the framework.

An unsigned universal Release archive built successfully with Xcode 27 beta.
Inspection of the resulting app proved:

- its main executable links
  `@rpath/Sparkle.framework/Versions/B/Sparkle` at current version 2.9.6;
- the framework contains exactly three Mach-O objects: `Sparkle`,
  `Autoupdate`, and `Updater.app/Contents/MacOS/Updater`;
- all three are arm64 plus x86_64;
- no `XPCServices` path or `.xpc` bundle remains;
- no `BinaryDelta`, `generate_appcast`, `generate_keys`, or `sign_update`
  enters the app; and
- the built property list retains both false profiling values, the one Bonjour
  service, the Local Network explanation, and release version `0.1.0`.

## Source SBOM correction

The deterministic source dependency SBOM no longer claims a two-package,
external-dependency-free release graph. It now records Mac Companion,
MacCompanionKit, and exact Sparkle 2.9.6, including the full revision and three
audited digests in the Sparkle package comment, plus the containing app's
`DEPENDS_ON` relationship. `filesAnalyzed`, license conclusion, and license
declaration remain `NOASSERTION`/false where appropriate; engineering license
inspection does not impersonate final legal approval. All ten adversarial SBOM
fixtures and a generated document pass.

## Remaining gates

This proves acquisition and unsigned archive topology, not release trust.
Still required are a permanent Sparkle adapter with no profile/custom feed
parameters, feed-authority injection, user-facing update UI, signed-feed and
Ed25519 validation, Developer ID nested re-sign inspection, two-version update
and failure recovery, notarization/stapling, exact candidate SBOM and packaging
equivalence, and physical clean-machine acceptance. The earlier Developer ID
package must be rebuilt because adding Sparkle materially changed its signed
code graph.

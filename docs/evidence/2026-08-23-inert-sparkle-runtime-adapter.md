# Inert Sparkle runtime adapter

Date: 2026-08-23

Status: full repository gate passed. The adapter has no usable release authority
in the tracked build, performed no update check, and cannot download or install
an update.

## Release authority

`MacUpdateReleaseAuthorityV0` is a package-level public-value boundary. It
accepts only profile `maccompanion.sparkle-release-authority.v1`, channel `beta`
or `stable`, one canonical ASCII HTTPS `.xml` feed URL, and one canonical Base64
32-byte Ed25519 public key. It rejects credentials, explicit ports, query,
fragment, localhost, `.local`, path ambiguity, non-HTTPS URLs, unknown channels,
and malformed or wrong-width keys without doing I/O.

The tracked Mac property list contains only build-setting placeholders for the
profile, channel, feed, and `SUPublicEDKey`. Missing or empty values are a
supported inert state. Partial, unresolved, or invalid values produce an
explicit invalid-configuration UI state and construct no Sparkle object. The
repository contains no usable feed URL or release key.

## Sparkle boundary

`MacCompanionSparkleAdapterV0` is owned only by the containing app and is
constructed side-effect free. After complete release authority is present,
application launch may construct `SPUStandardUserDriver` and `SPUUpdater`, but
sets system profiling, automatic checks, automatic downloads, and custom HTTP
headers off before starting Sparkle. Static property-list values independently
disable automatic checks, downloads, and installation while requiring signed
feeds and update verification before extraction. The delegate returns no feed
parameters and no allowed system-profile keys.

The local menu footer exposes only an explicit `Check for Updates` action. That
action mints one in-memory permit for Sparkle's informational probe method.
Delegate admission accepts only `SPUUpdateCheck.updateInformation`; ordinary
user checks and background checks remain denied. The proceed delegate likewise
admits only the informational driver and rejects cross-channel items,
informational-only items, installer packages, deltas, and noncanonical or
non-HTTPS whole-application ZIP URLs, so no archive is downloaded or installed.
The UI retains only a bounded display version and canonical numeric build from
an available item; remote error detail is not rendered.

## Verification

- The complete `CompanionLifecycle` source, including the new authority, passed
  Swift 6 type checking at the package's macOS floor.
- The adapter passed Swift 6 type checking against the exact audited Sparkle
  2.9.6 XCFramework and the current lifecycle module.
- All three permanent containing-app Swift sources passed one combined type
  check against current package products, the local XPC C module map, and exact
  Sparkle 2.9.6.
- Nine focused Swift Testing declarations pass, including eleven mutated feed
  URLs and eleven mutated archive URLs. A separate executable runtime check
  accepted the canonical beta authority and rejected all eleven
  unsafe/ambiguous feed mutations.
- The permanent Mac/Agent and iOS topology validators pass; the Mac validator
  now requires the exact static privacy/automatic-update keys, release
  placeholders, local lifecycle product, informational-probe call, and absence
  of ordinary/background checks, URLSession, dynamic feed setters, or enabled
  profiling/automatic settings.
- Property-list, JSON, shell syntax, and diff-hygiene checks remain clean.
- The public `scripts/validate.sh` gate passes all permanent policy, privacy,
  SBOM, signing, packaging, release-evidence, Swift package, app/UI compile, and
  disposable platform-probe phases: 1,520 MacCompanionKit tests plus 8
  PlatformAuthorityProbe tests. Its test-log `mktemp` template is now valid for
  BSD/macOS and still deletes the private transient log on exit.

## Remaining gates

No feed was contacted and no Sparkle UI, live appcast, download, or installer
ran. Before an update can install, the adapter must translate a validated
signed-feed candidate into the existing update trust model, bind one exact
foreground confirmation and runtime-shutdown authority to Sparkle's proceed
path, preserve cancellation/recovery, and pass a signed two-version upgrade and
failure matrix. Protected beta/stable values, a real Ed25519 key pair, nested
Developer ID inspection, notarization/stapling, final SBOM/packaging equivalence,
and physical clean-machine acceptance remain release gates.

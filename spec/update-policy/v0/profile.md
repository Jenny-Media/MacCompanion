# Mac Companion update trust policy v0.15

Status: normative for the first direct-distribution beta.

This profile freezes the trust and runtime gates around the admitted updater.
The source tree now embeds exact Sparkle and constructs a privacy-closed
adapter only when complete protected release authority is present. It does not
provide a usable feed or key, download an update, or grant installation.

## Dependency authority

The only admitted updater is Sparkle `2.9.6` from
`https://github.com/sparkle-project/Sparkle`, pinned to the full revision
`ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a`. SwiftPM must use an exact
semantic version and its resolved state must match that full revision. A tag,
branch, version range, binary download URL alone, or shorter revision is not
an equivalent authority.

The upstream `Package.swift` digest is
`076e7810d9a463f3d7f034f9429bd5dcb3ed72203d06e1636f221668ec327962`.
It declares one binary target named `Sparkle`; that target's official archive
checksum is
`8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606`.
The source and archive carry the same reviewed license bytes, digest
`389a4e4e9a32f059775b13a06e25a591445ba229d2838d26dd3e7c0c45127cfe`.
All of these facts are required together.

The pin must be re-reviewed before it changes. The review must cover upstream
security notes, the complete resolved revision, license, signed-code graph,
privacy manifest impact, helper/XPC topology, archive tools, and the final
Developer ID/notarization behavior. The repository's default dependency denial
remains in force until that integration review is complete.

## Privacy and embedded topology

Mac Companion sends no system profile and supplies no custom feed parameters.
It explicitly keeps `SUEnableSystemProfiling` and `SUSendProfileInfo` false and
sets the updater's `sendsSystemProfile` state false; it does not rely on an
absent preference. The audited upstream source and binary archive contain no
`PrivacyInfo.xcprivacy`. A future upstream manifest changes this recorded fact
and requires review; Mac Companion's own containing-app privacy manifest
remains authoritative for its behavior.

Mac Companion is not App Sandbox enabled. The final embedded Sparkle graph is
therefore minimized to the framework executable, `Autoupdate`, and
`Updater.app/Contents/MacOS/Updater`. `Installer.xpc` and `Downloader.xpc` are
removed from the copied framework, and Sparkle's release tools—including
`generate_appcast`, `sign_update`, `generate_keys`, and `BinaryDelta`—never
enter the app bundle. Archive/export re-signs every retained nested object with
the release identity, and the exact final graph is inspected before promotion.

## Feed and archive trust

Beta and stable have distinct HTTPS feed authorities supplied by protected
release configuration. Neither URL nor the public Ed25519 key has a usable
default in community builds.

The release-injected authority has profile
`maccompanion.sparkle-release-authority.v1` and exactly one `beta` or `stable`
channel, one canonical ASCII HTTPS `.xml` feed URL without credentials, port,
query, fragment, localhost, or `.local` authority, and one canonical Base64
32-byte Ed25519 public key. The tracked property list contains only unresolved
build-setting placeholders. Missing placeholders are an inert supported state;
partial or invalid values construct no updater. The adapter supplies the feed
through its delegate, sends no custom headers or parameters, and allows only a
single explicit informational probe. Every ordinary, background, download, or
installation check remains denied until the runtime installation gate owns an
exact handoff. Even an informational result is discarded unless its item
matches the configured channel, is a normal application update, advertises no
deltas, and points to one canonical HTTPS `.zip` URL without credentials,
port, query, fragment, localhost, `.local`, or encoded-path ambiguity.
The item must also come from a successfully validated signed appcast and carry
a nonzero archive length no greater than 4 GiB plus one canonical Base64
64-byte Ed25519 archive signature. Channel, installed build, candidate build,
display version, archive URL, archive length, and archive signature remain one
immutable observation through later admission.

The enclosure must also carry the closed Mac Companion release-evidence
projection in the namespace
`https://jenny.media/maccompanion/update-evidence/1`, using the exact
`maccompanion` prefix. Its 17 required attributes are:

- profile `maccompanion.update-release-evidence.v1` and evidence level
  `signedCandidate`;
- exact channel, candidate build, display version, archive URL, archive length,
  and archive Ed25519 signature duplicates;
- canonical non-placeholder SHA-256 digests for the archive, signed-candidate
  release manifest, platform-signing record, two-phase notarization record,
  and packaging-equivalence receipt; and
- exact `passed` claims for the Developer ID graph, notarization, application
  stapling, and whole-application ZIP evidence.

Missing, extra, non-string, noncanonical, failed, or candidate-mismatched custom
attributes make the item unavailable. The final signed appcast is itself
publication evidence, so its projection binds the complete `signedCandidate`
manifest rather than a `promotionReady` manifest that would include the
appcast and create a content-hash cycle. Human approval, physical scenarios,
and channel publication remain external release-lane gates.

The official build must enable both signed-feed verification and archive
verification before extraction. Every whole-application ZIP is signed with
Ed25519, Developer ID validated, and replaced only by a notarized complete
bundle. Installer packages and delta updates are excluded from the first beta.
The feed, release notes, archive length, archive signature, version, channel,
and minimum-system facts are one signed publication unit.

The first beta keeps automatic checks, automatic download, and automatic
installation disabled in both the tracked property list and runtime adapter.
A later automatic-check preference requires a policy and UX revision; it may
not silently arise from Sparkle defaults. A beta or stable client never falls
back to the other channel. Build numbers increase monotonically; downgrade is
not an updater recovery mechanism.

## Runtime installation gate

An install begins only after a fresh explicit local confirmation while the
menu application is foreground. The confirmation expires after five minutes
and is cancelled when the application loses foreground state. This is the
public-API-safe lock boundary: the product does not infer a precise lock state
from undocumented session APIs.

Before handing installation authority to Sparkle, Mac Companion must:

1. reject new remote sessions;
2. prove Interactive Control inactive, including no uncertain cleanup;
3. drain bounded work;
4. stop the Agent cleanly; and
5. retain exact containing-app/Agent version compatibility.

Any missing, stale, ambiguous, or failed fact denies installation. The updater
replaces the containing application as one unit and never swaps the embedded
Agent independently.

An informational signed-feed observation is not archive or replacement-bundle
validation. A later updater-owned validation observation must match its exact
channel, installed build, candidate build, display version, canonical archive
URL, archive length, and archive signature and carry every required trust fact
before it can mint the single-use runtime authority. Mismatch, missing trust,
cancellation, or reuse consumes that candidate and requires a fresh
informational observation.

Developer ID, notarization, stapling, and whole-ZIP requirements cross this
boundary only through the typed release-evidence value bound to the exact
candidate. The lower-level gate no longer accepts free Boolean parameters for
those release claims. The signed appcast authenticates the projection; the
protected release lane remains responsible for constructing it only from the
referenced passing records. Sparkle's archive signature continues to bind the
downloaded bytes because its delegate does not expose the staged archive for a
second client-side hash.

The informational publication and release evidence remain one typed value
through validation correlation. A package-owned single-use owner accepts only
one exact `willExtractUpdate`, then the matching `didExtractUpdate`, and then
one installation-readiness event from `showReadyToInstallAndRelaunch` for that
same publication. Channel, builds, display version, canonical archive URL,
length, Ed25519 signature, all release claims, and all five evidence digests
must remain equal. Mismatch, callback reordering, cancellation, concurrent
reuse, or repeated callbacks close both correlation and admission permanently.

In Sparkle 2.9.6, `didExtractUpdate` is a misleadingly named intermediate
event: it fires after the installer process accepts its input, before that
process asynchronously extracts and validates the archive. It cannot mint
installation authority. The containing app must subclass or proxy the standard
user driver and withhold its `.install` reply to
`showReadyToInstallAndRelaunch` until Mac Companion's foreground-confirmed
runtime coordinator admits the exact prepared update. An arbitrary Boolean is
not validation or installation-readiness evidence.

The containing app uses a complete `SPUUserDriver` proxy rather than a Swift
subclass. It forwards every required method to `SPUStandardUserDriver`,
serializes exact `willExtractUpdate` and `didExtractUpdate` observations, and
intercepts only the later readiness reply. Until the real foreground/runtime
owner is bound, the proxy must cancel correlation and reply `.skip`; it must
not reply `.dismiss`, because a dismissed prepared update may still install on
application termination, and it must never forward `.install` directly.

The Agent's `KeepAlive=true` job must be unregistered through the converging
ServiceManagement owner before updater handoff; process exit alone is not an
accepted stop. If the Agent is registered, the app must first persist one
compare-and-swap receipt bound to the exact source and candidate builds. A
failed handoff re-registers and verifies the source Agent. After a successful
replacement, only the exact source or candidate app build may re-register its
matching Agent and clear the receipt. Missing exact readiness or any receipt
conflict retains recovery state and keeps installation authority closed.

Registration state and the embedded Agent file are not evidence of the build
currently executing. The Agent must project its canonical numeric bundle build
inside the exact acknowledgement on the reciprocal code-signing-requirement
local-XPC handshake. Startup recovery may use a bounded one-use probe before
the dashboard starts. Runtime update shutdown must instead consume the build
observed on its already-authenticated dashboard lifetime, so it cannot replace
that live connection merely to query version. Malformed, missing, timed-out,
stale, or mismatched build evidence denies stop, recovery, or receipt clearing.

The active dashboard build lifetime has exactly one package-owned publication
from the authenticated hello acknowledgement. Production consumers may read
but cannot mutate it. Duplicate authentication, message-order failure, event
overflow, transport invalidation, dashboard finish, or object retirement clears
the build permanently. The containing app must pass that same lifetime to both
the dashboard product and the update-time Agent-stop dependency; the startup
probe remains a separate recovery-only mechanism. Merely constructing the stop
owner does not authorize network closure, Agent unregistration, updater
handoff, download, or installation.

The reactivation receipt must use the frozen canonical JSON projection in the
menu app's private Application Support root. Reads require one no-follow regular
descriptor with mode 0600 and bounded `fstat` size; cached pathname metadata is
not identity or size authority. Insert, phase advance, and clear require the
exact expected receipt under one process-shared lock, with file sync before
atomic rename and directory sync after rename or unlink. Any unknown entry,
symlink, malformed record, compare-and-swap conflict, or uncertain durability
retains the recovery gate.

The containing app must construct the system receipt store and concrete
ServiceManagement bindings before ordinary product routing. Startup repair
reads the receipt before it registers or probes anything. With no receipt it
performs no login-role or local-XPC effect. With a receipt, only the exact
source or candidate containing-app build may converge registration and use the
startup-only authenticated build probe before dashboard construction. Launch-
race start, invalidation, and timeout outcomes may retry at most four total
probes with fixed 250-millisecond spacing; cancellation, protocol-order
violation, unknown error, exhaustion, build mismatch, persistence conflict, or
composition failure keeps routing and the dashboard closed. No public
production initializer may replace authenticated build readiness with a
caller-supplied build claim.

Neither lifecycle event is Mac Companion's Developer ID identity or
notarization attestation. Sparkle 2.9.6 permits an Ed25519-valid update to
change Apple code-signing identity, and its callbacks do not report
notarization. The production bridge must therefore bind the exact downloaded
candidate to independently protected release evidence for the required Jenny
Media Developer ID graph, notarized and stapled replacement, and
whole-application ZIP. It may not manufacture those facts as unconditional
callback booleans.

Production consumers cannot directly construct or extract the lower-level
validated candidate or installation authority. One coordinator owns fresh
confirmation, resamples the foreground/clock fence at every transition, runs
only the ordered network-close, bounded-drain, Agent-stop, and updater-handoff
effects, and completes the authority's exact recorded recovery scope before
returning a failed installation attempt.

## Rotation and custody

Developer ID and Ed25519 signing authority remain in controlled external
custody. One release may rotate either the Developer ID certificate or the
Ed25519 key, never both. Rotation and compromised-release recovery require a
separately reviewed release record. A feed outage, signature failure, or lost
key never enables unsigned fallback.

## Executable policy

`scripts/update_policy.py` is the closed JSON validator.
`Tests/System/UpdatePolicy/manifest.json` indexes accepted and adversarial
fixtures generated by `scripts/validate_update_policy.py`. The valid fixture
contains only public policy facts, the public upstream repository URL, and an
opaque external feed-authority reference; it contains no feed URL, public key,
private key, credential, or release secret.

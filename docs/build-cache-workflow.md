# Local build caches and evidence

The native macOS, iOS VNC and visionOS builders, and `bash scripts/validate.sh`,
now reuse compiler workspaces. A new dated `--output` directory retains evidence
without creating another full dependency build and DerivedData tree.

## Hosted validation during rapid iteration

The GitHub **Public CI** workflow runs manually through Actions → Public CI →
Run workflow. Automatic pull-request and `main` push triggers are disabled.
Its full validation steps remain available; `bash scripts/validate.sh` remains
the local validation command required before handing off changes.

The separate [iOS Xcode Cloud workflow](xcode-cloud.md) archives the direct iOS
client for internal TestFlight delivery on `main` changes. It does not replace
the local validation requirement or automatically publish to Public Beta.

## Encryption submission metadata

The normal direct iOS, macOS and visionOS builders include the Boolean
`ITSAppUsesNonExemptEncryption = false` in the generated application Info.plist,
matching the saved standard-encryption declaration for distribution outside
France. Each builder checks the finished app before publishing a successful
build report. This declares the existing exemption from documentation; it does
not disable or remove SSH, OpenSSL or other encryption. No Apple-issued
`ITSEncryptionExportComplianceCode` is required for this declaration.

France remains excluded in App Store Connect for the app and both in-app
purchases. This is a standing distribution decision, not a question to repeat
for each upload. Reassess the declaration if the cryptography, applicable
requirements or distribution scope changes. The metadata applies to future
builds; it cannot modify an archive already uploaded. TestFlight public links
still have no country filter. Disposable visionOS probes and gated legacy
application targets do not inherit this direct-client declaration.

See [Apple's key reference](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption)
and [the saved France exclusion](execution-status.md#2026-10-06--france-excluded-from-app-store-distribution).

## Application names

The normal direct iOS, macOS and visionOS clients all build as
`Mac Companion.app`, with both `CFBundleName` and `CFBundleDisplayName` set to
`Mac Companion`. Bundle identifiers, Keychain access groups and signing
identities are unchanged. Executables and Swift module names stay compatible:

| Platform | Executable | Swift module |
| --- | --- | --- |
| iOS | `Mac Companion` | `Mac_Companion` |
| macOS | `MacCompanion` | `MacCompanion` |
| visionOS | `MacCompanionVision` | `MacCompanionVision` |

Build/archive callers must use the build report's `app` path and the app's
`CFBundleExecutable`, rather than inferring either from a scheme or target name.
Hosted test paths follow the same wrapper/executable split. Each normal builder
verifies the finished names before publishing its report. Disposable probes,
extensions and gated legacy target identities are unchanged.

## Normal usage

Keep using the existing builder arguments, including `--output`. For example:

```sh
python3 scripts/build_direct_macos.py \
  --source /path/to/pinned-libvncserver \
  --openssl-archive /path/to/openssl-source.tar.gz \
  --output /private/tmp/maccompanion-mac-review-20261014

bash scripts/validate.sh
bash scripts/validate.sh --evidence-root /private/tmp/maccompanion-validation-review
python3 scripts/build_cache.py status
```

A workspace is keyed by the canonical checkout path, selected Xcode/Swift and SDK
identity, platform, architecture and build profile. Commits, report dates and
output paths do not create new cache keys. Different worktrees, device versus
Simulator SDKs, visionOS probe versus client, and unsigned versus development
signed Mac builds stay isolated. Source/dependency hashes, package pins, platform
provenance and all existing admission checks still run on every build.

The default compiler root is `/private/tmp/maccompanion-build-cache-<uid>`.
Set `MACCOMPANION_BUILD_CACHE_ROOT` or pass `--cache-root` to use another dedicated
root outside the checkout. Managed roots must be owned by the current user;
existing unmarked output is preserved and rejected. Use a new evidence directory
when migrating from the old layout. Existing compiler trees are not moved,
adopted or deleted.

## Evidence and callers

Each builder saves one generation under `<output>/runs/<UTC-time>-<random-id>/`:

- A copy of the final verified app, generated project/configuration and current logs.
- The original report fields, plus `cacheWorkspace`, `evidenceRun` and cache identity.
- `run.json` records the run outcome and compiler workspace, including failed runs.

`build-report.json`, `project.json`, the generated `.xcodeproj` and `DerivedData`
at the output root point to the latest successful generation. Its DerivedData
contains the app snapshot, not intermediates or package checkouts. The report's
`app` path identifies a specific saved generation and survives later builds.
Use that path when installing or inspecting a particular build. Application
snapshots and evidence still consume space; they are retained until separately
approved for cleanup.

The Mac hosted QA, iOS Simulator QA and internal TestFlight preparation scripts
lease the original compiler workspace and reuse its compiler/package data. They
retain QA result bundles in the supplied evidence folder. Older legacy build
folders remain supported. A report whose compiler workspace has since been
reused, failed or changed toolchain cannot authorize QA/archive; rebuild first.
This prevents an old report from being paired with another run's compiler state.
No signing, installation, upload or release action is added by this workflow.

A visionOS `--prepare-only` run retains preparation evidence and prints the
managed project path; it does not publish a successful app report. Use the
builder for subsequent compilation so it acquires the workspace lock.

## Validation reuse

Validation always runs the same check set. `MacCompanionKit` macOS tests and
macOS target builds share one scratch directory. Its iOS Simulator target builds
share a second scratch directory. Independent experiment packages keep separate
directories. A workspace lock covers the entire validation run, so concurrent
invocations wait up to five minutes and fail without interrupting an active run.

Validation logs default to
`/private/tmp/maccompanion-build-evidence-<uid>/<checkout-key>/runs/...`.
`--evidence-root` or `MACCOMPANION_VALIDATION_EVIDENCE_ROOT` overrides that location.
For compatibility, the old `MACCOMPANION_VALIDATION_SCRATCH_ROOT` override is now
an evidence location; it no longer creates a new compiler cache for each dated
path. Use `MACCOMPANION_BUILD_CACHE_ROOT` to select the compiler root.
`MACCOMPANION_DISABLE_SWIFTPM_SANDBOX=1` remains an explicit opt-in and gets a
separate validation workspace. Existing Swift Testing failure detection remains
in place even when the toolchain incorrectly returns exit status zero.

## Fresh checks and space review

Pass `--cold` to any supported builder or to `bash scripts/validate.sh` when a
fresh compilation is required. It creates a new isolated workspace and retains
all previous ones. Routine validation should use the default reusable slot.

`python3 scripts/build_cache.py status --budget-gib 40 --inactive-days 2` reports
allocated size, current locks, budget status, and inactive/cold review candidates
under this managed root. The budget is advisory, not a hard limit. Scanning is
explicit; builds do not rescan the whole disk. APFS shared blocks may be counted
more than once by `du`. There is no prune/delete command, timer or scheduled
cleanup. Review and explicit approval are still required before removing caches
or evidence. The two-day Simulator-data rule does not automatically authorize
build-cache deletion.

Other repositories can use the same layout and lock policy, with their own
build entry points and namespace. This change is local to MacCompanion's build
workflow; it does not change global Xcode or SwiftPM preferences.

## Legacy feature and pairing checks

`bash scripts/verify_simulator_features.sh` and
`zsh scripts/verify_pairing_reliability.sh [--signed-builds]` also use
`BuildSession`. Their checkout/toolchain/SDK/configuration/architecture and
signing profiles stay separate from normal client builds and from each other.
The feature runner keeps its existing Simulator lease and requires an already
booted Simulator. No device, consent, signing or test-selection action is added.
The opt-in signed pairing command still requires its development team.

Compiler output goes to the existing internal managed root. Each invocation
retains a new evidence generation, including workflow logs and successful app
snapshots under `products/`. Feature reports, screenshots/result bundles and the
test-host binary remain in that generation. The lease lasts through compilation,
installation, testing, verification, child-process cleanup and app snapshotting.
The feature runner's final pairing checkpoint uses a distinct managed profile;
its evidence location is retained in `pairing.log`.

`MACCOMPANION_LEGACY_EVIDENCE_ROOT` optionally selects a dedicated evidence root
for one profile. Its ownership rules match other managed workflows: use a new
root after changing the profile. Default roots are selected automatically by
profile. `MACCOMPANION_LEGACY_COLD=1` requests a new compiler workspace without
deleting existing output. `MACCOMPANION_LEGACY_CACHE_VARIANT` separates deliberate
experimental compiler variants. Suite names, iteration counts and report dates
do not create another compiler tree.

The old `MACCOMPANION_LAB_DERIVED_DATA` and
`MACCOMPANION_PAIRING_DERIVED_DATA` overrides are rejected with migration guidance;
they cannot bypass the lease. Use `MACCOMPANION_BUILD_CACHE_ROOT` for a dedicated
internal compiler root. Toolchain selection honors `MACCOMPANION_DEVELOPER_DIR`,
then `DEVELOPER_DIR`, then `xcode-select`; it no longer defaults these callers to
an Xcode beta. An Xcode `.app` path is normalized to its developer directory.

The separately opted-in signed Agent/native-host probes and historical WebRTC
experiment recipes retain their existing layouts and admission requirements.
They are not entry points for these two managed workflows. The normal native
builders, validation command, hosted CI and paused platform work are unchanged.

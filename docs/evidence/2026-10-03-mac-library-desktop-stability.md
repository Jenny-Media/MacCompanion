# Saved Macs and Desktop stability — 2026-10-03

## Scope

The iOS product now supports a saved Mac library: select a Mac, pair another
Mac, rename a local entry, and forget an exact Mac locally. The normative
profile is `spec/capability-protocol/v0/client-mac-library.md`; its sole indexed
fixture is `client-mac-library-v0.1.json`.

Each selected Mac uses its own durable identity, pin, keys and route catalog.
Pairing completion selects its verified host ID explicitly. Startup with more
than one Mac opens the library without dialing. A single Mac retains automatic
connection. Missing keys can be managed from the library.

Retired pairing and network callbacks are generation-fenced. Failed network
owners are stopped and drained before another Mac is selected. Forget writes a
durable tombstone before removing the exact host's keys, routes and public
record. Startup validates the complete inventory, including tombstoned records,
before deleting any key; interrupted removal remains fenced and is retried.

## Verification

Three package tests cover independent host metadata, restart and interrupted
removal, conflicting identity/key references, invalid metadata, exact-record
removal, and route deletion without changing another Mac's catalog.

The normal native simulator journey additionally exercises My Macs, rename,
Pair Another Mac, return to the existing pairing, exact entry selection, and
restart using the persisted local name. The Rename editor uses an item-owned
sheet; earlier alert-based attempts failed the UI journey and were replaced.

Stable Xcode 27 `bash scripts/validate.sh` passed, including 124 indexed
protocol/product fixtures and the three new isolation/removal tests.

Private artifacts:

- Final stable validation: `/private/tmp/maccompanion-mac-library-isolated-port-stable-validation-20261003.log`.
- Final separate-port normal journey: `/private/tmp/maccompanion-mac-library-isolated-port-qa-20261003/report.json`, passed; two presented native sessions, verified restart, exact-source checks, key cleanup and simulator restoration.
- Sustained Desktop journey: `/private/tmp/maccompanion-mac-library-owner-drain-desktop-qa-20261003/report.json`, passed; one minute of client frame progress and native input.
- Release-source input SHA-256 for both simulator and iPhone builds: `3d6326e4ad7996b33fee59ae964fdc23cd289ee167f7be4b3c20886f008ae603`.
- Updated Mac app: `/Users/yihong/Applications/Mac Companion.app`; receipt `/private/tmp/maccompanion-mac-library-mac-installed-20261003.json`. The containing signature, exact bundled Sunshine catalog and existing Agent entitlements/service were preserved. A recoverable previous app bundle is retained privately.
- Final iPhone 18 Pro Max install and launch: `/private/tmp/maccompanion-mac-library-owner-drain-iphone18-install-20261003.json` and `/private/tmp/maccompanion-mac-library-owner-drain-iphone18-launch-20261003.json`. Existing provisioning, application identity and keychain group were preserved. The app was updated without uninstalling or resetting the pairing.

No screenshots, input text, pairing material, certificates or audit databases
are added to the repository.

## Desktop failure investigation

The user identified the affected device as iPhone 18 Pro Max and the affected
surface as full Desktop. A historical physical attempt displayed native video
and renewed its runtime lease. At 10:49:21 the Agent reported a native runtime
snapshot unavailable, followed by the Mac backend watcher retiring and the
client reporting a command failure. The logs do not establish which snapshot
or geometry check failed. The later invalid input-role read follows teardown
and is not sufficient evidence of an invalid input command causing the loss.

Added fixed diagnostic reasons for inactive/expired/not-ready menu snapshots,
unavailable/changed installed bindings, backend scope/permit/geometry checks,
and whitelisted numeric native TLS failure codes. These retain existing
authority checks and log no addresses, names, keys, certificates or input.

The physical Space/app-change failure has not yet been reproduced on the
updated build. This issue remains open; instrumentation is not a claimed fix.
A separate historical native preparation error happened before route binding
and also requires a fresh coded diagnostic before assigning a cause.

Two new physical attempts at 16:35 overlapped the sustained simulator run and
failed the Mac native backend's startup. The disposable probe and installed
host both used base port 58989. The probe now uses 59089, keeping its Sunshine
offset ports separate. This removes test interference; it does not establish
the cause of the earlier loss after a displayed Desktop/Space change.

The final sustained simulator journey passed all source-binding and cleanup
checks: one minute of client frame progress, continued capture and input,
compact keyboard/modifier/shortcut controls, and clean Stop. Finder and System
Settings were focused and Space-switch shortcuts were sent during this run.
The automation did not independently verify which Space became active.

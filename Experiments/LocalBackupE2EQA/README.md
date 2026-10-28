# Two-iPhone local backup journey

This opt-in Simulator app exercises the shipping `DirectLocalBackupSettings`,
`DirectLocalBackupStore`, Mac library and control stores. It uses actual app-file
and device-local Keychain persistence in the separate
`dev.maccompanion.backupe2e.ios` bundle/access group. It seeds synthetic Macs,
multiline saved text, shortcuts, row/menu placements and connection preferences.
Synthetic sign-in credentials stay in each device's Keychain. iCloud stays off;
this does not establish signed-account propagation or physical-device acceptance.

The app is only linked by the opt-in QA launcher. It is never part of the normal
application or release targets. File sharing is enabled only in this QA app so
Files can browse its Documents folder, **Mac Companion Backup QA**.

Reuse two existing, compatible and confirmed-idle project iPhone QA Simulators.
Hold both device reservations throughout the journey, including file transfers;
run the destinations sequentially. Do not create, reset or erase a device for
this check. Keep captures, exported files and results outside application Git.

Build the normal Simulator app with `scripts/build_vnc_ios_development.py` and its
managed cache, then run each stage through the existing launcher:

```sh
python3 -B scripts/verify_terminal_pro_simulator.py \
  --build /absolute/path/to/normal-simulator-build \
  --simulator EXISTING_QA_IPHONE_UUID \
  --local-backup-e2e --test-diagnostics never \
  --only-testing LocalBackupE2ETests/LocalBackupE2ETests/test01ExportSourceA
```

| Order | iPhone | Method | Result or next action |
| --- | --- | --- | --- |
| 1 | A | `test01ExportSourceA` | Save `MC-E2E-A.json` through native Files; relaunch. |
| 2 | B | `test02PrepareTargetB` | Seed and record the different target baseline. |
| transfer | A → B | Host file copy | Copy the exported bytes to B's Documents as `incoming-a.json`; verify SHA-256 equality. |
| 3 | B | `test03ImportAOnB` | Select the transferred file through Files, preview, restore and relaunch. |
| 4 | B | `test04RecoverPreviousB` | Restore Previous Data and relaunch. |
| 5 | B | `test05CancelThenRestoreAOnB` | Cancel an import, relaunch, then restore A again. |
| 6 | B | `test06EditAndExportReturnB` | Apply a synthetic edit through the production stores; export `MC-E2E-B-return.json`; relaunch. |
| transfer | B → A | Host file copy | Copy those exact bytes to A's Documents as `incoming-b-return.json`; verify SHA-256 equality. |
| 7 | A | `test07ImportReturnOnA` | Restore the edited return file and relaunch. |
| 8 | A | `test08RecoverPreviousA` | Restore A's original data and relaunch. |
| invalid file | A | Host fixture | Write `{"format":"invalid-synthetic-file","version":99}` to `Documents/invalid-backup.json`. |
| 9 | A | `test09RejectInvalidFileOnA` | Reject the invalid file and relaunch without changing saved data or recovery. |

Resolve only this QA app's container with
`xcrun simctl get_app_container UUID dev.maccompanion.backupe2e.ios data`.
The manual host copy bridges the two native Files pickers; this is not an AirDrop
or iCloud transfer test. Preparation is persistent, so retain the earlier stages
and resume at a failed stage rather than reseeding the devices. For another
journey, archive the generated output files before reusing their fixed names.

Each launch writes `observation-PHASE.json` and `details-PHASE.json` in Documents;
restores also write a `-changed` observation. Preserve these outside the device.
Compare every portable JSON field after removing only `createdAt`. Assert that:

- A's export matches B after import and relaunch, including both complete control
  profiles, all row/menu placements and all Mac preferences.
- Imported Mac IDs differ from both device baselines, and the imported records
  have neither SSH nor desktop sign-in credentials.
- B's recovery matches its baseline, including original Mac IDs and credential
  presence; cancelling leaves that baseline unchanged.
- B's edit persists, contains the new text/placements in both control families,
  and matches A after the return import and relaunch.
- A's recovery restores its original data, IDs and credential presence.
- The invalid file preserves A's data and its existing recovery copy.
- Every captured state has iCloud off, and neither exported file contains the
  synthetic device-local credential markers.

These checks deliberately inspect persisted state as well as successful UI
actions. Synthetic observations and screenshots are evidence, not production
App Store images or acceptance on a physical iPhone/Duo.

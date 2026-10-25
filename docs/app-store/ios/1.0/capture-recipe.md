# Reproducing the local capture session

The exact local driver scripts, commands, build reports, native screenshot
manifests and result bundles are retained under
`/private/tmp/maccompanion-ios-1.0-release-20261024/`. They contain no real host
credentials. Raw screenshots and control-tree diagnostics stay outside Git.
The durable handoff package is listed in [screenshots.md](screenshots.md).

The capture implementation is `Experiments/NormalVNCViewportQA/AppStoreCaptureTests.swift`.
It is an opt-in hosted XCTest using the normal application's views, the existing
labelled local `CompanionVNCDuoSampleWorkspace`, a local Terminal output fixture
and one synthetic Mac record. The Desktop session discards input and opens no
transport. Terminal uses `autoConnect: false`; no shell command is executed.
The temporary library has its own file and a synthetic UUID. It uses the shipping
Mirror Mac Screen preference. The test is excluded from production sources.

1. Run `scripts/build_vnc_ios_development.py` with the existing verified
   LibVNCServer/OpenSSL source directories, `--sdk iphonesimulator` and an external
   `--output` folder, using the repository's managed cache workflow.
2. Generate the private QA project with
   `scripts/verify_terminal_pro_simulator.py --build <build-output> --simulator <owned-UDID> --generate-only`.
   While holding `build_cache.compiler_workspace`, configure the generated QA
   test target to compile `AppStoreCaptureTests.swift`, set the scheme test
   environment `MACCOMPANION_STORE_CAPTURE=1`, language `en` and region `US`.
   Copy `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` for app and extension
   from the unchanged `Native/iOSCloud/project.json` into this generated capture
   project only. These captures used **1.0 (142)**. Regenerate with XcodeGen and
   build-for-testing under the same managed lease.
3. Preinstall the exact capture host on the owned Simulator before starting
   XCTest. Retain the entire first failed attempt if test-host registration or
   disk pressure interrupts a run. Do not reinstall while the capture host is
   running. Use a fresh output/result directory for every retry.
4. Launch test-without-building with
   `-only-testing:DirectClientTests/AppStoreCaptureTests/testCaptureReleaseMaterials`.
   Keep the managed compiler lease. The test host bundle is
   `dev.maccompanion.proqa.ios`; use that exact bundle ID in the generated
   xctestrun's `TestHostBundleIdentifier`. Set Simulator Light appearance and
   Large text, English/US, and use the status-bar override 9:41, full Wi-Fi and
   battery. These do not change application behavior.
5. In its data container's `Documents/AppStoreCapture`, wait for `ready`, then
   write a request such as `{"id":"01-desktop","screen":"desktop"}` to
   `request.json`. Screens are `desktop`, `terminal`, `trackpad`, `library`,
   `controls`, `desktop-keyboard` and `composer`. Wait until `capture-ready`
   equals the ID; the adjacent `<id>-geometry.json` records the actual bounds,
   locale and active division. Capture the actual display with
   `xcrun simctl io <owned-UDID> screenshot <external-path>.png`, then write the
   ID to `capture-ack`. Do not alter the viewport or inject fold geometry.
6. For Duo, select only the owned Simulator in Device Hub. Use native Closed,
   Open, Partially Open and Rotate Right controls. Capture outer display 1 or
   inner display 3 as appropriate. Record the requested posture separately from
   the app's actual division. System geometry, rather than the posture name or
   orientation alone, establishes Book/Tabletop rendering. If a software
   keyboard is needed, use Device > Keyboard > Toggle Software Keyboard after
   the appropriate view has focus.
7. End with `{"id":"stop","screen":"desktop","stop":true}` and require the
   selected capture test to pass. Shut down only the owned Simulator. Preserve
   the raw PNGs and their hashes. Create separate JPEG exports with macOS `sips`
   at original dimensions for ASC's no-alpha requirement; retain both raw and
   exported hashes. Do not replace or resize the originals.

The base normal managed development report uses legacy **0.1.0 (1)**. It verifies
application/dependency inputs. The separately generated hosted capture target's
**1.0 (142)** override, executable hash and app/extension bundle metadata are
recorded independently. Neither is an uploaded or release-admitted candidate.

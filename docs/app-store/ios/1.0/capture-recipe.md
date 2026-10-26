# Reproducing the designed screenshot set

The current external capture workspace is
`/private/tmp/maccompanion-store-design-v9/`; durable copies of the drivers and
logs are in the handoff's `sources/` and `evidence/` folders. Image and typed
fixture content stay outside Git. [screenshots.md](screenshots.md) lists the
current gallery, build provenance, device coverage and acceptance limits.

1. Reuse the normal managed iOS compiler workspace under
   `build_cache.compiler_workspace`. Verify its report's declared application
   hashes against the capture checkout. Never substitute an arbitrary old app.
2. Generate the private `DirectClientQA` project using the repository workflow.
   While holding the compiler lease, save its exact original configuration and
   replace the hosted test source with the external
   `StoreDesignCaptureTests.swift`, the repository's hosted `SSHTestServer.swift`, and apply only the v9 capture adapters below. Keep app and extension **1.0 (142)** metadata,
   the private QA bundle ID, `MACCOMPANION_STORE_CAPTURE=1`, language `en`, region
   `US`, Light appearance and Large text. Build for testing with XcodeGen and
   the managed DerivedData path. No capture fixture enters a release target.
3. Reuse the owned compatible QA devices. Acquire the per-device directory lock
   before boot, install or capture, and retain the compiler lease throughout
   the native test. Run destinations sequentially with
   `-parallel-testing-enabled NO` and
   `-maximum-concurrent-test-simulator-destinations 1`. Full-set captures reuse
   the four existing materials devices; incremental revisions recapture only
   affected devices and retain the other images with their original provenance.
   Do not create another device.
4. Launch the opt-in
   `DirectClientTests/StoreDesignCaptureTests/testCaptureReleaseMaterials`
   through test-without-building. XCTest can reinstall the host: re-resolve
   `simctl get_app_container` on every readiness poll. Preserve earlier
   `Documents/AppStoreCapture` folders before each run; never reinstall while
   the capture test is active.
5. Wait for `Documents/AppStoreCapture/ready`, then supply the native-window macOS
   workspace composition as `remote-workspace.png`. Requests select `desktop`,
   `desktop-keyboard`, `terminal`, `trackpad-keyboard`, `library`, `setup`, or
   `composer`. The feature additions also select `keyboard-editor` and `files`. Terminal optionally shows its native keyboard. The temporary Mac
   library and Terminal output are synthetic. The sample desktop viewer discards
   input and opens no Mac transport. Terminal connects only to an isolated SSH
   fixture inside the Simulator, with ephemeral keys and synthetic credentials.
   Require `canSendUserInput` and inspect the rendered controls; this is not
   physical Mac acceptance.
6. For desktop framing, wait until the native keyboard completes its layout,
   then apply the native scroll view's zoom and content offset while respecting
   its insets. Focused phone uses zoom ratio **2.4**, normalized center
   **(0.72, 0.43)**; Book uses **2.3** and **(0.72, 0.43)**. iPad Compose uses **1.8**, centered at **(0.72, 0.43)**;
   its landscape hero uses **1.05** at **(0.5, 0.5)** without the keyboard.
   Tabletop uses **1.45** at **(0.64, 0.42)**. This is ordinary
   native zoom/pan, not a screenshot crop or display-size protocol change.
7. On the exact owned device in Device Hub, choose the native orientation and
   Duo hinge posture. Read the resulting geometry rather than
   trusting the requested label. Use display **1** for phone/iPad and inner
   display **3** for Duo. Disable Simulate Hardware Keyboard for the owned Simulator when a software
   keyboard is needed. System keyboard introductions and wrong outer-display
   probes are preserved but excluded. Keyboard or rotation interactions use
   the documented native tools; no browser-fetch or AppleScript helpers.
8. For each request, wait until `capture-ready` matches its ID, save the actual
   Simulator screenshot plus adjacent geometry, then write `capture-ack`.
   Never overwrite a raw capture. End with the stop request and require a
   successful XCTest result before shutting down that owned device. Restore
   the exact original QA project and rebuild the original test bundle.
9. Keep [screenshot-copy.json](screenshot-copy.json) authoritative for headlines
   and sequence. Generate the external artboards using that copy, actual native
   captures, and matching official Apple bezel PNGs. Render each fixed-size
   HTML/CSS artboard through the documented Chrome runtime, then save a separate
   RGB JPEG clipped to the exact Apple-accepted dimensions. Never stretch the
   screen, retouch controls, replace native labels or export transparency.
10. Check all final image dimensions, aspect ratios, loaded assets, two-line
    headline bounds and hashes. Inspect every rendered export, not only its
    source HTML. Keep a gallery and per-device build/locale/capture provenance.
    Run the repository's required validation and retain its logs.

The external manifest distinguishes reused approved hero captures, newly
captured feature screens and excluded probes. Simulator rendering and saved
text fixtures do not establish input delivery to a physical Mac or physical Duo
acceptance. The loopback SSH fixture is QA infrastructure and is not a required
Mac Companion service.
No upload, selected-build change or review submission is part of reproduction.

## Capture-only content and feature fixtures

Keep three capture-only source adapters outside Git. Each is the exact shipping
source followed by a gated fixture entry point: `DirectFilesSession.swift` seeds
a synthetic ready directory, `TerminalControlsSettings.swift` opens the native
keyboard editor with a configured three-row profile, and
`TerminalFocusedEditors.swift` preserves the earlier optional Add Row helper.
The configured profile uses saved Copy, Paste, Save and Find shortcuts, Compose
Text, navigation keys and modifiers. The current artwork shows the configured
editor, rather than opening the preset picker. Their unchanged production prefixes
and hashes are recorded in `evidence/fixture-adapters.json`. Exclude the original
three files only in the temporary QA project and compile these external copies
in their place. Restore the exact project and original test bundle afterward.
No shipping control, label, entitlement behavior or application source is edited.

The seeded Files state demonstrates native browsing and individual-file transfer
controls, not completed transfers. The keyboard fixture demonstrates Pro UI and
is marked Pro in the artwork. Keep optional Copy Text from Screen out of the
current seven-image set until a separate useful native preview is approved.

For the Mac content, create synthetic files outside Git, open them in Finder and
TextEdit, and capture only those native windows. For a clean title bar, close
the staged TextEdit session, reopen the document from Finder, and capture it
without attaching computer-use window inspection to TextEdit again. Resolve
the exact synthetic window IDs, then use macOS `screencapture -x -o -l<id>`.
Check the saved pixels for normal controls before composing them. Keep account and unrelated
sidebar content out of the captured windows. Place the unchanged window captures
proportionally over the bundled macOS wallpaper, recording source hashes in
`evidence/macos-content-provenance.json`. Do not select the preserved AI workspace.

Use portrait iPad captures for Compose Text and keyboard customization. The
keyboard artwork includes a proportional enlargement of two unchanged native
configured rows outside the device frame; the full original screen stays in the
bezel. Keep the Pro label legible. Duo leads with native Tabletop, then Book
Terminal and Compose Text. Preserve every earlier raw capture and rejected probe.

## Final readability polish (v9)

Recapture only iPhone Pro keyboard customization and Duo Book Terminal. Keep
v8 and every rejected fixture attempt. The keyboard profile places Compose Text,
Copy and Paste in its first row and Save/Find with the modifiers; every row's
saved-action index must match its item placements and pass shipping validation.
Duo Terminal synthetic output starts two lines below the top with two leading
spaces, so its first prompt clears the native rounded corner. Preserve the
normal QA configuration and rebuild its original test bundle after both captures.

Use the v8 iPad Terminal and Compose raw files unchanged. The manifest records
pixel crop rectangles, uniform scale and native source hashes for separate
enlarged details. Keep each complete native screen proportionally in its bezel;
never repaint labels or stretch controls. Four setup images use the canonical
“Your Mac. / No helper needed.” headline. Preserve order and Pro badges. Only
eight exports change; the other twenty must match v8 byte for byte.

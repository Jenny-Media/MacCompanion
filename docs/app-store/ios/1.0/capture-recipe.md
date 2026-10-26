# Reproducing the designed screenshot set

The current external capture workspace is
`/private/tmp/maccompanion-store-design-v5/`; durable copies of the drivers and
logs are in the handoff's `sources/` and `evidence/` folders. Image and typed
fixture content stay outside Git. [screenshots.md](screenshots.md) lists the
current gallery, build provenance, device coverage and acceptance limits.

1. Reuse the normal managed iOS compiler workspace under
   `build_cache.compiler_workspace`. Verify its report's declared application
   hashes against the capture checkout. Never substitute an arbitrary old app.
2. Generate the private `DirectClientQA` project using the repository workflow.
   While holding the compiler lease, save its exact original configuration and
   replace only the hosted test source with the external
   `StoreDesignCaptureTests.swift`. Keep app and extension **1.0 (142)** metadata,
   the private QA bundle ID, `MACCOMPANION_STORE_CAPTURE=1`, language `en`, region
   `US`, Light appearance and Large text. Build for testing with XcodeGen and
   the managed DerivedData path. No capture fixture enters a release target.
3. Reuse the owned compatible QA devices. Acquire the per-device directory lock
   before boot, install or capture, and retain the compiler lease throughout
   the native test. Run destinations sequentially with
   `-parallel-testing-enabled NO` and
   `-maximum-concurrent-test-simulator-destinations 1`. The only new device is
   the missing iPhone 18 Pro model required for the medium display family.
4. Launch the opt-in
   `DirectClientTests/StoreDesignCaptureTests/testCaptureReleaseMaterials`
   through test-without-building. XCTest can reinstall the host: re-resolve
   `simctl get_app_container` on every readiness poll. Preserve earlier
   `Documents/AppStoreCapture` folders before each run; never reinstall while
   the capture test is active.
5. Wait for `Documents/AppStoreCapture/ready`, then supply the approved fictional
   workspace as `remote-workspace.png`. Requests select `desktop`,
   `desktop-keyboard`, `terminal`, `trackpad-keyboard`, `library`, `setup`, or
   `composer`. Terminal optionally shows its native keyboard. The temporary Mac
   library and Terminal output are synthetic; `autoConnect: false` and the
   sample viewer's discarded input keep all remote transport inactive.
6. For desktop framing, wait until the native keyboard completes its layout,
   then apply the native scroll view's zoom and content offset while respecting
   its insets. Focused phone uses zoom ratio **2.1**, normalized center
   **(0.74, 0.475)**; Book uses **2.05** and **(0.74, 0.5)**. This is ordinary
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
text fixtures do not establish live remote input or physical Duo acceptance.
No upload, selected-build change or review submission is part of reproduction.

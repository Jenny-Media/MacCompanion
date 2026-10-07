# Black desktop after login: decoder diagnosis and local correction

## Evidence and attribution boundary

The user reported a black desktop with a visible cursor after login in internal
TestFlight 1.0 (4). The connected iPhone's existing fixed diagnostic snapshot
reported a complete 3840 × 2160 baseline, three presented frames and failure
stage zero. These counters do not identify pixel contents, decoding success or
viewer geometry. They cannot prove which defect caused that photographed attempt.
No credentials, saved Mac records, input content or desktop pixels were extracted.

A hosted first-frame test now drives the actual viewer's frame and state handlers
in both orders relative to initial window layout. A synthetic colored desktop
renders correctly through login dismissal. This does not reproduce the phone's
black desktop as an adaptive-layout failure.

The pinned LibVNCClient 0.9.15 source has a concrete false-success defect:
`src/libvncclient/zrle.c` returns TRUE after a negative tile decode result. Its
outer callback then reports the entire rectangle as updated even when the
zero-initialized pixel buffer was never filled. Our coverage gate consequently
accepted and presented the untouched buffer as a complete black desktop.

A synthetic invalid ZRLE tile from the indexed fixture reproduced this sequence
through the real socket decoder. Before the correction, the inverted frame
expectation failed and `baselinePresented` became true. This establishes the
mechanism, not definitive attribution of the user's particular connection.

Pinned source:
https://github.com/LibVNC/libvncserver/blob/9b54b1ec32731bd23158ca014dc18014db4194c3/src/libvncclient/zrle.c

## Correction

- Advertise lossless Zlib, Hextile and Raw, excluding the affected ZRLE/ZYWRLE
  paths. Authentication, endpoints and framebuffer bounds are unchanged.
- Classify only the fixed upstream tile-error format string, without formatting
  or retaining its arguments. Reject coverage/presentation after that failure
  and end with a clear image-decoding recovery message, stage 103.
- Preserve valid fully black desktops. Color is never a readiness heuristic.
- Add fixed decoder-failure counts and numeric viewer geometry/image-presence
  fields to the existing single local diagnostic snapshot. No pixel samples,
  image-derived summaries, names, endpoints or content are recorded.
- Update the normative direct profile and sole indexed fixture before changing
  encoding preferences; update its canonical manifest digest.

The selected compression may change bandwidth and decode costs; no measured
performance comparison is claimed.

## Verification

Stable Xcode 27.0 direct-client Simulator QA: 124 tests, five opt-in screenshot
captures skipped, zero failures. The suite includes valid Zlib pixels through the
actual decoder, rejection of false-success ZRLE frames, legitimate black frames,
complete-baseline coverage and first-frame rendering before/after initial layout.
OpenSSH interoperability and sandboxed key-install preservation checks pass.
Eight focused frame-readiness/first-frame rendering tests also pass with Swift
`-O` and Clang size optimization enabled. This is an optimized hosted QA check,
not a new signed TestFlight archive or physical acceptance. Its first build
needed regeneration of the runner's temporary synthetic key resources; the
completed rerun has zero failures.

Required stable `bash scripts/validate.sh` passes with exit zero.
`git diff --check` passes. Logs and synthetic images remain outside Git.

The final normal iOS source was built with Xcode 27.1 RC, matched against its
input hashes, signed using the existing Apple Development identity/profiles,
and installed on the connected iPhone 18 Pro Max without uninstalling app data.
The local bundle has build number 5; it is a development installation, not an
uploaded TestFlight build. TestFlight build 4 remains unchanged.

## Physical retry: correction did not resolve the reported failure

The user retried the installed development correction and reported the same
black desktop. The new fixed diagnostic snapshot reports zero decoder failures,
one complete 3840 × 2160 baseline, three presented frames and two retained
background resumes. Its viewer has an image, neither canvas nor image is hidden,
and a 440 × 247.5 image is correctly fitted within a 440 × 796 canvas at zoom
0.11458333. This does not establish the image's contents. It rules out the
previous hypothesis of missing/offscreen image geometry in this snapshot.

An additional hosted test supplies a synthetic 3840 × 2160 Zlib desktop through
the actual socket decoder, session image construction, viewer crop/zoom and
login dismissal. The resulting BGRX image renders red pixels in the connected
viewer. This focused stable-toolchain test passes. The first harness attempt
blocked on a large synchronous socket write; the writer now feeds the decoder
concurrently. A subsequent Objective-C array-capture compile error was corrected
before the passing run. Neither harness issue reproduces the user's failure.

Read-only Mac-side checks identify the same-sized backing desktop as the only
active display: MacTools Virtual Display, 1920 × 1080 logical points and
3840 × 2160 backing pixels. CoreGraphics reports it online, active and awake;
no physical display is active.

The built-in Screen Sharing service records three
`SSAgent_ReadScreenDataIntoSharedMemory_rpc failed` events at 16:54:48,
16:55:07 and 16:55:12, matching the connection and resume period. Its capture
permission/check-in flags are nonzero and the agent's capture-start completion
reports success. The RPC's public error description is `unknown error code`;
no specific numerical error can be inferred from that description.

A separate five-second ScreenCaptureKit status-only probe targets this display.
Capture start and stop succeed, but no screen sample buffers arrive and no
stream-delegate errors occur. The probe never reads, saves or exports pixels.
An AppKit/run-loop probe repeats this check, then briefly creates and repaints a
synthetic window before automatically closing it. Neither the initial two-second
period nor the three-second repaint period delivers a sample buffer. The probe
does not read pixels or change display configuration.
This is evidence of an upstream Mac capture problem independent of our VNC
decoder/viewer. It does not yet distinguish virtual-display compatibility,
WindowServer/display state, or a stale built-in capture service.

The user was asked to open the Mac's lid or attach a physical monitor, then
reconnect using the already-installed iPhone client. A same-host known-good
client comparison was also requested. The open-lid result is recorded below;
the other-client comparison was not performed.

No additional iPhone build, Mac helper, display setting change or service restart
was performed during this investigation.

Required stable-Xcode `bash scripts/validate.sh` was rerun after the additional
regression and investigation notes and completed with exit zero.

## Open-lid confirmation

The user reports that the desktop works after opening M5's lid. No further iPhone
installation or client-source change occurred between the failed and successful
connections. Live display enumeration now shows the built-in Color LCD as the
only active display: 1512 × 982 logical points, 3024 × 1964 backing pixels.
The MacTools virtual display is no longer active.

Repeating the same five-second ScreenCaptureKit status-only probe against the
current main display delivers 155 complete frames and one idle frame, with zero
stream-delegate errors. The iPhone's fixed diagnostic snapshot reports 55
presented frames and 60 updated rectangles at 3024 × 1964, a complete baseline,
and zero decoder failures. The user confirms that the desktop is visible.

This confirms the reported failure depends on the closed-lid,
virtual-display-only host configuration: capture stalls before image delivery,
and activating the physical display restores it. It does not establish whether
the remaining defect belongs to the MacTools virtual-display configuration,
macOS capture/WindowServer behavior, or their interaction. It does not establish
that all virtual displays or all closed-lid Macs fail.

The current workaround is to keep the lid open. An external physical display
with the Mac connected to power and external keyboard/mouse is Apple's documented
closed-display configuration; that configuration has not been tested here.
Reference: https://support.apple.com/en-us/102501

The direct iOS client cannot repair the host's virtual-display producer. Do not
add a Mac Companion helper, change the VNC security profile, or classify a
legitimate black framebuffer as a capture error to work around this host issue.
Open-lid desktop acceptance is confirmed for the installed local development
build. Virtual-display-only reliability and exact TestFlight build acceptance
remain separate.

## Virtual-display lifecycle follow-up

The user requested diagnosis of MacTools' closed-lid capture failure. The execution
host is an M5 Pro running macOS 27.2, build 26B5101f, on external power. The running
MacTools Dev process loads the installed `keep-awake.mactoolsplugin`; its helper
exposes the same fixed descriptor/settings selectors as the checked-out source.
Binary equivalence to that checkout has not been established.

### Same installed helper with the lid open

The installed helper was run as a temporary child process without changing the
installed MacTools app. It created display 12 alongside physical display 1 with
the same 1920 × 1080 logical / 3840 × 2160 Retina mode used during the failure.
Existing Screen Recording access was present. The independent five-second
ScreenCaptureKit check delivered 10 complete and 146 idle callbacks with no error.
SCScreenshotManager also returned the configured 1920 × 1080 dimensions. Neither
probe inspected or saved pixel content.

A separate temporary run of the same helper created display 13. The legacy
CGDisplayStream comparison delivered 10 complete callbacks in five seconds with
zero start/stop errors. This deprecated/obsolete API is diagnostic only, not a
shipping fallback recommendation. Both helper children exited and live display
enumeration returned to the original Color LCD only.

These tests show the installed descriptor, 4K backing mode, HiDPI settings and
helper lifetime can produce frames when the physical display is active. They do
not prove those settings work without a physical display.

### Source-backed recovery gap and transition clue

MacTools' `KeepAwakePowerSourceState.canRunVirtualDisplay` requires external power
and an already closed lid. The plugin starts the helper when that condition is
met and no other external display is active. The helper prints `READY` immediately
after `applySettings` returns true. `KeepAwakeVirtualDisplayManager.isActive` checks
only whether the helper process is running. No frame-readiness check or stalled
capture recovery is present. A live display/helper therefore remains reported as
active even when WindowServer delivers no frames.

At the earlier closed-lid transition, 15:28:24, WindowServer logged the clamshell
change, `Broadcast: Will Sleep`, physical display power-off, and `Broadcast: Did
Sleep`. Virtual display 11 completed an on/off/on state sequence and remained
marked on. At 15:28:46–48, WindowServer logged `Will Wake` and `Did Wake`, while the
physical display stayed off. A loginwindow lock/unlock sequence occurred around
the same transition. These are display/session transition events; they do not
establish that the Mac stayed asleep during the later capture attempts. Repeated
Screen Sharing agents subsequently failed their image-read RPC, while the fixed
independent ScreenCaptureKit check received zero callbacks. Opening the lid later
powered physical display 1 on and restored capture.

The strongest current hypothesis is that the closed-lid sleep/wake transition
leaves the virtual-only rendering/capture path stalled on this OS/hardware, and
MacTools' process-only health check cannot detect or repair it. The exact internal
macOS defect and whether pre-creating the display avoids it are not yet proven.
Do not label virtual-display creation itself as the confirmed defect.

A sixty-second retained-display capture probe is prepared under
`Experiments/VirtualDisplayCaptureProbe/`. The first requested physical run is
recorded below; its initial sample was already closed, so the intended pre-creation
comparison remains unperformed. A controlled single-display comparison must still
distinguish transition timing from a virtual-only rendering limit. MacTools source,
installed apps, power/security preferences and the working iPhone client remain
unchanged. No permanent host component was installed.

### Follow-up verification boundary

Both diagnostic binaries compiled with stable Xcode; the runner syntax and
`git diff --check` pass. Required full repository validation was attempted twice
after adding this isolated experiment. Both runs stopped in
`scripts/verify_direct_mac_names.py` because Swift could not write its temporary
object file: `No space left on device` (errno 28). The second attempt followed
removal of only the 79 MiB disposable module cache created for these probes.
Unrelated builds, caches and evidence were preserved. Those two attempts did not
pass; the later successful full rerun is recorded below.

## Physical lid test: source loss across display sleep

The user replied ready and performed a close/open test. The lid was already closed
at the first probe sample, so this run does not test the originally intended
pre-creation-while-open hypothesis. The probe retained temporary display 15 for
sixty seconds, then terminated its own helper. It did not reconnect a failed stream
automatically or change the installed MacTools/client.

The initially closed display delivered 81 complete frames and 251 idle callbacks.
At elapsed second 16 it became inactive/asleep and delivered a stopped status.
ScreenCaptureKit reported `-3815`, which the stable SDK's `SCError.h` defines as
`SCStreamErrorNoCaptureSource`, followed by `-3805`
(`SCStreamErrorFailedApplicationConnectionInterrupted`). These are not the SDK's
system-stopped or internal-error enum values. At second 33 the display again
reported active/awake, while the original stream remained terminated and its
frame counts did not advance. At second 46 the lid was open and the physical main
display was restored. Final stopCapture returned `-3808`
(`SCStreamErrorAttemptToStopStreamState`) after the terminal failures. Metadata is
in the local, untracked temporary log
`/private/tmp/maccompanion-vd-lid-transition-20261006.jsonl`.

Host events align with the stream failure: WindowServer broadcast Will Sleep /
Did Sleep and powered display 15 off at 17:40:58.59; it broadcast Will Wake /
Did Wake and powered that same display on at 17:41:16.22. Powerd recorded the
MacTools remote-user-activity refresh at that wake. The helper itself continued
running across this interval. This gives a concrete mechanism for this test's
failure: display sleep invalidates the capture source/connection, and marking the
display awake later does not revive an already failed SCStream. An active helper
and active display are insufficient evidence of healthy capture.

The installed MacTools helper also repeatedly created/removed additional displays
14 and 16–31 during this run. Source inspection exposes a possible identification
race: the plugin treats any non-built-in display whose name/vendor do not both
match its virtual display as external. SystemDisplayService falls back to a generic
name when no matching NSScreen exists; the shared observer refreshes at begin-
configuration callbacks as well as completion. It does not exclude by the actual
owned display ID from READY. This can affect the decision to stop/start its helper,
but the installed process's exact decision path was not instrumented. An isolated
CLI identity observer received no reconfiguration callbacks; it did not establish
this race and its unused source was removed. Do not report the race as confirmed.

An unrelated FrameWink Simulator UI test was running concurrently and its
CUALockScreenGuardian contributed host user-activity events. It was not interrupted.
This, the already-closed initial sample, and the second diagnostic virtual display
limit attribution of the observed helper churn to the original single-display
failure. The controlled follow-up must run with a lid-open baseline, no concurrent
host-affecting UI automation and one owned virtual display, before a MacTools
lifecycle repair can be claimed as verified.

The finding narrows the prior generic capture-stall hypothesis: virtual-only capture
can deliver frames, and the observed failure follows a display sleep/source-loss
transition with no stream recovery. The exact original single-display trigger and
MacTools classification contribution remain open. All temporary helpers are removed
and the original physical display is restored. No host or client app update occurred.

### Final verification

After the physical probe, the required `bash scripts/validate.sh` completed with
exit status 0 using stable Xcode at `/Applications/Xcode.app/Contents/Developer`.
The full log is retained outside Git at
`/private/tmp/maccompanion-vd-physical-validation-20261006.log`.
This supersedes the earlier disk-blocked reruns for the current diagnostic source;
it does not verify a MacTools repair or closed-lid reliability. Diagnostic binaries
compiled, runner syntax checks and `git diff --check` also pass.

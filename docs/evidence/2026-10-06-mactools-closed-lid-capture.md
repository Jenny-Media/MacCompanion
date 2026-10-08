# MacTools Screen Tools: closed-lid capture handoff

Status: investigation paused at the user's request. Keep the M5 lid open while
using Mac Companion. No MacTools source, installed plugin, power preference or
Screen Sharing service was changed. No permanent helper was installed.

## What is established

The iPhone client can authenticate, receive a complete framebuffer and render a
cursor while the host's desktop capture is stalled. Opening the lid restored the
desktop using the same installed client, without another source change or install.
Independent host capture also changed from no callbacks to normal callbacks.

| Host configuration | Independent capture | Client / host evidence |
| --- | --- | --- |
| Closed lid; only MacTools virtual display, 1920 × 1080 logical / 3840 × 2160 backing | ScreenCaptureKit: zero samples in five seconds, including a repeat with synthetic repaint | Built-in Screen Sharing recorded three `SSAgent_ReadScreenDataIntoSharedMemory_rpc failed` events; client decoder-failure count was zero |
| Open lid; physical display, 1512 × 982 logical / 3024 × 1964 backing | Same five-second probe: 155 complete, one idle, zero errors | User confirmed visible desktop; client recorded 55 presentations and 60 updated rectangles |
| Open lid; same installed virtual-display helper alongside physical display | ScreenCaptureKit: 10 complete / 146 idle in five seconds; a separate legacy CGDisplayStream test delivered 10 complete callbacks | The descriptor and HiDPI mode can produce frames with a physical display active |

A separate sixty-second retained virtual-display probe started with the lid
already closed. It delivered 81 complete and 251 idle callbacks, then the display
became inactive/asleep at second 16. ScreenCaptureKit ended with `-3815`
(`NoCaptureSource`) followed by `-3805` (`FailedApplicationConnectionInterrupted`).
WindowServer's display sleep events aligned with the failure. The helper process
remained alive. The display was active/awake again at second 33; the terminated
stream did not resume. The lid opened at second 46. The probe did not create a
fresh capture stream after waking, so recovery by a new stream remains untested.

These observations establish a host capture problem in this configuration.
They do not establish a universal VNC or virtual-display incompatibility, or
identify MacTools as the sole cause. A separate source-backed LibVNCClient
false-success decoder defect was fixed earlier; that fix did not resolve this
physical closed-lid failure. See the [full chronology](2026-10-06-black-desktop-decoder.md).

## MacTools source findings to revisit

Read-only checkout: `/Users/yihong/work/MacTools`, HEAD `55dd249e`, clean when
inspected. Equivalence between that source and the installed binary was not
established. Paths below are relative to that checkout.

- `Plugins/KeepAwake/Sources/KeepAwakePowerSourceMonitor.swift`:
  virtual-display eligibility requires a portable Mac on external power with
  the lid already closed.
- `Plugins/KeepAwake/Sources/KeepAwakePlugin.swift`:
  Screen Tools starts the virtual helper for an active session with no other
  external display. Its external-display classification uses a name/vendor match
  rather than the owned display ID.
- `Plugins/KeepAwake/VirtualDisplayHelper/Sources/main.m`:
  private `CGVirtualDisplay`, vendor 505, 1920 × 1080 at 60 Hz with HiDPI;
  `READY <displayID>` is printed after `applySettings` succeeds.
- `Plugins/KeepAwake/Sources/KeepAwakeVirtualDisplayManager.swift`:
  `isActive` reports whether the helper process runs. READY is recognized but
  its display ID is not retained for ownership checks. Neither condition proves
  that the display produces capturable frames.
- Shared display naming falls back to a generic name before a matching NSScreen
  exists; display observers also process begin-configuration callbacks. Combined
  with name-based ownership this is a candidate identification race, not a proven
  explanation for the observed helper churn.
- KeepAwake uses idle sleep/display assertions, a closed-lid system-sleep
  assertion and periodic remote user activity. Those are not proof of a healthy
  WindowServer capture source. The current stable SDK marks the system-sleep
  assertion deprecated/unsupported; that annotation alone does not establish its
  exact runtime behavior on this Mac.

The live MacTools helper created/removed additional virtual displays during the
retained-display watch. A second diagnostic virtual display and an unrelated
Simulator UI test were also present. Their activity confounds attribution of the
churn. An attempted isolated identity observer received no reconfiguration
callbacks and did not prove the candidate race.

MacTools owns its display/helper lifecycle. Built-in macOS Screen Sharing owns
the VNC capture stream; MacTools cannot simply restart that stream as if it were
its own SCStream. Mac Companion remains an iOS-only client.

## Controlled follow-up when resumed

1. Stop unrelated UI automation. Compare one retained helper with MacTools-managed
   Screen Tools under matched power, lid and display conditions.
2. Establish a physical-display baseline; test creating the virtual display while
   open before closing, separately from creating it after closing. The earlier
   watch did not perform that intended comparison.
3. Record owned display ID, display power state, helper start/stop decisions and
   status-only capture callbacks. After a sleep/wake failure, explicitly compare a
   fresh independent capture stream with the ended stream.
4. Compare another VNC client against the same built-in server in each state.
5. If MacTools ownership/lifecycle is implicated, fix it in MacTools and verify
   closed-lid transitions with real Screen Sharing, rather than adding a host
   component to Mac Companion.

Turning Screen Tools off is not a verified closed-lid workaround. Without a
physical external display, closing the laptop normally puts it to sleep.
Apple's documented closed-display configuration uses an external display,
power and external keyboard/mouse; it has not been tested in this investigation.

References: [Apple closed-display setup](https://support.apple.com/en-us/102501),
[Mac sleep behavior](https://support.apple.com/en-gb/guide/mac-help/mh10330/mac),
[idle display sleep assertion](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridledisplaysleep),
[system sleep assertion](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventsystemsleep).

## Retention boundary

The repository retains this summary, the detailed chronology and isolated
experiment source under `Experiments/VirtualDisplayCaptureProbe/`. Earlier
`/private/tmp` build/probe logs have since been cleaned up; historical paths in the
chronology are not promises that those files still exist. No desktop pixels,
credentials or typed content were extracted for this investigation. All
temporary helper children were terminated after their tests.

# Native magnification research — 2026-10-07

## Current conclusion

**Native magnification through built-in macOS Screen Sharing is feasible on
the tested Mac.** The authenticated loopback probe delivered began, three
`+0.05` changed updates, and ended to an ordinary AppKit view's
`magnifyWithEvent:`. The source process was Apple's built-in
`ScreensharingAgent`; the probe did not post local CG events or use app shortcuts.
No production Mac helper was installed or required.

Three further complete sequences passed on the retained session without
reconnecting. The iPhone integration is installed in build 17, and the user
confirmed native pinch works. Separate Preview/Photos coverage, released macOS
compatibility and multiple-display acceptance remain open.

The earlier assumption that the standard RFB input model proves native pinch
impossible was too broad. Standard RFB and Apple's extensions are separate
evidence. The interrupted shortcut implementation has been removed from the
working tree. The subsequent iPhone implementation uses native magnification.

## Primary sources

- [RFB 6143, pointer events](https://www.rfc-editor.org/rfc/rfc6143.html#section-7.5.5):
  standard pointer position/button/wheel model.
- [Apple NSEvent magnify](https://developer.apple.com/documentation/appkit/nsevent/eventtype/magnify):
  the native event the isolated AppKit test view checks.
- Installed Apple `ScreenSharing.framework`, `screensharingd` and
  `ScreensharingAgent`, read-only binary
  inspection on arm64 macOS **27.2 (26B5101f)**. These are implementation evidence,
  not a documented Apple compatibility promise.

Read-only comparison with current iShareScreen and openvncviewer source did not
find native magnification support. That absence does not establish Apple's server
limits. No source from those projects was copied into the probe.

## Reproducible static observations

Installed binary paths:

```text
/System/Library/CoreServices/RemoteManagement/screensharingd.bundle/Contents/MacOS/screensharingd
/System/Library/CoreServices/RemoteManagement/ScreensharingAgent.bundle/Contents/MacOS/ScreensharingAgent
/System/Library/PrivateFrameworks/ScreenSharing.framework/Versions/A/ScreenSharing
```

Full universal-file SHA-256:

```text
screensharingd:     664a22ca601615443328e73f1df34860b969fb01a41a575739c414c29ef4d790
ScreensharingAgent: 1a36a9599340bcb9fefbe4be12d8582d287b47ff10ff55eb79edcff3de87becd
```

Read these with `dyld_info -disassemble`, or thin the arm64e slice to temporary
output with `lipo -thin arm64e` and use
`xcrun llvm-objdump --macho --disassemble --no-show-raw-insn`. Generated Apple
binary copies and disassemblies remain outside Git.

| Observation | x86_64 server | arm64e server / agent |
| --- | --- | --- |
| Client dispatcher entry `0x17` selects `HandleEventMessage2` | jump table `0x100044644`, destination `0x10003b1af` | Same handler verified separately |
| 4-byte header; 16-bit payload size at header offset 2 | `0x10003d3df`; consume at `0x10003f79b` | consume at `0x10003c2ec` |
| Payload version/kind endian conversion and control gates | `0x10003f7d5`–`0x10003f864` | `0x10003c320`–`0x10003c3b0` |
| Kind 3 minimum length: v1 16, v2 32 when header flag bit 0 is clear | size table `0x1000446dc` → `0x1000437f0` | Same layout verified separately |
| Kind 3 converts double at offset 4, x/y at 12/14, and v2 phase/mask at 16/24 | `0x1000439e0` | `0x10003fd50` |
| Forward payload to built-in `SSAgent_PostGestureEvent_rpc` | `0x100043c5c` → call `0x100076eb6` | `0x10003ffd0` → call `0x10006ef74` |
| Agent creates gesture type 29, subtype 8; double magnification field 113 | — | `0x100015964`–`0x1000159a0` |
| Agent sets gesture phase field 132 and mask field 133 from v2 payload | — | `0x1000159b4`–`0x1000159dc` |
| Agent kinds 1/2 synthesize native start/end gesture subtypes 61/62 | — | `0x1000151ec`, `0x1000152b0` |

The agent logs `magnify %f` and `set phase %lld mask %lld`; its common tail posts
the synthesized gesture into the macOS session. The client probe does not call
these private agent functions or local event synthesis APIs. It sends candidate
network messages to the already running Apple server.

The installed Apple client independently confirms the layout:

| Client observation | arm64e address |
| --- | --- |
| `-[SSCallScrollView beginGestureWithEvent:]` forwards `NSEvent.subtype` | `0x22e4ba490` |
| `magnifyWithEvent:` reads raw CG fields 132/133 | `0x22e4ba7c4` |
| `_RFBPostGestureEventStart` writes a 12-byte v1 boundary | `0x22e58724c` |
| `_RFBPostGestureEventEnd` also writes a v1 boundary | `0x22e58739c` |
| `_RFBPostGestureEventMagnify` writes a 32-byte v2 payload | `0x22e5876c8` |

Boundary offset 4 is the AppKit touch subtype **3**, not the magnification mask
**4**. CG field 132 uses **1/2/4** for began/changed/ended; the received AppKit
phase uses **1/4/8**. These are different enum values. The Apple framework resides
in the dyld shared cache; `xcrun dyld_info -disassemble` can inspect it without
extracting or altering the system cache. Addresses refer to this installed build.

Server gates include observe/control state and its existing input acceptance
check. We have not bypassed them. Production support negotiation and retained
session input acceptance need separate verification.

## Runtime evidence boundary

- Local `127.0.0.1:5900` accepted a read-only banner probe and advertised
  `RFB 003.889`.
- Disposable AppKit probe built against the clean existing LibVNCClient revision
  `9b54b1ec32731bd23158ca014dc18014db4194c3` using stable local Xcode 27.0.
- `bash scripts/validate.sh` passed in full after retrying with access to Xcode's
  module cache. `git diff --check` passed. These gates validate repository health,
  not the candidate native gesture's runtime delivery.
- Corrected the probe's Retina mapping before the authenticated test. This Mac
  has one display at 1512 × 982 AppKit points with a 2× backing scale. The probe
  scales its own target point to the authenticated ServerInit framebuffer size;
  multiple-display mapping is intentionally outside this first proof.
- The installed server is a macOS beta build; these observations do not establish
  support on released macOS versions.
- **Authenticated native event delivery: passed for the bounded loopback test.**
- **Retained-session repeats: three consecutive complete sequences passed.**
- **iPhone integration: build 17 installed; the user confirmed pinch works.**
- **Separate Preview/Photos coverage: not independently recorded.**

## Runtime result and previous probe errors

The corrected probe completes normal format/encoding setup and sends a
zero-area framebuffer update request, then sends magnification over the
authenticated RFB socket to its own view. No framebuffer pixels were requested
or collected.

Five received view events matched the synthesized sequence:

| Event | Delta | CG phase | AppKit phase |
| --- | --- | --- | --- |
| Began | 0 | 1 | 1 |
| Changed (three events) | +0.05 each | 2 | 4 |
| Ended | 0 | 4 | 8 |

All five had CG event type 29, gesture subtype 8, gesture mask 4 and a nonzero
source PID independently identified as the installed `ScreensharingAgent`.
They were delivered to the probe window at its blue view's center. Starting
from scale 1, the three updates produce `1.05^3 = 1.157625`.

Later physical pinches on the Mac produced additional events with source PID 0
and mask 0. An earlier probe UI counted those too, so its total count or a larger
square alone is not the network proof. The final source filters those physical
events out of the proof counter. That filtering change built successfully; the
recorded network success precedes it and uses the same verified wire sequence.

The earlier failure screenshot did not establish an unsupported transport:

1. The first probe did not complete normal session setup and had no app-level
   gesture observer, so it could not distinguish missing network delivery from
   missing view delivery.
2. After setup was corrected, v1 magnification reached the app event loop with
   phase 0, but not `magnifyWithEvent:` on the blue view.
3. The probe's boundary field incorrectly used mask 4 instead of touch subtype
   3. It also sent v2 boundaries, whereas Apple's client sends v1 boundaries.
   The corrected v1 boundaries plus v2 magnification phases reached the view.
   These corrections were tested together; their individual necessity was not
   separately isolated.
4. An intermediate local diagnostic observer queried `phase` on a mouse-moved
   event, which caused an AppKit exception. This was a probe bug. The corrected
   built-in observer queries magnification properties only for magnify events.

Earlier repeat attempts had successful socket writes but no matching
agent-originated gesture; ordinary pointer arrival was also not confirmed.
Those attempts overlapped local physical gesture checks. Three subsequent repeat
tests without that interaction each delivered all five matching native view
events on the same authenticated session. The interference mechanism has not
been isolated; do not infer a proven local-input suppression rule. A successful write must not be treated as a
live or controllable session. The ordinary pointer diagnostic was negative even
in the successful first v2 test, while the received magnify events had the correct
target coordinates, so pointer arrival is not a prerequisite for this gesture
proof.

## Next verification gates

- Verify long-lived input delivery with normal server-message handling and
  support/control negotiation; bounded retained-session repeats passed.
- Exercise native magnification in Preview and Photos, including cancellation
  and cursor targeting, then repeat on the iPhone.
- Verify released macOS builds and display-selection/Retina mapping.
- Normative specification and indexed native magnification vectors were updated
  before the iPhone wire changes. This experiment stays outside release targets.

## Secondary lead

The same handler has a distinct event kind `11` with precise scroll fields,
separate from standard wheel-button masks. It may provide the appropriate route
for two-finger scrolling. Its wire layout and runtime behavior need their own
bounded verification before changing the client.

## iPhone integration — 2026-10-07

The input-only viewer now uses a UIPinchGestureRecognizer for Mac-app
magnification; Desktop keeps UIScrollView image zoom. The existing RFB owner
serializes the verified boundary/magnify packets alongside pointer/key input.
A cancellation epoch also retires events already copied out of the queue.
Background, mode/crop/layout changes, controls opening, queue pressure and exit
end a gesture actually sent. Unsupported server/layout combinations send no
extension or shortcut substitute. Authentication remains ARD-30.

Stable local Xcode 27.0 builds both Simulator and iPhone variants. All 17 focused
hosted tests pass, including the actual socket owner releasing native pinch
before pause, retained-socket repeats, copied-event retirement, queue-pressure
cancellation, fixed cursor targeting and input-only recognizer routing. Indexed
checks verify 17 native packet/boundary vectors, support gates, malformed deltas,
short buffers and 100 repeated encoder lifecycles. Required repository validation
and `git diff --check` pass. These synthetic checks do not establish Preview or
Photos behavior, physical gesture arbitration or released macOS compatibility.

Development **1.0 (17)** was signed with the existing local identities, installed
and launched on iPhone 18 Pro Max. All 578 source inputs and app/widget Keychain
identities were verified; CoreDevice read-back confirms version/build and
installation sequence 9352. The user subsequently confirmed pinch works on the physical iPhone. Separate
results for both Preview and Photos were not provided. No push or TestFlight
upload occurred.
Two-finger scrolling retains the existing wheel path in this build.

The user confirmed native pinch works in installed build 17 and authorized its
source commit. Two-finger scrolling was reported too slow to use and remains a
separate follow-up.

## Precise scrolling follow-up

The installed Apple client `_RFBPostScrollWheelEvent` emits opcode 0x17, a 54-byte
version-1 kind-11 payload. The installed agent uses horizontal fields before
vertical fields, with line, fixed-16.16 and point deltas, CG scroll/momentum
phases, count and continuous flag bit 1 (value 2). Its legacy pointer-wheel path
calls CGEventCreateScrollWheelEvent with unit 0 (pixel), so sparse wheel ticks
can produce very small movement. These are static implementation observations
on the same macOS beta, not a measured scroll rate or compatibility promise.

The loopback comparison authenticated and completed socket writes, but did not
record corresponding native scroll or magnification delivery on this session.
This establishes neither precise-scroll delivery nor lack of server support.
A diagnostic-only attempt to handle unsolicited ZRLE baseline data without a
framebuffer crashed in HandleZRLETile24. The corrected source advertises Raw and
discards bounded responses without retaining, decoding or rendering their
contents. It still did not prove scroll delivery. Temporary debugger observations
stay outside Git; no debugger or Mac helper enters the iPhone targets.

The next iPhone candidate sends one bounded precise event per update, preserves
both axes and small-motion fractions, and uses three Mac scroll points per phone
point by default. Scroll Speed is adjustable from 0.25x to 4x independently of
Pointer Speed, shared by Desktop/Trackpad and available without a connected Mac.
The Apple banner/auth/layout gate and ARD-30 authentication remain unchanged.
Unknown hosts retain balanced standard wheel input. Native delivery and perceived
scroll speed on the physical iPhone remain acceptance gates.

Development **1.0 (18)** is installed and launched on the physical iPhone. Stable
Xcode builds, required repository validation, 18 indexed scroll vectors, 17
magnification vectors, repeated encoder lifecycles and focused owner/viewer/
settings tests pass. All 578 release-source inputs were checked at signing and
installation. The final native gesture tests also cover accumulated fractional
motion, both axes, bounded fast swipes and independent live speed changes.
These checks do not replace the user’s physical scroll acceptance. Pinch is
already committed; this scrolling follow-up remains uncommitted.

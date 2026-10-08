# Native trackpad gesture feasibility probe

Disposable research into native magnification through **built-in macOS Screen
Sharing**. This directory is not linked into any release target. It is not a
required or optional production Mac helper.

## Question

Can the existing iOS-only client forward a pinch as a native macOS magnification
gesture, using its existing ARD authentication, rather than app zoom shortcuts?

Standard RFB pointer messages only encode position and button/wheel masks.
That does not establish the limits of Apple's extensions. Inspection of the
installed Apple client, server and agent found a separate magnification path.
The authenticated loopback test delivered native magnification to the blue
AppKit view with began/changed/ended phases; see
[EVIDENCE.md](EVIDENCE.md) for the evidence and its limits.

## Run the isolated proof

Requires the clean LibVNCClient source pinned by
`Experiments/VNCPrototype/source-lock.json`, local Homebrew OpenSSL/CMake, and an
already enabled Screen Sharing service on the Mac running the probe. This build
uses local dependencies for research only, not release dependency admission.
The initial proof targets a single display and converts its AppKit coordinates
to the framebuffer's pixel coordinates, including Retina scaling. Multiple
displays require a separate mapping proof; the probe refuses that case.

```sh
python3 Experiments/NativeTrackpadGestureProbe/build.py \
  --source /path/to/pinned/libvncserver \
  --output /private/tmp/native-gesture-probe
/private/tmp/native-gesture-probe/NativeGestureProbe.app/Contents/MacOS/NativeGestureProbe
```

Enter this Mac's account/password in the probe's secure local UI, then choose
**Sign In and Verify**. Do not put credentials in shell arguments, files, logs,
or chat. The password field and handshake credential references are cleared;
credentials are not persisted. Authentication uses the unmodified, existing
LibVNCClient ARD implementation and admits only security type 30.

The probe connects only to `127.0.0.1:5900`, reads the normal ServerInit geometry,
and sends a bounded magnification to its own blue test view. It completes normal
format/encoding setup and sends a zero-area framebuffer update request to exercise
the server's control-availability path, without requesting any desktop pixels.
It does not allocate or render a framebuffer, collect screenshots, record keys or typed text,
install login items, change Screen Sharing permissions, or inject events through
local CGEvent APIs. A test starts only while the probe window is active. The
experiment sends a balanced start/magnify/end sequence, with three `+0.05`
updates. Closing the window terminates the probe and closes its connection.

Success requires the view to receive `magnifyWithEvent:` with the expected
magnification and phases, from the built-in Screen Sharing agent. `GESTURE_SEND`
only proves socket writes. It is **not** evidence of native delivery. The final
probe counts only magnification with a nonzero source PID and the network gesture
mask, during the bounded test; corroborate that PID with `ScreensharingAgent`.
A physical pinch on the test view is not an acceptable substitute. An earlier
probe counted local physical pinches too; the recorded proof relies on the five
matching agent-originated events, not that earlier UI's total count.

When launched in an interactive terminal, the fixed commands `verify-v1` and
`verify-v2` can reuse the already authenticated connection. The default is v2.
Three consecutive repeat tests delivered complete native sequences on the same
authenticated session. Longer-lived delivery and released macOS compatibility
remain open. See the evidence note for earlier missed repeats during local
physical gesture checks.

## Candidate wire layout — research only

Derived from installed Apple binaries, not an Apple-published protocol contract.
Multi-byte fields are big endian.

| Field | Size | Candidate value |
| --- | --- | --- |
| Client message | 1 | `0x17` |
| Header flags | 1 | `0` (no optional suffix) |
| Payload length | 2 | `32` for v2 magnification |
| Payload version | 2 | `2` |
| Payload event kind | 2 | `3` (magnification) |
| Magnification delta | 8 | IEEE-754 double |
| Pointer x / y | 2 + 2 | Position relative to shared display |
| Gesture phase | 8 | Raw CG field 132: began `1`, changed `2`, ended `4` |
| Gesture mask | 8 | `4` (magnification) |

Kinds `1` and `2` carry start/end boundaries: version **1**, kind, 32-bit
`NSEvent.subtype` (**3**, touch), and 16-bit x/y, making a 12-byte payload.
Apple's client uses v1 boundaries alongside v2 magnification. The wire phase
values map to AppKit `NSEvent.phase` values 1/4/8; those AppKit values must not
be sent as raw CG phases. The server checks minimum sizes and
control/observe state before forwarding the endian-normalized payload to its
built-in agent. The experiment uses the ordinary authenticated connection;
no alternate authentication or crypto semantics are implemented here.

The loopback proof establishes native magnification and its phases on this Mac.
Release integration still needs negotiation/support gating, long-lived delivery,
cancellation, multiple-display coordinates, app behavior and compatibility.
Then update the normative
specification and the existing authoritative fixture index before production
wire changes. Do not create a second fixture corpus in this experiment.

## Scroll comparison mode

Launch with `--scroll`; `verify-scroll` repeats on its retained login. It sends
three standard wheel-up ticks followed by a native kind-11 began/change/change/end
sequence (horizontal/vertical +12/+24, then -12/-24). The receiver logs only its
own numeric scroll properties during this bounded verification, including phase,
precision and source PID. Match that PID to ScreensharingAgent. Successful writes
alone do not establish delivery. Physical local scroll must not satisfy the proof.

The probe now advertises only Raw and discards bounded unsolicited server updates
without decoding, rendering or storing their contents. macOS may send a baseline
even for a zero-area request. An earlier diagnostic attempted normal decoding
without allocating an image buffer and crashed; this was an experiment error.
The standalone probe is closed after verification, so it cannot interfere with
physical iPhone testing. Current scroll runtime acceptance remains open; see the
evidence note. No debug-injected observer is part of this source or the iOS app.

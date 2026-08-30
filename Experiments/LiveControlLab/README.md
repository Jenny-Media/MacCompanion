# Live Control Lab

Test-only loopback host and Simulator composition. Shipping targets must never
depend on this package. It uses fresh, temporary software keys and seeded test
pairing/primary state in the older lanes; it never reads production Keychain or pairing storage.
The local test bootstrap is **not** evidence for production TLS, QR scanning,
Secure Enclave, or OS-backed presence. Those remain covered by golden/package
tests and the signed-device release checklist.

## Authenticated journey

```sh
MACCOMPANION_LAB_SUITE=journey bash scripts/verify_simulator_features.sh
```

This profile uses actual production pinned TLS, QR-payload pairing, session
authentication, SQLite paired-device/grant authority, client paired-host/route
files, and mutual-HMAC role-channel handshakes. It restarts both disposable
processes and reconnects from their saved state. Software keys and simulated
human consent replace hardware custody/presence only in this Debug-only lane.
The production client workspace drives Control; status comes from the real Mac
sampler. Tests require client-verified Observe responses and Stop without
re-authentication, plus no automatic Control on any recovery. QR camera
recognition and the outer shipping bootstrap are not covered.

Use `MACCOMPANION_LAB_ITERATIONS=3` to repeat the entire journey, and optionally
`MACCOMPANION_LAB_SOURCE=real-mac-window` to use the own-window capture/input
adapter described below. The command emits a machine-readable `report.json`
and fails if any required test or cleanup fails. Host and Simulator software
keys/stores are deleted on normal runner exit, including failed tests. A hard
kill bypassing shell cleanup requires inspecting the printed run directory.

The live lane exercises production Control messages and approval signatures,
surface/media/input state machines, H.264 encoding/decoding, UIKit gestures and
keyboard behavior over independent loopback sockets. Generated pixels and a
no-post input sink avoid privacy prompts and interaction with the user's apps.
Results must distinguish simulated source/input effects from real capture/TCC.

Follow the [Simulator-first development gate](../../docs/simulator-first-testing.md).
The full suite now includes a three-minute idle-video soak and five
Stop/drop/reconnect cycles with independently probed host capture/queue cleanup.
Use `MACCOMPANION_LAB_SUITE=soak`, `reconnect`, or `lifecycle` to isolate a
failure; `live` retains the shorter gesture/keyboard/surface scenario.

## Opt-in real Mac window lane

```sh
MACCOMPANION_LAB_SOURCE=real-mac-window MACCOMPANION_LAB_ONLY_LIVE=1 \
  bash scripts/verify_simulator_features.sh
```

This builds a separately development-signed `Mac Companion Real Mac Lab.app`
inside the lab derived-data directory. It uses ScreenCaptureKit to capture
only its own 641-by-361 test window (or a 321-by-241 crop), through the real
stream owner, H.264 encoder, transport, and Simulator decoder/display.
The production catalog aligns those odd source sizes to even encoded sizes
before creating the descriptor. Focused-to-focused changes also invoke the
real runtime's input pause before publishing the event, exercising input
already in flight across the independent event/input sockets.
The production input planner and event constructor feed a test-only posting
adapter hard-coded to `getpid()`. AppKit receives those OS-delivered events;
the test editor's actual text and received mouse/Return events determine the
result, not the input sender. No global HID event is posted. Key dispatch is
confined to that editor, not the foreground app or global menu shortcuts.
The test application deliberately dispatches received OS key events into the
owned editor's `NSTextInputClient` methods, so the Simulator can stay foreground.
This verifies event construction/delivery and actual editor text, not normal
foreground-app responder routing or arbitrary-app keyboard compatibility.

The mode accepts only primary clicks, pointer motion, Return without modifiers,
reset, and bounded synthetic test text. It cannot target another app, select a
user window, or become a general-purpose control endpoint. First pairing,
authentication, and approval remain seeded in the older live/integration lanes;
the journey replaces those with the production authorities described above.
Focus recommendations remain test-owned. This is **not** the installed Agent
or arbitrary-app AX-discovery lane.
The authenticated journey uses `AgentInteractiveLeaseRenewalOwnerV1` after the
owned runtime installs its exact lease. An internal Debug-only entry exercises
the same installed-lease read, validation, and scheduling path as shipping
install without inventing an Agent bootstrap. The adapter serializes renewal
with surface mutations and retires the runtime before returning an ambiguous
renewal error. It remains test-owned lease issuance, not Agent final-admission
or XPC evidence. Older live/integration profiles retain their own scheduler;
the separate `interactiveLeaseScheduler` and `agentRuntimeOwner` tests remain
required.

`MACCOMPANION_LAB_SUITE=journey-renewal` checks two healthy renewal deadlines
after a focus transition, then lost acknowledgement and expiry faults while
the keyboard is open. It checks full retirement, no renewal retry, Observe
recovery, and an explicit fresh Control request. `full` includes this test.

Screen Recording and event-posting access must already be allowed. The runner
returns exit 77 with `REAL_MAC_BLOCKED` when preflight fails; it never requests
or changes permissions and never substitutes generated video. After a user
grants access to the lab app, rerun the same command. Development signing can
be selected with `MACCOMPANION_LAB_SIGNING_IDENTITY`; do not use release keys.
Generated mode remains the default and needs none of these permissions.

For three consecutive live scenarios, add `MACCOMPANION_LAB_ITERATIONS=3`.
For a renewal-race stress run, add `MACCOMPANION_LAB_RENEW_MS=100` (test-host
only in older live/integration profiles; the normal interval is 3000 ms).
Authenticated profiles always use production deadline scheduling.
`MACCOMPANION_LAB_DENY_PERMISSIONS=1`
forces the preflight-denied path for a negative test; it cannot grant access.

The visible test window contains only synthetic content. Logs retain counters
and match booleans, not text or video. XCTest may retain Simulator screenshots
of this synthetic window in the temporary evidence directory. Cleanup stops
the owned process/window and removes the per-run bootstrap credentials.

## Additional isolated Agent/XPC lane

See [AGENT-XPC.md](AGENT-XPC.md) for the signed, disposable multi-process
startup/bootstrap/status tests. This lane does not use the Simulator, installed
Agent, or physical iPhone; it complements the live-control journeys above.

# Client Continuous Media Authority Handoff Evidence

Date: 2026-08-21

Environment: bundle-independent Interactive client authority and selected-
primary channel tests under Xcode 27 beta. This is unsigned construction
evidence. It is not physical H.264 decode/display, network-latency, posted-
input, stable-toolchain, signed-candidate, or release evidence.

## Boundary completed

Initial Desktop activation and steady surface control now have one continuous
media/input ownership path. After the renderer proves the initial clean frame
and the client sends its acknowledgement, the initial owner continues to admit
gap-free media for the exact descriptor while the host acknowledgement reply
is pending. The reply atomically hands the same media and input authorities to
the ordinary surface-control coordinator.

The handoff preserves the admitted decoder configuration, latest media
sequence and presentation timestamp, pending-free current descriptor, active
input descriptor, reliable-input sequence, and pressed-state fence. It does
not require another configuration record and does not recreate either
authority. The ordinary replacement command sequences still begin at three in
each direction because the initial request/acknowledgement exchange consumed
one and two. Closing after handoff sends the next reliable reset and then
fail-closes both input and media.

## Regression proof

The initial-coordinator regression admits configuration sequence 1, clean
keyframe sequence 2, and delta sequence 3; receives the exact acknowledged
reply; transfers ownership; then admits delta sequence 4 without another
configuration record. It proves that the first reliable pointer event remains
sequence 1, the selection reset is sequence 2, and the replacement request
uses primary sequence 3.

The selected-primary regression additionally admits delta sequence 3 after
the client acknowledgement request but before its reply, admits sequence 4
after the handoff, produces reliable input sequence 1, and closes with reset
sequence 2. These cases would fail under the previous reconstruction/routing
behavior that rejected post-activation media or discarded live media state.

## Remaining gates

- Exercise the same continuity through the authenticated media/input socket
  pumps with real VideoToolbox decode and display on a physical iPhone.
- Prove reset delivery, host-side post-event verification, backgrounding,
  replacement, revoke, and lock fallback on signed physical devices.
- Re-run on stable Xcode 26.6 and preserve signed-candidate evidence
  separately.

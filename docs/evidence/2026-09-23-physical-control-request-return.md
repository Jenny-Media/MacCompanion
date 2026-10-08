# Physical iPhone Control request return

Date: 2026-09-23

## Observed failure

On the paired physical iPhone 18 Pro Max, requesting Remote Control briefly
opened the live path and returned to the workspace. Four attempts in the
app's bounded, content-free diagnostic log reported
`interactive.media-pump.terminal` followed by
`interactive.activation.fail-closed`. A foreground console reproduction
identified the media-pump error as `invalidRead`; the primary connection then
closed and reconnected.

At the same attempt time, Mac Companion's `interactive-capture` logs showed
Screen Recording permission available, shareable-content enumeration complete,
and the H.264 capture stream started. Its local XPC log then showed
`webRTCOffer` failed with `unavailable`, followed by capture teardown. The
WebRTC offer failure is the initiating observed event; the iPhone read error
is a consequence of the host closing the media path. No crash was observed.

A second physical run with the repaired timing reached the exact initial
surface acknowledgement before `webRTCOffer`, then failed identically. The
new menu-adapter diagnostics did not run. Source inspection found that the
local XPC handler calls `makeWebRTCOffer(_:nowMonotonicNanoseconds:)` and
`acceptWebRTCAnswer(_:nowMonotonicNanoseconds:)`, while the concrete menu
adapter had implemented one-argument overloads. Protocol dispatch therefore
used its default `unavailable` methods. This is the root cause of the offer
failure.

## Repair installed

The iPhone now starts the development WebRTC candidate only after the
existing initial Desktop path confirms a rendered H.264 frame and reaches
the active Control state. A failed candidate restores the existing input path
when the baseline Control state remains active. The Mac offer adapter now
records content-free stage diagnostics to distinguish an inactive runtime,
expired lease, surface-fence mismatch, peer-construction failure, and offer
generation failure. Its offer and answer methods now implement the exact
two-argument local XPC handler requirements. These logs do not contain session identifiers, SDP,
addresses, screen content, or input.

Signed development Mac, Agent, and iPhone builds compiled and passed strict
deep signature verification. The staged bundles retained the built targets'
entitlements. Both normal apps were updated without deleting their data; the
registered Agent restarted. `bash scripts/validate.sh` passed the indexed
fixtures and policy stages, then stopped at the configured missing
`/Applications/Xcode-beta.app/Contents/Developer/usr/bin/stapler` tool. The
gate was not changed or waived. After the exact-method repair, the signed Mac
bundle was rebuilt, verified, installed into the normal application path, and
its registered Agent was restarted. The iPhone already has the timing repair.
The new Mac and Agent processes are running; the recorded bounce attempts
above belong to the previous Mac process.

## Remaining device evidence

The final corrected Mac build needs a fresh physical Control request to
confirm that the iPhone stays on the live screen and renders a WebRTC frame.
CoreDevice could not attach the post-install foreground console because the
phone was locked.
The local XPC channel still treats any optional WebRTC offer error as a
terminal command failure; a later failure could still close Control. The
candidate's cause and that failure handling need a fresh device result and
further repair before claiming reliable WebRTC operation.

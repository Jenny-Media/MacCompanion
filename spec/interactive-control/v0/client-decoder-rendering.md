# Client decoder and render authority v0

Status: normative bundle-independent decoder-generation and bounded render
state. Concrete VideoToolbox construction is compile-checked separately;
physical decoding and display remain release evidence.

Only a record already admitted by `ClientMediaStreamAuthorityV0` may enter this
authority; that upstream admission supplies the initial descriptor authority.
The decoder authority then requires the record type, payload length, its bound
session/epoch/surface/revision fence, signed-CoreMedia timestamp range, and
shared AVCC profile to agree before it emits a decoder command.

Initial configuration creates decoder generation 1. Discontinuity immediately
advances the generation, clears the latest frame, and requires configuration
plus a clean keyframe for the new exact fence. Reconfiguration without a
discontinuity also advances the generation and clears retained pixels. Every
decode command binds generation, media sequence, presentation time, dimensions,
clean-keyframe truth, and the complete surface fence.

Decoder callbacks are untrusted asynchronous results. A callback from an old
generation or fence, beyond the latest submitted sequence, or no newer than the
latest accepted frame is discarded without becoming visible. The authority
retains metadata for at most one latest frame; replacement drops the prior
opaque local frame reference. Discontinuity, end, channel close, backgrounding,
render loss, lock, or session teardown clears the frame before reporting a
blank state.

For initial Desktop activation, only a frame that passes this callback gate and
is then accepted by the concrete renderer may satisfy the primary-channel
acknowledgement fence. Decoder submission, callback admission without render
success, a stale callback, and a render failure never satisfy that fence.

Replacing or invalidating a concrete decoder waits for its submitted
asynchronous frames before invalidating the old VideoToolbox session. Callback
generation checks remain mandatory because completion may still race the pure
render authority and UI delivery.

No pixel buffer, format description, decoder object, or opaque frame reference
crosses the protocol, Agent IPC, logs, or persistence. Release acceptance needs
real configuration/access-unit decoding, pixel-format and dimension checks,
render-queue serialization, blanking screenshots, stale-callback races,
orientation changes, memory pressure, thermal behavior, and measured latency on
physical supported iPhones and iPads.

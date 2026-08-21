# Client render handoff v0

Status: normative bundle-independent callback-pressure and blanking profile.
The concrete iOS display-layer construction is compile-checked separately;
physical presentation remains release evidence.

VideoToolbox callbacks must not each enqueue independent main-actor work. A
single-slot mailbox owns at most one pending callback result and at most one
scheduled drain. A strictly newer generation/sequence replaces the pending
frame; an out-of-order callback cannot. A decoder failure cannot be replaced
until the main actor classifies it as current or stale.
The clean frame required by an initial or replacement acknowledgement is also
non-replaceable until the main actor drains and renders it; later delta
callbacks cannot overwrite that acknowledgement proof.
Completing a drain schedules exactly one successor only when another result
arrived during presentation.

The main-actor coordinator is the sole owner of decoder commands, decoded-frame
admission, and rendering. It presents a pixel buffer only after the decoder
authority accepts its exact generation, fence, and sequence. A stale callback
is discarded. A current-generation decoder failure, record-processing error,
renderer error, explicit close, end, or interruption closes the authority,
invalidates the decoder, closes the mailbox, and synchronously removes the
displayed image.

Configuration, reconfiguration, and discontinuity blank the prior displayed
image before a replacement decoder can become visible. The concrete renderer
accepts only the declared dimensions and the v0 bi-planar video-range pixel
format, constructs a display-immediate sample locally, flushes pending display
work, and retains no protocol-visible frame object. The view uses aspect fit;
input mapping remains bound to the separately calculated rendered-content
rectangle, not the view bounds or display layer.

Release acceptance requires a physical iPhone/iPad to prove that callback
bursts stay bounded, every terminal path removes pixels before reporting a
blank state, reconfiguration does not expose an old frame, background and
orientation transitions are safe, display-layer failure is observed, and
latency/frame pacing meet the product budget.

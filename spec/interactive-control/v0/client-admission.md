# Interactive Control client admission v0.1

After activation, media EOF, a terminal end record, or media admission failure
must retire local input/rendering and publish terminal Control progress for
the exact activation, primary connection, and interactive session. An already
active workspace is not exempt from that publication. Late callbacks from a
retired activation cannot affect a replacement. Explicit local close must not
produce a new failure publication. Observe remains independently usable; the
existing authenticated Stop exchange resolves the old session before another
explicit Control request. No wire message or grant is added by this rule.

Status: normative bundle-independent client composition for media admission and reliable input production. Client gesture-to-payload rules are defined separately in `client-input-mapping.md`; this document does not define channel sockets, VideoToolbox decoding, UIKit recognizer lifecycle, rendering, user-presence UI, or host authority.

## Media before decoding

The client creates one media authority from the strict current `AdaptiveSurfaceDescriptor`. A media payload remains opaque and is not given to a decoder until its fixed 96-byte header has passed:

- record-specific header and payload-length bounds;
- exact session, authorization epoch, surface ID, surface revision, and coordinate-space revision;
- strictly increasing media sequence and nondecreasing presentation timeline;
- exact encoded dimensions from the current descriptor; and
- decoder configuration followed by a clean random-access keyframe.

The authority observes only the payload byte count. It does not parse, retain, log, hash, or copy encoded screen content.

Initial presentation requires configuration plus a clean keyframe before the client may acknowledge the surface. A decoder configuration change again requires a clean keyframe before dependent video is admitted. Delta video before that boundary closes the channel.

## Surface transitions

Before a new descriptor can become current, it must carry the same session and authorization epoch and strictly advance both surface and coordinate-space revisions. Only a discontinuity record carrying the complete new fence activates it. Configuration and video for the pending surface before that discontinuity are terminal failures.

The new surface is acknowledgement-ready only after its exact configuration and clean keyframe arrive. The resulting acknowledgement fence contains the current session, epoch, surface, coordinate, and optional focus revisions. Input remains paused until the reliable control channel sends that acknowledgement and the client input producer is explicitly activated with the same descriptor.

Admitted payloads then pass through the independent decoder-generation and
latest-frame authority in `client-decoder-rendering.md`; admission alone never
makes decoded pixels current.

End and discontinuity records carry no content but still require the exact current or explicitly pending fence. An old record cannot reset or end a replacement stream. Any invalid remote media closes the authority and clears decoder/acknowledgement state.

## Reliable input production

The input producer starts paused and is activated only with an acknowledged descriptor for its exact session and authorization epoch. Later activation requires strictly newer surface and coordinate revisions.

Before assigning the next sequence number it verifies:

- nondecreasing client monotonic time and available safe-integer sequence space;
- the descriptor advertises pointer, keyboard, or text interaction for that payload;
- text has both Keyboard and Text interaction authority and is not bound to a positively identified secure focus; missing or ambiguous Accessibility focus remains usable as ordinary remote keyboard input;
- button and physical-key transitions are locally balanced; and
- the payload itself satisfies the closed reliable-input schema.

Rejected local input consumes no sequence number and changes no pressed state. Once assigned, an envelope is reliable and cannot be coalesced, dropped, or reordered by the socket adapter. Pointer movement may be coalesced only before this call.

Before a surface revision change or ordinary close, the producer emits one sequenced `reset` under the old acknowledged fence and enters paused/closed state. The socket owner sends that reset before activating a new descriptor; transport loss still causes the host to release all held input independently.

Sending on the input socket does not prove host receipt before the primary
selection request. A reset overtaken by successful host preparation is drained
without effects under the exact retired-fence rule in `menu-runtime-composition.md`.
This exception neither admits stale input nor resumes replacement input early.

## Acceptance boundary

Bundle-independent acceptance covers configuration/keyframe gating, stale fences, payload length and dimensions, sequence/timeline rollback, discontinuity transitions, acknowledgement fences, interaction classes, positive secure-focus denial without missing-focus denial, balanced transitions, monotonic client time, and reset-before-revision advancement. Release acceptance additionally requires bounded binary socket allocation, VideoToolbox format/decoder reset, render queue and blanking behavior, UIKit gesture/keyboard mapping, physical lock transitions, latency budgets, and content-free diagnostics.

# Local native runtime snapshot v0.1

The authenticated Agent-to-menu connection may request
`runtime.interactive.native.snapshot` with a command ID and the already admitted
native request fence. Success is `runtime.interactive.native.snapshot.ack`, bound
to the exact command ID and fence. This operation uses applyInteractiveSurface,
the shared one-command-in-flight generation gate, canonical JSON at most 4096
bytes, existing receiver/sender deadlines and malformed-traffic retirement.
It introduces no application authentication, approval or signature mechanism.

The menu reads one atomic active runtime snapshot only when the current Desktop,
App or Window has completed configuration, clean-frame and surface acknowledgement
admission. It rejects focus pause, transitions, expired lease/session, focused
region and fence mismatch. The projection contains host/device/session IDs,
epoch, opaque selected
display, immutable surface revisions/dimensions, install command generation,
visible menu generation/revision, current lease expiry and ORIGINAL session
deadline. It omits device names, physical display IDs, content, keys and pixels.
Lease renewal cannot change the install generation or original session deadline.

The projection also requires `logicalWidthPoints`, `logicalHeightPoints` and
`rotation` from that same acknowledged descriptor. Logical dimensions
are integers in 1…4294967295; rotation is the closed value 0, 90, 180 or 270.
Encoded dimensions cannot substitute for logical bounds. Renewal preserves all
three fields. Missing, malformed, zero or oversized logical dimensions, unknown
rotation or unknown fields fail closed; there is no encoded-only compatibility
fallback. This projection contains no capture-mode pixels or clean-aperture
evidence and cannot by itself release the native input pause.

The projection also carries the acknowledged `surfaceKind` as a closed
`desktop`, `application` or `window` value. The field must be present in
the canonical local receipt; missing, focused-region or unknown kinds fail
closed. App/Window require a completed surface acknowledgement and fresh
native enrollment under the replacement fence. The menu backend owner
must bind an absent selected-capture object only to Desktop and a present,
current selected-capture object only to the matching App or Window kind. This
prevents App/Window runtime admission from silently using the Desktop capture
path when the menu selection is unavailable.

The Agent checks its active primary/session and authenticated menu generation
before and after the request. It joins host/device/epoch to its current primary
context, copies client ID, host pin, primary ID and durable revisions from that
context, and uses the original session deadline to construct the native binding.
Its internal native runtime projection must retain both logical dimensions and
rotation without substituting encoded dimensions. Store-bound composition compares
these fields with the complete snapshot before and after inert backend construction
and on each later authority read. A geometry change invalidates the enrollment.
These metadata fields do not change enrollment signatures or grant input.
Stop, exact menu invalidation and terminal teardown fence native admission
before waiting for the serialized or platform cleanup chain.
Snapshot receipt alone grants neither host startup nor input. The existing
store-bound native composition must still recheck durable grants and registered
session key around backend construction and on every authority read.

An injected backend factory remains inert until attested enrollment preparation.
Physical display mapping and process startup remain owned by the menu runtime;
this snapshot never lets the Agent select a CoreGraphics display identifier.
Missing snapshot/backend support fails closed. Release targets cannot import
experimental dependency or host adapters.

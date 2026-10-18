# Direct iOS desktop size

The direct iOS client may request a landscape virtual desktop from the built-in
Mac Screen Sharing service. It retains SSH forwarding, host-key verification,
ARD authentication, foreground ownership and the existing input/frame epochs.
No authentication, pairing, cryptographic record layer or host helper is added.

The independent bounded message-29 builder and message-13 selection vectors in
`ios-dynamic-resolution-prototype-v1.json`, indexed by the sole fixture manifest,
remain authoritative wire facts. The tested resize handoff is promoted from the
isolated experiment; no `Experiments/` source is linked into the application.

## Product behavior

Edit Mac → Screen Sharing Display remembers a device-local choice for each Mac:
Virtual Display (recommended, Balanced by default) or Mirror Mac Screen (value 0).
Virtual Display creates a landscape desktop; the Mac's physical screen may go dark.
Mirror Mac Screen preserves its physical resolution and layout. Existing stored
presets 1–3 retain their meaning. A missing or invalid setting defaults to Balanced;
an explicit zero means mirror. Cancel in Edit Mac must not save a draft choice.

Display directly offers the same two choices on supported Apple hosts.
Desktop Size is shown directly in Display only for Virtual Display and offers Larger Text
(1024 × 640 points), Balanced (1280 × 800, recommended), and More Space
(1440 × 900), all landscape 16:10 at density 2. Rotation, keyboard, composer,
Fit and Zoom never request a resize. Explicit successful virtual changes are saved
only after matching layout and a fresh complete frame; failures retain the previous
choice. A configured virtual choice is restored at most once per replacement owner.

An explicit active-session change between Virtual Display and Mirror Mac Screen
first presents a confirmation. Titles are "Switch to Virtual Display?" and
"Switch to Mirror Mac Screen?". Messages are "Your connection will restart. Your
Mac’s screen may go dark." and "Your connection will restart to show your Mac’s
displays.". Actions are Cancel and Switch & Reconnect. If borrowed Files has an
active transfer, append "File transfers using this connection will stop." Cancel,
inactivity, exit and stale-owner confirmations cannot save or start a change.
Ordinary reconnects, initial saved choices and physical monitor selection have no
confirmation. Revalidate the captured owner and foreground readiness on acceptance.

Both confirmed mode changes use the same full restart, preserving only transient
login (including unremembered credentials), a dimmed preview and the target mode.
Retire input and the old native callbacks, join all prior SSH retirement including
cancelled connection-opening tasks, then create a fresh native and SSH owner.
Do not restore the old mode's crop, zoom, selected ID or pending resize. Keep one
"Switching display mode…" status through the whole transition. Save a new mode
only after its validated layout and complete fresh image have been presented.
Failed changes keep the previous saved preference and allow explicit retry of
the failed target using session login recovery.

A virtual-to-physical transition permits the existing bounded 16-second quiet
allowance after all known retirement work, without a promised completion countdown.
The allowance is not a host readiness acknowledgement. If a fresh complete layout
is still virtual, retire it and permit one additional full quiet/reconnect attempt
within the same operation. Initial saved Mirror with an unexpected virtual layout
uses that same bounded recovery once. No network/login retry, general reconnect
loop, helper, UDP negotiation, new wire packet or host process control is added.
Another connection can reset the host's idle exit timer; do not infer its source.

The independent native handoff gate blocks all user input while receiving frames.
A narrowly admitted handoff-only preset request may create the virtual display
without opening this gate: it still requires this established Apple owner's valid
metadata, fresh baseline and all foreground/review/pause/stop guards. Generic
resize APIs remain blocked during a mode handoff. Verify the requested mode and
complete pixels before enabling input. Unsupported legacy hosts retain ordinary
connection behavior and are not marked as verified mode changes.

Failure stage 116 means the host still reports a virtual display after Mirror
recovery; 117 means the requested virtual display could not be established; 118
means display metadata did not arrive within forty foreground seconds after
establishment or resumption. Interruptions invalidate the old timer; resumed
verification gets its own bounded timer on that owner. Preserve
these failures across intentional stop callbacks and manual retry, including
pre-frame failures. Stop/reconnect errors cannot replace them with a generic
connection-ended notice. Keep bounded numeric target, attempt, phase and last
failure diagnostics; no endpoint, credential, pixels or input values are retained.
Exit, owner replacement, inactivity or app locking cancels pending work. Cleanup
requirements survive interrupted foreground recovery; stale callbacks cannot
complete another owner's operation or save a preference.

Choose Display sends the indexed message-13 request on the existing authenticated
socket. IDs must come from validated metadata retained for this owner. ID zero
requests All Displays. Retain the full physical catalogue while a single display
is streamed, so another display and All Displays remain available. Menu visibility
must use this retained catalogue, not the one-monitor selected-stream layout. Selecting a
monitor must not crop an unrelated framebuffer using old catalogue coordinates.
Acceptance requires matching fresh geometry and complete pixels; all-display
acceptance additionally requires the retained catalogue's original dimensions and
IDs. Do not save a selection on a timeout, send failure, interruption or stop.
Unsupported Apple selection reports failure and recovers the current baseline.
Hosts without validated Apple metadata retain their existing local crop behavior.

## Admission and handoff

Only an established Apple desktop with a validated layout and ready foreground
input may admit a request. Input-only, text review, interruption, paused, stopping,
concurrent resize and active pointer interaction states reject it. The sole socket
owner releases actually-sent input before sending one request. Pending input and
old presentation epochs are retired. Physical monitor and same-mode virtual-size requests never reconnect or replay a resize;
mode changes use the full restart specified above. Generic packet building stays bounded at 6 million pixels;
the public preset API admits only the three indexed landscape sizes.

Validated single-display metadata may announce backing dimensions without a
standard DesktopSize rectangle. For requested virtual or selected streams, adopt
those dimensions only during the corresponding explicit operation on the socket
owner within framebuffer limits. The bounded physical All Displays recovery
below handles unsolicited catalogue changes separately. A matching late virtual
layout may be adopted on this owner while its original request is still current,
up to thirty seconds from the write; only complete matching fresh pixels may
reconcile the earlier timeout into success. A newer request, interruption or
retirement cancels that late-result window. A same-size transition
from physical to virtual also retires old pixels. Exact acceptance requires the
requested dimensions, matching single virtual layout and fresh complete pixels.
A different host-selected size is reported as different, not accepted. Physical
monitor selection retains its six-second layout bound. Virtual display creation
and same-mode virtual resizing allow twenty seconds for layout; do not apply the
physical-monitor timeout to host display creation. On timeout recover the current
baseline, or end a pending mode change with its specific recovery. Once the exact layout arrives, its fresh-pixel
baseline has the existing eight-second absolute deadline from that baseline's
reset. Do not discard a progressing matching image at the earlier layout deadline.
Never stretch old pixels or reopen input before the new frame is usable.

## Evidence boundary

The physical iPhone experiment successfully resized the test Mac after correcting
small-mode sizing and metadata handoff. The initial attempt timed out and then
reconnected at 1600 × 1200 rather than the requested 880 × 1912. Reconnection alone
is not evidence of acceptance and need not restore a physical desktop. These
results do not establish support on every Mac, a high-performance video engine,
or production/release admission. Simulator and stable-toolchain checks remain
separate from physical acceptance and distribution.

## Selected monitor metadata with a retained physical catalogue

Apple 1105 may retain all physical display records and their global backing
rectangles after message 13 selects one display. The header's backing size then
names only that display's stream, while its logical size may still describe the
combined desktop. A record outside the selected stream is not necessarily corrupt.
The current display ID is the big-endian uint32 at header offset 10.

For a nonzero, explicitly selected ID in this socket owner's previously validated
catalogue, accept this form only when header current ID matches, stream width and
height exactly match that display's bounded rectangle, and every retained catalogue
ID and rectangle still matches the validated catalogue. Normalize just the active
display to stream origin (0,0); keep the full catalogue separately for the picker
and All Displays. Compute the active display's backing scale from its own logical
and backing widths, not the combined logical width in the header.

Do not relax the ordinary all-display parser, admit unknown IDs/versions, accept
malformed companion records, or infer geometry from pixels. A fresh normalized
layout and complete selected-stream baseline must reopen input without reconnect.
Repeated identical catalogue-bearing metadata must not invalidate a ready baseline.
Virtual-to-mirror retirement/reconnect stays automatic; no manual reconnect is a
normal part of the display choice. An initial pixel baseline for the selected
monitor must not wait for unstreamed physical monitors or desktop gaps.

## Repeated selection and update ordering

Selecting the already active, fully presented physical stream is an immediate
success. Keep its input and pixels ready, do not send message 13, and do not start
a new deadline. This applies to All Displays only with the full matching catalogue.
An in-flight or incompletely presented stream is never treated as a no-op.

For an actual physical display selection, release held input and send selection
on the sole socket owner. Retain an already active, validated physical automatic
subscription until matching metadata arrives: disabling it first can silence the
path that reports the new layout. Never start or renew an old-bounds subscription
or send old-canvas full-frame requests while awaiting that metadata. Retire the
old subscription when adopting changed bounds, then arm only matching dimensions.
Routine incremental pulls remain suppressed during the switch, and old pixels
cannot reopen input. Pause, input-only and retirement still disable delivery.
Virtual sizing retains its stop-before-request handoff. Fresh-pixel watchdog retries must not request old bounds
while awaiting that layout; the existing bounded selection deadline still applies.

After selecting a new stream, one non-incremental standard framebuffer request
for the bounded 1 × 1 origin rectangle may solicit the new metadata while old
bulk delivery is stopped. Do not treat its pixels as a new complete baseline.
Send it once initially, then at most twice more at 0.5 and 1.5 seconds after
the write if matching metadata is still missing. A host may consume an early
request before its display handoff finishes. These tiny bounded requests do not
replay selection, rearm the old canvas, or extend the six-second layout deadline.
Normal full refresh and automatic delivery still wait for matching new layout.

## Switch refresh scheduling

While a selected-display baseline is incomplete, permit one initial full refresh
for that baseline. Coalesce repeated full-refresh flags for the same baseline.
Retry only after at least one second without newly covered required pixels, and
at least one second after the previous full request, with the same two-retry and
eight-second absolute baseline bounds. Repeated or out-of-bounds rectangles are
not progress. The eight-second deadline is not extended by progress.

During an actual Apple display switch, suppress LibVNCClient's automatic routine
incremental request after each incoming update until the fresh image is presented.
The explicit new-baseline request and Apple automatic delivery remain active.
After presentation (or bounded fallback), restart the ordinary incremental chain
exactly once on the sole socket owner; steady-state cursor-only pulls remain
unchanged. Paused, input-only and retiring owners must not restart it.

Diagnostic switch history is bounded to twelve numeric records for the current
socket owner. It may contain sequence, display ID, dimensions, owner-queue and
layout/frame durations, local unread-byte count, full-refresh/retry counts and
outcome. It never contains payloads, screenshots, endpoint names or input content.

## Per-switch timing diagnostics

The optional post-authentication read-service descriptor may collect counters
for successful plaintext RFB socket reads, bytes delivered to the parser, and
monotonic time spent explicitly waiting for socket readability. A buffered parser
read must not count the same socket bytes twice. Counters include no byte values
or payloads. SSH ciphertext, encryption overhead and physical network traffic
are outside this measurement. Disabled counters preserve ordinary read behavior.

Capture snapshots on the sole owner at selection write, matching layout and
complete fresh pixels. Retain bounded numeric deltas in the existing twelve-entry
switch history, alongside frame-copy and main-queue time. Socket waiting includes
inner partial-message and outer owner waits, and cannot distinguish host image
production, network transit, SSH relay scheduling or thread scheduling. Worker
thread CPU after layout is processing time, including parsing, decoding, coverage
bookkeeping and cooperative input service; it is not a pure decoder benchmark.
Do not label wall time minus CPU as network latency. Mark incomplete measurements
unavailable; never reuse a preceding switch or socket owner's values.

These counters do not modify packet order, compression, pixel quality, update
pacing, readiness, retry bounds or authentication. They are absent throughout the
handshake and detached before socket cleanup. No endpoint, cursor trajectory,
credential, typed text, screenshot or image bytes are retained by diagnostics.

## Local menu and pointer handoff

Opening the local control panel or a modal menu retires active remote pointer,
scroll and magnification recognizers and releases held input. Late pointer
callbacks while that local interface is open must not reactivate touch ownership.
An explicit display-picker choice retires any remaining previous interaction
before checking ordinary session readiness. This is a local UI handoff; direct
session requests during an actual pointer interaction remain rejected.

A rejected enabled choice must retain a visible four-second notice and a bounded
numeric rejection count/reason. No request, reconnect, preference save or readiness
relaxation is inferred from tapping a row. Foreground, review, pause, owner and
fresh-image requirements remain authoritative.

## Unsolicited physical catalogue recovery

An established Apple physical All Displays stream may announce a different full
physical catalogue without a standard DesktopSize rectangle. When there is no
pending or awaiting explicit operation, accept its backing dimensions only if an
ordinary validated version-5 body identifies All Displays with current ID
UINT32_MAX, is nonvirtual, and follows this owner's validated physical catalogue.
Selected-catalogue normalization, preauthentication, virtual and selected-ID
headers cannot authorize this recovery. Keep the existing framebuffer byte bound.

The sole owner stops old automatic delivery, reallocates at the validated bounds,
retires pending input/presentation and requests a fresh complete baseline. Adopt
the new full catalogue for subsequent selections. Input remains unavailable until
that baseline is presented. No selection packet, reconnect, preference save or
successful explicit-switch result is inferred. Track only a numeric adoption count.

## Stable picker targets and reconnect diagnostics

Repeated unchanged catalogue/selection refreshes must preserve visible picker rows
and the user's touch highlight. Update changed checkmarks in place. Actual display
catalogue changes still refresh the list; a chosen ID is admitted against the
latest validated owner, never guessed from a row position.

Retain at most one numeric post-authentication connection-failure snapshot across
reconnects in the same viewer. Clean intentional disconnects do not replace it.
The next normal diagnostic includes this snapshot so reconnecting does not erase
the failure evidence. No state text, endpoints, credentials, pixels or input
content is retained; the existing bounded numeric switch history remains bounded.

# Initial surface activation

The first Desktop is not a replacement transition. It has no old acknowledged
surface, no reset under an old fence, and no discontinuity requirement. It is
activated through a separate four-message exchange on the authenticated
application-primary command channel:

1. The client sends `interactive.surface.initial.request` after validating
   `interactive.session.accepted` and before producing any input.
2. The host replies with `interactive.surface.initial.descriptor`. The body
   carries an Agent-issued opaque `activationID`, the Desktop wire descriptor,
   `mediaSequenceBeforeActivation: 0`, and the next server sequence.
3. The client admits decoder configuration followed by a clean keyframe under
   that exact descriptor, VideoToolbox returns the exact current-generation
   frame, and the renderer accepts that frame for presentation. Only then may
   it send
   `interactive.surface.initial.ack` with the activation ID, complete surface
   fence, clean-frame media sequence, and next client sequence.
4. The host revalidates the live principal, lease, descriptor, activation ID,
   and menu-runtime media boundary. It resumes input locally before replying
   with `interactive.surface.initial.acknowledged`. The client activates its
   input producer only after validating that exact reply. The client then
   atomically transfers the already-live media authority and the newly active
   input authority to the ordinary surface-control owner; it must not recreate
   either authority at this boundary.

All four messages use the ordinary seven-field capability-protocol envelope.
Both requests have null `correlationID`; each reply correlates to its request.
The client and server sequences are the same per-direction positive safe-
integer sequences subsequently used by surface replacement messages. A gap,
duplicate, wrong correlation, wrong phase, or exhausted sequence closes the
surface-control authority and the Interactive session fails closed.

## Message bodies

`interactive.surface.initial.request` contains exactly
`interactiveSessionID`, `authorizationEpoch`, and `sequence`.

`interactive.surface.initial.descriptor` contains exactly `activationID`,
`descriptor`, `mediaSequenceBeforeActivation`, and `sequence`. The descriptor
uses the relative-validity projection frozen in `surface-control-messages.md`.
The media sequence is exactly zero in v0.1. The descriptor is Desktop, has
surface and coordinate revisions exactly one, has no app/window/focus tokens or
metadata, uses `visualOnly`, and binds the accepted session and epoch. Its
interaction classes are a subset of the approved effects and exactly match the
local execution lease.

`interactive.surface.initial.ack` contains exactly `interactiveSessionID`,
`authorizationEpoch`, `activationID`, `surfaceID`, `surfaceRevision`,
`coordinateSpaceRevision`, `readyMediaSequence`, and `sequence`. The initial
Desktop has no focus fields. The ready sequence is the exact positive clean-
keyframe sequence obtained from the media authority and confirmed by the
decoded-and-rendered frame receipt. Merely receiving, validating, or submitting
the compressed keyframe is not an acknowledgement boundary.

`interactive.surface.initial.acknowledged` repeats every acknowledgement field
except the request sequence, adds `inputResumed: true`, and carries the next
server `sequence`. It is emitted only after the visible menu runtime has
accepted the acknowledgement and enabled the same lease fence.

## Local runtime ordering

Install success means only that the indicator is visible and capture is ready.
It sets initial surface admission to `requiresConfiguration(activationID)` and
keeps input denied. Initial media must be configuration then clean keyframe,
and that exact clean keyframe must complete the current decoder generation and
be accepted by the renderer;
an initial discontinuity, delta frame, input event, or acknowledgement before
that boundary is rejected. The existing typed local acknowledgement command
uses the install command ID as its `transitionCommandID`; this is a local
correlation field only and does not turn initial activation into a replacement.
Expiry, revoke, Agent IPC loss, malformed media, or acknowledgement mismatch
still invokes the complete release/stop/blank/indicator-clear safety path.

After both secondary role channels authenticate, the iOS client immediately
presents its live-control destination and begins the initial Desktop request;
it does not require a second user action after device-presence approval. This
ordering makes the verified renderer the prompt consumer of the host's bounded
capture stream. A manually delayed navigation step must not leave authenticated
media unread until transport backpressure terminates the safety runtime.
The host encoder keeps one frame in flight through the complete downstream
publication acknowledgement, not merely through the VideoToolbox callback.
While publication is suspended it retains at most the newest waiting source
frame and requires that replacement to be clean. A capture callback cannot
start another encode until publication completes, so role-channel startup
latency cannot bypass this bounded backpressure or overflow the menu queue.

A system-stopped Desktop capture, including the stop ScreenCaptureKit emits
when the console locks, retires the platform input configuration immediately.
It does not by itself discard the approved Interactive session or prevent an
otherwise exact lease renewal. While the same session, authorization epoch,
display, surface, and revisions remain current, the menu may retry that capture
after a bounded delay. Every retry first publishes a gap-free discontinuity
under the current lease fence, resets decoder configuration state, and uses a
new encoder whose first accepted access unit is clean. Input remains unusable
until the platform capture and input configuration have both been rebuilt.
Any non-system capture termination, failed discontinuity publication, changed
surface, revoke, expiry, or IPC authority loss performs the normal fail-closed
session teardown instead of recovery.

The media stream does not pause while the client waits for the exact
`interactive.surface.initial.acknowledged` reply. After the clean-frame fence
has been taken, the initial owner continues to admit gap-free media for the
same descriptor, including delta access units. On the exact acknowledged reply,
the steady surface-control owner inherits that same media authority, including
its decoder configuration, last admitted media sequence and presentation time,
and the same input authority, including its next reliable-input sequence and
pressed-state fence. The handoff retains the next primary command sequence of
three in each direction. Reconstructing media or input state, requiring a
second decoder configuration, accepting a media gap, or resetting reliable
input at this ownership boundary is non-conformant and fails closed.

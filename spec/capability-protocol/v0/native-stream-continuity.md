# Native stream continuity v0.1

Ordinary selected-display, selected-window and selected-application changes may
retain the owned native host, its certificate, enrolled client certificate and
encrypted video connection. This is a resource optimization within the existing
Control approval. It does not carry presentation or input authority forward.

The normal client owns a view change until fresh native presentation and input
admission finish, not merely until the surface-selection reply arrives. During
that interval another local view choice is rejected locally without retiring
Control. A repeated active workspace publication cannot release this gate.
Stop or background may cancel the gate; a late completion cannot reopen it.
Measure elapsed transition stages with a monotonic clock and content-free
local attempt identifiers. A successful selection reply is not a successful
view-change measurement. The completion point is fresh input admission.

An absent capture observation during initial native presentation may remain
pending for at most two seconds, bounded by the original Control deadline.
Recheck exact authority and backend activity across every suspension. A sample
with a wrong binding, invalid shape or future timestamp is rejected immediately;
pending observations are never presentation or input admission.

After a previously presented native view fails, the normal client may request
one fresh Desktop enrollment under the exact still-active primary and original
Control binding and deadline. This also applies to a Desktop capture failure.
Never retry after Stop, background or loss of Control. Limit recovery to one
attempt until video and input remain healthy for 30 seconds or the user chooses
another view. This prevents a broken capture source from creating a retry loop.

Before selection changes, fence input and revoke the installed posting
authorization. Retain the original deadline, registered session key, primary
connection and Control install generation. Only one replacement may be in
flight. Stop, background, primary loss, grant loss, deadline or malformed
replacement always retires the retained resources. Old cancellation and health
observations cannot cancel or admit a newer surface.

An asynchronous backend watcher also binds its assessment to the exact local
operation and lifecycle generation it observed. A phase change invalidates an
in-flight assessment even when the logical operation ID is unchanged. Discard
that obsolete result and validate the current owner on the next bounded watcher
iteration. This never restores revoked input or extends Control or handoff
deadlines. A current assessment of original Control loss still drains the owner.

Each replacement uses the existing acknowledged surface descriptor and a fresh
native enrollment challenge and proof. The existing golden signing transcript
is unchanged. Reuse requires the same client DER and host DER, original binding
and deadline. A proof for the previous surface cannot activate the replacement.
The proof transition changes the capture selection; it does not launch a second
host, register a different certificate or invoke a second native `/launch`.

The encoded canvas stays fixed for the connection. Each new selection supplies
its own current logical bounds, source pixel dimensions and centered aspect-fit
rectangle. Never stretch source content or use encoded pixels as Mac points.
The selected-stream adapter updates the filter and configuration on its existing
SCStream. Its serial queue drops samples during the update and samples whose
display time precedes completion. Both update completions must succeed before
the new selection is eligible to deliver a sample. The first fresh sample must
pass all existing image, format, content-rectangle, freshness and current-owner
checks. A failed update fences delivery and joins stream stop. Stop during an
update owns the terminal state; late completions cannot resume delivery.

After both update completions, content placement may remain unsettled. Before
the first strictly matching complete frame, the adapter may discard a placement
mismatch for at most two seconds from configuration completion. Such a sample
is never delivered, epoch-tagged or used as capture/presentation/input evidence.
Every other existing owner, format, metadata and timestamp check still applies.
The first matching frame closes this interval; a later placement change remains
terminal. An owned timer ends the interval even without another sample. Stop,
revocation or an obsolete update cannot reopen it or extend the original Control
deadline. This is a maximum waiting bound, not a delay before a valid frame.

The timestamp cutover additionally covers the existing 100 ms allowance for
scheduled future samples. Otherwise an old queued sample with a future display
time and unchanged geometry could be mislabeled as the new view. This bound may
discard up to 100 ms of otherwise fresh samples; it adds no multi-second delay.

Native video carries a selected-surface epoch in a user-data SEI preceding the
encoded picture. The marker binds the acknowledged surface UUID, surface
revision and coordinate-space revision. Capture attaches the epoch before
encoding, and encoding preserves that exact frame association. Reading the
current epoch when an old encoded packet is emitted is forbidden. The client
drops old-epoch and unmarked frames during replacement, flushes old display
buffers and waits for an independently decodable new-epoch frame. A marker
alone grants no authority. The fresh native presentation receipt and validated
new content geometry are still required before input resumes.

The SEI user-data UUID is `D5E7C93A-1DA9-4BF2-8F2B-09A1DE105A51`.
Its payload is exactly 48 bytes: that UUID's 16 network-order bytes, the selected
surface UUID's 16 network-order bytes, and two unsigned 64-bit big-endian
revisions. Both revisions are positive JSON-safe integers. H.264 uses a type-6
SEI NAL; HEVC uses a type-39 prefix SEI NAL. Standard emulation-prevention
escaping applies. The marker precedes the picture, and a new view requires an
IDR (H.264 type 5) or independently decodable HEVC IRAP (types 16 through 21).
Missing, truncated, duplicate, unsafe or conflicting markers cannot complete a
view change. Bound parsing to 64 MiB per frame and never retain picture bytes in
logs or fixtures.

The embedded RTP depacketizer preserves valid selected-surface prefix SEI NALs
in picture-data entries on both its ordinary and parameter-set/IDR paths. It
continues stripping unrelated SEI and AUD NALs. Duplicate selected-surface
markers remain visible to the adapter so that its existing rejection applies.
Packet reassembly must not erase the marker before the adapter checks the
fresh epoch and independent picture. Once the replacement epoch is configured,
the client requests an IDR through the retained connection's existing native
recovery API: an earlier keyframe may have been dropped while selection was
fenced. This creates no second connection or authority. Input readiness for a view transition
requires the new frame and its admission callback; old presentation callbacks
during input draining cannot complete a new transition.

These rules apply only when the complete continuity implementation is admitted
by both normal-app adapters. Unsupported peers continue using the existing
replacement enrollment and connection path. A connection failure may use that
existing recovery path under the original approval and deadline. Do not silently
relax the existing surface, key, identity or geometry checks to enable reuse.

## Explicit continuity exchange

An enrollment request may include `streamContinuity: true` only when the full
client adapter is available. The host may advertise it in
`interactive.native.ready` only in response to that explicit request and only
when its complete adapter supports retention. This avoids sending a new field
to a legacy closed-schema client. A `previousFence` requires that same explicit
request. `interactive.native.ready` may include `streamContinuity: true`. Omission means the
existing replacement path. No client assumes support from its own renderer.
With that admission, `interactive.native.cancel` may include `retainStream: true`;
the correlated cancelled reply must include `streamRetained: true` before the
client retains its transport. These optional fields admit only literal true,
never false or null. Retention revokes presentation/input and suspends capture
delivery before acknowledging, while keeping credentials and sockets owned.
The next enrollment request includes `previousFence`, exactly the retained
negotiation's fence. The normal golden challenge/proof binds the new surface
and the exact retained certificate hashes. A missing or different predecessor,
changed primary, key, Control binding, deadline or encoded canvas is rejected.
At most one predecessor and one replacement may exist. An uncompleted retained
handoff expires within 15 seconds and never past the original Control deadline.
Ordinary cancel, Stop, background or failure joins the retained resource drain.

## Private owned-child capture context

The local continuity adapter uses `maccompanion.selected-capture-context.v0.2`
only inside its existing owner-mode 0700 directory. The closed canonical record
keeps the v0.1 bounds, dimensions, operation and process-instance fields and adds
`frameEpochHex`, exactly 96 lowercase hexadecimal characters encoding the
indexed 48-byte epoch. Window/application checks are unchanged. Desktop is
admitted only by this new profile: windowID, processID and process launch are
zero, bundleIdentifier is empty, and current physical display bounds, rotation,
scale and source dimensions must match the current CGDisplayMode native pixel dimensions. CGDisplayPixelsWide/High may report the logical mode size on Retina displays and cannot substitute for those capture pixels. All records retain the original Control
deadline. This context never crosses Agent IPC or the remote primary.

The child may resolve another filter only after a serialized delivery pause.
Both SCStream updates must complete before it changes sample epoch or reports
new geometry. Private handoff commands and receipts remain in that same owned
directory; they correlate exact original transport operation, predecessor,
new operation and monotonically advancing local sequence. They cannot change
credentials, sockets, encoded canvas or original deadline. A malformed command,
missing original owner or handoff timeout drains capture. No command listener
or independent remote control channel is introduced.

The manifest-indexed `native-stream-continuity-v0.1.json` is the authoritative
continuity fixture. Physical acceptance additionally records host process and
video connection identity across repeated switches and window resizes.
## Owned native child handoff

The private `maccompanion.capture-handoff.v1` channel is an owned-child file
exchange, never a remote listener or a substitute Control grant. Commands and
receipts reside in the same already owned physical 0700 directory as the
initial context. Readers retain the directory descriptor and accept only a
single-link, same-owner, regular 0600 file opened without following symlinks;
commands are canonical closed JSON of at most 8192 bytes. Replies are written
by exclusive private temporary creation and atomic rename in that directory.

Every command binds the original `transportOperationID`, current logical
`operationID`, increasing positive JSON-safe `sequence`, and unchanged original
`expiresAtMonotonicNanoseconds`. `action: "pause"` has exactly these fields plus
`profile`. Its acknowledgement follows all old delivery callbacks. A
`action: "select"` command additionally has `previousOperationID` and `context`:
the exact paused predecessor, a different logical operation, a v0.2 context
with a different valid frame epoch, and the original encoded canvas/deadline.
Selection before pause, an altered duplicate sequence, or any mismatch drains
the owned capture. An exact duplicate may repeat its receipt but cannot extend
the handoff deadline. The deadline is the lesser of original expiry and 15
seconds from beginning pause. A receipt echoes the command identity and has
only `result: "paused"`, `"selected"`, or `"rejected"`.

Atomic publication can replace a record while its reader holds the previous
inode open. Readers discard that snapshot and retry within the same original
deadline when the current directory entry is a different, same-owner, regular
0600 single-link file. They never parse or admit the discarded bytes. A symlink,
hard link, wrong owner/mode, missing replacement or mutation of the same named
inode remains a rejection. Both command and receipt readers apply this rule.
Repeated exact commands keep an already identical safe receipt in place; they
do not rewrite it on every polling tick. A missing receipt can be republished.

Stop and handoff timeout fence publication immediately and join any pending
pause or capture update before terminal completion. A late update cannot write
a successful receipt or reopen delivery. The indexed child records and cases
are part of `native-stream-continuity-v0.1.json`.

Temporary encoder capability captures have their own handoff lifetime. The
last capture must join handoff termination and release that exact owner before
waking the encoder probe waiter. A later probe creates a fresh handoff; it
cannot reuse a stopped delivery fence. Repeated or late termination from a
removed stream cannot stop a newer stream or clear its owner. Genuine capture
failure remains latched and cannot be repaired by starting another probe.

An open surface/display picker observes the same normal-client transition gate.
During recovery or selection it shows progress and disables remote choices and
refresh, while leaving local cancellation available. Successful Desktop recovery
keeps the picker open, refreshes its surface-bound one-use inventory after fresh
presentation admission, and restores selection only after that refresh. Old
inventory completions crossing a transition cannot re-enable stale choices.
The picker does not dismiss or submit a second selection while the gate is held.

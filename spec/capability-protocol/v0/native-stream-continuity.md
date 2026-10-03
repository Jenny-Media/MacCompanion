# Native stream continuity v0.1

Ordinary selected-display, selected-window and selected-application changes may
retain the owned native host, its certificate, enrolled client certificate and
encrypted video connection. This is a resource optimization within the existing
Control approval. It does not carry presentation or input authority forward.

Before selection changes, fence input and revoke the installed posting
authorization. Retain the original deadline, registered session key, primary
connection and Control install generation. Only one replacement may be in
flight. Stop, background, primary loss, grant loss, deadline or malformed
replacement always retires the retained resources. Old cancellation and health
observations cannot cancel or admit a newer surface.

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

These rules apply only when the complete continuity implementation is admitted
by both normal-app adapters. Unsupported peers continue using the existing
replacement enrollment and connection path. A connection failure may use that
existing recovery path under the original approval and deadline. Do not silently
relax the existing surface, key, identity or geometry checks to enable reuse.

The manifest-indexed `native-stream-continuity-v0.1.json` is the authoritative
continuity fixture. Physical acceptance additionally records host process and
video connection identity across repeated switches and window resizes.

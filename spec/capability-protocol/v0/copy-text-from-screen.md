# iOS Desktop: Copy Text from Screen

This is a free, explicitly invoked local presentation tool for the direct iOS
Desktop client. It installs no helper, changes no authentication or wire kinds,
and does not expose remote application semantics. macOS clipboard transfer is
separate future work. Native Terminal continues to copy real selected text.

The default Desktop quick-action grid places Copy Text beside Mouse Mode. The
same tool remains in View & Display as Copy Text from Screen. Preserve stored
action ordering, hidden actions, limits and Pro customization policy. Offer the
new standard through Add Action; do not rewrite existing saved profiles. Exclude
it from Terminal, video-free Trackpad & Keyboard, and the macOS action catalogue.

Copy Text availability and review admission require the current connection owner's
complete, presented Desktop baseline. Authentication alone does not admit extraction;
a retained recovery image and an incomplete or superseded baseline remain unavailable.
Recheck this readiness under the owner lock when suspending input for review.

Capture one immutable, fully presented framebuffer and its selected-display crop.
Preselect the unobscured visible viewport, preserving its position and zoom as
space permits. Selection uses original received pixels, independent of UIKit
points and Retina scale. The snapshot has a visible frozen-screen label. Prefer system Live Text selection
on supported devices: analyze the bounded original image automatically, allow
native word/range selection, and expose Copy, optional editable review and Done.
Keep normal one-finger pan and pinch zoom on this local image. Native image
analysis remains local, bounded and generation-owned; its system text menu only
exports text through an explicit user action.

Select Area remains an explicit fallback, and is the initial presentation if
system image analysis is unsupported or the full image exceeds recognition
bounds. Retain generous crop handles, a transient magnifier while resizing,
accessible expand/shrink actions and visible/full-image selection in More. Drag
inside the rectangle to move it; pan outside it or with two fingers. Automatically
recognize after selection adjustment settles and any active crop drag ends, with only one request in flight
across the native and area paths. Editing the selection cancels/invalidates old
results before they can be copied. No separate Recognize step is required.
Round an admitted selection outward to pixel boundaries and intersect it with
the frozen image. Reject empty/non-finite selections. Bound a snapshot to
32 Mi pixels and each recognition to 16 Mi pixels and 8192 pixels per side;
ask for a smaller area rather than silently reducing resolution.

Before presenting, close input admission and acknowledge release of held remote
keys/buttons/gestures on the existing socket owner. Keep receiving live frames
and connection state. Every remote input entry point, including composed text, remains closed during
review. Opening review retires queued and copied composed-text groups with one
failed local completion; a later return cannot replay their remaining events. Return to Live Desktop requests a fresh complete frame before reopening
input; it preserves the viewport only when its display crop remains valid.
Background during that wait pauses the established owner without disconnecting.
Brief inactivity cancels review through the same fresh-frame return path.
Interruption admission remains separate from review admission: an active return
cannot clear a pending review refresh, and a complete frame arriving while
inactive cannot admit input until the app is active again.
If the display baseline changes during presentation, the superseded callback
cannot reopen input; wait for a complete frame from the current baseline.
Cancellation/replacement/background/lock/closure clears the snapshot, local
editor, share presentation and OCR result, and cancels pending recognition.
Late release/OCR callbacks cannot present content or resume a replacement session.

Area fallback uses Apple Vision off the UI thread, at most one request per
review, with accurate recognition, automatic language detection by default and
an override chosen only from the request's supported languages. Disable language
correction in this fallback. System Live Text owns its own recognition heuristics;
do not promise identical results or whitespace to the configurable Vision path. Retain best-effort line order, breaks and indentation; never claim
lossless code/whitespace recovery from pixels. Keep the frozen image visible while an optional compact editable review is open.
Area results appear in that compact review automatically. Hiding and reopening an
editable review preserves corrections, including an empty draft. A new native
selection or area adjustment retires the previous review. Copy continues to use
reviewed text while it is hidden. Disable autocorrection
and smart substitutions in editable text. Expose Copy and optional Share through
explicit actions, plus loading, empty-result and retry states. Copy confirms
without dismissing review. Done returns to the live screen explicitly; interactive
swipe dismissal is disabled. Recognition failure never prints image contents or recognized text.

No image or recognized text is uploaded, logged, automatically saved, synced or
placed in ActivityKit. Only explicit export actions (Copy, Share or a system selection-menu action)
export text. Analysis and selection never export automatically. Share/export
copies remain user-controlled after export. VoiceOver, Dynamic Type, landscape,
keyboard avoidance and Reduce Motion retain reachable controls. At accessibility
text sizes, scroll the heading, editor, status and actions above the keyboard;
keep Done and More fixed.

Geometry vectors live only in the manifest-indexed direct-screen-sharing-v1.json
fixture. Synthetic hosted tests exercise selection, input isolation, callback
retirement, recognition and existing Terminal copy. Real built-in Screen Sharing
and physical device acceptance remain separately recorded gates.

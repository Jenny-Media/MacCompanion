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

Capture one immutable, fully presented framebuffer and its selected-display crop.
Preselect the unobscured visible viewport, preserving its position and zoom as
space permits. Selection uses original received pixels, independent of UIKit
points and Retina scale. The snapshot has a visible input-paused label and local
pinch, pan, generous crop handles and accessible whole-area/reset selection.
Round an admitted selection outward to pixel boundaries and intersect it with
the frozen image. Reject empty/non-finite selections. Bound a snapshot to
32 Mi pixels and each recognition to 16 Mi pixels and 8192 pixels per side;
ask for a smaller area rather than silently reducing resolution.

Before presenting, close input admission and acknowledge release of held remote
keys/buttons/gestures on the existing socket owner. Keep receiving live frames
and connection state. Every remote input entry point remains closed during
review. Return to Live Desktop requests a fresh complete frame before reopening
input; it preserves the viewport only when its display crop remains valid.
Background during that wait pauses the established owner without disconnecting.
If the display baseline changes during presentation, the superseded callback
cannot reopen input; wait for a complete frame from the current baseline.
Cancellation/replacement/background/lock/closure clears the snapshot, local
editor, share presentation and OCR result, and cancels pending recognition.
Late release/OCR callbacks cannot present content or resume a replacement session.

Apple Vision recognition runs off the UI thread, at most one request per review,
with accurate recognition, automatic language detection by default and an
override chosen only from the request's supported languages. Disable language
correction. Retain best-effort line order, breaks and indentation; never claim
lossless code/whitespace recovery from pixels. Show the image alongside editable
plain text, with autocorrection disabled, Copy Text, Share, Reselect Area,
loading/cancel, empty-result and retry states. Copy confirms without dismissing
review. Return to Live Desktop is explicit and interactive swipe dismissal is
disabled. Recognition failure never prints image contents or recognized text.

No image or recognized text is uploaded, logged, automatically saved, synced or
placed in ActivityKit. Only explicit Copy or Share exports text. Share/export
copies remain user-controlled after export. VoiceOver, Dynamic Type, landscape,
keyboard avoidance and Reduce Motion retain reachable controls.

Geometry vectors live only in the manifest-indexed direct-screen-sharing-v1.json
fixture. Synthetic hosted tests exercise selection, input isolation, callback
retirement, recognition and existing Terminal copy. Real built-in Screen Sharing
and physical device acceptance remain separately recorded gates.

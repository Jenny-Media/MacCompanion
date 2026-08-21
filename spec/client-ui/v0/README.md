# Client UI composition profile v0

Status: normative for bundle-independent UI projection and compile-checked iOS
SwiftUI composition. Camera capture, app navigation, localization, live
services, physical accessibility, and release-target evidence remain app work.

`CompanionClientUI` consumes values from `CompanionPresentation`; it does not
own transport, pairing, persistence, grants, Interactive Control authority, or
reconnect state. Views receive immutable presentation values and emit only
closed user intents through initializer callbacks. The future app composition
root decides how an intent reaches the appropriate authority.

The pairing surface preserves these security distinctions:

- a scanned fingerprint is labeled unverified until pinned TLS succeeds;
- progress never exposes the QR secret, route value, certificate bytes, or
  transcript;
- the comparison code appears only from verified transcript/SAS presentation;
- pairing is not called complete while durable publication is pending; and
- failure uses a closed reason and cannot display remote arbitrary text.

The paired-host summary makes Remote Control optional. A connected, inactive
Mac remains useful for status and approved actions, while `Open Remote Control`
is a separate intent. `viewing`, `controlling`, lock-paused, approval, start,
and teardown states remain visibly distinct. It presents only the locally
confirmed Mac name and coarse route class, never raw addresses, discovery
labels, credentials, or remote content.

The surface picker adds Desktop locally, then renders only the Agent-approved
privacy-limited target inventory. Application rows contain the sanitized app
name; window rows contain that app name plus a deterministic ordinal. Window
titles and document names are absent by construction. Unavailable targets stay
visible but disabled, refresh requests a new short-lived inventory, and
selection returns only the closed kind plus opaque one-time target token.

The live-control representable receives one stable main-actor session object.
UIKit owns recognizers and synchronous payload emission; the decoder coordinator
owns VideoToolbox callback admission and pixels. Aspect-fit content geometry is
recomputed from declared encoded dimensions and view bounds. Geometry, mode,
disable, and teardown transitions reset held input before rebuilding or
blanking. SwiftUI never owns a pixel buffer, gesture state machine, or input
sequence.

The activity-history surface renders only the host-scoped response returned by
`audit.readSelf`. It maps closed event and outcome codes to local copy, never
renders protocol identifiers or remote-supplied identity text, preserves every
declared retention or rate-limit gap, and offers continuation only when the
server supplies an exclusive cursor. An empty page with a gap is presented as
no retained activity, not as proof that no activity occurred.

Views use native labeled buttons, progress indicators, Dynamic Type-compatible
text, aspect-independent layout, and explicit accessibility labeling for the
authentication code. Release acceptance requires localization review, VoiceOver
and Voice Control testing, large-text and contrast checks, Reduce Motion,
camera denial/recovery, navigation restoration, and physical iPhone/iPad
pairing and connected-host flows.

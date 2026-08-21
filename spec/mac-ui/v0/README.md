# Mac local-authority UI composition profile v0

Status: normative for bundle-independent UI projection and compile-checked
macOS SwiftUI composition. Menu-bar/window composition, authenticated XPC,
localization, physical accessibility, and release-target evidence remain app
work.

`CompanionMacUI` consumes immutable values from `CompanionPresentation` and
emits explicit local intents through initializer callbacks. It owns neither the
Agent connection nor grant, pairing, capture, input, or lifecycle authority.
The future app composition root must create correlated IDs, send commands over
authenticated local IPC, and publish receipt-validated presentation updates.

The capability review identifies the locally confirmed device name, provider
title and summary, capability ID, and every declared effect fact. Host-owned
labels describe data access, local-state changes, disruption, external-service
use, credential use, destructiveness, foreground requirements, locked-session
eligibility, and cancellation separately. The UI has no aggregate risk score
and cannot approve future or unshown capabilities. Applying and terminal states
disable duplicate decisions; a confirmed failure may be explicitly retried or
declined.

The Interactive warning is not a grant editor. It visibly distinguishes phone
approval, startup, active capture/input, pause, teardown, and ended state. It
lists only the exact closed session effects and offers a local stop until
teardown begins. The ended state can appear only after the presentation layer
has accepted the exact receipt proving both remote-authority end and local
runtime teardown.

The device-name editor starts only from Agent-owned locally confirmed state.
It exposes closed validation failures, does not optimistically replace the
confirmed name while saving, and emits no raw discovery or remote-suggested
label.

The local activity-history surface consumes one bounded, correlated local-IPC
detailed-audit page rather than a database record.
It resolves device labels only through the Agent-owned confirmed-name map;
unknown devices use the fixed local fallback `Paired device`, and system-wide
rows have no device label. Closed event and outcome codes become local copy,
retention and rate-limit gaps remain explicit, and pagination is possible only
from the store-provided exclusive cursor. An incomplete empty page is never
presented as a complete absence of activity.

Views use native controls, labeled symbols, scalable text, explicit progress,
and layouts that can grow vertically. Release acceptance still requires
reviewed localization, VoiceOver and Voice Control, Full Keyboard Access,
contrast and Reduce Motion checks, multi-window/menu-bar focus behavior, and
physical evidence that the warning and stop remain available throughout a live
session.

# Mac Companion Adaptive Remote Surfaces

Status: coding-baseline product and protocol specification. This document defines how Interactive Control becomes more useful than a conventional scaled desktop. It is subordinate to the identity, grant, visibility, revocation, and lock rules in the Interactive Control specification.

## 1. Purpose

An iPhone is not a small Mac display. Mac Companion should present the most useful authorized representation of the current task:

- The complete desktop when broad visual context is required
- One application or window at phone-readable scale
- A live close-up of the focused region
- A native iOS input experience when a compatible editable element is focused
- Later, verified native controls or an app-provided remote surface

These representations are called **Remote Surfaces**. They make Interactive Control adaptive without hiding what is happening on the Mac or inventing authority that the Mac did not grant.

## 2. Product principles

### Desktop is the escape hatch

Raw desktop video, pointer, and keyboard remain the dependable fallback. Mac Companion never blocks access to the visual session merely because application metadata or Accessibility information is missing.

### Prefer the smallest useful context

App Focus should show the selected work at a readable scale instead of wasting phone pixels on the entire desktop. Smart Zoom should enlarge the active control without pretending to recreate the application.

### Semantics are confidence-rated

The host distinguishes:

1. **Visual only:** pixels and ordinary input; no semantic claim.
2. **Assisted visual:** pixels plus verified bounds, focus, type, or action metadata.
3. **Verified semantic:** a native iOS control backed by a current, settable or invokable host element.
4. **Provider-native:** a reviewed application adapter supplies a versioned remote presentation and action contract.

The client never promotes an ambiguous Accessibility node into a destructive native control.

### Every mode has an honest fallback

If a window disappears, focus changes, an Accessibility call times out, a dialog opens outside the captured window, or a provider becomes stale, the client returns to the nearest safe visual surface and explains the transition.

### Better presentation does not broaden permission

Remote Surfaces exist only inside an active Interactive Control session. They use its named-device grant, fresh phone user presence, authorization epoch, visible Mac indicator, timeouts, suspension, and revocation. They never imply shell, files, clipboard, app-provider actions, or AI authority.

## 3. Surface kinds and release scope

| Kind | Description | Initial scope |
| --- | --- | --- |
| `desktop` | One selected display with absolute pointer and keyboard input | Required baseline |
| `application` | The selected application's relevant window set, activated and scaled for iPhone | MVP App Focus |
| `window` | One identified application window captured independently | MVP App Focus |
| `focusedRegion` | A live crop around a verified focused element or pointer region | MVP Smart Zoom |
| `textInput` | A native iOS keyboard/input presentation bound to one focused editable element | Gated MVP experiment |
| `semantic` | Native iOS controls derived from verified Accessibility semantics | Post-MVP |
| `provider` | A reviewed app adapter supplies an explicit remote surface | Post-MVP |

Only one visual surface is authoritative for coordinates at a time. A `textInput` presentation may accompany the current visual surface but does not replace the visual evidence of where input is going.

## 4. Common surface model

Every surface descriptor contains bounded, versioned fields:

- `surfaceID`: random identifier valid only for the current Interactive Control session
- `interactiveSessionID` and `authorizationEpoch`
- `kind` and schema version
- `surfaceRevision`: advances whenever identity, content source, interaction profile, or privacy policy changes
- `coordinateSpaceRevision`: binds pixels and coordinate input to one transform
- Owning application token and optional window token, both session-scoped
- Visual-source descriptor and current encoded dimensions
- Interaction profile: view, pointer, keyboard, semantic actions, or text mode
- Privacy classification and allowed metadata fields
- Current focus token when safely available
- Parent and fallback surface identifiers
- Creation, freshness, and expiry times

Process IDs, AXUIElement references, Core Graphics window IDs, and ScreenCaptureKit object identities are never durable protocol identity. The menu app maps them to opaque session tokens and invalidates those tokens when the source disappears or changes ownership.

## 5. Surface lifecycle

The agent owns the authoritative selection state; the menu app resolves and executes it.

```text
desktopActive -> switching -> appActive|windowActive|focusedRegionActive
appActive|windowActive -> switching -> desktopActive|appActive|windowActive
desktopActive|appActive|windowActive -> focusedRegionActive
focusedRegionActive -> parentSurfaceActive
anyActive -> fallbackPending -> nearestSafeVisualSurface
anyActive -> suspended|ended
```

A selection request includes the current surface and coordinate revisions. The host rejects stale requests rather than applying them to a newly focused app or window. A successful transition sends a discontinuity, new descriptor, and keyframe before accepting coordinates in the new space.

Surface switching never restarts pairing or user-presence approval, but suspension, authorization-epoch change, lock transition, menu-app loss, or session expiry invalidates every surface token.

## 6. App Focus

### User experience

Within Interactive Control, the iPhone presents a transient app/window switcher. Selecting an entry:

1. Requests activation of the application or raising of the window.
2. Resolves the current shareable window or related window set on the Mac.
3. Updates the ScreenCaptureKit content filter.
4. Sends a new surface and coordinate revision followed by a clean keyframe.
5. Scales the result to fill the iPhone while preserving aspect ratio.

The user can return to the desktop at any time. The iPhone always displays whether it is controlling the desktop, an application, or one window.

### Application and window listing

The menu app derives candidates from ScreenCaptureKit shareable content, running applications, and conservative Accessibility relationships. Candidate metadata is available only during an active Interactive Control session.

The initial picker may transmit:

- Localized application name and icon
- Session-scoped application token
- Window count and a generic ordinal such as “Window 2”
- Whether a current window is available and focusable

Window titles, document paths, URLs, thumbnails, Accessibility labels, and text contents are omitted by default. A later privacy-reviewed setting may permit transient window titles, but they are never written to audit or diagnostics.

Mac Companion's administration and local-suspend UI is excluded from focused-app convenience listings. System dialogs and security surfaces are never described as ordinary app content or used to grant permissions remotely.

### Related windows and fallback

Sheets, popovers, menus, dialogs, and auxiliary panels may not belong to the same independently captured window. The menu app observes window and focus changes and chooses one of three outcomes:

- Expand to a verified related-window set
- Temporarily use an application-filtered display surface
- Fall back to the desktop with an explanation

The host never leaves the user interacting with an invisible modal dialog. If it cannot prove the relationship, it favors the desktop fallback.

App activation and window raising are allowed only as Interactive Control input effects. They do not authorize launching an unlisted executable, terminating an app, altering Mac Companion grants, or approving macOS privacy prompts.

## 7. Smart Zoom

Smart Zoom is an assisted-visual surface. It keeps live pixels as the evidence and uses only enough Accessibility metadata to locate the focus.

The menu app may create a focused region from:

- A verified focused Accessibility element and its screen bounds
- The current pointer region after an explicit client zoom gesture
- A verified modal dialog or sheet

The crop includes configurable context around the target rather than only the exact element. The iPhone can pan or zoom within the parent visual surface and return without losing session state.

The MVP Smart Zoom profile transmits only:

- Focus token
- Element category needed for presentation, such as text, button, list, dialog, or unknown
- Bounds and coordinate revision
- Whether the element is editable or secure
- Supported interaction class, not arbitrary labels or values

Focus changes advance the focus token. Input with a stale focus token or coordinate revision is rejected. If Accessibility is unavailable, slow, incomplete, or inconsistent with the visual source, Smart Zoom becomes manual visual zoom.

## 8. Smart Input experiment

Smart Input presents a native iOS keyboard and editing controls when the host verifies that the current focused element is editable. It is not required for the first external Interactive Control alpha.

### Initial input profiles

1. **Keystroke-only:** the iPhone provides a native keyboard and editing toolbar, but the Mac sends no field value. Text, delete, return, tab, escape, arrows, and bounded shortcuts become ordered input events. A live visual crop shows the destination.
2. **Selection-aware:** the host may report bounded selection location and text length without reporting the value, when the application exposes consistent information.
3. **Mirrored editor:** full text and selection synchronize with a native editor. This profile is deferred until app-specific compatibility, conflict, privacy, and commit behavior are proven.

The first experiment implements only keystroke-only behavior. It does not use the clipboard or replace a whole Accessibility value.

### Text session binding

A text session binds:

- Interactive session and authorization epoch
- Parent surface and coordinate revision
- Opaque focus and element tokens
- Application token and element category
- Input profile, allowed commands, size and rate limits
- Creation, renewal, and expiry

Focus loss, element invalidation, app switch, lock, surface change, permission loss, menu-app loss, or revision mismatch ends the text session before further input is admitted. The user must deliberately start a new text session after focus moves.

### Secure and sensitive fields

A field identified as a secure text field is `secureOpaque`:

- The host never reads or transmits its value, selection, length, label, placeholder, or Accessibility description.
- Mirrored and selection-aware profiles are unavailable.
- If credential typing is permitted by the current Interactive Control state, only ordered key/text events are forwarded and the visual surface remains authoritative.
- The iPhone uses an appropriate private input presentation and does not add predictive, logging, or diagnostic capture behavior.

Absence of a secure subrole is not sufficient proof that a value is safe. Unknown or contradictory metadata defaults to keystroke-only or ordinary visual keyboard control.

### Experiment exit gate

Smart Input can enter the private-route beta only if physical-device tests show:

- No input reaches a different field after focus or app change.
- Secure fields never expose value-derived metadata.
- Unicode, deletion, return, tab, modifiers, keyboard layouts, and input-method limitations are documented honestly.
- Application rejection, timeout, or invalid element returns to visual control without losing or duplicating input.
- No text, selection, key identity, or field metadata enters audit, diagnostics, or crash reports.

Failure of this gate does not block App Focus, Smart Zoom, or ordinary Interactive Control.

## 9. Semantic and provider-native surfaces

These are post-MVP because they can misrepresent application behavior if generalized too early.

### Verified semantic overlay

The menu app may later map reviewed Accessibility roles to native iOS components such as buttons, toggles, sliders, tabs, and list rows. Each node includes an ephemeral element token, semantic revision, role, bounded state, supported actions, privacy classification, and visual bounds.

Before invocation the host re-resolves the element and verifies:

- Same application, surface, focus context, and semantic revision
- Same role and allowed action
- Element is current, enabled, visible, and not secure
- Effect remains inside the Interactive Control grant or has a separate semantic capability grant

Ambiguous, custom-drawn, destructive, credential, communication, purchase, permission, or Mac Companion administration controls remain visual-only unless a separately reviewed capability explicitly authorizes them.

### Provider-native surface

An application adapter may publish a versioned, bounded remote presentation designed for iPhone. Provider surfaces use the provider identity, generation, schema, effect, privacy, policy, and default-deny rules from the capability architecture. Installation never exposes a surface remotely by default.

A provider can propose presentation and actions but cannot:

- Read Interactive Control media or input directly
- Bypass the agent or menu-app process boundary
- Grant itself device access
- Hide the active indicator
- Weaken host policy or secure-field handling
- Send arbitrary executable UI or web content as a trusted native surface

MacTools is the first candidate for proving action cards and a narrow provider surface after the market-MVP gate.

## 10. Protocol messages

Surface control uses the authenticated Interactive Control session-control path. It does not create another transport or carry video in capability messages.

Initial messages are:

| Message | Purpose |
| --- | --- |
| `interactive.surface.list` | Return bounded, privacy-filtered session candidates and the current surface. |
| `interactive.surface.select` | Request a transition using current surface and coordinate revisions. |
| `interactive.surface.get` | Return authoritative surface, focus, fallback, and transition state. |
| `interactive.surface.ack` | Acknowledge a new descriptor and keyframe boundary before coordinate input resumes. |
| `interactive.surface.focusChanged` | Publish a host-derived focus token and permitted assisted-visual metadata. |
| `interactive.surface.fallback` | Explain a host-initiated return to a safer visual surface. |
| `interactive.text.begin` | Request a bounded input profile for the current verified editable focus. |
| `interactive.text.input` | Send ordered, rate-limited input bound to the text and focus revisions. |
| `interactive.text.end` | End the text session and release transient input state. |

Every message binds the Interactive Control session, authorization epoch, surface revision, and message sequence. Coordinate or text messages additionally bind the relevant coordinate or focus revision. Unknown kinds, actions, privacy values, or critical fields fail closed.

Golden fixtures cover every MVP surface message, transition, stale-revision error, secure-field redaction, related-window fallback, and text-session termination path.

## 11. Process ownership

The LaunchAgent:

- Authorizes surface and text-session requests against the current Interactive Control session
- Owns session-visible surface state, revisions, rate limits, and metadata policy
- Issues bounded menu-app leases and relays approved control and metadata
- Relays encoded media without inspecting or persisting it
- Ends every surface and text token on suspension or epoch change

The persistent menu app:

- Resolves ScreenCaptureKit applications, windows, and filters
- Observes focus and UI changes through Accessibility
- Activates or raises an approved app/window as an Interactive Control effect
- Creates visual crops and performs verified element actions
- Owns all protected content capture and input execution
- Applies host privacy filtering before returning metadata

The iOS client:

- Renders only host-described modes and confidence levels
- Never infers semantic authority from pixels or labels
- Uses current revisions for all selection and input
- Clearly identifies the active Mac, app/window mode, focus mode, and fallback
- Discards all transient surface metadata when the session ends

## 12. Privacy and audit

Remote Surface metadata can be as sensitive as screen pixels. The host uses an allowlist per mode.

Never persisted or included in audit, logs, diagnostics, crash reports, or support bundles:

- Window titles, document names and paths, URLs, thumbnails, and app content
- Accessibility labels, values, descriptions, help, selected text, and text lengths
- Focused-field content, selection, secure-field metadata, typed text, or key events
- Surface screenshots, crops, semantic node trees, or provider presentation values

Audit records only session metadata such as surface kind transitions, application-token changes, switch success/failure class, fallback reason, counts, duration, and protocol errors. Session tokens are meaningless outside their session.

The Interactive Control consent explanation includes transient application/window enumeration and focus-assisted presentation. A future setting that exposes window titles or semantic values requires a separate privacy review and explicit local enablement.

## 13. Accessibility and usability

Remote Surfaces should make Mac control more accessible rather than merely enlarging pixels:

- Native iOS surfaces support Dynamic Type, VoiceOver, Switch Control, and sufficient touch targets.
- Assisted-visual overlays keep the underlying pixels visible when semantics are incomplete.
- Color is never the only indicator of mode, focus, confidence, lock, or control state.
- Gestures always have discoverable controls and external-keyboard alternatives.
- The user can pin the desktop, disable automatic Smart Zoom, or use manual visual control.

## 14. Performance targets

On a healthy LAN:

- App/window selection to first current keyframe: p95 at or below 1.0 second
- Focus change to stable Smart Zoom crop: p95 at or below 300 ms
- Surface fallback after invalidation: p95 at or below 500 ms
- No unbounded window, AX element, icon, crop, or semantic metadata cache
- App Focus does not increase the Interactive Control memory or energy budget by more than a measured and documented Stage 0 allowance

These targets are measured gates, not guarantees for every app or private route.

## 15. Compatibility and test matrix

Stage 0 and alpha testing must include:

- Native AppKit and SwiftUI applications
- A browser and an Electron application
- An application with custom-drawn or incomplete Accessibility controls
- Single and multiple windows, tabs, sheets, popovers, menus, dialogs, and full-screen Spaces
- Window creation, destruction, minimization, app quit, crash, and relaunch
- Rapid focus changes, stale elements, AX timeouts, unresponsive apps, and permission revocation
- Multiple displays, scaling, rotation, and a selected window moving between displays
- Secure and ordinary single-line and multiline fields
- Non-US keyboard layouts, emoji, composed Unicode, hardware keyboards, and input methods
- Lock, unlock, user switch, menu-app crash, network loss, and authorization-epoch change during every surface kind

The test record states which apps support visual, assisted-visual, or verified-semantic behavior. Mac Companion does not advertise universal semantic compatibility.

## 16. MVP acceptance

The adaptive Interactive Control MVP is ready when:

- Desktop control remains usable without Accessibility-derived surface metadata.
- A user can enter and leave App Focus without losing orientation or control.
- Modal and related-window ambiguity always produces a visible related surface or desktop fallback.
- Smart Zoom follows verified focus without sending labels or values and becomes manual zoom when confidence is insufficient.
- Surface, focus, and coordinate revisions reject stale selection and input.
- Lock, suspension, revocation, menu-app loss, and epoch change invalidate every surface token immediately.
- App/window/focus metadata is absent from durable logs and support artifacts.
- Five testers use App Focus and Smart Zoom for real tasks and prefer them to manual desktop pinch-and-pan.
- Smart Input remains disabled unless its independent experiment gate passes.

The post-MVP semantic/provider phase is ready only after users demonstrate that native surfaces solve repeated jobs better than either App Focus or a bounded semantic capability.

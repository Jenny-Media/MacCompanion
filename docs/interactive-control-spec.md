# Mac Companion Interactive Control Specification

Status: coding-baseline draft for Stage 0A and Stage 0B. Platform spikes may change measured limits or replace an unavailable Apple API, but they may not weaken the consent, visibility, revocation, or lock-screen rules without a recorded architecture decision.

## 1. Purpose and product boundary

Interactive Control implements Mac Companion's first-class **Control** path. It lets the owner of a paired iPhone or iPad view one locally selected display and send mouse and keyboard input to a logged-in personal Mac. Its Adaptive Remote Surfaces can focus the desktop stream onto an application, window, or current region so the iPhone is more useful than a scaled monitor. Users may enter Control directly for visual work; they do not need to attempt an Observe or Act task first.

Interactive Control is not:

- A requirement for Observe status or Act capabilities
- Granted by pairing, Monitor Only, Standard Control, or a provider installation
- A shell, arbitrary file browser, clipboard channel, audio stream, automation surface, or AI-control permission
- A vendor relay, rendezvous service, VPN account, or public port-forwarding service
- A way around macOS login, the lock screen, FileVault, TCC, or another macOS security boundary

One device grant cannot imply any future administrator capability such as shell, files, clipboard, audio, provider execution, or AI control. Each such capability requires its own local grant, protocol, threat model, indicator treatment, and revocation behavior. Desktop, App Focus, Window Focus, and Smart Zoom are presentation modes inside Interactive Control and do not broaden its grant.

## 2. Initial supported envelope

The first implementation supports:

- One configured macOS account that is already logged in
- Up to eight retained paired iPhone or iPad clients per Mac, with one active
  Interactive Control session admitted at a time
- One active Interactive Control session per Mac
- One selected physical display streamed at a time, with fail-closed switching
  inside the active session
- One authoritative visual surface at a time: Desktop, App Focus, Window Focus, or a focused-region crop
- H.264 video without audio
- Absolute pointer movement, primary and secondary click, drag, bounded scrolling, physical-key input, modifiers, and bounded text input
- Foreground iOS use over the local network or a user-managed private route such as Tailscale
- A persistent Mac activity indicator and a local suspend control

It does not promise wake-from-sleep, logout or login-window control, FileVault preboot access, a different active console user, headless operation, multi-display composition, clipboard transfer, drag-and-drop files, remote audio, or background iPhone operation.

## 3. Participants and authority

### iOS client

The client presents video and host-declared Remote Surface modes, selects a surface-appropriate interaction profile with a visible user override, transforms touch and keyboard interaction into bounded input messages, obtains fresh user presence for every new session, pins the Mac identity, and reports foreground and rendering state honestly. It never decides that a grant exists, that the Mac is unlocked, or that pixels imply a safe semantic action.

### Per-user LaunchAgent

The agent is the sole network and authorization authority. It:

- Authenticates the paired device and pinned host session
- Reads the device-specific Interactive Control grant and authorization epoch
- Verifies the short-lived user-presence approval
- Creates the session and secondary-channel credentials
- Enforces duration, foreground lease, rate, display, and input limits
- Owns session state and audit metadata
- Owns surface selection, privacy profile, focus, surface and coordinate revisions, and fallback state
- Advances the authorization epoch and closes channels on suspension or revocation
- Forwards only admitted session and input messages over authenticated local IPC
- Relays bounded encoded media records returned over IPC to the media connection without decoding, inspecting, or persisting their content

The agent cannot capture a screen or inject input.

### Persistent menu app

The menu app is the sole interactive executor. It:

- Owns ScreenCaptureKit capture and VideoToolbox encoding
- Owns Accessibility trust and `CGEvent` input injection
- Resolves ephemeral app/window candidates, focused-element bounds, capture filters, and Smart Zoom crops
- Displays the controlling device and current activity in a persistent status item
- Offers a local `Suspend <device>` action
- Accepts work only with a current agent-issued IPC lease
- Returns encoded access units tagged with the session, authorization epoch, and coordinate revision over the same authenticated IPC boundary
- Stops capture and releases every pressed key and button when its lease or IPC disappears

The menu app never receives device private keys, durable grants, the remote network socket, or direct access to the authorization database. Quitting or crashing it immediately makes Interactive Control unavailable even if the agent remains healthy.

### macOS

macOS remains the authentication and session authority. Mac Companion observes public session-state signals conservatively. It does not implement an unlock screen, collect a password, or claim that successful input means the Mac is unlocked.

## 4. Consent and authorization

### Pairing defaults

A newly paired device receives Monitor Only. Pairing never grants Interactive Control.

### Durable device grant

Interactive Control is enabled from the Mac for one named paired device. The Mac shows a concrete warning that the device can see the current display, transiently enumerate applications and windows for App and Window Focus, observe limited focus metadata for Smart Zoom, and operate the mouse and keyboard, including interaction with other applications and potentially destructive UI. Acceptance records the device, grant revision, policy revision, time, configured Mac account, and current authorization epoch.

The grant remains until locally suspended, disabled, revoked, or invalidated by a security event. The device can request a session but cannot enable, broaden, or restore its own grant.

### Session approval

Every new session requires a fresh signature from the client's Secure Enclave-backed approval key after Face ID, Touch ID, or device-passcode-backed user presence. The signed challenge binds at least:

- Host and client identity
- Session request and approval IDs
- Interactive Control capability and schema version
- Device grant and policy revisions
- Current authorization epoch
- Requested display, initial surface, and session effects
- Issued and expiry times
- Negotiated protocol version
- Fresh server challenge and live authenticated-session identity

The approval expires after 60 seconds, is consumed atomically once, and cannot authorize a different session, host, device, capability, or authorization epoch. App unlock is not session approval.

An unconsumed approval is not a permanent session lock. Expired pending
approval material is removed before admitting a later request. A new explicit
request on the exact same authenticated primary supersedes that primary's
older unconsumed challenge; a different primary remains fenced until the
challenge expires or its owning connection closes. A late proof for the
superseded challenge cannot consume or erase the replacement approval. Local
Face ID, Touch ID, passcode, or protected-key failure is presented as a local
Control failure and does not close the authenticated primary.

### Suspension and revocation

- `Disconnect` ends the current session without changing the durable device grant.
- `Suspend device` is device-wide: it advances the device authorization epoch, ends Interactive Control, closes the capability transport and Observe subscriptions, invalidates unused approvals and channel credentials, prevents queued Act work from claiming execution, and prevents reconnection until the Mac owner resumes it locally and advances the epoch again.
- `Revoke device` permanently removes the pairing and all grants, advances the epoch, and closes every live transport for that device.

Permission loss, menu-app loss, logout, fast user switching, active-console ambiguity, and local disablement have the same immediate effect on active capture and input as suspension, while preserving only the records required to explain and recover from the state.

## 5. Session state model

The agent publishes exactly one authoritative state and a transition reason:

| State | Meaning |
| --- | --- |
| `idle` | No Interactive Control session exists. |
| `approvalRequired` | A valid request exists and fresh client user presence is required. |
| `starting` | Approval is consumed; IPC, display, and media setup are in progress. |
| `activeUnlocked` | The configured user is active; admitted video and input may flow. |
| `activeLocked` | Only the genuine macOS lock surface may be shown and operated. This state exists only if Stage 0 proves public API support. |
| `lockedInteractionUnavailable` | The user is logged in but macOS does not expose a supportable lock-surface capture/input path. No old desktop frame may be presented as live. |
| `suspended` | Local policy, permission, process, or security state has stopped the session. It cannot resume remotely. |
| `ending` | Channels are closing and pressed inputs are being released. No new input is admitted. |
| `ended` | The immutable terminal record contains the reason and end time. |

The client may retry only by creating a new request. It may not infer `activeUnlocked` from receiving pixels or successful input.

Allowed transitions are:

```text
idle -> approvalRequired -> starting -> activeUnlocked
activeUnlocked -> activeLocked|lockedInteractionUnavailable
activeLocked|lockedInteractionUnavailable -> starting -> activeUnlocked
approvalRequired|starting|active*|lockedInteractionUnavailable -> suspended|ending
suspended -> ending
ending -> ended
ended -> idle
```

Any unrecognized or ambiguous host state moves toward `suspended` or `lockedInteractionUnavailable`, never toward greater access.

## 6. Locked-session contract

The coding contract is deliberately conservative:

- Logged in and unlocked: full video, pointer, and keyboard operation is expected after permissions and grant checks pass.
- Logged in and locked: desktop capture stops before the lock transition is published. If the managed entitlement and public APIs expose the genuine macOS lock UI, that UI alone may be streamed and ordinary pointer and physical-key input may be forwarded to macOS. macOS owns authentication.
- Logged in and locked without public support: state becomes `lockedInteractionUnavailable`, the client blanks the last frame, and no input is accepted.
- Another console user, logout, login window without the configured user, FileVault preboot, or unverifiable ownership: the session ends.

Text insertion is disabled while locked. Mac Companion does not label credential fields, inspect typed values, store key events, synthesize an unlock result, or preserve the last desktop image on the lock screen. The desktop stream resumes only after macOS reports the configured user active, the session returns through `starting`, and a new descriptor, coordinate-space revision, and clean keyframe have been acknowledged. Unlock never revives a pre-lock surface token.

Lock invalidates every application, window, focus, semantic, and text-session token before evaluating whether the genuine macOS lock surface is available. Adaptive app/window surfaces never continue on the lock screen.

Support for `activeLocked` is a Stage 0 feasibility result, not a product promise until verified on the supported OS and hardware matrix. Failure of that spike does not block the unlocked Interactive Control MVP; it fixes the documented result at `lockedInteractionUnavailable`.

## 7. Transport profile

### Connections

The baseline uses the authenticated, host-pinned TLS 1.3 capability connection for session control and reliable input, plus one short-lived TLS 1.3 media connection for binary video. Both use the same listener and application identity. Bonjour, a private IP, private DNS, or Tailscale changes routing only.

The media connection performs a fresh role-specific challenge/response bound to the host, client, Interactive Control session, authorization epoch, protocol version, primary authenticated-session identity, and a one-time channel credential. The credential:

- Expires after 30 seconds if unused
- Is consumed atomically by one connection
- Cannot be used for input or a different session role
- Becomes invalid on epoch change, session end, or primary-session loss

The exact approval signature and role-specific channel-binding constructions are frozen in `spec/interactive-control/v0/security-profile.md` with golden fixtures. Closed handshake messages and authority-state consumption must also be frozen before production networking code. Authentication and state changes never use TLS 0-RTT.

TCP/TLS is the starting implementation because it is available on local and user-managed private routes without another system service. A QUIC or datagram media path requires a measured Stage 0 result and an ADR; it cannot create a second identity or authorization system.

### Control messages

Session and input messages use the bounded envelope in `protocol-outline.md`. They are reliable and ordered. Every Interactive Control message also binds:

- `interactiveSessionID`
- `authorizationEpoch`
- Monotonic per-direction sequence
- Surface revision and session-scoped surface token when a Remote Surface is involved
- Coordinate-space revision when coordinates are present
- Focus revision when focus-derived input is present
- Message type and bounded payload length

Duplicate state transitions are idempotent. Duplicate non-idempotent button and key transitions are rejected rather than replayed.

### Media records

The media channel is a sequence of length-bounded binary records. The version-1 header contains:

| Field | Purpose |
| --- | --- |
| Magic and format version | Reject cross-protocol and unsupported records. |
| Record type and flags | Configuration, video access unit, discontinuity, or end. |
| Header and payload lengths | Permit bounds checking before allocation. |
| Session ID and authorization epoch | Fence reuse across sessions and revocation. |
| Surface ID and surface revision | Fence reuse across adaptive-surface replacement. |
| Media sequence | Detect duplicates and gaps. |
| Presentation timestamp | Schedule display without relying on arrival time. |
| Coordinate-space revision | Bind pixels to the current visual-surface transform. |
| Encoded width and height | Validate decoder and input transform state. |

All integers use big-endian network byte order. Unknown record types and oversized values close the media channel. The exact 96-byte v1 layout and golden binary vectors are defined in `spec/interactive-control/v0/media-records.md`.

## 8. Video profile

The initial encoder profile is:

- ScreenCaptureKit source from one explicitly selected physical display, application/window filter, or host-derived crop
- VideoToolbox hardware H.264 when available
- H.264 High profile, level 4.1 or a lower mutually supported level
- 4:2:0 video-range pixel buffers and AVCC access units
- Decoder configuration record sent at start and after every format change
- Maximum encoded dimensions of 1920 by 1200 and maximum 2,304,000 pixels
- Maximum 30 frames per second and 8 Mbit/s target bitrate
- Initial keyframe interval no longer than two seconds; immediate keyframe on format change, resume, or bounded client request
- At most one waiting unencoded frame and a latency-first drop policy

The host may adapt among bounded resolution, frame-rate, and bitrate profiles based on encode time, send backlog, measured receive health, thermal state, and client rendering. It drops stale delta frames and requests a clean keyframe instead of building an unbounded queue. The client never presents a decoded frame from an old authorization epoch or coordinate-space revision as current.

The encoded-record handoff preserves decoder order and never evicts an older
H.264 record to admit a newer one. When its bounded record/byte budget is full,
one producer may wait behind downstream capacity; that backpressure reaches
the encoder, whose separate one-frame latency policy replaces only a waiting
unencoded source frame and forces a clean frame when required. Teardown purges
retained records and rejects the waiting producer. Queue congestion by itself
does not end Control, while malformed records, mixed-session ownership, or a
failed safety purge remain terminal.

Initial performance targets on a healthy LAN are:

- Session request to first current frame: p95 at or below 2.5 seconds
- Display-to-client glass latency: p50 at or below 150 ms and p95 at or below 300 ms
- Pointer input to visible response: p50 at or below 180 ms and p95 at or below 350 ms
- No unbounded memory growth during a 60-minute session

The targets are gates for measurement, not claims for every private route.

## 9. Visual surface and coordinate model

At session start the host publishes a Desktop surface descriptor containing a session-scoped display ID, pixel dimensions, point dimensions, scale, rotation, visible frame, encoded dimensions, `surfaceRevision`, and `coordinateSpaceRevision`.

Pointer positions are encoded as unsigned normalized coordinates from 0 through 65,535 in the active visual surface's current logical space. The menu app applies the authoritative transform into the selected display, app/window, or crop. The client does not send raw global macOS coordinates.

A display disconnect, resolution, scale, rotation, or selected-display change:

1. Stops input admission.
2. Advances `coordinateSpaceRevision`.
3. Sends a new descriptor and video discontinuity.
4. Waits for client acknowledgement.
5. Resumes with a fresh keyframe.

Input carrying an old surface or coordinate revision is rejected. The initial product ends or pauses the session if the selected display disappears; it does not silently redirect control to another display.

While Control is active, its persistent toolbar exposes a `Display` selector.
Its periodically refreshed catalog contains only an
opaque display ID, stable session ordinal, bounded pixel dimensions, and the
main-display flag; it never exposes a macOS display name or platform display
identifier. Newly connected displays can appear without ending Control. A live
display change is carried as an ordinary authenticated Desktop surface
replacement: the client pauses and resets input, the menu app applies the
opaque selection and publishes a successor admission revision, the replacement
execution lease binds that display, and the Agent returns success only after a
discontinuity and clean frame are acknowledged under advanced surface and
coordinate revisions. A disconnected selected display fails closed; the MVP
does not silently redirect or compose multiple displays.

### Adaptive Remote Surface integration

The required MVP modes are Desktop, App Focus, Window Focus, and Smart Zoom. A selection advances surface and coordinate revisions, pauses and resets input under the old fence, obtains exact menu-runtime preparation proof, sends a discontinuity/configuration/clean-keyframe boundary under the new fence, and waits for the full surface/focus acknowledgement before either endpoint reactivates input. Cross-device descriptors carry relative validity rather than host-monotonic timestamps. An app quit, window disappearance, unresolved modal dialog, stale focus, Accessibility timeout, or inconsistent transform falls back to an application-filtered or Desktop surface rather than leaving invisible input active.

The initial app/window picker transmits only localized app names and icons, opaque session tokens, generic window ordinals, and availability. Window titles, document paths, URLs, thumbnails, labels, values, and content are excluded. Smart Zoom initially uses category, bounds, editability, security status, and focus revision without transmitting the focused value or label.

Smart Input is a gated experiment. Its first profile provides an iOS keyboard and visual focus crop while transmitting ordered key/text events, not field contents or whole-value replacements. Secure or ambiguous fields never transmit value, selection, length, label, placeholder, or description. The normative state and privacy rules are in `adaptive-remote-surfaces.md`.

The baseline Desktop surface may still expose a manually invoked iOS software
keyboard. That keyboard is not Smart Input: it does not inspect macOS focus,
crop to a field, or receive field metadata. Its stateless proxy forwards each
bounded UIKit insertion as one ordered text payload and Delete as a balanced
physical-key stroke, retains no entered text, selection, or remote value, and
resigns immediately when input authority closes.

## 10. Input profile

Supported input types are:

- Absolute pointer move
- Primary and secondary button down/up
- Drag as explicit button state plus pointer movement
- Horizontal and vertical pixel or line scroll with bounded deltas
- Physical key down/up using a documented USB HID usage plus modifiers
- Modifier-state synchronization
- Bounded UTF-8 text insertion while unlocked
- `input.reset` to release all remotely held buttons and keys

Each event carries a sequence number and client monotonic-millisecond timestamp. Pointer moves may be coalesced before sequence assignment; button and key transitions may not. The agent and menu app enforce sliding per-session rates, with a ceiling of 120 pointer moves and 240 total input messages in `(now - 1000 ms, now]`. A text insertion is limited to 4 KiB, requires an exact focus fence, is disabled while locked, and is never implemented by writing the clipboard. The exact closed envelope and tagged payload union are defined in `spec/interactive-control/v0/input-messages.md`.

The host maintains the authoritative set of remotely pressed buttons and keys. It emits matching releases when the session ends, the channel stalls, IPC closes, the app resigns foreground without renewing its lease, or authorization changes. A repeated `down`, unmatched `up`, invalid HID usage, out-of-bounds coordinate, excessive delta, stale sequence, or stale coordinate revision is rejected and counted without entering content-bearing audit data.

The phone's explicit Stop action sends `interactive.session.end` on the
authenticated primary connection for the exact current session and
authorization epoch. It disables local input immediately. The Mac clears
admission before teardown and returns `interactive.session.ended` only after
channels, input, capture, queued media, and retained output have crossed their
idempotent safety boundary. Connection loss is still fail-closed teardown, but
the phone must not present it as an acknowledged Stop reply.

The first release documents keyboard-layout limitations. It must not silently claim that physical-key events reproduce every character on every layout.

## 11. Lifetime, presence, and failure limits

- Approval challenge: 60 seconds
- Unused secondary-channel credential: 30 seconds
- Agent-issued menu-app execution lease: 10 seconds, renewed while the full chain remains authorized
- Lost primary connection or foreground lease: stop admitting input immediately and terminate within 15 seconds
- A real iOS background transition may retain the existing authenticated route
  for at most 10 seconds so a brief app switch can return without a reconnect;
  an exact foreground return fences the stale deadline, while a durable
  background stay still closes normally and cannot restart Control
- Maximum session duration: four hours measured from approval consumption; setup, lock, unlock, reconnect, or surface replacement cannot extend it, and continuing requires a new user-presence approval
- One active session and one starting request per host
- No automatic session restart after agent, menu app, OS, network, or permission recovery

Actual video transmission or accepted input contributes to host-derived `dataAccessActive`. A client-declared foreground or viewing lease can refine the displayed surface but cannot hide real activity.

On any uncertain failure, the host prioritizes stopping input, releasing state, stopping capture, invalidating credentials, and explaining the terminal reason over attempting seamless continuation.

## 12. Visibility, privacy, and audit

While a session is starting or active, the Mac status item remains visible and identifies the controlling device. Its menu provides `Suspend <device>` without opening settings. The iOS surface continuously identifies the Mac, route, host lock state, grant state, and whether control is active or view-only.

Audit may store only bounded metadata such as:

- Host, device, session, grant, policy, and authorization-epoch identifiers
- Start and end times, route class, surface kind and ephemeral source-token changes, format changes, byte and frame counters
- State and surface-kind transitions, privacy-safe fallback reason, permission changes, rate-limit events, and terminal reason

Audit, logs, diagnostics, crash reports, and support bundles must not store video frames, screenshots, thumbnails, OCR, typed text, key identities, pointer coordinates, clipboard data, application/window titles or content, Accessibility labels or values, focused-field metadata, or semantic trees. Providers cannot opt this data into logs.

## 13. Error model

The client distinguishes at least:

- `interactive.grantRequired`
- `interactive.approvalRequired`
- `interactive.approvalExpired`
- `interactive.sessionBusy`
- `interactive.hostLocked`
- `interactive.lockedInteractionUnavailable`
- `interactive.menuAppUnavailable`
- `interactive.screenPermissionRequired`
- `interactive.accessibilityPermissionRequired`
- `interactive.displayUnavailable`
- `interactive.coordinateRevisionMismatch`
- `interactive.surface.unavailable`
- `interactive.surface.revisionMismatch`
- `interactive.surface.fallback`
- `interactive.surface.focusChanged`
- `interactive.text.sessionEnded`
- `interactive.text.secureFieldRestricted`
- `interactive.channelExpired`
- `interactive.authorizationChanged`
- `interactive.rateLimited`
- `interactive.hostUnavailable`
- `interactive.protocolViolation`

Errors are localized for users but retain a stable machine code, retry class, and recovery owner. A retryable route error must not be presented as a permission error, and a permission error must not be disguised as an empty screen.

## 14. Stage 0 proof obligations

Coding can begin with isolated Stage 0 harnesses only after this specification is accepted. Product implementation proceeds when the harnesses establish:

1. Persistent Content Capture entitlement request and approval path for the final App ID.
2. TCC attribution and prompts when the persistent menu app owns ScreenCaptureKit and Accessibility while the agent owns the network.
3. Capture, encoding, and input behavior on current stable macOS 26 hardware.
4. Application/window capture switching, related-window fallback, Smart Zoom focus bounds, stale revisions, Accessibility timeouts, and secure-field redaction across the compatibility matrix.
5. Exact behavior through lock, display sleep, fast user switching, logout, menu-app crash, permission revocation, and OS update.
6. Authenticated local IPC with code-identity and audit-token checks.
7. TLS control and media framing over LAN and a user-managed Tailscale route, including revocation during active traffic.
8. Latency, bandwidth, thermal, energy, and memory measurements against the initial budgets.

If locked-session interaction cannot be proved with public APIs, the supported contract becomes `lockedInteractionUnavailable`; no private API or credential workaround is acceptable.

## 15. Acceptance checklist

Interactive Control is ready for an external alpha only when:

- Pairing alone cannot start a session.
- A named device has an inspectable local grant and fresh client user presence starts each session.
- Revocation, suspension, epoch change, menu-app loss, logout, and user switch stop video and input deterministically.
- Every remote key and button is released on every termination path.
- Stale frames and stale coordinate input cannot cross a lock or display revision.
- Stale surface and focus tokens cannot select, zoom, or type into a replaced app, window, or element.
- App Focus, Window Focus, and Smart Zoom fall back visibly when modal, Accessibility, or window identity is ambiguous.
- The visible local indicator cannot be hidden while Interactive Control remains usable.
- No content-bearing video or input data enters audit or diagnostics.
- App/window/focus metadata follows the Adaptive Remote Surface allowlist and secure-field rules.
- One-hour physical-device sessions meet documented resource and latency budgets or produce an approved ADR.
- Testers can distinguish paired, connected, viewing, controlling, locked, suspended, and unreachable states without assistance.
- An independent security review has no unresolved critical finding before public beta.

# Mac Companion Product Proposal

## Summary

Mac Companion is a private operations companion for observing, operating, and interactively controlling personal Macs from a native iPhone or iPad app without a Mac Companion account or vendor-operated network relay.

The first implementation consists of:

1. **Mac Companion Agent**, a standalone per-user macOS service with a trusted menu-bar administration UI.
2. A native iOS and iPadOS client that pairs directly with one Mac initially, using identities that preserve future many-to-many support.
3. A bounded, self-describing capability protocol shared by both apps.
4. A separate Interactive Control protocol with Adaptive Remote Surfaces for an explicitly granted live screen, mouse, and keyboard session.
5. Bonjour discovery for local connections and saved user-managed private-network endpoints for remote connections.

MacTools is not required for the MVP. After the native no-relay beta passes its repeat-use gate, a MacTools adapter becomes the first external provider so the product can validate its ecosystem advantage before publishing a general provider SDK.

## Positioning

Mac Companion is not a screen-first remote desktop. Existing products already provide pointer, keyboard, media, SSH, screenshot, community-package, and Tailscale features.

Mac Companion starts with the job: show what the Mac is doing, offer dependable operations, and escalate to Interactive Control only when a dashboard or semantic action is insufficient. Interactive Control adapts from the desktop to a phone-readable application, window, or focused region instead of treating the iPhone as a small monitor.

Its operating model is:

- The Mac is always the final authority.
- Remote exposure is explicit and default-deny.
- Actions have structured effects, permissions, availability, and results.
- Interactive Control is a separate, named grant for live screen, mouse, and keyboard access.
- App Focus and Smart Zoom improve presentation inside that grant without creating another permission tier.
- Active viewing and control are visible and session-audited.
- Consequential, destructive, credential, communication, and general shell operations are excluded from the first product.
- MacTools capabilities can later be exposed through the same policy boundary without giving the remote client access to plugin internals.

The primary beachhead hypothesis is owners of a logged-in personal Mac who want private, no-relay remote operation. Research should compare these subsegments without treating any one as proven in advance:

1. People with an always-on Mac mini or home Mac who want status, dependable controls, and occasional live intervention.
2. MacTools users who want carefully selected remote capabilities.
3. People managing several personal Macs who value a single private operations surface.

Developers seeking a safer alternative to broad SSH access are a secondary audience, not the first positioning target.

## Why standalone-first still matters

Mac Companion Agent remains independent of MacTools. This provides a reference host for the protocol and prevents MacTools-specific packaging, plugin lifetime, or UI assumptions from defining the network model.

Standalone-first does not mean designing in isolation. Stage 0 includes an explicit mapping to MacTools' existing action registry, parameters, concurrency, availability, permissions, and executor. Neutral status sampling code should be shared or extracted where practical rather than reimplemented twice.

## Product principles

### Local-first

Mac Companion works on a local network without an account or internet access. Remote access uses a private network the user already manages, such as Tailscale. Network reachability never grants Mac Companion authorization.

### Dashboard-first, interactive when needed

The client opens on current state, recent work, and named desired-state actions. Live screen, pointer, and keyboard control are an intentional escalation surface, not the default destination. Within that surface, the user can keep the desktop, focus one app or window, or zoom to the current control. This gives the user broad reach without reducing the product to a screen mirror.

### Adaptive, with an honest fallback

App Focus and Smart Zoom use ScreenCaptureKit and conservative Accessibility metadata to improve readability. The complete desktop remains one gesture away and becomes the automatic fallback when windows, dialogs, focus, or semantics cannot be resolved safely. A native control is shown only when the host can verify what it represents and can revalidate it immediately before use.

### Host-controlled

Clients and providers request operations. The host policy engine validates identity, scope, parameters, provider revision, permissions, current session state, concurrency, and approval immediately before execution.

### Visible activity

Paired, connected, viewing, controlling, capturing, and agent-active are different states. Activity is visible whenever the user's macOS session UI is visible and is recorded even while the display is locked.

### Provider-neutral, not schema-unbounded

The protocol uses neutral host, provider, property, action, event, and task concepts. The first client supports a deliberately small schema and presentation profile. Unknown or unsupported schemas are shown as unavailable, never guessed into an unsafe UI.

### No lock bypass

Read-only status and explicitly declared background-safe operations may continue while the display is locked. If public APIs and the approved entitlement permit it, Interactive Control may show and send input to the genuine macOS lock screen so the owner can authenticate normally. Mac Companion never reveals the desktop behind the lock, stores or audits credential input, bypasses authentication, or silently unlocks the desktop.

### Honest reachability

While the user remains logged in, the per-user service can operate while the display is locked. After logout, before login, while asleep, or when the network is unavailable, the first product is unreachable. The client distinguishes current observations from cached or last-reported state.

### Foreground-oriented iOS operation

Live connections, viewing presence, and task progress are reliable while the iOS app is foregrounded. Without an APNs provider or vendor relay, Mac Companion does not promise background iPhone alerts, continuous monitoring, or network-triggered wakeups.

## Primary user stories

### Pairing

As a Mac owner, I can pair my phone by scanning a short-lived QR code, verify both endpoints, choose an explicit permission profile, and later revoke the device.

### Monitoring

As an iPhone user, I can see current or clearly labeled last-known status for each Mac, including reachability, user-session state, service health, CPU, memory, disk, thermal, and power information.

### Safe control

As an authorized user, I can invoke a small set of desired-state actions, understand their effects, confirm sensitive operations with device user presence, and see durable progress and results.

### Interactive intervention

As an explicitly authorized owner, I can open a live view of one Mac display and use touch, pointer, scroll, and keyboard input when a semantic action is insufficient. I can focus one app or window at phone-readable scale and zoom to the current control without losing a direct route back to the desktop. Interactive Control is session-scoped, visible at the Mac, and immediately suspendable or revocable.

### Focused input

As an iPhone user, when a compatible ordinary text field has focus, I can use a native iOS keyboard surface bound to that exact focus. If the field is secure, ambiguous, or changes before input is admitted, Mac Companion exposes no value and falls back to ordinary visual keyboard control.

### Future multiple devices

As a user with several Macs and phones, I can pair them many-to-many and assign permissions independently. New providers or capabilities do not silently inherit authorization.

### Active-use awareness

As the person at the Mac, I can see which device is actively viewing or controlling it and can terminate that device's session. Session termination stops new requests and remote input and requests cancellation of operations that declare cancellation support; it does not claim to undo completed or non-cancellable effects.

### Private remote access

As a Tailscale user, I can save a private hostname or address for the same paired host identity without port forwarding or a Mac Companion relay.

## Product surfaces

### iPhone and iPad

The root library lists paired Macs with:

- Name and icon
- Reachable or unreachable state
- Current user-session state when observed
- Last reported state and timestamp when unreachable
- Compact health summary
- Active operation when connected

Each Mac has:

1. **Overview:** System status, freshness, service health, and favorite approved controls.
2. **Capabilities:** Controls grouped by provider, including Native System and later MacTools.
3. **Interactive Control:** An explicit transition into a live screen, mouse, and keyboard session with Desktop, App Focus, and Smart Zoom modes.
4. **Activity:** Connections, presence, decisions, approvals, results, and security events.

Sensitive confirmations identify the Mac, provider, exact operation, parameters, effect categories, reversibility, expiration, and whether external systems or people are affected.

### Mac

The menu-bar app provides:

- Service and endpoint state
- Pair New Device
- Paired Devices and permission profiles
- Active Sessions
- Interactive Control permission and Screen Recording and Accessibility readiness
- Providers and remotely exposed capabilities
- Activity Log
- Local Network and other permission guidance
- Diagnostics

During remote activity, the menu-bar item changes appearance. Opening it identifies the device, activity type, operation, duration, and an End Session command. If the display is locked, the event remains audited and the indicator is visible after the session UI becomes visible again.

## Technical alpha scope

The local-only technical alpha includes:

- One Mac and one iPhone
- Per-user LaunchAgent and menu-bar administration app
- Bonjour discovery and Local Network permission handling
- QR pairing with pinned host identity
- Monitor Only permission
- A bounded native system-status snapshot and subscription
- Connected and foreground-viewing presence
- Immediate active-session revocation
- Bounded local audit history
- Diagnostic CLI
- Lock, unlock, sleep, wake, logout, crash, and relaunch testing

It deliberately excludes Tailscale, many-to-many UX, generic provider manifests, remote actions, iOS background alerts, and MacTools integration.

## Interactive-control alpha scope

After the view-only lifecycle is trustworthy, the local Interactive Control alpha adds:

- One selected display at a time
- H.264 low-latency screen streaming
- App/window switcher and App Focus using transient, privacy-filtered candidates
- Smart Zoom around a verified focused element with manual visual fallback
- Touch-derived absolute pointer, click, drag, and bounded scroll input
- Physical-key and bounded text input with stuck-key recovery
- A device-specific Interactive Control grant and fresh phone user presence at session start
- Persistent menu-bar activity indication and a local suspend control
- Explicit unlocked, locked, unavailable, ended, and revoked session states
- No shell, file browser, clipboard synchronization, audio, relay, unattended pre-login operation, or multi-display composition

Native Smart Input is an experiment during this alpha, not an exit requirement. It can enter the private-route beta only after focus-race, secure-field, Unicode, application-compatibility, and content-free-diagnostics gates pass. Generic semantic overlays and app-provided native surfaces remain post-MVP.

Locked-session interaction is accepted only if physical-device spikes prove that public APIs show the genuine macOS lock surface and accept normal authentication input. Otherwise the session remains connected but reports `lockedInteractionUnavailable`.

## First differentiated beta scope

The beta adds:

- Saved Tailscale or private-network endpoints
- Guided, provider-neutral private-route diagnostics with no Mac Companion account or relay
- Monitor Only, Standard Control, and a separate Interactive Control grant
- User-presence-backed approvals
- One evidence-backed desired-state native action
- Durable operation IDs and reconnectable task results
- Interactive Control over a user-managed private route
- App Focus and Smart Zoom over the selected private route
- Quantitative usability, reliability, resource, and repeated-use validation

The first market-facing MVP continues to support one Mac and one phone in the product UX. Many-to-many presentation and the MacTools adapter follow the repeat-use gate; their identifiers and storage constraints are preserved from the start.

## Initial native actions

Candidate actions are selected before the action protocol is finalized because they shape idempotency, approval, availability, and UI semantics:

1. `setAudioMuted(Boolean)` — reversible and naturally idempotent.
2. `setAppearance(system | light | dark)` — reversible and desired-state based.
3. `startKeepAwake(until)` and `stopKeepAwake` — bounded, expiring, and reversible.

Toggles, arbitrary scripts, clipboard access, process termination, sleep, restart, shutdown, purchases, communications, credential entry, and destructive actions are not initial native actions.

## Explicit non-goals

- General shell access
- Arbitrary file browsing or clipboard synchronization
- Audio capture or microphone forwarding
- Reliable iOS background monitoring or alerts without an explicit APNs design
- Autonomous AI or visual computer use
- Purchases, messages, credentials, or external consequential actions
- A public internet relay
- Team or enterprise administration
- Boot-time or no-user service operation
- Lock-screen bypass
- Revealing or controlling the logged-in desktop behind the macOS lock screen
- A fully general JSON Schema renderer

## Product validation

The technical alpha validates feasibility. The differentiated beta validates product value with target users.

Initial product gates:

- At least 5 target users complete pairing without documentation.
- At least 4 use Mac Companion on three separate days during a two-week test.
- At least 3 identify one repeated monitoring or control job they would keep using.
- Users can correctly explain paired, connected, viewing, and controlling after using the product.
- Interactive Control testers can start, identify, suspend, and revoke a session without confusing it with Standard Control.
- Interactive Control testers use App Focus and Smart Zoom for real tasks and prefer them to repeated desktop pinch-and-pan.
- Modal dialogs, stale focus, or incompatible applications return to a comprehensible visual surface instead of accepting hidden or misdirected input.
- Pointer and keyboard tasks succeed over LAN and the selected private route without hidden local activity.
- No participant mistakes unreachable or stale status for live status, or assumes that unreachable proves the Mac is sleeping.

These are learning gates, not launch-scale business targets.

## Naming

**Mac Companion** is the final product and iPhone/iPad app name for planning and implementation.

Naming system:

- Product and iPhone/iPad app: **Mac Companion**
- Proposed App Store subtitle: **Monitor and control your Mac**
- Installed Mac component: **Mac Companion Agent**
- Protocol: **Mac Companion Capability Protocol**
- Interactive media protocol: **Mac Companion Interactive Control Protocol**
- Plain-language description: **A secure companion for monitoring and controlling your Mac from iPhone and iPad.**

The name deliberately favors immediate comprehension over a metaphorical brand. “Mac Connect” describes pairing more than the product’s lasting value. “Mac Remote Control” is crowded and makes the screen mirror the whole product. “Mac Companion” accommodates monitoring, bounded native controls, MacTools actions, and explicit Interactive Control without implying a general shell or arbitrary filesystem access.

This product decision does not replace clearance. “Mac companion” is used descriptively throughout the category, and historical products and publications have used similar wording. Apple also requires a unique App Store name and places conditions on third-party product names containing “Mac.” Trademark review, App Store name reservation, bundle identifier, domain, GitHub organization, package registry, and social-handle checks must finish before public launch or irreversible identifiers.

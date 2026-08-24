# Mac Companion Research and Decision Record

Research checked on 2026-08-19. Product listings, platform behavior, and documentation can change. Naming notes are preliminary product research, not legal advice or trademark clearance.

## Product-name decision

**Decision:** use **Mac Companion** as the product and iPhone/iPad app name. Use **Mac Companion Agent** for the installed macOS component and **Monitor and control your Mac** as the proposed App Store subtitle.

The name favors immediate comprehension and recall over a metaphorical brand. “Companion” is broad enough for monitoring, bounded system controls, MacTools actions, and later providers, while the subtitle explains the concrete job.

The current-product screen found that direct alternatives in this category are unusually crowded: Helm, MacReach, MacTap, MacLink, Maccess, Control My Mac, and Mac Remote Controller are all current products. “Mac companion” is also a common descriptive phrase in competitor copy, and similar wording has historical uses. This weakens exclusivity even though the exact proposed App Store title was not found in the initial screen. Before public launch, the project still needs:

- Trademark searches in intended jurisdictions and classes
- Apple App Store and Mac App Store searches across locales
- Company, domain, social-handle, package-registry, and code-host searches
- Professional legal review if commercial use is planned

**Why not MacHelm or Helm:** [Helm: Mac Remote Controller](https://apps.apple.com/us/app/helm-mac-remote-controller/id6761204919) is already an App Store product in the same broad category. The collision would make discovery, differentiation, and potential legal clearance unnecessarily difficult.

**Why not Mac Connect:** it names the pairing step, not the lasting value, and is too generic to search or protect well.

**Why not Mac Remote Control:** it is the clearest category label but is crowded and would reduce the product to only its flagship Control path. Mac Companion also supports status and bounded operations without requiring a screen session.

**Naming constraint:** [Apple’s App Review Guideline 2.3.7](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata) asks developers to choose a unique app name and limits it to 30 characters. [Apple’s third-party trademark guidance](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html) permits “Mac” in a product name only under stated conditions, including combining it with a non-generic word. Legal review and App Store name reservation therefore remain release gates even though the planning name is final.

Other candidates were screened out because exact or close names were already used by software products or companies, or because they were too generic. Keep those rejected candidates out of public collateral until a formal naming search is complete.

## Market evidence and positioning

The [2026-08-23 task-level competitive matrix](research/2026-08-23-competitive-task-matrix.md)
supersedes the initial feature-list comparison below. It records official-source
claims, pricing, conflicts, unknown time-to-first-frame evidence, a hands-on
calibration protocol, and explicit Stage 4–7 re-entry gates. The principal
finding is that app/window focus, QR pairing, direct LAN/private routes, and
touch control are category parity. The product hypothesis to test is instead
the combination of independently useful Observe/Act/Control paths,
revision-safe adaptive interaction, and truthful authorization, recovery, and
route state.

[ADR-0002](adr/0002-stage-3-product-evidence.md) converts that hypothesis into
the Stage 3 product gate: it freezes the initial audience, real-job definitions,
smallest three-path slice, separate calibration/confirmatory cohorts, exact
denominators and thresholds, safety overrides, and local user-exported evidence
boundary before any cohort result is reviewed.

The adjacent market already contains products described as Mac remotes:

- [Helm: Mac Remote Controller](https://apps.apple.com/us/app/helm-mac-remote-controller/id6761204919) occupies the exact former name and category.
- [MacReach](https://apps.apple.com/us/app/macreach-remote-control/id6773302981), [MacTap](https://apps.apple.com/us/app/mactap/id6762417419), [MacLink](https://maclink.space/), and [Maccess](https://www.mymaccess.app/) demonstrate how crowded direct `Mac + function` names have become.
- [Control My Mac](https://apps.apple.com/us/app/control-my-mac-remote-mouse/id6781458180) and [Mac Remote Controller](https://macremotecontroller.com/) already occupy the most literal action-led language.
- [Unyx](https://unyxapp.com/) uses “Mac companion” descriptively for its installed Mac component, illustrating why Mac Companion will need stronger visual identity and metadata rather than relying on exclusive ownership of the words.
- [CommandDeck](https://apps.apple.com/us/app/commanddeck-remote-for-mac/id6774549798) markets a Mac menu-bar companion and community command packages.
- [Shellcove](https://apps.apple.com/us/app/shellcove-remote-coding/id6774076404) markets remote coding with Tailscale and pinned TLS.
- [Cuevello](https://cuevello.app/) already combines display and app-window streaming, app switching, touch and keyboard control, menus, workflows, files, and local or VPN connectivity.
- [MacReacher](https://macreacher.app/) advertises full-desktop and single-app streaming, a remote app switcher, direct LAN or user-managed VPN sessions, and multiple touch-control modes.
- [Apperture](https://runapperture.com/) is explicitly positioned around filling an iPhone or iPad with one Mac application rather than the complete desktop.
- [Tomaco](https://tomaco.app/) competes on conventional remote-desktop performance, advertising peer-to-peer operation and up to 5K at 120 Hz on a local network.

App/window focus, QR pairing, peer-to-peer networking, Tailscale compatibility, hardware video, and touch control are category features rather than sufficient differentiation by themselves.

**Decision:** position Mac Companion around three first-class paths: **Observe**, **Act**, and **Control**. Adaptive Remote Desktop is the flagship Control capability, but Mac Companion is not only a remote desktop: status and bounded actions remain useful without starting capture. The differentiation hypothesis is the combination of surface adaptation, interaction adaptation, honest fallback, host-authoritative safety, and nonvisual operations under one private device and permission model.

That is a hypothesis, not proof of demand. Competitive teardown and product definition run alongside Stage 0 rather than blocking coding. Dogfooding, an external TestFlight cohort, user-exported privacy-preserving evidence, and repeat-use gates are required before calling the product a market-facing MVP; formal interviews are optional rather than mandatory.

### App Store classification risk

[App Review Guideline 4.2.7](https://developer.apple.com/app-store/review/guidelines/#minimum-functionality) adds restrictions when a remote desktop mirrors specific software rather than generically mirroring the host. Mac Companion therefore keeps full Desktop first-class, implements App and Window Focus generically rather than as an app catalog, renders and executes all Mac software on the user-owned host, and does not remotely install or sell Mac software. Because the product also supports a user-managed private route, its App Review explanation and TestFlight behavior must be tested early rather than treating approval as automatic.

Apple recommends [`SCContentSharingPicker`](https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker) instead of a custom capture picker, while the managed [Persistent Content Capture entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.persistent-content-capture) exists for VNC applications. Stage 0 must determine the supported relationship among local capture consent, persistent capture, and remotely requested display/application/window changes. The entitlement request and review notes describe the actual generic remote-desktop behavior rather than assuming that an iPhone-side app/window picker is automatically permitted.

## Platform findings

### iOS background execution

Apple's guidance explains that iOS does not provide a general-purpose mechanism for keeping arbitrary networking code running continuously in the background. Suspended apps stop running; background modes exist for defined use cases rather than as a generic socket exemption. See Apple's [iOS background execution guidance](https://developer.apple.com/forums/thread/685525).

Reliable remote notifications require a provider server that sends requests to APNs, as described in [Setting up a remote notification server](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server).

**Decision:** the private-network, no-relay product is foreground-first on iPhone and iPad. It does not promise persistent connections or reliable iPhone alerts while suspended. A future notification service would be a distinct architectural and privacy decision.

### Mac service lifecycle

Apple's Service Management APIs include `SMAppService` for registering login items and agents; see [`SMAppService`](https://developer.apple.com/documentation/servicemanagement/smappservice).

**Decision:** the first Mac service is a per-user LaunchAgent registered and administered by the menu-bar app. It can remain available while settings windows are closed and the session is locked, but it starts only after login and stops at logout. A persistent status item remains visible while the product is enabled. Login-window and no-user operation are out of scope unless a later privileged daemon is separately justified and reviewed.

The first Mac build uses direct Developer ID distribution, the hardened runtime, notarization, and an embedded `SMAppService` agent. A sandboxed listener may require the [`com.apple.security.network.server` entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.server), while IPC, provider integration, updater behavior, and MacTools compatibility make a Mac App Store build a later feasibility question rather than an MVP target.

### Interactive capture and input

Apple documents ScreenCaptureKit as the framework for high-performance screen content capture; see [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit). Apple separately documents a managed [Persistent Content Capture entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.persistent-content-capture) for VNC apps that need persistent access. Accessibility trust can be queried or prompted with [`AXIsProcessTrustedWithOptions`](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions), and Core Graphics provides event construction and posting APIs such as [`CGEvent`](https://developer.apple.com/documentation/coregraphics/cgevent).

**Decision:** Interactive Control is part of the MVP path and supports one live display plus mouse and keyboard. The persistent, visible menu app owns capture, encoding, Accessibility trust, and input injection. The LaunchAgent owns the network, device identity, grants, authorization epochs, session credentials, policy, and audit. If the menu app or its indicator is unavailable, Interactive Control stops while eligible status and semantic operations may remain available.

The Jenny Media LLC Account Holder prepared the managed-entitlement request against the registered final Mac App ID. Apple's form requires an App Store URL and numeric App Apple ID; because the directly distributed product is unreleased, submission waits for a verified prerelease App Store Connect path or Apple Developer Support confirmation. An Entitlements support case was opened on 2026-08-21 with its Case ID retained privately. External persistent Interactive Control distribution remains gated on approval or a reviewed public alternative.

### Locked-session feasibility

Apple's public documentation establishes capture and input APIs but does not promise that a third-party app can continuously capture and operate the lock surface in every logged-in state.

**Decision:** locked interaction is a Stage 0 hardware spike, not an assumed capability. If public APIs and the approved entitlement expose the genuine macOS lock UI, Mac Companion may stream that surface and forward ordinary input while macOS performs authentication. It never captures a behind-lock desktop or implements an unlock mechanism. If support is absent, the explicit result is `lockedInteractionUnavailable`. Logout, another active console user, the no-user login window, and FileVault preboot remain unavailable.

### Adaptive app, window, and focus presentation

ScreenCaptureKit can enumerate displays, applications, and windows and capture one desktop-independent window with an [`SCContentFilter`](https://developer.apple.com/documentation/screencapturekit/sccontentfilter). A running [`SCStream` can update its content filter](https://developer.apple.com/documentation/screencapturekit/scstream/updatecontentfilter%28_%3Acompletionhandler%3A%29) without creating a separate identity or permission system. AppKit's [`NSRunningApplication`](https://developer.apple.com/documentation/appkit/nsrunningapplication) can identify and request activation of a running application.

macOS Accessibility exposes the [`kAXFocusedUIElementAttribute`](https://developer.apple.com/documentation/applicationservices/carbon_accessibility/attributes/kaxfocuseduielemenattribute), element bounds, roles, attributes, and actions through [`AXUIElement`](https://developer.apple.com/documentation/applicationservices/axuielement). Editable elements may expose values and [`kAXSelectedTextRangeAttribute`](https://developer.apple.com/documentation/applicationservices/kaxselectedtextrangeattribute); secure fields have a documented [`kAXSecureTextFieldSubrole`](https://developer.apple.com/documentation/applicationservices/kaxsecuretextfieldsubrole).

**Decision:** Mac Companion adopts Adaptive Remote Surfaces within Interactive Control. Desktop remains the visual escape hatch. App Focus, Window Focus, Smart Zoom, and surface-adaptive interaction are MVP requirements because public APIs provide credible primitives and they make the iPhone experience more useful than a small desktop mirror. Smart Input begins keystroke-only and remains gated on secure-field, focus-race, Unicode, input-method, and compatibility evidence. Generic semantic reconstruction and app-provided native surfaces follow the market-MVP gate.

Accessibility metadata is advisory and can be incomplete, stale, or app-specific. The host confidence-rates it, uses ephemeral revision-bound tokens, and falls back to live pixels whenever it cannot prove the current app, window, focus, action, or privacy classification. Absence of a secure subrole is not proof that a value is safe to transmit.

### Local Network privacy

Apple documents Local Network privacy behavior and common Bonjour issues in [TN3179: Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

**Decision:** onboarding must explain why local access is needed, use a single declared Bonjour service type, and provide a recovery path after denial. Discovery output is untrusted routing information; it never establishes host identity.

### Device keys and user presence

Apple documents protecting keys with the Secure Enclave in [Protecting keys with the Secure Enclave](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave).

**Decision:** a paired iPhone or iPad has two identities:

1. A session key used to prove that the paired device is reconnecting.
2. A separate Secure Enclave-backed approval key that signs a short-lived, operation-specific challenge after Face ID, Touch ID, or passcode-backed user presence.

Unlocking the app and approving a particular operation are not treated as the same event.

### Private reachability

[Tailscale MagicDNS](https://tailscale.com/docs/features/magicdns) supplies stable names inside a tailnet, and [Tailscale HTTPS certificates](https://tailscale.com/docs/how-to/set-up-https-certificates) can cover tailnet names. Those names and certificates aid reachability; they do not replace Mac Companion pairing, device grants, host identity pinning, or operation approval.

**Decision:** Tailscale is an optional private route, not the product's authorization layer and not a cloud relay operated by Mac Companion. Mac Companion will not operate a relay or rendezvous account in the early or final product. It may guide the user through Tailscale or another user-managed private route and diagnose reachability without retaining VPN credentials.

### Status data and privacy manifests

Apple's privacy-manifest documentation applies data-collection declarations to
all supported platforms, while its current required-reason API platform list
does not include macOS. The current source nevertheless uses covered API
families for Mac-only uptime, disk-space, and durable-latch implementation.

**Decision:** the strict [Apple privacy-manifest profile](../spec/privacy-manifest/v0/profile.md)
and live validator inventory every covered source occurrence, validate the iOS
transitive target closure, and own one candidate resource per planned
executable bundle. The no-relay/no-analytics architecture currently declares
no developer collection or tracking; any developer-accessible transmission,
retention, SDK, or changed data flow must revise that decision before code is
admitted. The alpha excludes public-IP discovery, top-process lists,
screenshots, and third-party data calls until each receives a separate value
and privacy review. Application/window/focus metadata is excluded from status
and audit; the Adaptive Remote Surface allowlist permits only transient app
names/icons, generic window ordinals, bounds, category, editability, and secure
classification during an active Interactive Control session.

## Protocol research

The [W3C Web of Things Thing Description](https://www.w3.org/TR/wot-thing-description11/) is useful prior art for describing machine-readable properties, actions, events, schemas, and security metadata.

**Decision:** use it as conceptual input only. Mac Companion has a smaller security and lifecycle model and does not claim wire compatibility.

The [JSON Canonicalization Scheme, RFC 8785](https://www.rfc-editor.org/rfc/rfc8785.html), defines deterministic JSON suitable for cryptographic hashing and signing.

**Decision:** use RFC 8785 if approval challenges and durable operation digests are represented as JSON. If the transport selects a deterministic binary encoding, publish equivalent cross-language golden fixtures.

## Architecture decisions

### D1 — Observe, Act, and Control are first-class

The Mac library is the root, and each Mac workspace exposes current state, bounded capabilities, activity, and a prominent Connect or Resume control. Observe and Act never require a video session. Adaptive Remote Desktop is the flagship Control path and can be entered directly rather than only after another path fails. The three paths share identity, revocation, visibility, and audit foundations but retain separate grants. Terminal protocols, arbitrary commands, general filesystem browsing, clipboard, audio, and autonomous control remain outside the first product.

### D2 — Per-user authority plus a visible interactive executor

The LaunchAgent owns networking, pairing, durable grants, authorization epochs, policy, task state, and audit. The persistent menu app owns TCC-sensitive capture and input and must remain visible while Interactive Control is available. The two use authenticated, role-limited local IPC. A local process is not trusted merely because it runs as the same user or knows a socket path.

### D3 — Foreground iOS and no APNs dependency

The first product reports unreachability honestly and refreshes on foreground/reconnect. It does not invent a background-socket guarantee or hide notification infrastructure inside the MVP definition.

### D4 — Native MVP, then a MacTools adapter before a public provider SDK

The Observe, native Act, and Adaptive Control MVP must not depend on MacTools. Stage 0 records only a paper compatibility map. After the no-relay three-path beta, MacTools supplies the first concrete integration model with bounded parameters, availability, progress, cancellation, concurrency, timeout, and final executor revalidation. The adapter must add a distinct default-deny remote-exposure policy and translate effects safely. Generalize only after this real integration exposes the correct boundary.

### D5 — Effect facts instead of one risk number

Policy needs to know what an operation reads, changes, invokes, disrupts, and whether it works while locked or can be cancelled. A single ordinal risk label hides those independent decisions and does not compose reliably across providers.

### D6 — Durable IDs with bounded idempotency

Operation records are stored before provider admission. Repeated identical IDs return the same record, while digest mismatches fail. After a crash, unknowable external effects become `outcomeUnknown`; generic exactly-once execution is not claimed and unsafe operations are not silently retried.

### D7 — Desired-state actions first, with independent feasibility gates

The initial controls favor desired state over toggles or imperative scripts.
Audio mute is the required MVP action and bounded keep-awake is a
candidate-only lease. The proposed three-state system-appearance action is a
[Stage 0 no-go](research/2026-08-21-native-system-appearance-feasibility.md):
public AppKit controls only Mac Companion's own appearance, while System Events
Automation adds explicit permission but cannot represent the user's
automatic/system mode. A later light/dark Automation action would be a new,
separately reviewed capability.

### D8 — Current observation is distinct from last-known state

Disconnect means `unreachable`, accompanied by the last reported state and timestamp. It does not prove the Mac is sleeping. Every status value carries observation and freshness metadata.

### D9 — Active revocation and bounded audit from alpha

Revoking a device closes active sessions and invalidates unused approvals. Audit storage has quotas, retention, rate limits, redaction, and explicit disk-full behavior before any control action ships.

### D10 — Technical alphas before market MVP

The local Observe alpha proves lifecycle, identity, freshness, presence, revocation, and audit. The local Adaptive Control alpha proves capture, input, surface adaptation, interaction adaptation, visibility, authorization fencing, and privacy. The no-relay three-path beta must then demonstrate repeat use of real Control jobs and at least one nonvisual Observe or Act path before the project claims a market-facing MVP. No individual user is required to use all three. MacTools breadth follows rather than defines that gate.

### D11 — Consent permits broad control but does not erase containment

A user may knowingly grant one paired device Interactive Control. The grant acknowledges the real ability to operate arbitrary visible UI and the residual risk that follows. It does not imply shell, files, clipboard, providers, future capabilities, AI control, or remote self-elevation. Fresh client user presence, local device-specific enablement, visible activity, authorization epochs, immediate suspension, active revocation, bounded protocols, and content-free audit remain mandatory.

### D12 — No Mac Companion network relay

LAN, private DNS, and user-managed overlay networks are routes to the same pinned host identity. Mac Companion does not operate an account, relay, rendezvous service, VPN, public discovery service, or port-forwarding service. This keeps routing responsibility with the user and means the iOS app is foreground-first, cannot promise wake, and cannot promise reliable background alerts.

### D13 — Direct distribution and current stable platforms

The Mac app ships directly with Developer ID, hardened runtime, notarization, a notarized DMG, an embedded `SMAppService` agent, and signed Sparkle 2 updates. The iOS app uses TestFlight and then the App Store. The first deployment target is the stable macOS/iOS 26 generation, built with stable Xcode 26.6; generation 27 betas are compatibility tests. The Jenny Media LLC team is the release authority.

### D14 — Adaptive Remote Surfaces inside Interactive Control

Desktop, application, window, focused-region, and experimental text-input surfaces are ephemeral presentations inside the existing Interactive Control grant. The agent owns selection and revision authority; the visible menu app resolves ScreenCaptureKit and Accessibility objects; the iOS client renders declared confidence and fallback and selects a surface-appropriate input profile with a visible override. Surface switching cannot persist beyond the session or broaden access.

### D15 — Pixels outrank uncertain semantics

Desktop is the universal escape hatch. App Focus, Window Focus, and Smart Zoom may use verified application/window identity and focused-element bounds, but modal ambiguity, stale elements, timeout, incomplete Accessibility support, or privacy uncertainty returns to a visible app or desktop surface. Native controls require verified current semantics and are post-MVP; Mac Companion never guesses a consequential action from ambiguous metadata.

### D16 — Product-first execution and bounded completion

When an end-to-end slice is unblocked, permanent signed targets and physical behavior outrank more construction-only infrastructure. The runnable order is LAN pairing and reconnection, Observe, native `setAudioMuted`, then Desktop pixels plus mouse and keyboard; adaptive surfaces then complete the Stage 2 proof. The goal completes at a signed, installable external Stage 3 beta with market-MVP evidence. Stages 4–7 may pass, receive an evidence-backed no-go, or remain explicitly deferred rather than forcing speculative scope into the release.

### D17 — Official identity and open-source policy

Jenny Media controls the `media.jenny` reverse-DNS namespace, so official role-based identifiers use `media.jenny.maccompanion`. Development identities may be installed on the development Mac, while distribution and promotion credentials remain in separate controlled custody. Apache-2.0 plus a distinct Mac Companion/Jenny Media trademark policy is the selected publication model subject to legal review, with GitHub private vulnerability reporting first. Further pushes and external contributions pause until the policy, history, and provider-protection gates pass.

## Open decisions

- Formal Mac Companion trademark review and App Store name reservation
- Remaining explicit Agent distribution plus iOS/XPC App ID registration; the Jenny Media LLC Team ID is confirmed privately, the company-controlled prefix is fixed as `media.jenny`, `media.jenny.maccompanion` is registered, and the app-wrapped `media.jenny.maccompanion.agent` identity plus private Keychain group are development-profile-authorized
- Persistent Content Capture request submission after resolving Apple's required App Store URL/Apple ID path, then managed-entitlement approval
- Exact transport framing and serialization
- Local IPC primitive and code-identity verification method
- Pairing user experience and out-of-band fingerprint confirmation
- Measured locked-session support using public APIs
- Smart Input compatibility and secure-field evidence across the supported app and keyboard matrix
- Audit quotas and retention periods
- Which initial actions remain reliable across the supported OS matrix
- Final legal approval and publication of the selected Apache-2.0 license, trademark, contribution, and security-reporting policies
- Commercial model, free/Pro boundaries, pricing, and Family Sharing; a lifetime non-consumable is the working hypothesis while Mac Companion operates no recurring network service

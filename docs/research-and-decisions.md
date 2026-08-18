# Mac Companion Research and Decision Record

Research checked on 2026-08-17. Product listings, platform behavior, and documentation can change. Naming notes are preliminary product research, not legal advice or trademark clearance.

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

**Why not Mac Remote Control:** it is the clearest category label but is crowded and would reduce the product to its pointer-and-keyboard fallback. Mac Companion includes Interactive Control, but its differentiator is moving from status to semantic action to live intervention without making a blank remote screen the whole product.

**Naming constraint:** [Apple’s App Review Guideline 2.3.7](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata) asks developers to choose a unique app name and limits it to 30 characters. [Apple’s third-party trademark guidance](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html) permits “Mac” in a product name only under stated conditions, including combining it with a non-generic word. Legal review and App Store name reservation therefore remain release gates even though the planning name is final.

Other candidates were screened out because exact or close names were already used by software products or companies, or because they were too generic. Keep those rejected candidates out of public collateral until a formal naming search is complete.

## Market evidence and positioning

The adjacent market already contains products described as Mac remotes:

- [Helm: Mac Remote Controller](https://apps.apple.com/us/app/helm-mac-remote-controller/id6761204919) occupies the exact former name and category.
- [MacReach](https://apps.apple.com/us/app/macreach-remote-control/id6773302981), [MacTap](https://apps.apple.com/us/app/mactap/id6762417419), [MacLink](https://maclink.space/), and [Maccess](https://www.mymaccess.app/) demonstrate how crowded direct `Mac + function` names have become.
- [Control My Mac](https://apps.apple.com/us/app/control-my-mac-remote-mouse/id6781458180) and [Mac Remote Controller](https://macremotecontroller.com/) already occupy the most literal action-led language.
- [Unyx](https://unyxapp.com/) uses “Mac companion” descriptively for its installed Mac component, illustrating why Mac Companion will need stronger visual identity and metadata rather than relying on exclusive ownership of the words.
- [CommandDeck](https://apps.apple.com/us/app/commanddeck-remote-for-mac/id6774549798) markets a Mac menu-bar companion and community command packages.
- [Shellcove](https://apps.apple.com/us/app/shellcove-remote-coding/id6774076404) markets remote coding with Tailscale and pinned TLS.

**Decision:** do not lead with “remote desktop for your Mac.” Position Mac Companion as a **secure companion for monitoring and controlling a Mac you own**: semantic status, bounded actions, visible presence, host-enforced policy, provider integrations, and a separately granted live screen/mouse/keyboard fallback.

That is a hypothesis, not proof of demand. Stage -1 interviews and the differentiated-beta repeat-use gates are required before calling the product a market-facing MVP.

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

The managed-entitlement request must be submitted by the Jenny Media LLC Account Holder against the final App ID. External Interactive Control distribution is gated on approval or a reviewed public alternative.

### Locked-session feasibility

Apple's public documentation establishes capture and input APIs but does not promise that a third-party app can continuously capture and operate the lock surface in every logged-in state.

**Decision:** locked interaction is a Stage 0 hardware spike, not an assumed capability. If public APIs and the approved entitlement expose the genuine macOS lock UI, Mac Companion may stream that surface and forward ordinary input while macOS performs authentication. It never captures a behind-lock desktop or implements an unlock mechanism. If support is absent, the explicit result is `lockedInteractionUnavailable`. Logout, another active console user, the no-user login window, and FileVault preboot remain unavailable.

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

Apple lists [`ProcessInfo.systemUptime`](https://developer.apple.com/documentation/foundation/processinfo/systemuptime) among APIs whose use may require an approved reason declaration in a privacy manifest.

**Decision:** Stage 0 inventories every status API and release-manifest obligation. The alpha excludes public-IP discovery, top-process lists, application and window names, screenshots, and third-party data calls until each receives a separate value and privacy review.

## Protocol research

The [W3C Web of Things Thing Description](https://www.w3.org/TR/wot-thing-description11/) is useful prior art for describing machine-readable properties, actions, events, schemas, and security metadata.

**Decision:** use it as conceptual input only. Mac Companion has a smaller security and lifecycle model and does not claim wire compatibility.

The [JSON Canonicalization Scheme, RFC 8785](https://www.rfc-editor.org/rfc/rfc8785.html), defines deterministic JSON suitable for cryptographic hashing and signing.

**Decision:** use RFC 8785 if approval challenges and durable operation digests are represented as JSON. If the transport selects a deterministic binary encoding, publish equivalent cross-language golden fixtures.

## Architecture decisions

### D1 — Dashboard first, Interactive Control when needed

Status, semantic capabilities, visible sessions, and host-enforced policy are the core. A separately granted live screen, mouse, and keyboard session is the broad fallback in the MVP, opened from a Mac task or overview rather than used as the home screen. Terminal access, arbitrary commands, general filesystem browsing, clipboard, audio, and autonomous control remain outside the first product.

### D2 — Per-user authority plus a visible interactive executor

The LaunchAgent owns networking, pairing, durable grants, authorization epochs, policy, task state, and audit. The persistent menu app owns TCC-sensitive capture and input and must remain visible while Interactive Control is available. The two use authenticated, role-limited local IPC. A local process is not trusted merely because it runs as the same user or knows a socket path.

### D3 — Foreground iOS and no APNs dependency

The first product reports unreachability honestly and refreshes on foreground/reconnect. It does not invent a background-socket guarantee or hide notification infrastructure inside the MVP definition.

### D4 — Native MVP, then a MacTools adapter before a public provider SDK

The view-only and Interactive Control MVP must not depend on MacTools. After the no-relay private-operations beta, MacTools supplies the first concrete integration model with bounded parameters, availability, progress, cancellation, concurrency, timeout, and final executor revalidation. The adapter must add a distinct default-deny remote-exposure policy and translate effects safely. Generalize only after this real integration exposes the correct boundary.

### D5 — Effect facts instead of one risk number

Policy needs to know what an operation reads, changes, invokes, disrupts, and whether it works while locked or can be cancelled. A single ordinal risk label hides those independent decisions and does not compose reliably across providers.

### D6 — Durable IDs with bounded idempotency

Operation records are stored before provider admission. Repeated identical IDs return the same record, while digest mismatches fail. After a crash, unknowable external effects become `outcomeUnknown`; generic exactly-once execution is not claimed and unsafe operations are not silently retried.

### D7 — Desired-state actions first

The initial controls set audio mute, set appearance, and start or stop a bounded keep-awake lease. They are easier to validate and reconcile than toggles or imperative scripts.

### D8 — Current observation is distinct from last-known state

Disconnect means `unreachable`, accompanied by the last reported state and timestamp. It does not prove the Mac is sleeping. Every status value carries observation and freshness metadata.

### D9 — Active revocation and bounded audit from alpha

Revoking a device closes active sessions and invalidates unused approvals. Audit storage has quotas, retention, rate limits, redaction, and explicit disk-full behavior before any control action ships.

### D10 — Technical alphas before market MVP

The local view-only alpha proves lifecycle, identity, freshness, presence, revocation, and audit. The local Interactive Control alpha proves capture, input, visibility, authorization fencing, and privacy. The no-relay operations beta must then demonstrate repeat use of the selected job before the project claims a market-facing MVP. MacTools breadth follows rather than defines that gate.

### D11 — Consent permits broad control but does not erase containment

A user may knowingly grant one paired device Interactive Control. The grant acknowledges the real ability to operate arbitrary visible UI and the residual risk that follows. It does not imply shell, files, clipboard, providers, future capabilities, AI control, or remote self-elevation. Fresh client user presence, local device-specific enablement, visible activity, authorization epochs, immediate suspension, active revocation, bounded protocols, and content-free audit remain mandatory.

### D12 — No Mac Companion network relay

LAN, private DNS, and user-managed overlay networks are routes to the same pinned host identity. Mac Companion does not operate an account, relay, rendezvous service, VPN, public discovery service, or port-forwarding service. This keeps routing responsibility with the user and means the iOS app is foreground-first, cannot promise wake, and cannot promise reliable background alerts.

### D13 — Direct distribution and current stable platforms

The Mac app ships directly with Developer ID, hardened runtime, notarization, a notarized DMG, an embedded `SMAppService` agent, and signed Sparkle 2 updates. The iOS app uses TestFlight and then the App Store. The first deployment target is the stable macOS/iOS 26 generation, built with stable Xcode 26.6; generation 27 betas are compatibility tests. The Jenny Media LLC team is the release authority.

## Open decisions

- Formal Mac Companion trademark review and App Store name reservation
- Jenny Media LLC Team ID and company-controlled reverse-DNS bundle prefix
- Persistent Content Capture managed-entitlement approval
- Exact transport framing and serialization
- Local IPC primitive and code-identity verification method
- Pairing user experience and out-of-band fingerprint confirmation
- Measured locked-session support using public APIs
- Audit quotas and retention periods
- Which initial actions remain reliable across the supported OS matrix

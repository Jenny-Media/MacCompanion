# Mac Companion Staged Validation Plan

## Objective

Validate the riskiest platform, security, and product assumptions before expanding Mac Companion into a broad personal-Mac control platform.

The plan distinguishes a technical alpha—proof that the secure lifecycle works—from a differentiated beta—proof that people repeatedly use Mac Companion for real operational jobs.

Mac Companion validates three independently useful, connected experiences: **Observe** current Mac state, **Act** through bounded operations, and **Control** through an explicitly granted Adaptive Remote Desktop session. Control is the flagship capability and may be entered directly, but users do not need to stream the screen to check status or invoke an approved action. Interactive Control does not include a shell, arbitrary files, clipboard, audio, provider execution, or autonomous control and must never be implied by ordinary pairing, `Standard Control`, a provider installation, or a broad “allow future capabilities” switch.

The execution target is a signed, installable external Stage 3 beta that passes the market-MVP evidence gate. Stages 4–7 continue only where evidence and safety gates justify them and may close with explicit `passed`, `no-go`, or `deferred` decisions. Whenever unblocked, implementation prioritizes the shortest signed, physical, runnable product slice over additional construction-only infrastructure.

## Product evidence workstream: positioning and validation

This workstream runs alongside Stage 0 and does not block isolated platform spikes or repository scaffolding. Its evidence gates the external beta and public positioning rather than the start of coding.

### Work

- Use **Mac Companion** as the working product and iPhone/iPad app name, **Mac Companion Agent** for the installed Mac component, and **Monitor and control your Mac** as the proposed App Store subtitle.
- Complete written trademark review and reserve the App Store name before public branding, marketing domains, paid naming work, or external launch. Company-controlled bundle identifiers use stable role-based identifiers and do not wait for public-name reservation.
- Prepare Apache-2.0 licensing and a separate Mac Companion/Jenny Media trademark policy, both subject to legal review. Use GitHub private vulnerability reporting initially and hold further pushes and external contributions until the license, trademark, security, full-history, and provider-protection gates are complete.
- Build a task-level competitor matrix for Helm, Cuevello, MacReacher, Apperture, Tomaco, CommandDeck, Shellcove, generic screen sharing, and SSH. Compare pairing, time to first frame, LAN and private-route behavior, app/window focus, keyboard and touch behavior, nonvisual actions, permission onboarding, recovery, privacy, pricing, and support boundaries.
- Use owners of logged-in personal Macs who want private, no-relay remote operation as the beachhead hypothesis. Define representative Observe, Act, and Control jobs without assuming that every user needs all three in every session.
- Dogfood repeated jobs such as checking a build, inspecting Simulator, operating Terminal or Xcode, checking Mac health, running one bounded action, recovering from a modal dialog, and reconnecting over Tailscale. Record every return to the physical Mac and why it was necessary.
- Define privacy-preserving TestFlight measurements and a tester-exported diagnostic report before the beta. Optional conversations and short surveys may add context, but formal interviews are not a prerequisite for implementation.
- Write an ADR selecting the initial audience, representative jobs, positioning, and the smallest three-path product slice that can test the thesis.

### Exit criteria

- No unresolved high-risk naming conflict in target markets; Mac Companion remains the implementation and intended product name, while public use remains gated by written trademark review and App Store name reservation.
- The initial audience, representative Observe, Act, and Control jobs, current workarounds, and value hypothesis can be stated without depending on future AI or provider breadth.
- The competitive teardown identifies which features are category parity and which adaptive or nonvisual behaviors still need product proof.
- The TestFlight evidence plan can detect pairing failure, connection failure, unintended input, adaptive-surface avoidance, nonvisual task completion, and repeat use without collecting screen contents, app titles, typed text, coordinates, or Accessibility values.

## Stage 0A: constraint spikes and architecture decisions

This stage produces small harnesses and decision records, not a polished app.

### Platform and distribution

- Initialize version control and CI before production scaffolding; release-shaped artifacts and security fixtures must be reproducible from a recorded revision.
- Use macOS 26 and iOS/iPadOS 26 as the initial deployment targets. Permit installed Xcode 27 beta for development, compatibility, signing setup, device work, and currently supported TestFlight uploads; reproduce final signed release evidence with stable Xcode 26.6 and Swift 6.3.
- Use the Jenny Media-controlled `media.jenny` bundle prefix and the role-based identifiers recorded in the distribution plan. The Team ID is confirmed privately and `media.jenny.maccompanion` is registered; register remaining permanent role App IDs only with their target scaffolds.
- Permit development signing identities on the development Mac, while keeping Developer ID, App Store distribution, notarization, Sparkle, and promotion credentials in a separate controlled release environment. Provisional permanent-target builds now verify the local Apple Development and Developer ID Application identities, so do not create duplicates; stable-toolchain reproduction and final credential custody remain release gates.
- Select and spike the initial deployment topology: Developer ID distribution, an embedded `SMAppService` LaunchAgent, authenticated XPC/Mach IPC, and the process and bundle boundaries for the menu app, service, CLI, and protocol libraries.
- Validate code signing, hardened runtime, notarization, login-item registration, update, rollback, uninstall, and authenticated local IPC using release-shaped artifacts.
- Decide whether a Mac App Store build is viable only after testing sandbox, listener entitlement, LaunchAgent, update, capture, and input constraints.
- Prove the per-user LaunchAgent lifecycle through app quit, service crash, screen lock, fast user switching, logout, sleep, wake, and login-item disablement.
- Write an ADR for one configured macOS account as the initial host owner. Define lock versus fast-user-switch behavior and fail closed when the active console owner cannot be established.
- Write an ADR for activity visibility. Closing settings must not quit the menu-bar indicator while the service is enabled; define automatic restoration and degraded/fail-closed behavior if the indicator process crashes.
- Resolve Apple's required App Store URL and numeric Apple ID path for the unreleased, directly distributed product, then submit the already prepared Persistent Content Capture request through the Jenny Media LLC Account Holder and record its private status as an Interactive Control dependency.
- Record how Apple’s system ScreenCaptureKit picker, the managed Persistent Content Capture entitlement, and remotely initiated display/application/window changes can coexist. Do not assume that a custom remote picker is acceptable without entitlement and App Review evidence.
- Review App Store Guideline 4.2.7 against the actual iOS experience. Keep full Desktop first-class, keep App and Window Focus generic, render all Mac software on the user-owned host, avoid app-store-like browsing or remote installation, and test how user-managed private routes are described to App Review.
- Spike the persistent menu app as the owner of ScreenCaptureKit, VideoToolbox, Accessibility trust, and `CGEvent` input while the LaunchAgent remains the network and policy authority.
- Prove capture and input across unlocked, locked, display-sleep, display-change, menu-app crash, fast-user-switch, logout, and permission-revocation transitions. Lock-screen success means showing and operating only the genuine macOS lock surface.
- Spike display-to-window and application-filter switching, related sheets/popovers/dialogs, full-screen Spaces, application activation, and clean-keyframe transitions.
- Spike conservative Accessibility focus observation across AppKit, SwiftUI, browser, Electron, and custom-drawn apps. Measure stale-element and timeout behavior and prove that secure fields expose no value-derived metadata.
- Write an ADR adopting Remote Surfaces: Desktop remains the visual escape hatch, App Focus, Window Focus, and Smart Zoom are MVP requirements, Smart Input is a gated experiment, and semantic/provider-native surfaces are post-MVP.
- Add a permission matrix mapping each capability to its executing process, entitlement or TCC service, allowed session states, onboarding owner, and revocation behavior.
- Record SSH as excluded from runtime capability transport. A later SSH-assisted installer may deploy the same signed package, but may not retain SSH credentials or bypass pairing, policy, audit, and visibility.

### Networking and identity

- Exercise Local Network permission grant, denial, later recovery, and Bonjour discovery using one declared service type.
- Make first pairing a foreground same-LAN flow. After pairing, allow reconnection over ordinary private LAN routes or user-entered, explicitly saved Tailscale/private-DNS/IP endpoints; never infer a private-route product or authorization state from an interface, DNS suffix, or installed process.
- Choose the default listener interfaces and re-evaluation behavior for Wi-Fi, Ethernet, VPN, Tailscale, and public-network transitions.
- Select exact TLS 1.3 transport, channel framing, bounded message encoding, and canonicalization. Prefer the smallest implementation that satisfies the measured lifecycle; document why if choosing QUIC or HTTP/2 over TLS/TCP.
- Prove host certificate pinning across Bonjour, direct private IP, and Tailscale endpoint changes.
- Prototype the session key and separate Secure Enclave-backed user-presence approval key.
- Document key loss, phone replacement, host migration, revocation, and re-pairing.

### Data and actions

- Verify every native status field on supported hardware, locked sessions, missing sensors, and permission-denied states.
- Inventory required-reason API and privacy-manifest obligations, including system uptime.
- Define the transient Remote Surface metadata allowlist. Application/window candidates, focus bounds, secure-field classification, and future semantic values must not inherit the status or audit data policy implicitly.
- Spike `setAudioMuted`, `setAppearance`, and bounded keep-awake start/stop as desired-state actions. Record the result for each independently: mute is the required MVP action, bounded keep-awake is candidate-only pending physical and UX proof, and the three-state system-appearance action is a no-go because public AppKit is app-local while System Events Automation cannot represent the user's automatic/system mode.
- Record a paper compatibility map to MacTools' current action, availability, concurrency, cancellation, result, and generation concepts. Do not build the bridge or let MacTools requirements expand the MVP protocol before the native three-path beta passes.
- Select Keychain policy for private keys and a service-owned SQLite model for devices, grants, authorization epochs, replay windows, operations, and audit.
- Define schema migration, rollback compatibility, transaction boundaries, quotas, and disk-full behavior before implementing pairing or control.
- Establish the test harness architecture: injectable clock, randomness, storage, network, session state, and provider boundaries; golden fixtures; fuzz targets; crash hooks; and a fake provider.

### Exit criteria

Stage 0A is tracked as independently statusable platform, identity/networking, data/action, and delivery lanes. A blocked lane prevents only the artifact or promotion gate that depends on it; it does not stop unrelated specifications, pure packages, tests, or disposable experiments.

- Every decision required by a promoted artifact has a recorded result, rejected alternatives, remaining risk, and evidence link or an explicit `no-go` disposition.
- Harnesses demonstrate the selected lifecycle and pinned connection on physical Macs and iPhones before Stage 1 promotion; lack of that evidence does not block bundle-independent protocol work.
- The team can name which claims are supported by public APIs and which remain conservative approximations.
- No Stage 1 requirement depends on an unresolved entitlement or background-execution assumption.
- Target, signing, IPC, TCC, data ownership, update order, and component compatibility are concrete before release-shaped targets are promoted, without preventing identity-neutral scaffolding.
- The execution ledger identifies every external blocker and the independent work that continues around it.

## Stage 0B: executable mini-RFC and threat model

### Specification work

- Freeze the first wire envelope, canonicalization method, size limits, timeouts, and version negotiation.
- Specify a normative authenticated handshake: algorithms, certificate construction, QR-pinned host-key binding, fresh server challenge, client proof bound to the live TLS channel and protocol version, key confirmation, rotation, recovery, resumption, and a no-0-RTT rule for authentication or state changes.
- Specify race-safe pairing using a 256-bit one-time QR secret and a short authentication string derived from both device keys, host identity, pairing ID, negotiated protocol, and complete transcript. The phone pins the QR host identity before disclosure, both devices display the same authentication string, local approval binds its transcript hash, and pairing-session consumption is atomic and durable.
- Define bounded status, capability, parameter, result, effect, error, presence, audit, and operation schemas.
- Publish golden fixtures for canonical requests, approval challenges, signatures, errors, and version handling.
- Define the exact signed operation digest, including host, client, capability and schema, provider generation, canonical parameters, effects, authorization epoch and policy revision, expiry, and protocol version.
- Define grant revisions, policy profiles, default-deny capability addition, authorization-epoch fencing, and active revocation at an atomic provider-admission boundary.
- Define ordered snapshots, event sequence, resume windows, gaps, and resnapshot behavior.
- Define durable replay windows, approval consumption, operation identity, duplicate-request behavior, cancellation, crash recovery, and `outcomeUnknown` behavior.
- Separate host-derived `dataAccessActive` state from client-declared viewing UX. Define `Disconnect`, reversible `Suspend device`, and permanent `Revoke` semantics.
- Define host-owned audit redaction, retention, quota, rate-limit, at-rest protection, and security-write failure policy. Providers cannot opt sensitive fields into logs by omission.
- Freeze one operation state machine and one effect vocabulary across the architecture and protocol.
- Specify exact Keychain access-control and user-presence behavior across reboot, first unlock, biometric enrollment changes, passcode removal, restore, reinstall, and host migration.
- Freeze the Interactive Control session, channel, video, input, coordinate, lock-state, indicator, timeout, and error profiles in `interactive-control-spec.md`.
- Freeze surface kinds, selection, focus, related-window fallback, Smart Input, privacy, and confidence rules in `adaptive-remote-surfaces.md`.
- Publish binary header, H.264 format, surface and coordinate transforms, pointer, keyboard, session/surface transitions, focus changes, secure-field redaction, fallback, and key-release fixtures shared by the Mac and iOS implementations.

### Security work

- Complete the threat cases listed in the protocol outline.
- Review local IPC designated requirements and audit-token checks, pairing races and rate limits, transcript relay and downgrade defense, replay across restart and TLS resumption, schema limits, authorization/admission races, malicious providers, audit fault injection, and interface-change exposure.
- Treat provider installation as extending local trust unless the provider is independently sandboxed. Require host-reviewed publisher identity, effect metadata, exposure, and host-generated approval warnings.
- Add signed-update threat cases covering metadata, signer rotation, downgrade resistance, interrupted updates, compromised-release recovery, mixed component versions, and database migration.
- Schedule an independent security review before any public beta that permits control actions.

### Exit criteria

- Separate client and service implementations can build the same narrow `status.snapshot` and `setAudioMuted` exchange from the documents and golden fixtures.
- Golden and negative tests reject MITM, reverse-proxy relay, key or certificate substitution, cross-host and cross-session replay, pairing races, reused approvals, authorization-epoch races, oversized or malformed data, downgrade, and unauthorized inputs.
- Interactive tests reject stale or forged channel credentials, frames and input after epoch change, duplicate button transitions, stuck keys after disconnect, pre-lock desktop frames after a lock transition, and control while the menu app or indicator is unavailable.
- Adaptive-surface tests reject substituted app/window tokens, stale surface/coordinate/focus revisions, invisible modal interaction, secure-field metadata, input after focus moves, and semantic promotion from ambiguous Accessibility data.
- Open protocol questions are explicitly deferred and cannot silently change security semantics.
- Pairing, privilege elevation, and consequential control fail closed when their required durable security record cannot be committed. Revocation first advances the durable device epoch and records a minimal security event atomically; if that transaction fails, the service activates its reserved emergency deny latch, closes all remote work, and refuses remote startup until local recovery proves writable, consistent security storage.

## Stage 1: local Observe and lifecycle alpha

### Scope

- One Mac and one iPhone or iPad
- Per-user LaunchAgent, menu-bar administration UI, and `maccompanionctl` diagnostics
- Bonjour discovery on the local network
- QR pairing with host fingerprint verification
- `Monitor Only` device grant
- Bounded system overview: host identity, OS, uptime, power, CPU, memory, storage, and private-interface summaries
- Connected state, host-derived data-access activity, and advisory client viewing leases with a persistent local indicator
- Immediate device revocation and active session closure
- Bounded local audit history
- Foreground-only iOS operation with clear unavailable and stale states

Public IP lookup, top-process lists, application/window names, screenshots, control actions, and third-party providers are out of scope. This is an implementation dependency, not a statement that Observe outranks Act or Control in the product.

### Verification

- Five target testers complete the journey from clean Mac and iPhone installs through first current snapshot without assistance; record time-to-value, abandonment point, and help required.
- Revocation prevents new authenticated requests and closes the active session within one second on a healthy local connection.
- The local indicator reflects actual snapshot or subscription traffic even when a client omits or falsifies its viewing lease; the lease may only refine the claimed UI surface.
- Local reconnect reaches a current snapshot in a measured p95 of three seconds or less on the test network.
- The client never labels stale or disconnected observations as live.
- Status remains available while locked; logout makes the host explicitly unreachable.
- Local Network denial has a usable recovery path and never produces a misleading empty device list.
- A seven-day soak stays within documented memory, CPU, energy, log, audit, and disk budgets.

### Exit gate

Proceed only if lifecycle, presence, revocation, and freshness semantics are dependable enough that testers correctly understand who is connected and whether data is current.

## Stage 2: local Adaptive Control alpha

The first runnable Control vertical slice is deliberately narrower than this stage's exit scope: one Desktop stream plus mouse and keyboard, with the required grant, visible indicator, suspension, revocation, and fail-closed lifecycle. App Focus, Window Focus, Smart Zoom, and interaction adaptation follow on the same authority and remain required before Stage 2 can pass.

### Scope

- One Mac and one paired iPhone or iPad on the local network
- A separate, device-specific Interactive Control grant with fresh phone user presence at session start
- One selected display streamed with the H.264 baseline profile
- Desktop as the persistent escape hatch, App Focus for a privacy-filtered related-window set, and explicit Window Focus for one independently captured window
- Manual Smart Zoom plus verified focus-assisted framing, with manual visual zoom as the fallback
- Surface-specific trackpad, direct-touch, and keyboard defaults with a persistent user override
- Native iOS keyboard and modifier toolbar while live pixels remain authoritative
- Absolute pointer movement, click, drag, bounded scroll, physical-key, modifier, and bounded text input
- Persistent menu-bar indication identifying the controlling device and a local suspend control
- Agent-enforced session creation, expiry, authorization epoch, channel credentials, rate limits, and audit metadata
- Menu-app-owned ScreenCaptureKit, VideoToolbox, and Accessibility-mediated input over authenticated local IPC
- Explicit unlocked, locked, locked-interaction-unavailable, suspended, revoked, ended, and host-unavailable states
- Session-scoped surface, application/window, coordinate, and focus revisions with visible fallback reasons

Smart Input may run as a disabled-by-default compatibility experiment but is not an alpha exit requirement. Tailscale, many-to-many UX, semantic overlays, provider-native surfaces, semantic control actions, MacTools, shell, files, clipboard, audio, multi-display composition, wake-from-sleep, headless operation, and pre-login access remain out of scope.

### Verification

- Revocation, suspension, menu-app loss, permission loss, logout, user switch, and authorization-epoch change stop capture and input and invalidate unused channel credentials.
- Disconnect releases every remotely pressed key and pointer button without inventing a click or key repeat.
- Display and scale changes create a new coordinate-space revision; stale input is rejected rather than applied to the wrong location.
- App/window switches create new surface and coordinate revisions; input remains paused until the descriptor and clean keyframe are acknowledged.
- Sheets, dialogs, window disappearance, app exit, stale focus, AX timeout, and incomplete Accessibility data produce a visible related-window, application, Desktop, or manual-zoom fallback rather than hidden input.
- The candidate picker omits titles, document paths, URLs, thumbnails, labels, values, and content, and no ephemeral application/window/focus metadata enters durable logs.
- The host never transmits a pre-lock desktop frame after reporting `userSessionLocked`.
- If public APIs support lock-surface interaction, the client sees only the genuine macOS lock UI and macOS performs authentication. Otherwise it receives `lockedInteractionUnavailable`.
- Video and input bytes, frames, text, and key events do not enter audit, diagnostics, crash metadata, or support bundles.
- The alpha meets the initial LAN budgets in the Interactive Control specification or records an ADR changing them from measured evidence.
- Five testers can start, identify, use, end, suspend, and revoke a session without assistance or confusion with Standard Control.
- Five testers can move among Desktop, App Focus, Window Focus, and Smart Zoom, recover from fallback, override the interaction profile, and complete focused tasks with less pinch-and-pan than Desktop-only control.

### Exit gate

Proceed only when the capture/input process boundary, visible-indicator dependency, authorization fencing, Remote Surface revisions and fallback, privacy rules, and lock transition are deterministic on physical devices. The managed entitlement must be approved or Apple must confirm a public alternative before an external Interactive Control beta.

## Stage 3: no-relay three-path beta

### Scope

- Saved user-managed Tailscale MagicDNS, private DNS, IPv4, and IPv6 endpoints with no Mac Companion relay, rendezvous account, port forwarding, or embedded VPN credentials
- Guided Tailscale setup and provider-neutral connectivity diagnostics that distinguish route, reachability, authentication, permission, lock, and sleep failures
- One evidence-backed desired-state action, beginning with `setAudioMuted`
- Durable operation records, bounded idempotency, approval when effects require it, progress, cancellation, terminal results, and `outcomeUnknown`
- Interactive Control over the selected private route with adaptive frame rate, resolution, and bitrate
- App Focus, Window Focus, Smart Zoom, and surface-adaptive interaction over that route with explicit fallback and mode indication
- Observe and Act tasks that complete without starting or maintaining a screen stream
- Smart Input only if its secure-field, focus-race, Unicode, input-method, compatibility, and content-free-diagnostics experiment gate passes
- One Mac and one phone remain the supported UX; identifiers and storage preserve future many-to-many expansion

### Product evidence

- A 10–20 person calibration TestFlight cohort attempts self-initiated real-world uses over two weeks. Before reviewing its repeat-use results, record a dated ADR with the confirmatory cohort thresholds; the calibration cohort alone cannot establish the market-facing MVP.
- A separate confirmatory cohort passes the preregistered thresholds. The initial targets are: at least 80% of eligible testers complete clean-install pairing without developer intervention, at least 60% of activated testers complete a real job on three distinct days within 14 days, at least five testers repeat a Control job, and at least three testers repeat an Observe or Act job. No individual user is required to use all three paths.
- Testers can explain the difference between paired, connected, viewing, controlling, and approval-required.
- Testers can distinguish Desktop, App Focus, Window Focus, Smart Zoom, interaction-profile overrides, visual fallback, and Smart Input when enabled without assuming that every app has a native iPhone interface.
- Consented, user-exported study logs plus optional diaries or surveys show no recurring confusion between unreachable, stale, locked, and sleeping; centralized telemetry is not assumed.
- No input reaches an unintended surface or field because of a stale application, window, coordinate, focus, or authorization revision.
- If Control sessions spend overwhelmingly most of their time in Desktop and users avoid App Focus, Window Focus, and Smart Zoom, treat adaptive differentiation as unproven. If Observe and Act see little use, simplify those paths rather than making them mandatory ceremony.

### Exit gate

Call the result a market-facing MVP only when a signed, installable external Stage 3 beta passes both security gates and repeat-use evidence, no-relay onboarding succeeds without developer intervention, and users understand Observe, Act, and Control as independent paths with distinct permissions. Control must be easy to enter directly without making screen capture mandatory for other tasks. Feature completeness alone is insufficient.

## Stage 4: MacTools differentiation and provider contract

### Scope

- Ship a narrow authenticated MacTools host/Core bridge before a general provider SDK.
- Add explicit `remoteExposurePolicy` metadata with a deny-by-default migration for every MacTools action.
- Preserve MacTools as final authority for availability, run policy, concurrency, execution revision, cancellation, timeout, and result.
- Translate only the bounded schema subset; unsupported actions remain unavailable.
- Handle MacTools quit, upgrade, generation change, and unavailable capability without affecting native or Interactive Control surfaces.
- Evaluate a narrow MacTools action-card or provider-native Remote Surface only after the action bridge is stable; it cannot be required for the provider-contract exit gate.
- Extract the proven bridge into a versioned provider SDK and manifest only after the MacTools contract stabilizes.
- Add provider authentication, generation, health, quotas, schema validation, redaction, and conformance tests.
- Evaluate explicit adapters for MCP, Shortcuts/App Intents, Home Assistant, and selected command-line tools.
- Require per-capability remote exposure and effect review for every adapter.

### Exit criteria

- A third-party provider cannot reduce host policy, escape schema bounds, impersonate another provider, or expose a capability implicitly.
- Provider installation, upgrade, disappearance, and removal have deterministic registry and audit behavior.
- At least one non-MacTools provider solves a validated user job without broadening the core protocol.

## Stage 5: verified semantic and provider-native surfaces

After the market-MVP gate, evaluate native iOS presentations that are more useful than an adaptive visual surface or a bounded capability.

### Scope

- Add a confidence-rated Accessibility semantic overlay for a small reviewed role set such as button, toggle, slider, tab, and list row.
- Bind every node to ephemeral application, surface, semantic, coordinate, and authorization revisions and revalidate it before invocation.
- Keep custom-drawn, ambiguous, secure, destructive, credential, communication, purchase, permission, and Mac Companion administration controls visual-only unless a separate capability explicitly authorizes them.
- Define a bounded provider-native Remote Surface schema with no executable UI, arbitrary web content, direct media access, or implicit remote exposure.
- Prove one app-specific surface for a repeated user job, using MacTools only if the validated job calls for it.
- Support Dynamic Type, VoiceOver, Switch Control, large touch targets, and a visible assisted-visual fallback.

### Exit criteria

- Native controls never survive provider, application, element, focus, or semantic revision change.
- Users can distinguish verified semantic, assisted visual, and visual-only presentation.
- Unknown or contradictory metadata fails back to pixels rather than producing a guessed action.
- Secure or private values do not enter durable logs or an unrelated provider boundary.
- Product evidence shows the native surface completes a repeated job materially better than App Focus or a bounded action.

## Stage 6: additional administrator capabilities

After the MVP proves demand, evaluate shell, file access, clipboard synchronization, audio, multi-display composition, headless support, and wake or pre-login components as separate workstreams and separately grantable advanced capabilities. Each receives its own `pass`, `no-go`, or `deferred` disposition; one blocker cannot hold the others open. Mac Companion cannot semantically validate or make arbitrary commands, file operations, or clipboard contents safe.

### Enablement and containment

- Each administrator capability is enabled locally on the Mac for one named paired device. It cannot be enabled, renewed after expiry, or broadened solely from the remote device.
- The Mac presents a short concrete risk summary covering screen contents, input injection, commands, files, credentials, communications, and destructive actions. Acceptance is specific and recorded; it is not bundled into ordinary terms or pairing.
- Shell, files, clipboard, audio, and other capabilities are independent grants and never an unbounded wildcard over future providers.
- Session-scoped access is the default. Remembered access, if product evidence requires it, receives a second local confirmation, periodic review, and immediate suspension and revocation controls.
- Starting broad control requires fresh proof from the paired device and policy-selected user presence. Key or biometric enrollment changes, device revocation, permission reduction, or host-owner change terminate or suspend it.
- A persistent, non-provider-controlled local indicator shows the controlling device and active capabilities. Closing settings cannot hide it. A local kill switch suspends the device without needing the remote client.
- Each capability uses an explicit protocol and isolated execution boundary. A defect or grant in Interactive Control does not silently authorize another capability.
- Audit records session start, stop, device, capabilities, route, authorization changes, and outcome. Raw terminal input, screen contents, clipboard data, and file contents are not retained by default because the audit log would become a second sensitive-data store.
- Initial testing remains on a private route with no vendor relay. App Store viability, TCC ownership, input and screen APIs, shell and file semantics, bandwidth, accessibility, and support burden receive new Stage 0-style spikes.

### Exit criteria

- Testers can accurately explain what each advanced grant allows, distinguish it from Standard and Interactive Control, identify the active indicator, and suspend or revoke access without assistance.
- A stolen paired device, malicious client, crashed indicator, user switch, screen lock, route change, or worker crash produces the documented visible and fail-closed behavior.
- An independent security review has no unresolved critical findings in the advanced session protocol, isolation boundary, enablement flow, or updater.
- Product evidence shows that broad control solves a repeated job better than adding another bounded capability; implementation breadth alone is not sufficient.

## Stage 7: assisted operation

Potential work includes visual workflows and AI-assisted planning. AI planning remains separate from both semantic permissions and Interactive Control.

Before any AI feature can request execution:

- The model operates as an untrusted planner.
- Plans are converted into known capability requests.
- Existing schema, policy, approval, idempotency, provider, and audit checks remain authoritative.
- Remote content and provider text are treated as untrusted input.
- Prompt-injection and confused-deputy tests are part of the security gate.

An AI feature cannot silently obtain or drive an Interactive Control, Remote Surface, or administrator-capability session. That requires a separate, explicit product and threat-model decision. No Stage 5, Stage 6, or Stage 7 promise is needed to validate the earlier product.

### Exit criteria

- One validated assisted-operation job has a written user outcome and performs materially better than the non-AI workflow, or Stage 7 receives an evidence-backed `no-go` or `deferred` disposition.
- The planner cannot expand grants, bypass user presence, call unregistered capabilities, or convert visual content into authority.
- Prompt-injection, malicious-provider, stale-plan, replay, cancellation, revocation, and partial-execution tests pass against the same policy and durable-operation boundaries as direct requests.
- Every model, data flow, retention rule, disclosure, cost boundary, offline/unavailable state, and distribution dependency is documented before external testing.

## Cross-stage quality gates

### Security

- No reusable secret appears in QR payload logs, audit output, crash reports, or client presentation.
- Revocation and permission reductions are active, not eventual administrative metadata.
- New capabilities and new effect dimensions fail closed.
- Protocol and provider inputs pass fuzz, size, rate, and malformed-data tests.
- Pairing never implies control, Standard Control never implies Interactive Control, and no provider or remote request can elevate its own tier.
- Remote Surface presentation never implies a new capability grant, and a surface or focus revision cannot outlive its Interactive Control authorization epoch.
- Consent for advanced control is informed, device-specific, locally granted, inspectable, visible while active, and immediately suspendable. Consent acknowledges residual risk; it does not replace authentication, secure defaults, containment, or honest failure behavior.

### Reliability

- Every displayed value includes a freshness model.
- Every operation has a durable identity and bounded retention behavior.
- Crash recovery never reports a stronger outcome than the stored evidence permits.
- Service, UI, provider, and network restarts are covered by deterministic tests.
- Mixed component versions and database migrations either preserve the documented security semantics or refuse operation with a recoverable explanation.

### Privacy

- Status fields have a documented user value, collection method, retention, and redaction policy.
- Privacy manifests and required-reason declarations are checked in release builds.
- Public IP, process lists, screenshots, and provider-private data require separate review. Transient application/window/focus metadata is permitted only by the Adaptive Remote Surface allowlist during an active session and is never durable audit data.

### Performance budgets

Exact numbers are set during Stage 0A and measured continuously. At minimum track:

- Idle and active CPU and energy use
- Resident memory for service and UI
- Network bytes at idle and while viewing
- Snapshot and event latency
- Surface switch, focus-to-zoom, fallback, and text-session termination latency
- Reconnect and pairing time
- Audit and operation-store growth
- Battery impact on iPhone and portable Macs

### Release discipline

- Automated compatibility tests cover the oldest supported OS versions and at least one current beta before major OS releases.
- Protocol golden fixtures run in both Mac and iOS builds.
- Security-sensitive dependency and platform changes trigger focused threat-model review.
- User-visible lifecycle limitations remain in onboarding and settings, not only engineering documentation.
- Release signing, update metadata, signer rotation, downgrade resistance, rollback, compromised-release recovery, and complete uninstall are tested with release-shaped artifacts.

## Success definition

The technical alpha succeeds when Mac Companion can establish, display, revoke, and audit a trustworthy foreground session and a visible local Interactive Control session, move safely among Desktop, App Focus, Window Focus, and Smart Zoom with appropriate interaction profiles, and fall back without misleading the user about host or focus state.

The differentiated beta succeeds when users repeatedly rely on Mac Companion for real jobs, choose appropriately among Observe, Act, and Control, and understand the security and activity model. Success does not require every user or session to use every path.

Only then should Mac Companion invest in MacTools breadth, a general provider ecosystem, background delivery infrastructure, additional administrator capabilities, or AI planning. Interactive Control is part of the MVP, but shell, files, clipboard, audio, and autonomous operation do not inherit its grant or security conclusions.

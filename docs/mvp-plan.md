# Mac Companion Staged Validation Plan

## Objective

Validate the riskiest platform, security, and product assumptions before expanding Mac Companion into a broad remote-control platform.

The plan distinguishes a technical alpha—proof that the secure lifecycle works—from a differentiated beta—proof that people repeatedly use Mac Companion for real operational jobs.

Mac Companion validates three connected experiences: **Observe** current Mac state, **Act** through bounded semantic operations, and **Intervene** through an explicitly granted live screen, mouse, and keyboard session. Interactive Control is part of the MVP path because it supplies broad fallback reach, but it is not the default screen and does not include a shell, arbitrary files, clipboard, audio, or autonomous control. It must never be implied by ordinary pairing, `Standard Control`, a provider installation, or a broad “allow future capabilities” switch.

## Stage -1: name and product evidence

### Work

- Use **Mac Companion** as the working product and iPhone/iPad app name, **Mac Companion Agent** for the installed Mac component, and **Monitor and control your Mac** as the proposed App Store subtitle.
- Complete written trademark review and reserve the App Store name before permanent bundle identifiers, domains, paid identity work, or public launch.
- Build a task-level competitor matrix for Helm, CommandDeck, Shellcove, screen sharing, SSH, and adjacent remote-access products. Compare setup, remote reachability, supported jobs, authorization granularity, activity visibility, auditability, and extensibility.
- Use owners of logged-in personal Macs who want private, no-relay remote operation as the beachhead hypothesis; interview MacTools users and multiple-Mac owners as subsegments rather than separate products.
- Interview at least five people in the selected subsegment. Record the repeated job, frequency, current workaround, failure cost, and where a dashboard, semantic action, or Interactive Control is preferable.
- Measure the current workaround's completion time, error rate, setup burden, and help required, then set the minimum improvement that would justify switching.
- Test the “secure operations console,” “remote control,” and “monitoring dashboard” positions using the selected job rather than abstract feature descriptions.
- Write an ADR selecting one adoption-driving segment, one repeated job, and the smallest control model that can solve it.

### Exit criteria

- No unresolved high-risk naming conflict in target markets; Mac Companion remains a working name until the evidence above is complete.
- At least three independent people in the same selected segment report the same repeated remote job and a credible reason to replace or supplement the current workaround.
- The initial audience, job, frequency, current workaround, and value hypothesis can be stated without depending on future AI or provider breadth.
- The first implementation slice is selected from evidence. The three native actions remain protocol fixtures unless the selected job validates them as product features.

## Stage 0A: constraint spikes and architecture decisions

This stage produces small harnesses and decision records, not a polished app.

### Platform and distribution

- Initialize version control and CI before production scaffolding; release-shaped artifacts and security fixtures must be reproducible from a recorded revision.
- Use the current stable macOS 26 and iOS/iPadOS 26 lines as the initial deployment target and stable Xcode 26.6 with Swift 6.3; test macOS and iOS 27 betas without making beta software a release dependency.
- Select and spike the initial deployment topology: Developer ID distribution, an embedded `SMAppService` LaunchAgent, authenticated XPC/Mach IPC, and the process and bundle boundaries for the menu app, service, CLI, protocol library, and MacTools bridge.
- Validate code signing, hardened runtime, notarization, login-item registration, update, rollback, uninstall, and authenticated local IPC using release-shaped artifacts.
- Decide whether a Mac App Store build is viable only after testing sandbox, listener entitlement, LaunchAgent, update, and provider-bridge constraints.
- Prove the per-user LaunchAgent lifecycle through app quit, service crash, screen lock, fast user switching, logout, sleep, wake, and login-item disablement.
- Write an ADR for one configured macOS account as the initial host owner. Define lock versus fast-user-switch behavior and fail closed when the active console owner cannot be established.
- Write an ADR for activity visibility. Closing settings must not quit the menu-bar indicator while the service is enabled; define automatic restoration and degraded/fail-closed behavior if the indicator process crashes.
- Submit the Persistent Content Capture managed-entitlement request through the Jenny Media LLC Account Holder and record approval status as an Interactive Control dependency.
- Spike the persistent menu app as the owner of ScreenCaptureKit, VideoToolbox, Accessibility trust, and `CGEvent` input while the LaunchAgent remains the network and policy authority.
- Prove capture and input across unlocked, locked, display-sleep, display-change, menu-app crash, fast-user-switch, logout, and permission-revocation transitions. Lock-screen success means showing and operating only the genuine macOS lock surface.
- Add a permission matrix mapping each capability to its executing process, entitlement or TCC service, allowed session states, onboarding owner, and revocation behavior.
- Record SSH as excluded from runtime capability transport. A later SSH-assisted installer may deploy the same signed package, but may not retain SSH credentials or bypass pairing, policy, audit, and visibility.

### Networking and identity

- Exercise Local Network permission grant, denial, later recovery, and Bonjour discovery using one declared service type.
- Choose the default listener interfaces and re-evaluation behavior for Wi-Fi, Ethernet, VPN, Tailscale, and public-network transitions.
- Select exact TLS 1.3 transport, channel framing, bounded message encoding, and canonicalization. Prefer the smallest implementation that satisfies the measured lifecycle; document why if choosing QUIC or HTTP/2 over TLS/TCP.
- Prove host certificate pinning across Bonjour, direct private IP, and Tailscale endpoint changes.
- Prototype the session key and separate Secure Enclave-backed user-presence approval key.
- Document key loss, phone replacement, host migration, revocation, and re-pairing.

### Data and actions

- Verify every native status field on supported hardware, locked sessions, missing sensors, and permission-denied states.
- Inventory required-reason API and privacy-manifest obligations, including system uptime.
- Spike `setAudioMuted`, `setAppearance`, and bounded keep-awake start/stop as desired-state actions.
- Spike a narrow authenticated MacTools host/Core bridge. Do not assume the existing plugin API can enumerate or execute other providers' actions.
- Design an explicit per-action MacTools remote manifest and map action, policy, provider generation, progress, cancellation, validation, effect, result, and error models. Default every action to unavailable remotely until reviewed.
- Select Keychain policy for private keys and a service-owned SQLite model for devices, grants, authorization epochs, replay windows, operations, and audit.
- Define schema migration, rollback compatibility, transaction boundaries, quotas, and disk-full behavior before implementing pairing or control.
- Establish the test harness architecture: injectable clock, randomness, storage, network, session state, and provider boundaries; golden fixtures; fuzz targets; crash hooks; and a fake provider.

### Exit criteria

- Every decision above has a recorded result, rejected alternatives, and remaining risk.
- Harnesses demonstrate the selected lifecycle and pinned connection on physical Macs and iPhones.
- The team can name which claims are supported by public APIs and which remain conservative approximations.
- No Stage 1 requirement depends on an unresolved entitlement or background-execution assumption.
- Target, signing, IPC, TCC, data ownership, update order, and component compatibility are concrete enough to scaffold without later changing the security boundary.

## Stage 0B: executable mini-RFC and threat model

### Specification work

- Freeze the first wire envelope, canonicalization method, size limits, timeouts, and version negotiation.
- Specify a normative authenticated handshake: algorithms, certificate construction, QR-pinned host-key binding, fresh server challenge, client proof bound to the live TLS channel and protocol version, key confirmation, rotation, recovery, resumption, and a no-0-RTT rule for authentication or state changes.
- Specify race-safe pairing using either a high-entropy one-time QR secret bound to the complete transcript or a short authentication string derived from both device keys, host identity, pairing ID, and transcript and compared on both devices. Pairing-session consumption is atomic and durable.
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
- Publish binary header, H.264 format, coordinate-transform, pointer, keyboard, session-transition, and key-release fixtures shared by the Mac and iOS implementations.

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
- Open protocol questions are explicitly deferred and cannot silently change security semantics.
- Pairing, privilege elevation, and consequential control fail closed when their required durable security record cannot be committed; revocation remains available under degraded storage.

## Stage 1: local view-only technical alpha

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

Public IP lookup, top-process lists, application/window names, screenshots, control actions, and third-party providers are out of scope.

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

## Stage 2: local Interactive Control alpha

### Scope

- One Mac and one paired iPhone or iPad on the local network
- A separate, device-specific Interactive Control grant with fresh phone user presence at session start
- One selected display streamed with the H.264 baseline profile
- Absolute pointer movement, click, drag, bounded scroll, physical-key, modifier, and bounded text input
- Persistent menu-bar indication identifying the controlling device and a local suspend control
- Agent-enforced session creation, expiry, authorization epoch, channel credentials, rate limits, and audit metadata
- Menu-app-owned ScreenCaptureKit, VideoToolbox, and Accessibility-mediated input over authenticated local IPC
- Explicit unlocked, locked, locked-interaction-unavailable, suspended, revoked, ended, and host-unavailable states

Tailscale, many-to-many UX, semantic control actions, MacTools, shell, files, clipboard, audio, multi-display composition, wake-from-sleep, headless operation, and pre-login access remain out of scope.

### Verification

- Revocation, suspension, menu-app loss, permission loss, logout, user switch, and authorization-epoch change stop capture and input and invalidate unused channel credentials.
- Disconnect releases every remotely pressed key and pointer button without inventing a click or key repeat.
- Display and scale changes create a new coordinate-space revision; stale input is rejected rather than applied to the wrong location.
- The host never transmits a pre-lock desktop frame after reporting `userSessionLocked`.
- If public APIs support lock-surface interaction, the client sees only the genuine macOS lock UI and macOS performs authentication. Otherwise it receives `lockedInteractionUnavailable`.
- Video and input bytes, frames, text, and key events do not enter audit, diagnostics, crash metadata, or support bundles.
- The alpha meets the initial LAN budgets in the Interactive Control specification or records an ADR changing them from measured evidence.
- Five testers can start, identify, use, end, suspend, and revoke a session without assistance or confusion with Standard Control.

### Exit gate

Proceed only when the capture/input process boundary, visible-indicator dependency, authorization fencing, privacy rules, and lock transition are deterministic on physical devices. The managed entitlement must be approved or Apple must confirm a public alternative before an external Interactive Control beta.

## Stage 3: no-relay private operations beta

### Scope

- Saved user-managed Tailscale MagicDNS, private DNS, IPv4, and IPv6 endpoints with no Mac Companion relay, rendezvous account, port forwarding, or embedded VPN credentials
- Guided Tailscale setup and provider-neutral connectivity diagnostics that distinguish route, reachability, authentication, permission, lock, and sleep failures
- One evidence-backed desired-state action; use `setAudioMuted` as the fallback fixture
- Durable operation records, bounded idempotency, approval when effects require it, progress, cancellation, terminal results, and `outcomeUnknown`
- Interactive Control over the selected private route with adaptive frame rate, resolution, and bitrate
- One Mac and one phone remain the supported UX; identifiers and storage preserve future many-to-many expansion

### Product evidence

- At least four of five pilot users complete self-initiated real-world uses on three separate days within two weeks.
- At least three repeatedly use the Observe, Act, or Intervene path for the validated job and prefer it to the workaround measured in Stage -1.
- Testers can explain the difference between paired, connected, viewing, controlling, and approval-required.
- Consented study-log exports plus tester diaries and interviews show no recurring confusion between unreachable, stale, locked, and sleeping; centralized telemetry is not assumed.
- The validated workflow meets the Stage -1 improvement target for completion time, error rate, or setup burden.
- Pause or pivot if fewer than three testers independently repeat and prefer the selected job.

### Exit gate

Call the result a market-facing MVP only when both security gates and repeat-use evidence pass, no-relay onboarding succeeds without developer intervention, and Interactive Control is understood as an escalation from the dashboard rather than the entire product. Feature completeness alone is insufficient.

## Stage 4: MacTools differentiation and provider contract

### Scope

- Ship a narrow authenticated MacTools host/Core bridge before a general provider SDK.
- Add explicit `remoteExposurePolicy` metadata with a deny-by-default migration for every MacTools action.
- Preserve MacTools as final authority for availability, run policy, concurrency, execution revision, cancellation, timeout, and result.
- Translate only the bounded schema subset; unsupported actions remain unavailable.
- Handle MacTools quit, upgrade, generation change, and unavailable capability without affecting native or Interactive Control surfaces.
- Extract the proven bridge into a versioned provider SDK and manifest only after the MacTools contract stabilizes.
- Add provider authentication, generation, health, quotas, schema validation, redaction, and conformance tests.
- Evaluate explicit adapters for MCP, Shortcuts/App Intents, Home Assistant, and selected command-line tools.
- Require per-capability remote exposure and effect review for every adapter.

### Exit criteria

- A third-party provider cannot reduce host policy, escape schema bounds, impersonate another provider, or expose a capability implicitly.
- Provider installation, upgrade, disappearance, and removal have deterministic registry and audit behavior.
- At least one non-MacTools provider solves a validated user job without broadening the core protocol.

## Stage 5: additional administrator surfaces

After the MVP proves demand, evaluate shell, file access, clipboard synchronization, audio, multi-display composition, headless support, and wake or pre-login components as separately grantable advanced surfaces. Mac Companion cannot semantically validate or make arbitrary commands, file operations, or clipboard contents safe.

### Enablement and containment

- Each administrator surface is enabled locally on the Mac for one named paired device. It cannot be enabled, renewed after expiry, or broadened solely from the remote device.
- The Mac presents a short concrete risk summary covering screen contents, input injection, commands, files, credentials, communications, and destructive actions. Acceptance is specific and recorded; it is not bundled into ordinary terms or pairing.
- Shell, files, clipboard, audio, and other surfaces are independent grants and never an unbounded wildcard over future providers.
- Session-scoped access is the default. Remembered access, if product evidence requires it, receives a second local confirmation, periodic review, and immediate suspension and revocation controls.
- Starting broad control requires fresh proof from the paired device and policy-selected user presence. Key or biometric enrollment changes, device revocation, permission reduction, or host-owner change terminate or suspend it.
- A persistent, non-provider-controlled local indicator shows the controlling device and active surfaces. Closing settings cannot hide it. A local kill switch suspends the device without needing the remote client.
- Each surface uses an explicit protocol and isolated execution boundary. A defect or grant in Interactive Control does not silently authorize another surface.
- Audit records session start, stop, device, surfaces, route, authorization changes, and outcome. Raw terminal input, screen contents, clipboard data, and file contents are not retained by default because the audit log would become a second sensitive-data store.
- Initial testing remains on a private route with no vendor relay. App Store viability, TCC ownership, input and screen APIs, shell and file semantics, bandwidth, accessibility, and support burden receive new Stage 0-style spikes.

### Exit criteria

- Testers can accurately explain what each advanced grant allows, distinguish it from Standard and Interactive Control, identify the active indicator, and suspend or revoke access without assistance.
- A stolen paired device, malicious client, crashed indicator, user switch, screen lock, route change, or worker crash produces the documented visible and fail-closed behavior.
- An independent security review has no unresolved critical findings in the advanced session protocol, isolation boundary, enablement flow, or updater.
- Product evidence shows that broad control solves a repeated job better than adding another bounded capability; implementation breadth alone is not sufficient.

## Stage 6: assisted operation

Potential work includes visual workflows and AI-assisted planning. AI planning remains separate from both semantic permissions and Interactive Control.

Before any AI feature can request execution:

- The model operates as an untrusted planner.
- Plans are converted into known capability requests.
- Existing schema, policy, approval, idempotency, provider, and audit checks remain authoritative.
- Remote content and provider text are treated as untrusted input.
- Prompt-injection and confused-deputy tests are part of the security gate.

An AI feature cannot silently obtain or drive an Interactive Control or administrator-surface session. That requires a separate, explicit product and threat-model decision. No Stage 5 or Stage 6 promise is needed to validate the earlier product.

## Cross-stage quality gates

### Security

- No reusable secret appears in QR payload logs, audit output, crash reports, or client presentation.
- Revocation and permission reductions are active, not eventual administrative metadata.
- New capabilities and new effect dimensions fail closed.
- Protocol and provider inputs pass fuzz, size, rate, and malformed-data tests.
- Pairing never implies control, Standard Control never implies Interactive Control, and no provider or remote request can elevate its own tier.
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
- Public IP, application names, process lists, screenshots, and provider-private data require separate review.

### Performance budgets

Exact numbers are set during Stage 0A and measured continuously. At minimum track:

- Idle and active CPU and energy use
- Resident memory for service and UI
- Network bytes at idle and while viewing
- Snapshot and event latency
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

The technical alpha succeeds when Mac Companion can establish, display, revoke, and audit a trustworthy foreground session and a visible local Interactive Control session without misleading the user about host state.

The differentiated beta succeeds when users repeatedly rely on the selected Mac job, choose appropriately among Observe, Act, and Intervene, and understand the security and activity model.

Only then should Mac Companion invest in MacTools breadth, a general provider ecosystem, background delivery infrastructure, additional administrator surfaces, or AI planning. Interactive Control is part of the MVP, but shell, files, clipboard, audio, and autonomous operation do not inherit its grant or security conclusions.

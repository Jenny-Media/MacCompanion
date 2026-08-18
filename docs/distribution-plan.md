# Mac Companion Distribution and Release Plan

Status: release baseline for the first implementation. This document fixes the intended channels, signing boundary, update model, and release gates; it does not create a release system.

## 1. Decisions

- The Mac product is distributed directly by Jenny Media LLC, outside the Mac App Store.
- Every Mac executable is signed with Developer ID, uses the hardened runtime, is notarized, and ships in one app bundle.
- The initial Mac installer experience is a notarized DMG containing `Mac Companion.app`; no root installer or separately copied daemon is required.
- The embedded per-user LaunchAgent is registered through `SMAppService` after the user opens and enables the app.
- Mac updates use Sparkle 2 with HTTPS, Ed25519 archive signatures, Developer ID validation, and notarized replacement bundles.
- The iPhone and iPad app uses TestFlight for alpha and beta, then the App Store for release.
- The initial deployment targets are macOS 26.0 and iOS/iPadOS 26.0. Release builds use stable Xcode 26.6 and Swift 6.3; Xcode and OS 27 betas are compatibility targets, not release dependencies.
- Mac Companion operates no account, relay, rendezvous, VPN, analytics, or update proxy. The download site and signed update feed are the only vendor-hosted runtime-adjacent services.

Apple describes Developer ID and notarization for software distributed outside the Mac App Store in [Signing Mac software with Developer ID](https://developer.apple.com/developer-id/) and [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). The toolchain baseline is recorded in [Xcode 26.6 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_6-release-notes).

## 2. Identifier and account preflight

The following values must be confirmed in the Jenny Media LLC Apple Developer account before the Xcode project is created:

- Legal team name: Jenny Media LLC
- Team ID
- Reverse-DNS bundle prefix controlled by the company
- Developer ID Application certificate availability and custody
- Apple Development and Apple Distribution certificate strategy
- App Store Connect access and agreements
- Final macOS App ID to use for the Persistent Content Capture request

Until the prefix is confirmed, documentation uses these placeholders:

| Target | Planned identifier |
| --- | --- |
| macOS containing app and menu UI | `<bundle-prefix>.maccompanion` |
| Embedded per-user agent | `<bundle-prefix>.maccompanion.agent` |
| Local XPC services, if selected | `<bundle-prefix>.maccompanion.xpc.<role>` |
| iOS/iPadOS app | `<bundle-prefix>.maccompanion.ios` |

The prefix is a pre-scaffold decision because bundle IDs become part of Keychain access, designated requirements, LaunchAgent identity, update configuration, managed-entitlement approval, audit migrations, and App Store records. Renaming them later is not treated as a cosmetic change.

The Persistent Content Capture entitlement is managed. Apple says it enables VNC apps to view and record the screen and requires a request before use; see [Persistent Content Capture](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.persistent-content-capture). The Jenny Media LLC Account Holder should submit the request against the final Mac App ID as soon as the identifier exists. Stage 1 monitoring can proceed while it is pending; an external Interactive Control build cannot.

## 3. Shipped component boundary

`Mac Companion.app` contains and signs as one release unit:

- Persistent menu-bar app and settings UI
- Embedded per-user LaunchAgent executable
- Authenticated local IPC services selected in Stage 0
- Shared protocol and domain libraries
- Diagnostic CLI, if retained, as a signed bundle resource rather than a root-installed binary
- Sparkle framework and only its required services

The first release does not install a privileged helper, system daemon, kernel extension, system extension, packet tunnel, SSH key, or file under `/usr/local`. MacTools remains a separate application; a future bridge authenticates its installed identity and is not copied into its bundle.

All embedded code is signed before the outer app. The outer app is then signed once, verified recursively without relying on an unsafe blanket deep-signing repair, notarized, stapled, and tested from the exact downloaded artifact.

## 4. Capability, entitlement, and privacy ownership

The Stage 0 permission matrix must confirm the final target ownership. The baseline is:

| Capability | Executing target | Release requirement | User-facing behavior |
| --- | --- | --- | --- |
| Persistent display capture | Menu app | Managed Persistent Content Capture entitlement, provisioning profile, usage description, Screen Recording consent | Explain before the system prompt; show readiness and recovery in settings. |
| Mouse and keyboard injection | Menu app | Accessibility trust; no attempt to bypass TCC | Explain exact control, deep-link to System Settings where supported, and recheck after revocation. |
| Private-network listener | LaunchAgent | Minimal network entitlement only if the selected sandbox requires it | Bind to selected private interfaces; never make discovery equal trust. |
| Bonjour discovery | LaunchAgent and iOS app | One declared Bonjour service type and applicable Local Network usage descriptions | Explain local discovery and provide denial recovery. |
| Device and approval keys | iOS app | Keychain and Secure Enclave access-control configuration | Pairing identity and fresh approval identity remain separate. |
| Host identity and grants | LaunchAgent | Keychain access and service-owned protected database | Menu app receives bounded views over authenticated IPC, not direct database access. |
| Login item | Containing Mac app | Embedded, signed `SMAppService` registration | User enables the agent explicitly and can disable it from both Mac Companion and System Settings. |
| Automatic updates | Menu app | Sparkle public Ed25519 key, HTTPS appcast, signed update archives | Never replace the app during an active control session without explicit termination. |

TCC grants belong to the code identity that performs the protected action. Stage 0 must verify attribution on clean machines; it must not move capture or input into the network agent merely to simplify prompts.

The first direct Mac build is not App Sandbox-enabled unless the Stage 0 lifecycle spike proves that sandboxing does not break the listener, IPC, updater, capture, input, or MacTools boundary. Hardened Runtime remains mandatory either way, and each exception requires a written reason.

## 5. Mac installation and onboarding

The clean-user path is:

1. Download the HTTPS-served, notarized DMG.
2. Drag `Mac Companion.app` to Applications and open it through normal Gatekeeper flow.
3. Verify the application identity and show a short product boundary: private route, no vendor relay, logged-in user required.
4. Ask the user to enable the per-user agent. Verify `SMAppService` state and explain recovery if the login item is disabled.
5. Establish the local authenticated IPC relationship and show agent health.
6. Request Local Network access only when the user starts pairing or discovery.
7. Pair an iPhone or iPad with Monitor Only by default.
8. Request Screen Recording and Accessibility only when the user explicitly enables Interactive Control for a named device.
9. Confirm the visible status item, local suspend action, grants, and uninstall location.

Onboarding never asks for an SSH password, administrator password, Tailscale credentials, Apple ID, or Mac Companion account. Tailscale guidance assumes the user installs and owns Tailscale separately; Mac Companion stores only the private endpoint needed to reach the already-paired host.

## 6. Mac update design

Sparkle's current documentation describes an HTTPS appcast, incrementing bundle versions, Ed25519-signed archives, and Developer ID validation; see [Sparkle documentation](https://sparkle-project.org/documentation/).

### Channels

- `internal`: development-signed and local-team-only artifacts; never offered to customers
- `beta`: notarized Developer ID builds for invited testers, with an explicit pre-release label
- `stable`: notarized public builds promoted only after beta gates pass

Beta and stable use distinct signed appcast URLs. A client never moves to beta without a local choice. Returning from beta to stable is an explicit supported migration, not a version-number trick.

### Trust and key custody

- Appcast and archives are served only over HTTPS.
- Every update archive has a Sparkle Ed25519 signature verified by the public key embedded in the app.
- Every executable retains the expected Jenny Media LLC Developer ID identity and hardened runtime.
- The final artifact is notarized and its ticket is stapled before publication.
- The Sparkle private key and Apple release credentials are stored outside the repository in controlled Keychain or CI secret storage, with documented recovery owners.
- A signer-rotation release changes only one trust anchor at a time and is tested from the oldest supported release.
- Update metadata rejects downgrades unless a separately signed emergency procedure authorizes a known-safe target.

### Compatibility and choreography

Every component publishes application version, protocol range, database schema, and local IPC version. The agent and menu app refuse an unsafe mixed-version control path while preserving a recoverable administration surface.

Before installation the menu app:

1. Stops accepting new Interactive Control and semantic operations.
2. Presents and records the update transition.
3. Ends active Interactive Control, releases input, stops capture, and asks the agent to drain bounded operations.
4. Verifies that durable security state is committed.
5. Allows Sparkle to replace the complete containing app bundle atomically.
6. Relaunches, revalidates the embedded agent identity, and reconciles `SMAppService` registration.
7. Runs forward-only database migration in a transaction and reports any recoverable failure.

The update never swaps an individual agent executable in place. Pairing keys and grants remain in Keychain and service-owned data rather than in the replaceable bundle. A rollback must understand the stored schema or refuse with a clear recovery path; silently reading a newer schema is forbidden.

Automatic download may be offered later. Initial beta installs updates only after local confirmation and never while the Mac is locked or an Interactive Control session is active.

## 7. iPhone and iPad distribution

### Alpha and beta

- Use internal TestFlight for the engineering team and first physical-device matrix.
- Use external TestFlight only after App Review beta information accurately describes the Mac companion requirement, private-network model, Screen Recording use, and absence of a relay.
- Pair TestFlight cohorts with a specific minimum Mac beta version and compatibility range.
- Keep the app foreground-first and avoid background-mode declarations that do not match an Apple-defined use case.

### App Store release

The iOS listing and review notes must state:

- A separately downloaded, signed Mac Companion app is required.
- The user's devices communicate directly over LAN or their own private route.
- Mac Companion does not provide internet reachability, wake, or background alerts.
- Interactive Control requires a logged-in Mac, a local device-specific grant, macOS Screen Recording and Accessibility permissions, and fresh phone user presence.
- Lock-screen operation is described only if the supported public-API matrix proves it.

App privacy answers are derived from actual data flows. No telemetry or account data is declared merely as future intent, and no diagnostics upload occurs without an explicit later design.

## 8. Release pipeline and evidence

The repository will define reproducible, non-secret release commands after Stage 0. The release pipeline must produce and retain:

- Clean build log with exact Xcode and SDK versions
- Test and protocol-fixture results
- Component version and compatibility manifest
- Signed `.app`, update archive, and DMG checksums
- Expanded entitlements and designated requirements for every executable
- `codesign` and Gatekeeper verification results
- Notary submission ID, accepted log, and stapling verification
- Software bill of materials and dependency licenses
- Sparkle appcast entry and signature evidence
- Human release approval, channel, and publication time
- Clean-install, upgrade, rollback, permission-revocation, and complete-uninstall results on physical Macs

A pull request build cannot publish. Stable publication requires a tagged revision, protected release credentials, and a separate promotion approval. CI logs must never print private signing keys, one-time notarization credentials, pairing material, or live provisioning profiles.

## 9. Versioning and compatibility policy

- User-visible app releases use semantic product versions.
- `CFBundleVersion` is monotonically increasing across every distributed build in a channel.
- Protocol major versions are incompatible; minor features negotiate explicitly.
- At least the current stable Mac and iOS client versions interoperate during staged rollout.
- Security revocation can raise the minimum accepted version with an explicit user explanation.
- Provider contracts and database schemas version independently from the app presentation.
- The oldest supported stable release is included in update and migration tests.

The first public support policy targets only macOS 26.x and iOS/iPadOS 26.x. Each annual platform release triggers a decision to advance the minimum or carry one prior major version based on measured support cost and adoption; the project does not promise indefinite backward compatibility.

## 10. Uninstall and recovery

The Mac app provides `Disable and Remove Mac Companion Data` before the user deletes the app. It:

- Suspends access and advances all authorization epochs
- Ends sessions and operations safely
- Unregisters the per-user agent
- Revokes pairings and removes durable grants, audit, operations, saved endpoints, and host keys after confirmation
- Explains which macOS privacy grants may remain visible in System Settings and how to remove them
- Leaves no privileged helper or copied executable because none was installed

Deleting only the app is detected as an incomplete uninstall case in testing. Documentation provides a signed, non-destructive recovery route for a stale login-item registration. Reinstall does not silently inherit remote authorization unless protected retained state and product policy explicitly support recovery.

## 11. Go/no-go gates

### Ready to scaffold

- Team ID and reverse-DNS prefix are confirmed.
- Final target identifiers are registered.
- Developer ID certificate custody is verified.
- Persistent Content Capture request is submitted.
- Stable Xcode 26.6 is installed and recorded.
- The process, entitlement, TCC, and update ownership in this document has no unresolved boundary change.

### Ready for external Mac alpha

- Developer ID signing, hardened runtime, notarization, stapling, Gatekeeper, DMG, Sparkle, and clean uninstall pass on clean physical Macs.
- The agent survives expected lifecycle transitions and cannot outlive local disablement.
- The update path safely drains active work and preserves or refuses database state.
- A revoked or expired signing/provisioning scenario has a documented recovery plan.

### Ready for external Interactive Control beta

- Apple's managed entitlement is approved for the shipped App ID, or a documented public alternative passes equivalent review.
- Screen Recording and Accessibility onboarding and revocation are verified on every supported OS version.
- Locked behavior matches the published contract exactly.
- A security review has no unresolved critical finding in signing, update, local IPC, or Interactive Control.

### Ready for public release

- Mac download and iOS App Store metadata describe the same compatibility and privacy model.
- Beta-to-stable and stable-to-next-stable upgrades pass from the oldest supported version.
- Signing-key owners, rotation, incident response, compromised-release response, and update-feed recovery are assigned.
- A user can install, pair, understand permissions, update, suspend, revoke, and completely uninstall without engineering help.

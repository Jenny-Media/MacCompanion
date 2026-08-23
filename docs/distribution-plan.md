# Mac Companion Distribution and Release Plan

Status: release baseline for the first implementation. This document fixes the intended channels, signing boundary, update model, and release gates; it does not create a release system.

## 1. Decisions

- The Mac product is distributed directly by Jenny Media LLC, outside the Mac App Store.
- Every Mac executable is signed with Developer ID, uses the hardened runtime, is notarized, and ships in one app bundle.
- The initial Mac installer experience is a notarized DMG containing `Mac Companion.app`; no root installer or separately copied daemon is required.
- The embedded per-user LaunchAgent and the containing menu app's login launch are registered through their appropriate `SMAppService` roles after the user opens and enables the app. Stage 0 verifies crash recovery separately from an intentional local Quit and Disable action.
- Mac updates use Sparkle 2 with HTTPS, Ed25519 archive signatures, Developer ID validation, and notarized replacement bundles.
- The iPhone and iPad app uses TestFlight for alpha and beta, then the App Store for release.
- The initial deployment targets are macOS 26.0 and iOS/iPadOS 26.0. Installed Xcode 27 beta may be used for development, compatibility, signing setup, device work, and currently supported TestFlight uploads. Final release evidence is reproduced with stable Xcode 26.6 and Swift 6.3; generation 27 beta remains outside the final release dependency.
- Mac Companion operates no account, relay, rendezvous, VPN, analytics, or update proxy. The download site and signed update feed are the only vendor-hosted runtime-adjacent services.
- Development signing identities may live on the development Mac. Developer ID, App Store distribution, notarization, Sparkle, and promotion credentials remain in a separately controlled release environment.

Apple describes Developer ID and notarization for software distributed outside the Mac App Store in [Signing Mac software with Developer ID](https://developer.apple.com/developer-id/) and [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). The toolchain baseline is recorded in [Xcode 26.6 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_6-release-notes).

## 2. Identifier and account preflight

The following account facts are tracked before permanent release-shaped Apple targets are completed. They do not block the normative specification, pure Swift packages, public unsigned CI, or disposable experiments:

- Legal team name: Jenny Media LLC
- Team ID (confirmed privately)
- Reverse-DNS bundle prefix controlled by the company: `media.jenny` (confirmed)
- Developer ID Application certificate availability and custody
- Apple Development and Apple Distribution certificate strategy
- App Store Connect access and agreements
- Final macOS App ID to use for the Persistent Content Capture request (registered as `media.jenny.maccompanion`)

The confirmed planned identifiers are:

| Target | Planned identifier |
| --- | --- |
| macOS containing app and menu UI | `media.jenny.maccompanion` |
| Embedded per-user agent | `media.jenny.maccompanion.agent` |
| Local XPC services, if selected | `media.jenny.maccompanion.xpc.<role>` |
| iOS/iPadOS app | `media.jenny.maccompanion.ios` |

The Team ID and final containing-app App ID preconditions are resolved. The embedded standalone Agent now has a build-proven reverse-DNS code-signing identifier and LaunchAgent identity without requiring a new portal App ID for this packaging step. Remaining iOS/XPC App IDs, authenticated designated-requirement policy, Keychain groups, update configuration, managed-entitlement approval, audit migrations, and App Store records still need to be bound deliberately. Renaming an official identifier later is not treated as a cosmetic change.

The Persistent Content Capture entitlement is managed. Apple says it enables VNC apps to view and record the screen and requires a request before use; see [Persistent Content Capture](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.persistent-content-capture). The Jenny Media LLC Account Holder prepared the request against `media.jenny.maccompanion`, including the authorization acknowledgement, but Apple's form requires an App Store URL and numeric App Apple ID. Because the directly distributed Mac app is unreleased, the request remains unsent until a truthful prerelease App Store Connect record path is verified or Apple Developer Support confirms the direct-distribution alternative. An Entitlements support case was opened on 2026-08-21 and its Case ID is retained privately. Stage 1 monitoring can proceed; an external persistent Interactive Control build cannot.

### Open-source builds

The intended source license is Apache-2.0 with a separate Mac Companion/Jenny Media trademark policy, both subject to legal review. GitHub private vulnerability reporting is the initial reporting channel; a company security address may later supplement or replace it. Because the remote repository is already public, further pushes and external contributions remain paused until those policies, a full-history review, and provider-side branch/secret/push protections are complete.

Publishing source does not publish Jenny Media's binary identity. Official Mac Companion releases alone use the Jenny Media bundle IDs, managed entitlement, Developer ID identity, notarization records, Sparkle feed, and App Store listing. A fork must choose its own product and bundle identities, request its own Apple capabilities, sign its own binaries, and configure an independent update feed.

The repository may contain public keys, expected designated requirements for official verification, reproducible non-secret build logic, and release evidence formats. It must not contain Developer ID or distribution private keys, provisioning profiles, managed-entitlement profiles, notarization credentials, Sparkle private keys, App Store API keys, or a default configuration that lets an unofficial build consume the official update channel.

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
| Accessibility focus observation | Menu app | Accessibility authorization and a privacy-filtered metadata adapter | Explain focus-assisted framing separately; prove stale-element, secure-field, and revocation behavior. |
| Mouse and keyboard injection | Menu app | Post-event authorization as required by supported macOS; no TCC bypass and no unnecessary Input Monitoring request | Explain exact control, deep-link to System Settings where supported, release all input on loss, and recheck after revocation. |
| System appearance | None in MVP | No Automation entitlement or Apple Events usage description for this rejected action | Do not advertise the three-state action; a future menu-owned light/dark Automation capability requires separate product, permission, and distribution review. |
| Private-network listener | LaunchAgent | Minimal network entitlement only if the selected sandbox requires it | Bind to selected private interfaces; never make discovery equal trust. |
| Bonjour discovery | LaunchAgent and iOS app | One declared Bonjour service type and applicable Local Network usage descriptions | Explain local discovery and provide denial recovery. |
| Pairing-code camera | iOS app | Camera usage description and foreground VisionKit QR scanning | Ask only after explicit Scan; accept one bounded Mac Companion candidate, stop immediately, and keep canonical/expiry verification in the pairing authority. |
| Device and approval keys | iOS app | Keychain and Secure Enclave access-control configuration | Pairing identity and fresh approval identity remain separate. |
| Host identity and grants | LaunchAgent | Keychain access and service-owned protected database | Menu app receives bounded views over authenticated IPC, not direct database access. |
| Agent login item | Containing Mac app | Embedded, signed `SMAppService.agent` registration | User enables the agent explicitly and can disable it from both Mac Companion and System Settings. |
| Visible menu app at login | Containing Mac app | `SMAppService.mainApp` or a Stage 0-proven equivalent | Closing settings preserves the status item; intentional Quit and Disable is distinct from crash recovery. |
| Automatic updates | Menu app | Sparkle public Ed25519 key, HTTPS appcast, signed update archives | Never replace the app during an active control session without explicit termination. |

TCC grants belong to the code identity that performs the protected action. Stage 0 must verify attribution on clean machines; it must not move capture or input into the network agent merely to simplify prompts.

The normative [Apple privacy-manifest profile](../spec/privacy-manifest/v0/profile.md)
owns a separate candidate `PrivacyInfo.xcprivacy` resource for the iOS app,
Mac containing app, and embedded Agent service. The current no-relay,
no-analytics architecture declares no developer collection, tracking, or
tracking domains. The iOS target graph declares no required-reason API use;
macOS-only covered calls remain source-inventoried even though Apple's current
required-reason platform list does not include macOS. A dependency, telemetry,
data-flow, covered-API, executable-topology, or Apple-catalog change requires a
policy review before admission. Permanent targets must copy the indexed
resource into each final executable bundle and retain the built-bundle proof.

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
8. Request Screen Recording, Accessibility observation, and post-event control only when the user explicitly enables the corresponding Interactive Control behavior for a named device; verify each grant and recovery independently.
9. Confirm the visible status item, local suspend action, grants, and uninstall location.

Onboarding never asks for an SSH password, administrator password, Tailscale credentials, Apple ID, or Mac Companion account. Tailscale guidance assumes the user installs and owns Tailscale separately; Mac Companion stores only the private endpoint needed to reach the already-paired host.

## 6. Mac update design

The normative [update trust policy](../spec/update-policy/v0/profile.md) admits
only Sparkle `2.9.6`, pinned to full revision
`ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a`. Current upstream documentation
requires HTTPS, incrementing bundle versions, Ed25519-signed archives, and
Developer ID validation; signed feeds additionally require verification before
archive extraction. The [completed provenance and topology audit](evidence/2026-08-23-sparkle-provenance-and-topology-audit.md)
binds the exact upstream manifest, binary archive, shared license, archive
shape, privacy behavior, and signed-code acquisition graph. The
[exact dependency admission](evidence/2026-08-23-exact-sparkle-dependency-admission.md)
now pins that version and revision in the shared lockfile, disables static
profiling, embeds Sparkle only in the containing app, removes both unused XPC
services from non-sandboxed archives, excludes release tools, and verifies the
retained unsigned topology. The permanent updater adapter must additionally
disable runtime profiling and custom feed parameters; the
[inert adapter checkpoint](evidence/2026-08-23-inert-sparkle-runtime-adapter.md)
now does so while admitting only explicit informational probes behind complete
release-injected authority. Download and installation remain disconnected from
the UI until the runtime installation authority controls one exact handoff.
Signed archive builds must re-sign and inspect every retained nested object. See
[Sparkle documentation](https://sparkle-project.org/documentation/) and the
[2.9.6 release](https://github.com/sparkle-project/Sparkle/releases/tag/2.9.6).

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
3. Refuses installation while Interactive Control is active or cleanup is
   uncertain; after the user stops it, verifies input release and capture stop,
   then asks the Agent to drain bounded operations.
4. Verifies that durable security state is committed.
5. Allows Sparkle to replace the complete containing app bundle atomically.
6. Relaunches, revalidates the embedded agent identity, and reconciles `SMAppService` registration.
7. Runs forward-only database migration in a transaction and reports any recoverable failure.

The update never swaps an individual agent executable in place. Pairing keys and grants remain in Keychain and service-owned data rather than in the replaceable bundle. A rollback must understand the stored schema or refuse with a clear recovery path; silently reading a newer schema is forbidden.

Automatic checks and download may be offered later; the initial beta keeps both
off. Initial beta installs require a fresh
five-minute local foreground confirmation that is cancelled when the menu app
loses foreground state. This prevents a locked Mac from retaining installation
authority without claiming an undocumented exact lock-state API. Installation
also requires Interactive Control to be inactive and unambiguous, network
admission closed, bounded work drained, and the Agent stopped.

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
- Mac Companion is a generic companion for a user-owned Mac: Observe and Act can work without capture, while Control can mirror the full desktop or generically focus an application or window.
- All mirrored software executes and renders on the Mac. The iOS client does not offer a software catalog, remote installation, or a thin client to a hosted cloud Mac.
- Interactive Control requires a logged-in Mac, a local device-specific grant, macOS Screen Recording and Accessibility permissions, and fresh phone user presence.
- Lock-screen operation is described only if the supported public-API matrix proves it.

Before external TestFlight, record an App Review strategy for Guidelines 4.2.3(i) and 4.2.7 plus the system ScreenCaptureKit picker recommendation. The required Mac companion, Observe/Act APIs beyond streaming, and private-route operation are explicit review risks. The first external review build is LAN-first, keeps full Desktop first-class, demonstrates a generic user-owned host mirror before App or Window Focus, supplies the notarized Mac download and complete reviewer pairing resources, and does not imply that Tailscale satisfies a LAN-only interpretation. Review notes explain how the approved Persistent Content Capture entitlement and local Mac consent support remotely initiated surface changes. Existing third-party approvals are market evidence, not a guarantee that Apple will classify Mac Companion the same way.

The candidate-bound metadata, reviewer instructions, attachments, prerequisite
checklist, and rejection decision path live in the [external TestFlight review
package](testflight-review-package.md). It is a prepared draft only; no field is
copied into App Store Connect while a placeholder or readiness item remains.

App privacy answers are derived from actual data flows. Under Apple's
developer-access definition, current real-time peer-to-peer traffic and
on-device records are not developer collection because neither Jenny Media LLC
nor a third party can access them. No telemetry or account data is declared
merely as future intent, and no diagnostics upload occurs without an explicit
later design and a prior privacy-policy/manifest revision.

### Commercialization hypothesis

The no-account, no-relay architecture does not yet justify a recurring subscription. The working hypothesis is a free Mac host and iOS client with one non-consumable **Mac Companion Pro** purchase for convenience and advanced official-client features. Exact pricing, free limits, Family Sharing, and Pro features remain TestFlight experiments rather than release-baseline decisions.

Encryption, device identity, consent, visibility, safe fallback, suspension, revocation, accessibility support, and essential diagnostics are never paywalled. Pairing and host grants do not trust StoreKit state. If a feature is commercialized, the official iOS client checks purchase entitlement when requesting it while the Mac independently enforces authorization and safe hardware, thermal, and bandwidth ceilings. Because the source is intended to be public, commercial value comes from official App Store distribution, Jenny Media signing and entitlements, updates, compatibility work, support, and brand trust rather than pretending that client-side feature gating is an unbreakable security boundary.

## 8. Release pipeline and evidence

Stage 0 defines the reproducible, non-secret build, verification, packaging, and evidence-manifest command skeleton needed by its own release-shaped experiments. Publication credentials and promotion automation are added only after those commands are proven. The release pipeline must produce and retain:

The normative [release evidence v0.1 profile](../spec/release-evidence/v0/profile.md)
and its validator make `unsignedConstruction`, `signedCandidate`, and
`promotionReady` distinct machine-checked claims. A lower claim cannot carry
promotion evidence, and a higher claim cannot omit or placeholder the evidence
listed below. The manifest records references and public verification results;
it never embeds credentials. Every referenced file is path/size/SHA-256 bound,
and a release job uses `--verify-files` against the retained bundle before
promotion. The unsigned generator records the current source and toolchain but
cannot create a signed-candidate or promotion-ready claim.

- Clean build log with exact Xcode and SDK versions
- Test and protocol-fixture results
- Component version and compatibility manifest
- Signed `.app`, update archive, and DMG checksums
- Expanded entitlements and designated requirements for every executable
- Descriptor-bound complete Mach-O/bundle/architecture discovery graph for the
  exact application ZIP and xcarchive, with every Apple verification step
  still explicitly `notRun` until the protected platform lane executes it
- Canonical signing policy whose exact SHA-256 is supplied independently by the
  protected release runner and whose object, slice, signer, requirement,
  third-party, runtime, timestamp, and entitlement rules bind exactly to that
  release, SBOM, and graph
- `codesign` and Gatekeeper verification results
- Notary submission ID, accepted log, and stapling verification
- Software bill of materials and dependency licenses
- Sparkle appcast entry and signature evidence
- Human release approval, channel, and publication time
- Clean-install, upgrade, rollback, permission-revocation, and complete-uninstall results on physical Macs

CI is split into three trust lanes:

- **Public pull request:** unsigned package builds, fixture conformance, dependency-boundary checks, linting, and tests with no Apple or publication secrets.
- **Trusted internal:** development-signed Apple targets and controlled physical-device evidence; artifacts are never promoted automatically.
- **Tagged release:** protected Developer ID/App Store signing, notarization, Sparkle signatures, checksums, the [exact-candidate artifact SBOM](../spec/artifact-sbom/v0/profile.md) derived from the packaged executable-bearing ZIPs, the independently pinned [signing policy](../spec/signing-policy/v0/profile.md), the fixed-tool [platform signing evidence](../spec/platform-signing-evidence/v0/profile.md), the [Mac packaging-equivalence receipt](../spec/mac-packaging-equivalence/v0/profile.md) produced by explicit read-only reinspection of the exact DMG, reviewed license evidence, and an explicit human promotion record. The deterministic source dependency SPDX document is an input, not a substitute for artifact inspection. Promotion revalidates the policy, platform record, receipt, ZIPs, and DMG after platform inspection; schema-only, synthetic, beta-toolchain, or attach-free evidence cannot make a signed-candidate claim.

A pull request build cannot publish. Stable publication requires a tagged revision, protected release credentials, and a separate promotion approval. CI logs must never print private signing keys, one-time notarization credentials, pairing material, or live provisioning profiles.

The local trusted lane begins with an already Developer ID-signed `.xcarchive`.
`scripts/package_mac_release.py` verifies the official app/Agent identity and
runtime facts, produces the canonical app and update ZIPs, creates an APFS/UDZO
DMG with `diskutil image create from`, signs that DMG, and publishes a
no-overwrite local directory. Its summary must retain `notarized`, `stapled`,
`sparkleArchiveSigned`, and `promotionReady` as false. The artifact-SBOM and
packaging-equivalence generators then inspect those outputs independently.
Notarization and every later promotion action remain separate, explicitly
authorized commands.

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
- Unregisters both the per-user agent and the menu app's login launch
- Revokes pairings and removes durable grants, audit, operations, saved endpoints, and host keys after confirmation
- Explains which macOS privacy grants may remain visible in System Settings and how to remove them
- Leaves no privileged helper or copied executable because none was installed

Deleting only the app is detected as an incomplete uninstall case in testing. Documentation provides a signed, non-destructive recovery route for a stale login-item registration. Reinstall does not silently inherit remote authorization unless protected retained state and product policy explicitly support recovery.

## 11. Go/no-go gates

### Ready for permanent release-shaped Apple targets

- Team ID is confirmed privately; the reverse-DNS prefix is fixed as `media.jenny`.
- Final target identifiers are registered.
- Developer ID certificate custody is verified.
- Stable Xcode 26.6 is installed and recorded.
- The process, entitlement, TCC, and update ownership in this document has no unresolved boundary change.

The final Mac App ID is registered. Completing the Persistent Content Capture request now waits only on Apple's required App Store URL/Apple ID path for this unreleased, directly distributed Mac app. Pending request status does not block non-capture permanent targets; approval gates the release entitlement/profile and external persistent Control builds.

The registered containing-app identity and standalone Agent code identity have
therefore advanced independently: the [containing-app target](evidence/2026-08-21-permanent-mac-containing-app-target.md)
and [embedded inert Agent](evidence/2026-08-21-permanent-embedded-mac-agent-target.md)
prove the non-capture bundle topology, distinct Developer ID designated
identifiers, and privacy ownership on Xcode 27 beta. The checklist above still
gates the remaining Apple targets and final release evidence; this proof does
not waive stable-toolchain, authenticated lifecycle, notarization, packaging,
or clean-machine requirements.

The [permanent iOS application target](evidence/2026-08-22-permanent-ios-application-target.md)
now fixes `media.jenny.maccompanion.ios`, iOS/iPadOS 26.0, the exact permission
declarations, and the indexed privacy resource in a generated release-shaped
bundle. The [release application composition](evidence/2026-08-22-permanent-ios-release-composition.md)
now binds protected QR/SAS pairing, crash-recoverable first-route provenance,
configured no-relay reconnect, and the first-party Observe, Approved Actions,
and separately authorized Remote Control workspace into that target. The build
remains unsigned; App ID registration, provisioning, signed device launch,
physical permission/network evidence, TestFlight, and final privacy/submission
inspection remain promotion gates.

### Ready for external Mac alpha

- Developer ID signing, hardened runtime, notarization, stapling, Gatekeeper, DMG, Sparkle, and clean uninstall pass on clean physical Macs.
- The agent survives expected lifecycle transitions and cannot outlive local disablement.
- The update path safely drains active work and preserves or refuses database state.
- A revoked or expired signing/provisioning scenario has a documented recovery plan.

### Ready for external Interactive Control beta

- Apple's managed entitlement is approved for the shipped App ID, or a documented public alternative passes equivalent review.
- Screen Recording, Persistent Content Capture, Accessibility observation, and post-event input onboarding and revocation are independently verified on every supported OS version.
- Locked behavior matches the published contract exactly.
- A security review has no unresolved critical finding in signing, update, local IPC, or Interactive Control.

### Ready for public release

- Mac download and iOS App Store metadata describe the same compatibility and privacy model.
- Beta-to-stable and stable-to-next-stable upgrades pass from the oldest supported version.
- Signing-key owners, rotation, incident response, compromised-release response, and update-feed recovery are assigned.
- A user can install, pair, understand permissions, update, suspend, revoke, and completely uninstall without engineering help.

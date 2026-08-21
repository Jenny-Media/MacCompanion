# ADR-0001: Process and trust boundary

- Status: Accepted for Stage 0 implementation
- Date: 2026-08-19
- Owners: Mac Companion architecture and security

## Context

Mac Companion must remain useful for Observe and bounded Act work while making live screen and input control visible, locally suspendable, and dependent on the macOS process that owns the relevant privacy grants. A single invisible network daemon with capture and input authority would collapse these boundaries.

## Decision

The first product uses three process roles:

1. **Mac Companion Agent** is a per-user `SMAppService.agent` LaunchAgent. It owns network listeners, host identity, paired-device records, grants, authorization epochs, durable operations, provider policy, audit storage, and authenticated local IPC. It cannot capture the screen or post input.
2. **Mac Companion menu app** is the persistent visible administration and activity process. It owns ScreenCaptureKit, VideoToolbox, Accessibility observation, application/window activation, and post-event input. It registers login launch through `SMAppService.mainApp` or a Stage 0-proven equivalent. It acts only under short-lived agent-issued leases bound to device, authorization epoch, interactive session, surface revision, coordinate revision, and expiry.
3. **iOS/iPadOS client** owns device identity, user-presence approval, presentation, decoding, and input intent. It is never authoritative for grants, host state, surface identity, policy, or operation outcome.

The menu app and Agent authenticate each other over typed local IPC. On macOS
26, each inactive XPC endpoint installs a same-Apple-team requirement for the
other process's exact signing identifier, and the Agent repeats its requirement
on every incoming peer session before activation. The only pre-authentication
request is the constant closed v0.1 hello. A
[signed disposable probe](../evidence/2026-08-21-signed-local-xpc-peer-identity-probe.md)
provisionally proves the exact Mac/Agent identities, invalid-identifier and
invalid-signer rejection in both directions, and closed version/shape
rejection. The
[production handshake construction](../evidence/2026-08-21-production-local-xpc-handshake-construction.md)
now binds those requirements to the permanent Mach service and targets,
publishes generation-bound authentication only after a successful exact
acknowledgement, and invalidates that observable lifetime exactly once. The
[menu-readiness binding](../evidence/2026-08-21-local-xpc-menu-readiness-binding.md)
adds one exact post-authentication lifecycle-ready request, keeps hello
non-authorizing, admits readiness only after its acknowledgement, and binds
authentication/readiness/invalidation to the existing lifecycle root through
one ordered generation-fenced event stream. Authenticated replacement cancels
the old peer without a false recovery event; lifecycle failure returns the exact
generation for fail-closed transport cancellation. Production content-free
status binding, complete permanent-Agent bootstrap instantiation, signed
permanent-target runtime, and broader capability revocation evidence remain
required before IPC ships.

If the menu app disappears, the agent ends capture/input leases, releases all input, suspends Interactive Control, and preserves eligible Observe or bounded Act service. Crash recovery is distinct from an explicit local **Quit and Disable**, which unregisters both login roles. Until recovery is proved, Control fails closed.

No root daemon, privileged helper, system extension, kernel extension, retained SSH credential, or pre-login service is part of this boundary.

## Consequences

- Official bundle identifiers use the confirmed Jenny Media `media.jenny`
  prefix. The Team ID remains private. Permanent embedded Mac and Agent targets
  provisionally prove their exact reciprocal signing requirements without
  tracking that Team ID. The CLI identity and stable-toolchain final-candidate
  repetition remain separate gates.
- Screen Recording, persistent capture, Accessibility observation, and post-event behavior must be tested against the menu app identity independently.
- A menu-app compromise cannot directly rewrite grants or durable authorization state; an agent compromise remains security-critical and is contained by OS user scope, signed updates, bounded data, and local revocation rather than sandbox theater.
- Logout and pre-login remain unsupported. Locked interaction is an optional physical-device result, not an architectural promise.

## Rejected alternatives

- **SSH-only host:** cannot provide the required visible, policy-rich, TCC-aware Adaptive Control boundary.
- **One all-powerful background agent:** simpler deployment but makes capture/input invisible and combines network parsing with TCC authority.
- **Privileged system daemon:** broadens pre-login and multi-user risk without an MVP requirement.
- **MacTools-owned network service:** couples product identity, lifetime, and protocol security to an optional post-MVP provider.

## Required evidence

- Registered agent and menu-app login lifecycle across login, close, crash, explicit disable, lock, user switch, logout, update, and uninstall.
- Invalid local clients rejected by identity and role, including same-user unsigned and differently signed processes.
- Menu-app loss releases pressed keys/buttons and stops capture before the agent publishes Control unavailable.
- No release target links an experiment-only entitlement or grants the agent capture/input authority.

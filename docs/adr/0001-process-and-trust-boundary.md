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

The menu app and agent authenticate each other over typed local IPC. Stage 0 must select exact audit-token, code-signing, designated-requirement, version-negotiation, and invalid-peer checks using final process identities before production IPC ships.

If the menu app disappears, the agent ends capture/input leases, releases all input, suspends Interactive Control, and preserves eligible Observe or bounded Act service. Crash recovery is distinct from an explicit local **Quit and Disable**, which unregisters both login roles. Until recovery is proved, Control fails closed.

No root daemon, privileged helper, system extension, kernel extension, retained SSH credential, or pre-login service is part of this boundary.

## Consequences

- Official bundle identifiers use the confirmed Jenny Media `media.jenny` prefix. The Team ID is confirmed privately, the containing-app App ID `media.jenny.maccompanion` is registered, and provisional Apple Development plus Developer ID builds verify that identity. Cross-process release designated requirements still wait for the remaining role App IDs, embedded signed code, and stable-toolchain evidence.
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

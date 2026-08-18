# Mac Companion

Mac Companion is a native iPhone and iPad companion for observing, operating, and—when needed—interactively controlling a personal Mac through a standalone macOS agent.

The product is local-first, policy-driven, and dashboard-first. Status and semantic actions are the primary experience; live screen, mouse, and keyboard control are an explicit escalation surface rather than the home screen. It is not a general shell, arbitrary file browser, vendor relay, or hidden agent. The Mac remains the final authority, and active remote use is visible and audited.

> **Name decision:** The product and iPhone/iPad app are named **Mac Companion**, with the proposed App Store subtitle **Monitor and control your Mac**. The installed Mac component is **Mac Companion Agent**. This is final for planning and implementation, but public launch still requires trademark review and App Store name reservation.

## Product position

Mac Companion is a secure operations console for personal Macs, especially always-on home Macs, multiple-Mac setups, and MacTools users. Its differentiators are:

- Per-device authorization and default-deny remote exposure
- Host-side policy and execution revalidation
- Clear paired, connected, viewing, and controlling states
- Understandable local audit history
- Direct local or user-managed private-network connectivity
- On-demand Interactive Control for live screen, mouse, and keyboard access
- A provider model that can expose MacTools and other canonical capabilities without exposing arbitrary internals

## Core decisions

- Build an independent macOS service and native iOS client first.
- Treat the first local-only build as a technical alpha, not the market MVP.
- Validate the native no-relay MVP before adding a MacTools adapter; use MacTools as the first external integration before generalizing a public provider SDK.
- Use a per-user LaunchAgent for reliable service ownership after login, with the menu-bar app as its trusted UI and administration client.
- Explicitly treat logout or no logged-in user as offline in the first release; a boot-time daemon is a later packaging decision.
- Bundle a diagnostic CLI that uses the same local policy, executor, and audit path.
- Use Bonjour locally and a saved Tailscale or private-network endpoint remotely.
- Operate without a Mac Companion relay or network account; private-route setup remains user-managed.
- Keep host identity independent of network address so LAN and private-network endpoints can change without re-pairing.
- Keep iOS live monitoring foreground-oriented. A no-relay release does not promise background iPhone alerts or continuous sockets.
- Use desired-state, retry-safe actions instead of toggles where possible.
- Include live screen, pointer, and keyboard control in the MVP validation path, but keep shell, arbitrary files, clipboard synchronization, and AI outside it.
- Require a logged-in macOS user. A locked session may remain observable and may expose the genuine macOS lock screen if public APIs permit; Mac Companion never bypasses authentication or reveals the desktop behind the lock.

## Documents

- [Product proposal](docs/product-proposal.md)
- [Architecture](docs/architecture.md)
- [Protocol outline](docs/protocol-outline.md)
- [Interactive Control specification](docs/interactive-control-spec.md)
- [MVP plan](docs/mvp-plan.md)
- [Distribution plan](docs/distribution-plan.md)
- [Implementation orchestration](docs/implementation-orchestration.md)
- [Research and decisions](docs/research-and-decisions.md)

## Proposed products

- **Mac Companion for iPhone and iPad:** Pair with Macs, view fresh status, invoke approved actions, open Interactive Control, review operations, and inspect activity.
- **Mac Companion Agent:** A per-user LaunchAgent that owns pairing, networking, identity, grants, policy, providers, audit history, and durable task state while that user remains logged in.
- **Mac Companion menu app:** Persistent local administration and activity UI. It owns ScreenCaptureKit and Accessibility-mediated input, and Interactive Control stops if this visible process is unavailable.
- **`maccompanionctl`:** Bundled diagnostic CLI that communicates only with the local service.
- **MacTools adapter:** First post-MVP external provider integration and the proving ground for the provider contract.

## Current status

This folder contains a product, architecture, protocol, Interactive Control, distribution, research, and delivery design only. It intentionally contains no implementation.

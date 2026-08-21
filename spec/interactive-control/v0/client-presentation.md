# Interactive Control client presentation composition v0.1

Status: normative for platform-neutral iOS presentation state. SwiftUI layout, localization, accessibility labeling, rendering, and physical foreground/background evidence remain app-target work.

The Interactive client surface always identifies the paired host by host UUID plus a locally confirmed Mac display name. It may show only a coarse route class: local discovery, direct private address, or private hostname. It never renders a raw address, Bonjour instance, credential, certificate fingerprint, or untrusted discovery label as the trusted Mac identity.

Presentation modes are closed: unreachable, inactive, approval required, starting, viewing, controlling, paused, and ending. A disconnected/background/no-network/retrying/action-required/manual-disconnect state overrides any retained active session, lock, or surface fact: mode becomes unreachable, lock becomes unknown, and no active surface is published. A connected active session requires `view`; pointer, keyboard, or text authority makes the mode controlling, while view alone remains viewing. Text without keyboard is inconsistent and fails closed.

Host lock states are unknown, unlocked, locked with control available, or locked interaction unavailable. The unavailable lock state is paused and publishes no surface because the last frame must already be blank. Connected active-unlocked and supported active-locked states may publish only the current acknowledged surface kind. Idle, ended, approval, suspended, and ending states cannot invent an active surface beyond the explicit starting transition.

Every session terminal reason maps to one closed recovery cause. Connection-derived recovery causes remain distinct from terminal session causes, and arbitrary remote/platform error text is never presentation state.

# Conservative network request contexts

Date: 2026-08-22

## Claim

`MacAgentConservativeRequestContextProductV1` supplies the prepared Agent
network product with live wall and monotonic clocks, fresh response message IDs,
and a thread-safe macOS host-state snapshot without claiming unavailable
lock-state knowledge.

## Construction

- The product installs one exact-event-filtering `NSWorkspace` observer before
  its initial sample and removes its token on one idempotent terminal finish.
  A revision fence prevents that sample from overwriting a lifecycle event
  delivered during startup.
- Its context closures retain the product, so a live listener cannot outlast
  the clock and state owner and receive fabricated fallback values.
- Public Core Graphics session facts are sampled through an injected boundary.
  No public fact combination produces `userSessionActive` or
  `userSessionLocked`; ambiguity maps to `otherConsoleUserActive`.
- Will-sleep publishes `hostPreparingForSleep`. Screen and session events do not
  erase that state before did-wake. Power-off is terminal, and later events
  cannot roll it back.
- Response IDs are generated independently for every primary and pairing
  context request.
- Revision exhaustion fails closed to `serviceStoppingForLogout`.

The API research and no-go boundary are recorded in
[`2026-08-22-public-macos-session-state.md`](../research/2026-08-22-public-macos-session-state.md).

## Deterministic verification

The package tests inject a notification center, session facts, clocks, and a
UUID sequence. They prove:

1. Same-user/on-console/login-complete, switched-user, off-console, missing,
   login-incomplete, and partially known facts never become unlocked.
2. Primary and pairing contexts receive exact live values and distinct IDs.
3. Sleep, wake, power-off, finish, repeated start, and post-terminal events
   converge without state resurrection, including notification delivery during
   the initial sample.
4. Finish removes observers and all later primary contexts report stopping.

Focused command:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --filter MacAgentConservativeRequestContextProductV1Tests
```

Result: 4 tests passed.

## Non-claims

This checkpoint does not start the listener from a permanent target, prove a
signed two-process exchange, distinguish locked from unlocked, or enable Act or
Interactive Control. Those remain separate composition and physical-evidence
gates.

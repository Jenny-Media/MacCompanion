# Other-console lifecycle fail-closed evidence

Date: 2026-08-22

## Claim

The product lifecycle can represent an ambiguous or different active console
user without fabricating that the configured user is unlocked or locked.
Observe remains independently useful while new Interactive Control and local
administration fail closed. The separately implemented conservative request
context reports `HostState.otherConsoleUserActive`; a future atomically fenced
product binding to that context will make operation admission deny Act. This
lifecycle checkpoint alone does not claim that binding.

## Construction

- `ConsoleSessionState.otherConsoleUserActive` is distinct from `active`,
  `locked`, and `loggedOut`.
- An enabled, ready Agent remains Observe-eligible in that state. The state does
  not stop either managed process or close the authenticated primary session.
- New Interactive Control admission and local administration are available only
  for a positively observed `active` configured-user session.
- Until the ordered genuine-lock-surface transition is implemented and
  physically proven, a lock event also ends Interactive Control while keeping
  Observe available. The conditional lock-surface contract remains a later
  replacement for that fail-closed teardown, not an authority retained by
  silence.
- `otherConsoleUserBecameActive` ends Interactive Control but preserves the
  primary session and Observe ingress.
- `configuredUserBecameActive` is the only lifecycle transition from the
  other-user state back to active. It must come from a future supported
  positive observation; it is not inferred from silence or reused as an unlock
  event.
- The dashboard reports only that the configured session is not confirmed
  active, explains that status may remain available, and does not infer that a
  different user is present. It offers no pairing or device/activity
  administration.

The source-of-truth limitation remains documented in
[`2026-08-22-public-macos-session-state.md`](../research/2026-08-22-public-macos-session-state.md):
the currently composed public session source never emits active or locked.

## Verification

Focused lifecycle, durable-startup, Agent-composition, and dashboard suites
prove the state predicates, transitions, Interactive teardown, Observe
preservation, initial durable-state handling, canonical local-status wire
round-trip, and fail-closed presentation. The consolidated focused command was:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --jobs 2 --filter \
'ProductLifecycleStateTests|LocalAgentStatusWireCodecV1Tests|MacRemoteAccessIntentStoreV1Tests|AgentRequiredAuditCompositionV0Tests|CompanionMacUITests'
```

Result: 65 tests passed across the five selected suites: 8 lifecycle, 5 local
status codec, 8 durable-intent/startup, 10 Agent-composition, and 34 Mac UI.

`swift test list` reports 1,309 unique package tests.

The complete repository gate passed:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
/bin/bash scripts/validate.sh
```

Result: 64 indexed JSON fixtures, 920 repository files, 1,107 historical
blob-paths, 14 repository-material fixtures, four Swift package manifests, 12
dependency-policy fixtures, permanent Apple-target policy, and the full package
and platform-probe gate passed on Xcode 27 beta. Stable Xcode 26.6 remains a
release-evidence gate.

## Non-claims

This checkpoint does not identify a public positive unlocked/locked signal,
activate the permanent Agent target, start a network listener, enable Act or
Control, or replace the signed physical session-state evidence gates.

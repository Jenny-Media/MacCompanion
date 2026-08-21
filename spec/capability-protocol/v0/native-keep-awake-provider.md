# Native bounded keep-awake provider v0.1

Status: bounded macOS provider candidate. It is not part of the advertised MVP
registry until its product UI and signed physical behavior pass the Stage 1
gates. Construction alone grants and activates nothing.

## Capabilities

The provider owns two explicit capabilities rather than a toggle:

- `maccompanion.system.startKeepAwake` accepts the closed object
  `{ "untilUnixMilliseconds": integer }` and returns the same closed object.
- `maccompanion.system.stopKeepAwake` accepts the empty closed object `{}` and
  returns `{ "stopped": true }`.

Start is accepted only when the operation itself is unexpired and `until` is
between 60 seconds and 4 hours after the provider's current wall-clock sample.
The provider never silently clamps or extends a request. Stop is idempotent.
Both actions are reversible local-state changes with no data, credential,
external-service, or destructive effect. They may affect energy use, require
no foreground session, are non-cancellable after execution begins, and remain
disallowed while locked until signed physical evidence proves the intended
behavior and UI.

## IOKit boundary

The macOS adapter uses the public IOPM assertion API with
`kIOPMAssertionTypePreventUserIdleSystemSleep`. This prevents only automatic
user-idle system sleep: it does not force the display awake and cannot prevent
lid-close, explicit, low-battery, thermal, or other system-directed sleep.

Each start creates an assertion with a system-enforced timeout and release
action. The human-readable assertion name is fixed and contains no remote
device, operation, or user content. A replacement first releases the prior
owned assertion and fails closed if release or creation cannot be verified.
Stop releases only the exact assertion owned by this controller. The operating
system also removes process-owned assertions when their process ends; provider
restart therefore restores no stale keep-awake state.

The controller reports `provider.unavailable`, `provider.rejected`, or
`provider.executionFailed` without exposing raw IOKit codes. A release whose
outcome cannot be proven becomes `outcomeUnknown`; it is never silently retried
because the prior bounded assertion may still be active until its timeout.

## Promotion gate

The capability stays candidate-only until a signed clean-device probe proves
create, replacement, stop, timeout, Agent crash, logout, lid-close/system-sleep
limitations, battery/thermal behavior, and user-visible assertion attribution.
The first market MVP continues to require only one evidence-backed desired-
state action, currently `setAudioMuted`.

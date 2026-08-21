# Native system-appearance no-go evidence — 2026-08-21

## Outcome

The proposed three-state `setAppearance(system | light | dark)` native action
is a Stage 0 no-go. The decision is evidence-backed and does not block the
independent Observe, audio-mute Act, keep-awake candidate, or Control lanes.

The supporting [feasibility review](../research/2026-08-21-native-system-appearance-feasibility.md)
records the public-AppKit boundary, the installed System Events dictionary,
the missing automatic/system scripting state, and the Automation privacy and
entitlement requirements.

## Repository boundary

`scripts/validate_native_appearance_boundary.py` now fails if Swift package
sources use known undocumented global-appearance mutation spellings. It also
fails if Agent, host-authority, or native-provider targets acquire Apple Event
APIs. Four policy self-tests cover allowed app-local appearance, a forbidden
global-default mutation, forbidden Agent-owned Apple Events, and the fact that
a future separately reviewed menu-owned adapter is not pre-emptively banned.

This is a targeted regression guard, not proof that every possible private
mechanism can be recognized lexically. Code review and the target ownership
matrix remain authoritative.

Forty focused wire, domain, persistence, and operation tests pass after the
rejected appearance identifier was replaced with an explicitly synthetic test
capability. The hardened repository gate passes across 800 validated files,
including 4 appearance-boundary policy self-tests over 281 Swift source files,
1,129 Swift tests, both required iOS Simulator cross-compiles, the macOS UI
compile, and all three no-prompt/no-network platform probes. The emitted
user-cache warnings are the expected read-only SwiftPM cache warnings.

## Promotion state

No appearance capability descriptor or provider is admitted. A future
Automation-backed light/dark action must receive a new contract and its own
evidence; it may not reuse the rejected three-state identifier while omitting
`system` behavior.

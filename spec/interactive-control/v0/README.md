# Interactive Control shared authority profile v0.1

Status: normative for bundle-independent session authority. Pinned TLS role admission, message handshakes, and media/input records are frozen in their linked profiles; concrete Network.framework and Apple media/input adapters remain platform work.

This profile defines the host-owned state machine implemented by `CompanionInteractiveShared`. It does not authorize a remote request by itself. Every session remains bound to a paired device, a current grant, a current authorization epoch, and one freshly consumed user-presence approval.

The visible Mac-side one-session warning and local stop presentation are defined in [`../../capability-protocol/v0/local-authority-presentation.md`](../../capability-protocol/v0/local-authority-presentation.md). That presentation neither creates a grant nor replaces the phone approval.

## Session invariants

- States are exactly `idle`, `approvalRequired`, `starting`, `activeUnlocked`, `activeLocked`, `lockedInteractionUnavailable`, `suspended`, `ending`, and `ended`.
- Approval expires at its monotonic deadline and is consumed once before executor setup.
- The four-hour maximum starts when approval is consumed. Setup, lock, unlock, reconnect, or descriptor replacement cannot extend it.
- Lock pauses input, releases every pressed input, invalidates all surface tokens, stops desktop capture, and blanks the last frame before any lock result is published.
- Unlock from either lock state returns through `starting`; input remains denied until a fresh desktop descriptor and clean keyframe are acknowledged.
- `suspended` cannot resume remotely. It can only proceed to terminal teardown.
- Ending or suspension fails closed by releasing input, invalidating surface authority, stopping capture, and blanking retained video.

Allowed success-path transitions are:

```text
idle -> approvalRequired -> starting -> activeUnlocked
activeUnlocked -> activeLocked|lockedInteractionUnavailable
activeLocked|lockedInteractionUnavailable -> starting -> activeUnlocked
approvalRequired|starting|activeUnlocked|activeLocked|lockedInteractionUnavailable -> suspended|ending
suspended -> ending -> ended -> idle
```

Any ambiguous host state moves toward suspension or termination, never toward greater authority.

## Implementation boundary

The pure reducer emits effects but does not perform capture, input injection, IPC, persistence, or networking. A platform composition root must execute those effects and report success through an explicit subsequent event. Pixels or successful input are never evidence of session state.

The closed [session and channel messages](session-channel-messages.md), [initial
surface activation](initial-surface-activation.md), [surface-control
messages](surface-control-messages.md), [interactive display catalog and
selection](display-catalog-messages.md), [surface target
inventory](target-inventory-messages.md), and cryptographic bytes for approval and
role-specific credentials are frozen in the [security
profile](security-profile.md). Other independently frozen components are the
[media record profile](media-records.md), [reliable input
profile](input-messages.md), [client viewport/input mapping
profile](client-input-mapping.md), [macOS input-mapping
profile](macos-input-mapping.md), [client decoder/render authority
profile](client-decoder-rendering.md), [client render handoff and blanking
profile](client-render-handoff.md), [client media/input admission
composition](client-admission.md), [client approval and role-channel
composition](client-security-composition.md), [client presentation
composition](client-presentation.md), [host primary-command
composition](host-command-composition.md), [initial runtime lease/receipt
preparation](initial-runtime-preparation.md), and [visible menu-app runtime
composition](menu-runtime-composition.md); none authorizes or opens a channel
by itself.

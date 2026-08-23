# Opaque display and lease-scheduling checkpoint

Date: 2026-08-22

## Result

The permanent visible menu application now owns the first concrete display
selection and publishes only its random opaque UUID in the revision-1
Interactive admission value. `MacInteractiveOpaqueDisplaySelectionV1` retains
the corresponding `CGDirectDisplayID` only inside the macOS menu-platform
module. It exposes no display name, geometry, process identifier, or physical
identifier across local XPC, logs, or presentation state.

The initial policy is intentionally narrow: select the current main online
display at menu-process construction. A missing or offline display produces no
selection. Once the exact display disappears, the mapping is discarded and
never redirects the same opaque UUID to another display. The package-only
resolver will be shared by the concrete capture and input adapters.

The Agent now has a transport-independent automatic lease-renewal owner. It:

- starts only after the exact initial runtime install and active-lease read;
- schedules two seconds before the acknowledged lease deadline;
- samples the monotonic clock again when issuing renewal;
- uses only the exact returned replacement lease as the next deadline;
- validates that every authority binding is unchanged and the counter advances
  exactly once; and
- never retries a failed or ambiguous renewal. A structurally changed returned
  lease triggers protocol-violation termination.

The underlying `AgentInteractiveRuntimeOwnerV1` still performs the final
durable-plus-visible admission read and compensating revoke. The scheduler does
not infer completion from transport send and does not widen its runtime seam.

## Verification

- Two display-selection tests prove opaque resolution, mismatched-token
  rejection, unavailable construction, explicit invalidation, and permanent
  no-redirect behavior after display loss.
- Three scheduler tests prove the exact first delay and send-time sample, one
  renewal from the returned deadline, no retry after ambiguous failure, clean
  termination forwarding, and protocol-violation teardown for a changed
  replacement lease.
- The focused display, dashboard-publication, and scheduler tests passed under
  Xcode 27 beta.
- The complete MacCompanionKit catalog passed all 1,418 Swift tests under the
  supported SwiftPM/compiler sandbox-disable flags.

## Non-claims and next work

No display enumeration, capture, encoding, media delivery, or input posting was
performed. The mapper is retained by the permanent menu application, but the
permanent product still supplies no concrete Interactive runtime owner. The
next checkpoint must bind the existing serialized menu runtime to concrete
indicator, capture, input-release, frame-blanking, input-posting, and bounded
media adapters, then connect the authenticated secondary channels. Signed
physical display-loss and permission behavior remains a platform gate.

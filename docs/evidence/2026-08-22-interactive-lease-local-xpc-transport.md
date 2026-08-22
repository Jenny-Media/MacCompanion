# Interactive lease local-XPC transport

Date: 2026-08-22

## Result

The production local-XPC transport now carries the three lifecycle operations
needed to place the visible menu-process Control runtime under the current
authenticated-and-ready Agent generation: install, renew, and revoke. This is
the transport authority only. It does not activate screen capture, publish
media, or post input.

## Closed boundary

- The indexed v0.1 profile fixes three exact request/success pairs, a 4,096-byte
  payload ceiling, a four-second menu execution deadline, and a five-second
  Agent reply deadline.
- Payload-bearing messages use strict canonical JSON and are decoded into the
  existing validated `InteractiveRuntime*V0` values. Renewal success is exactly
  payload-free.
- One transaction gate spans all three command families for each authenticated
  generation. Commands never queue behind one another.
- The Agent sender admits commands only after authentication, accepted menu
  readiness, and exact local-method authorization. The menu receiver admits
  them only from that same profile and generation.
- Runtime rejection has no handled error envelope. Timeout, cancellation after
  send, malformed data, reply-kind substitution, concurrency, generation
  replacement, and transport failure retire the exact peer generation.
- Menu-side connection loss invokes unacknowledged runtime invalidation. This
  is the local safety path and does not wait for an Agent or network receipt.

The C/XPC layer owns only exact dictionary parsing, retained request/reply
lifetime, and asynchronous send classification. Swift owns canonical payload
validation, correlation, transaction generation fences, deadlines, and runtime
dispatch.

## Verification

- The C bridge passed `clang -fblocks -fsyntax-only` against the Xcode 27 beta
  macOS SDK.
- Focused codec, transaction-gate, and local-XPC handshake tests passed.
- The complete MacCompanionKit Swift Testing catalog passed all 1,400 tests
  with SwiftPM and compiler subprocess sandboxing disabled through their
  supported flags.
- `git diff --check` passed before this evidence update.

The run used the installed Xcode 27 beta. Stable Xcode 26.6 and signed
two-process execution remain release gates.

## Non-claims and next composition

This checkpoint does not connect the transport to the permanent Agent's
`InteractiveSessionRuntimeOwningV0`, construct the menu's concrete indicator,
capture, input, frame, or media adapters, or prove physical Control. It also
does not put media or input events on local XPC.

The next slice is a separate generation-aware Control authority. It must
re-read the durable device/grant state and current visible-menu/display state
at final install, translate the verified bootstrap through
`InteractiveInitialRuntimeCommandAuthorityV1`, retain the installed session and
lease for renewal/revocation, and expose only the narrow lease sender. The
existing pairing/recovery presentation authority remains Control-free.

# Permanent Agent host-recovery service

Date: 2026-08-23

## Gap closed

The permanent menu already retained an exact reviewed host-identity recovery
command and could submit it through authenticated local XPC. The permanent
Agent still selected an authentication-only service whenever startup found a
missing established key or a durable recovery fence, so no Agent-issued
review/resume surface or recovery handler could become reachable.

Production Agent preparation now turns both nonready recovery results into one
inert `MacAgentHostIdentityRecoveryProductV1`: a fresh missing-key result binds
the exact recovery reason to a new Agent-issued review, while a durable fence
binds the exact persisted recovery UUID to the existing resumable command. The
application-platform selector starts and retains this product as the sole
service owner for that launch.

## Narrow profile and authority

`MacLocalXPCServerProfileV1.hostIdentityRecovery` is distinct from enabled,
disabled-bootstrap, and authentication-only profiles. It admits only:

- authenticated menu readiness;
- a typed source-unavailable status reply so the dashboard remains closed;
- Agent-to-menu host-recovery review, durable-resume, and withdrawal
  presentation; and
- menu-to-Agent submission of the exact
  `LocalHostIdentityRecoveryCommandV0`, returning only its correlated
  `LocalHostIdentityRecoveredReceiptV0`.

Construction requires exactly a status reader and host-recovery handler. It
rejects pairing, disabled bootstrap, update quiescence, Interactive admission,
Interactive lease/input/media, network-listener, and provider authority. The
handler owns only the exact delivery capability created from the same
required-audit storage root after an authenticated ready generation; it never
receives a caller role, raw store, raw coordinator, or general Agent product.
Generation replacement or endpoint loss invalidates and withdraws only the
matching recovery delivery.

The menu dashboard now waits for a usable ordinary status snapshot before
publishing Interactive admission. A recovery Agent's source-unavailable status
therefore cannot accidentally cause the menu to send Control authority merely
because readiness succeeded.

## Verification

Focused tests prove exact profile properties, construction rejection for
missing or mismatched authorities, recovery-profile selection, no presentation
before authenticated readiness, generation-bound presentation invalidation,
status-before-Control admission, production fresh/resume mode mapping, and
application-platform selection without starting a signed service or touching
Keychain custody.

The complete repository gate passed over 1,195 repository files, 2,177
historical blob-paths, 73 indexed JSON fixtures, 372 Swift source files, 1,609
MacCompanionKit Swift tests, eight platform-probe tests, cross-platform
compiles, and the three no-prompt/no-network probes.

## Subsequent completion boundary

This checkpoint does not execute destructive host recovery. No Keychain key,
host identity, pairing, grant, work, or audit record was mutated.

The subsequent [host-recovery completion acknowledgement](2026-08-23-host-recovery-completion-acknowledgement.md)
adds the exact receipt echo, atomic replay-journal retirement, recovery-only
startup replay before acknowledgement, and one-shot restart convergence after
durability. It supersedes this checkpoint's open source-level
response/restart boundary.

No real recovery was executed by this checkpoint. Signed reciprocal process
execution, real Secure Enclave/Keychain recovery,
stable Xcode, first-unlock and response-loss fault injection, accessibility,
and explicit user-observed destructive confirmation remain release evidence
gates.

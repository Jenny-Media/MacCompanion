# Physical iPhone reconnect: terminal-cleanup deadlock

Date: 2026-08-28. Local Xcode 27 beta evidence; not release acceptance.

## Observed failure

The physical iPhone reached the Mac over Wi-Fi and completed the network
handoff, but its primary connection was immediately closed. Agent logs showed
repeated `connection bind failed role=applicationPrimary error=transitionInProgress`.
This was not a missing listener, discovery failure, or evidence that pairing
needed resetting.

The preceding physical Control session had installed successfully. At its
renewal, the menu runtime returned `noActiveSession`, invalidating the local
channel. The Agent logged `interactive-only primary transition started` but
never completed that transition. Later reconnects remained denied.

## Cause and repair

A failed generation-bound endpoint operation awaited its router's terminal
notification. That notification could retire Interactive authority and join
the lease-renewal task. The renewal task was still awaiting the failed endpoint
operation, forming a cycle. The primary transition stayed busy indefinitely.

The router now fences its exact generation immediately, retains the product-loss
notification asynchronously, and allows the failed operation to unwind. Its
external finish barrier joins both endpoint retirement and the product-loss
notification. Stale generations cannot retire replacements; new admission stays
closed; cleanup is still required and a terminal request is not a success receipt.
No pairing, grant, signature, TLS, or execution-lease checks were relaxed.

The normative rule is in [local IPC](../../spec/local-ipc/v0/README.md).

## Evidence

- The new `endpointFailureUnwindsBeforeProductCleanupJoinsItsOperation` regression
  failed on the old implementation with both a blocked operation and an incomplete
  external finish barrier: `/private/tmp/maccompanion-endpoint-cleanup-red.log`.
- After the repair, **99 local-XPC tests and 131 Agent-platform tests passed**:
  `/private/tmp/maccompanion-endpoint-cleanup-green.log`.
- Full validation passed: **1,720 Swift tests**, repository policy/fixture checks,
  and platform builds: `/private/tmp/maccompanion-reconnect-deadlock-validation.log`.
- The signed Mac app/embedded Agent built and passed deep/strict signature checks:
  `/private/tmp/maccompanion-reconnect-deadlock-signed-build.log`.
- Installed the fix after stopping the stuck Agent and orderly app shutdown.
  The previous app remains at
  `/private/tmp/maccompanion-reconnect-backup.h4uFoH/Mac Companion.app`.
  The installed Agent binary matches the verified build.
- The physical iPhone reconnected using its existing pairing. Device logs show
  `reconnect=connected`, and Agent logs show `connection active role=applicationPrimary`
  at 02:51:58 EDT. The connection remained established more than 80 seconds later,
  without another stuck transition. Device evidence:
  `/private/tmp/maccompanion-physical-reconnect-after-fix.log`.

Pairing and permissions were not reset; no new Control approval was performed.
The iPhone was subsequently relaunched normally to stop console capture.

## Remaining boundary

This repairs and verifies primary reconnection. It does **not** explain every
possible reason the earlier menu runtime had already ended, or prove a fresh
physical Control stream survives renewal, surface changes, and lock/unlock.
That requires a new genuine phone approval and a separately recorded session.
The isolated Simulator host bypasses the installed Agent/XPC composition; its
green live-video tests did not cover this product cleanup cycle. Keep this
production regression in addition to, not replaced by, those tests.

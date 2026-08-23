# Persistent Control indicator and lease-expiry checkpoint

Date: 2026-08-22

## Result

The permanent menu target now constructs one process-lifetime Interactive
runtime instead of omitting the runtime handler. Its production-safe interim
composition keeps capture, media, and input closed, so an install cannot report
success before those concrete adapters exist. Desktop preparation and the
runtime lifecycle nevertheless traverse the real permanent menu composition.

The same process owns one `MacInteractiveActivityIndicatorV1`. A successful
runtime show publishes the locally confirmed device name, exact Interactive
session, process generation, and positive monotonic revision. Exact replay is
effect-free; another session cannot replace a visible one. The menu-bar icon
changes persistently while the indicator is visible, and the open menu shows a
red named activity banner with a local Stop button.

Stop first changes the still-visible state to `stopping`, then invokes the same
serialized runtime teardown used for Agent loss. Only runtime cleanup may clear
the indicator. A failed stop restores a visible active state. The underlying
runtime was tightened so indicator clearing is not attempted until input
release, capture stop, and retained-frame blanking are all proven. Partial
cleanup retains the indicator and retries only uncertain safety effects.

## Independent monotonic expiry

The local-XPC runtime adapter now owns one system monotonic timer for the exact
deadline retained by the runtime owner:

- successful install arms the exact lease deadline;
- successful renewal cancels and replaces the old timer only after the runtime
  has installed the exact replacement deadline;
- a private callback token plus exact-deadline check rejects stale timers;
- an early callback schedules only the remaining monotonic duration;
- at or after the deadline, local teardown runs without another IPC, input,
  media, network, or wall-clock event; and
- successful revoke, local Stop, and Agent-IPC invalidation disarm the timer
  before teardown.

A missing or mismatched runtime deadline after successful install/renewal is a
terminal composition failure: the adapter disarms, invalidates local runtime
authority, and latches safety recovery instead of returning false success.

## Verification

- Runtime tests prove an uncertain capture stop and retained-frame blank keep
  the indicator visible until their exact retry succeeds.
- Indicator tests prove device/session naming, process generation and revision,
  exact replay, substitution rejection, stopping visibility, cleanup-driven
  clearing, and failed-stop restoration.
- Adapter tests prove exact initial delay, renewal replacement, cancellation,
  forced stale-callback rejection, early-callback rescheduling, and expiry at
  the exact injected monotonic sample.
- The focused Interactive-runtime and Mac application-platform suites pass
  under Xcode 27 beta.
- The permanent unsigned Mac target builds with the package-owned runtime,
  indicator, menu-bar state, and Stop surface.
- The complete repository gate passes 1,438 MacCompanionKit Swift tests, all
  macOS/iOS cross-builds, and eight platform-probe tests.
- `git diff --check` passes.

## Non-claims and next work

No screen capture, encoded media, frame rendering, Accessibility observation,
or Core Graphics input posting ran. The interim capture adapter always rejects
install and the other unavailable adapters grant no capability. The next slice
must replace those closed effects with concrete ScreenCaptureKit capture,
bounded media/frame ownership, input release/posting, and physical permission
evidence without changing this indicator or expiry authority.

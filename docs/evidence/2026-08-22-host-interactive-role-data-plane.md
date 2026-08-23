# Host Interactive role-data-plane checkpoint

Date: 2026-08-22

## Result

The shared Agent listener now transfers the concrete authenticated input and
media connections only after both roles carry the same client, primary
connection, Interactive session, and authorization epoch. A production pair
consumer is mandatory whenever Interactive authentication is enabled. Missing,
rejected, or mismatched ownership cancels both connections; ready sockets can
no longer remain silently undrained in the release composition.

One generation-fenced Agent authority owns the pair. It requires an installed
menu role-data route and independently rechecks that the existing Interactive
runtime is active for the same menu generation and session before starting
traffic. Menu-generation invalidation stops the pump before invalidating its
runtime lease, while terminal product shutdown retires the data plane before
the runtime authority.

The input pump performs exact four-byte big-endian length reads, caps strict
JSON bodies at 65,536 bytes, and checks the authenticated session and epoch
before forwarding the typed envelope. The media pump requests one complete
validated record at a time, checks payload length, session, epoch, and strictly
increasing sequence, then awaits the exact network send before asking for the
next record. Either direction failing closes both connections and requests
exact-session termination. Role traffic cannot create, renew, or broaden a
lease.

## Verification

- The fixture validator passes all 69 indexed protocol/product fixtures,
  including the canonical host role-data-plane profile.
- Five focused tests cover input forwarding, one-at-a-time media send,
  cross-fence rejection, runtime-generation admission, lifecycle teardown, and
  concrete listener-to-pair-owner transfer.
- The complete repository gate passes 1,449 MacCompanionKit Swift tests, all
  macOS/iOS cross-builds, and eight platform-probe tests under Xcode 27 beta.
- `git diff --check` passes.

## Non-claims and next work

The local Agent-to-menu input route and menu-to-Agent media source are not yet
implemented. Production therefore rejects a proven role pair until that exact
authenticated-generation XPC transport is installed. No ScreenCaptureKit
stream, VideoToolbox encoder, bounded media drain, Core Graphics event post,
physical network exchange, or signed live-Control session ran. Those remain
separate evidence gates.

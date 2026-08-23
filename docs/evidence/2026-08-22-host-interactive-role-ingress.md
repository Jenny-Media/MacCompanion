# Host Interactive role-ingress checkpoint

Date: 2026-08-22

## Result

The shared TLS listener now recognizes a secondary connection only from one
complete, strict `interactive.channel.hello` frame and derives the closed input
or media role from the decoded body. The classifier transfers that exact frame,
the verified TLS binding, and the one-use connection together; it does not
classify from an unvalidated top-level kind string or read into later role
traffic.

The listener advances only one unauthenticated candidate at a time and retains
at most three later accepted connections in FIFO order. This lets the client's
parallel input/media dials both progress without concurrent unauthenticated
framing work; excess connections close and queued candidates retain their
original acceptance time for deadline enforcement.

One host handshake pump owns the challenge, proof, and accepted exchange. It
uses exact four-byte length framing, immediate-predecessor correlation, distinct
response IDs, a fresh host nonce, and a 30-second monotonic deadline. Role
traffic remains unavailable until the accepted frame send completes. Any
malformed frame, correlation failure, authority rejection, timeout,
cancellation, or transport failure invalidates the challenged role authority
and closes the connection.

The permanent Agent runtime retains each one-time credential. The network pump
can invoke only begin, consume, and invalidate facets through the stable
generation-bound runtime authority; no credential bytes cross that boundary.
Production composition passes the exact concrete runtime owner separately from
its lease-renewal wrapper, and menu-generation invalidation fences both facets.

After authentication, listener ownership retains the exact client, primary
connection, Interactive session, authorization epoch, channel, and role. Input
and media become one retained pair only when the shared identity fields match.
A duplicate role cannot displace an active role, and a cross-session or
cross-epoch candidate closes both connections rather than combining them.

## Verification

- The fixture validator passes all 68 indexed protocol/product fixtures,
  including the host role-ingress profile and canonical hash.
- Focused tests prove strict role classification, accepted-before-ready
  ordering, correlation-failure invalidation, Agent-retained exact credential
  consumption, successful same-session role pairing, and cross-session pair
  rejection.
- The complete repository gate passes 1,444 MacCompanionKit Swift tests, all
  macOS/iOS cross-builds, and eight platform-probe tests under Xcode 27 beta.
- `git diff --check` passes.

## Non-claims and next work

The ready input and media connections are retained but no production role-data
pump consumes or produces their bytes yet. No ScreenCaptureKit session,
VideoToolbox encoder, media-queue drain, Core Graphics input posting, or
physical live-control session ran. The next slice must define the
generation-fenced Agent/menu role-data handoff, then connect bounded input
decoding and media draining before enabling concrete capture.

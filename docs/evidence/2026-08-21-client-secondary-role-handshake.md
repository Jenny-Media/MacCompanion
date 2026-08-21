# Client Secondary Role Handshake Evidence

Date: 2026-08-21

Environment: bundle-independent Swift authorities, injected exact-read byte
I/O, and macOS/iOS package cross-compiles on Xcode 27 beta. This is protocol,
framing, route-provenance, and unsigned construction evidence. It is not a
live Network.framework role connection, captured frame, rendered frame,
posted input event, physical-device, stable-toolchain, or release claim.

## Normative boundary

The secondary-channel profile now requires both role sockets to reuse the
exact endpoint and port that produced the owning authenticated primary. The
client may not re-resolve, re-race, infer, or substitute either route. Each
handshake message has a four-byte unsigned big-endian length followed by
`1...4,096` strict-JSON bytes. Receivers read the prefix and declared body
exactly, so accepting a handshake cannot consume immediately following input
or media bytes. Input later uses the same framing with the existing 65,536-byte
strict-JSON limit; media begins directly with its self-framing 96-byte header.

Both roles may authenticate concurrently, but neither live viewing nor live
input may be published until input and media are ready and the initial Desktop
clean-media acknowledgement completes. Either role's failure closes the pair
and requires a fresh Interactive session. Primary replacement closes both old
roles before releasing that selection.

## Construction

`ClientInteractiveRoleHandshakePumpV0` wraps the existing
`ClientInteractiveChannelAuthorityV0`; it does not duplicate pin, credential,
role, transcript-HMAC, replay, or proof policy. The injected I/O boundary reads
only the current prefix/body remainder, serializes hello and proof sends,
schedules the authority's fixed 30-second monotonic deadline, cancels the
transport on every failure, and publishes a role/channel handoff only after the
correlated server proof makes the underlying authority ready.

The selected-primary product now carries its exact winning endpoint into the
application owner as package-private state. Role-channel composition can obtain
that endpoint only together with a still-current authenticated session and an
accepted Interactive session whose host, client, connection ID, and
authorization epoch exactly match. The endpoint and channel credentials remain
absent from public UI snapshots.

## Focused verification

Three new pump tests cover both input and media roles, one-byte fragmentation,
two serialized client sends, exact server-proof convergence, and a sentinel
role record left completely unread after acceptance. They also prove the
4,097-byte rejection boundary, input/media role-swap rejection, transport
cancellation, and an inclusive fixed monotonic deadline. The selected-product
test additionally proves that the exact endpoint survives primary selection
without becoming presentation state.

## Full gate

The hardened unsigned repository gate passes with 60 indexed protocol/product
fixtures, 731 current repository files before this evidence record plus 34
historical blob paths and 14 repository-material fixtures, four Swift package
manifests and 12 dependency-policy fixtures, three privacy manifests with 12
fixtures and six required-reason API source records, 10 source-SBOM fixtures,
16 release-evidence fixtures, and 1,005 Swift tests. All macOS/iOS package
cross-compiles and all three no-prompt/no-network construction probes pass.
Only the expected read-only user SwiftPM cache warnings appear.

## Remaining gates

- Add the concrete exact-endpoint Network.framework role connector and retain
  both ready socket owners as an all-or-none selected-primary generation.
- Drive the initial Desktop descriptor and media decoder/render path, then
  acknowledge the first clean frame before enabling input or live UI state.
- Prove live pinned role connections, media, input, backgrounding, replacement,
  and lock fallback on signed physical devices.
- Re-run on stable Xcode 26.6 and preserve signed release evidence separately.

# SSH Screen Sharing feasibility evidence

Date: 2026-10-09. Toolchain: stable Xcode 27.0 (27A266a), arm64 macOS.

## Verified automatically

The isolated package builds and the five focused tests pass:

- A generated, ephemeral loopback SSH server accepts `direct-tcpip` only for
  `127.0.0.1:5900`. A 4 MiB synthetic byte sequence is preserved in both directions
  across SSH and the Unix socket bridge, exceeding socket buffers and SSH windows.
- A different host key is rejected before any user authentication request or
  forwarding channel reaches the server.
- Cancellation while a server sends no SSH banner closes the parent connection.
- A buffer exceeding the 256 KiB hard queue limit closes both bridge endpoints.
- Loss of the parent SSH connection closes the consumer socket. Repeated cleanup
  is safe and the parent, SSH child, and bridge are inactive afterward.

The final focused run executed five tests with zero failures. Logs/build outputs
are outside the checkout, under `/private/tmp/maccompanion-ssh-screen-sharing-*`.
`bash scripts/validate.sh` also passed on stable Xcode. All nine resolved
prototype dependency revisions match the existing production dependency pins.
The local SSH (22) and Screen Sharing (5900) services are reachable. No user
credentials, real host keys, screenshots, framebuffer bytes, or user input are
part of these tests or this evidence file.

## Real Screen Sharing proof

Passed after the user entered their existing Mac account password locally in the
generated probe. The result was recorded at 2026-10-10 02:40:55 UTC (October 9 in
the user's America/New_York time zone): `ardHandshakePassed`, 654 outbound bytes,
1,075 inbound bytes, and a 1,028-byte peak relay queue. The probe verified this
Mac's SSH host key against local public host keys, authenticated to built-in
Remote Login, and completed Apple ARD authentication through `direct-tcpip` to
built-in Screen Sharing. The result records no requested framebuffer updates and
no sent user input.

Cleanup was independently checked after the result: the still-running probe
process had zero active TCP sockets and zero established TCP sockets. The
aggregate result remains outside Git at
`/private/tmp/maccompanion-ssh-screen-sharing-probe/result.json`. No credentials,
actual public host keys, desktop names, screenshots, pixels, or input are in the
record. This proves the real authentication path, beyond a synthetic echo server
or anonymous RFB banner.

## Limits and production work

The experiment has no release-target membership. It does not render desktop
updates, send input, or prove iPhone performance, reconnect behavior, background
lifecycle, multi-address dialing, or public distribution readiness. It uses local
public host keys only to establish the loopback server identity; production must
use an explicit first-use trust decision and persistent changed-key rejection.

For production, first update the direct connection specification
and its authoritative fixture index, then integrate an iOS tunnel owner with the
existing validated numeric endpoint connector. Forward only to the selected
Mac's loopback Screen Sharing port. Require Remote Login and Screen Sharing,
preserve separate SSH and ARD authentication responsibilities, close every layer
on cancellation/error, and never fall back to plaintext. Test the new production
login/trust flow and physical Desktop/Trackpad gestures before selecting a new
App Review build.

Exact corresponding-source packaging and Apple distribution terms review remain
separate release requirements; this transport experiment does not resolve them.

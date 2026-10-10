# Screen Sharing over SSH feasibility probe

Disposable macOS experiment, excluded from every release target. It uses the
existing Citadel dependency and pinned LibVNCClient, with no Mac helper.

The real probe connects only to this Mac's built-in Remote Login at
`127.0.0.1:22`, verifies the server key against the local `/etc/ssh/*.pub` public
host keys, and opens an SSH `direct-tcpip` channel to `127.0.0.1:5900` on that
server. A Unix socket pair feeds LibVNCClient. There is no local forwarding
listener and no fallback to unencrypted RFB.

The user enters the existing Mac password in a secure field. It is used for SSH
and the existing Apple ARD authentication, kept in memory for this attempt only,
and never logged or saved. The probe requests no desktop updates and sends no
pointer, keyboard, or gesture input. It verifies the RFB/ARD handshake, then
closes the sockets and SSH session. Diagnostic results contain only outcomes
and aggregate byte counts.

Build outputs, dependency caches, results, and synthetic keys stay outside Git:

```sh
python3 Experiments/SSHScreenSharingProbe/build.py \
  --output /private/tmp/maccompanion-ssh-screen-sharing-probe \
  --vnc-source /path/to/pinned/libvncserver \
  --vnc-build /path/to/macos/libvncclient-build \
  --openssl /path/to/macos/openssl-arm64
```

Run the generated app and choose **Sign In and Verify**. Run the generated
package's tests with `swift test --package-path <output>/Package --disable-sandbox`.
Tests use an ephemeral loopback SSH server, generated in-memory host keys, and
synthetic bytes. They do not use the user's account or modify any system service.

This experiment is not release admission. Production work requires specification
and authoritative fixture updates, a separately tested iOS implementation,
host-key trust UX, credential separation, lifecycle testing, and a new build.

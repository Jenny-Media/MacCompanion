# Screen Sharing over SSH: production integration and Simulator evidence

Date: October 9, 2026 (America/New_York). Stable Xcode 27.0 (27A266a).
Baseline commit: `ce85d33cdabe87a39ff97641d7cbfe1c91a733c0`; this evidence
covers the subsequent uncommitted working-tree candidate.

## Implemented path

The direct Screen Sharing specification and the existing authoritative fixture
were updated before the production transport. The fixture remains indexed only
by `spec/fixtures/manifest.json`.

Desktop and Trackpad & Keyboard now authenticate to built-in macOS Remote Login
and forward their existing Screen Sharing connection over SSH. The remote target
is fixed to `127.0.0.1` with the saved Screen Sharing port. No Mac helper, local
TCP listener, plaintext fallback, input replay or post-authentication address
retry is introduced. The existing validated numeric-address connector selects
the SSH endpoint and uses the saved SSH port.

Host-key verification precedes authentication. First use requires the existing
verification UI; changed keys fail closed. Desktop and Terminal share the saved
server key for the Mac, while their saved accounts, passwords and Terminal keys
remain separate. The relay has bounded reads, backpressure and a 256 KiB hard
queue limit. Cancellation retires pending handshakes; established native input
releases precede tunnel cleanup. Closing either forwarding endpoint closes the
SSH parent.

Setup, progress and recovery copy now explain the required built-in services and
SSH failures. The website source and generated local output are prepared for the
same behavior; they have not been deployed.

## Evidence

- The preceding isolated macOS probe completed verified SSH and real Apple ARD
  authentication against this Mac's built-in services after local user sign-in.
  It requested no framebuffer updates and sent no user input. Its running
  process had zero active TCP sockets after cleanup. See
  `Experiments/SSHScreenSharingProbe/EVIDENCE.md` for its aggregate-only record.
- A normal-source development app builds and launches on the iPhone 18 Pro Max
  Simulator (iOS 27). All **583** recorded application source inputs match the
  checkout. The app retains the existing development identities.
- The direct-client Simulator QA suite executes **195** tests: **182 pass**, 13
  opt-in capture cases are skipped and there are zero failures. OpenSSH encrypted
  export and sandboxed setup interoperability checks also pass.
- A final focused run passes all **8** SSH transport tests. They cover a 4 MiB
  transfer, queue bounds, handshake cancellation, custom Screen Sharing ports,
  first-use approval/rejection/cancellation, server loss, changed-key rejection
  before authentication, wrong passwords, denied forwarding, normal Desktop and
  Trackpad rendering/input, pause/resume on the same connection, balanced key
  release and cleanup.
- The Simulator tests use fresh synthetic SSH keys, credentials and a controlled
  RFB server. That server completes the client's ARD protocol exchange and emits
  a synthetic framebuffer; it does **not** verify macOS account authentication.
  Real Mac authentication is evidenced by the separate probe above.
- The settled verification sheet, connected Desktop and connected Trackpad
  screenshots were inspected. They contain synthetic data only and stay outside
  Git. They are test evidence, not replacement App Store artwork.
- Required `bash scripts/validate.sh` passes on stable Xcode, including all 133
  indexed fixtures. Website generation/checks and `git diff --check` pass.

## Reproduction and local artifacts

Normal Simulator output:
`/private/tmp/maccompanion-ssh-production-20261009-simulator/`.

Full QA command:

```sh
python3 scripts/verify_terminal_pro_simulator.py \
  --build /private/tmp/maccompanion-ssh-production-20261009-simulator \
  --simulator 2B7E5AB2-FBFD-4744-BA63-B79AB4E29AB5
```

Result bundles: `QA/Results.xcresult` and `QA/SSH-Final-UI-v2.xcresult`.
Logs: `/private/tmp/maccompanion-ssh-production-qa-driver.log`,
`/private/tmp/maccompanion-ssh-production-final-ui.log` and
`/private/tmp/maccompanion-ssh-production-validation.log`.
Final synthetic captures: `/private/tmp/maccompanion-ssh-production-final-ui-proof/`.
Disposable test sources remain under `Experiments/NormalVNCViewportQA/`, outside
application targets. The full run passed before Xcode's lengthy post-test
diagnostic collection; stopping only that diagnostic child allowed result
finalization with exit status zero. The final focused run disabled diagnostic
collection and completed normally.

## Remaining release checks

This is Simulator and prototype evidence. Physical iPhone acceptance of the
integrated tunnel, real Desktop/Trackpad gestures, app switching and performance
remains required. Both Remote Login and Screen Sharing must be enabled for these
modes. A new signed archive, upload and build selection must replace App Store
Connect build 25, which predates the encrypted transport. No upload, submission
or public release occurred during this integration.

Exact corresponding-source packaging and Apple distribution terms review remain
separate release gates. The development build report keeps
`releaseAdmitted: false`; this evidence does not override those gates.

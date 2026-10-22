# Terminal compatibility Simulator integration

The hosted tests use the production direct SSH client, terminal surface, and
pinned renderer. `TerminalCompatibilityTests` runs synthetic golden scenarios
over an authenticated SSH connection inside Simulator. The runner requires zero expected failures; the historical audit evidence retains
the original three reproduced gaps.

`TerminalToolIntegrationTests` optionally connects to this test-only host and
runs real tmux, Zellij, and Herdr binaries. Each case checks shell execution,
Unicode terminal text, output after resize, and persistence of a shell variable after
disconnect/reattach with the terminal focused and software keyboard open. It waits
for the pane prompt and a quiet period after focus/layout negotiation before
typing. Reattachment uses the production fresh-PTY reset with no harness reset.
It does not qualify splits, mouse/copy mode, nested editors,
graphics, hardware keyboards, physical iOS suspension, or arbitrary user configs.

Commands model separate paste and Return actions. The test sends the paste,
waits until the whole command is echoed in the renderer (ignoring whitespace
introduced by viewport wrapping), and then sends one native Return. Execution
and shell-persistence assertions still require their distinct output markers.
This sequencing avoids an independently reproduced Zellij 0.44.3 input-parser
limitation: when Paste and legacy Enter arrive in one stdin read, the first
parsed event drains the raw bytes and the following Enter can carry no bytes to
the pane. See the pinned [stdin parser](https://github.com/zellij-org/zellij/blob/v0.44.3/zellij-client/src/stdin_handler.rs#L147-L192)
and [pane forwarding](https://github.com/zellij-org/zellij/blob/v0.44.3/zellij-server/src/panes/terminal_pane.rs#L1271-L1280).
Coalesced paste plus Return remains unqualified by these staged cases. The
production transport is unchanged and does not enforce peer read boundaries.

## Run

Create a temporary Python virtual environment and install `requirements.txt`.
The dependency is for the loopback host only, not the app. Build the client using
`scripts/build_vnc_ios_development.py` and the normal managed-cache workflow.

```sh
/private/tmp/<venv>/bin/python scripts/verify_terminal_compatibility_simulator.py \
  --build /private/tmp/<build-evidence> \
  --simulator <booted-iOS-Simulator-UUID> \
  --output /private/tmp/<new-test-evidence> \
  --herdr /path/to/reviewed/herdr \
  --include-ui-regressions
```

tmux and Zellij default to installed binaries and are required. Herdr defaults to
an installed binary, or a reviewed explicit path; its test skips when unavailable.
The runner never downloads or installs a binary. `--include-ui-regressions`
adds five existing toolbar, number-row, palette and native-editing cases to the
nineteen terminal cases (24 total). The number-row test waits for UIKit menu
transitions and the resulting action rather than assuming a fixed animation delay. Record release hashes alongside
test evidence when providing a downloaded executable.

## Isolation and evidence

- The SSH listener binds only `127.0.0.1` on an ephemeral port. It uses a new
  in-memory Ed25519 host key and generated password. No key file, user account,
  user SSH configuration, forwarding, subsystem, or exec request is used.
- Each tool gets a generated session name, private configuration/data/runtime
  directories, and a test-owned Bash pane shell with user startup files disabled
  and a fixed readiness prompt. tmux additionally uses an exact
  private socket and no user config. Herdr receives an explicit config-path
  environment override. Shell history is disabled and its file is `/dev/null`.
  The PTY child acquires only its own controlling terminal.
- The authenticated tool name selects a fixed executable/argv; the host does
  not accept arbitrary launch commands. App input and output are forwarded in
  memory, without raw I/O recording. Only synthetic test commands are sent.
- Teardown closes the listener/transports and waits for client processes and
  bridge threads. Cleanup targets only the generated tool sessions/socket. The
  private host descriptor is unlinked to retire its test password. Caches, tool
  binaries, test roots, and xcresult evidence are retained.
- `run-summary.json` and `tool-host-report.json` report versions, test exit code,
  availability, cleanup and transport-error types. The XCTest log and xcresult
  remain under the build evidence's `QA/` directory. Inspect individual test,
  failure and skip results; exit code zero alone does not certify support.
  The runner also selects the existing first-trust/PTY/lifecycle and changed-key
  rejection regressions. It verifies the intended 19 or 24 cases from the xcresult
  summary, requires zero expected failures, and records executable SHA256 hashes. Timeout attachments contain only the
  dedicated synthetic test screen, never a user's terminal session.

The phased product work and broader acceptance matrix are in
`docs/terminal-compatibility-implementation-plan.md`.

Run the failure-path host regressions without a Simulator or real tool sessions:

```sh
/private/tmp/<venv>/bin/python -m unittest discover \
  -s Experiments/TerminalCompatibilityQA -p 'test_*.py' -v
```

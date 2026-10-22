# Terminal compatibility Simulator integration

Date: 2026-10-20. App baseline: `61c78ca`. Plan and test additions are on
`codex/terminal-compatibility-plan-tests`; production Terminal sources are unchanged.

## Verified result

Stable Xcode 27.0 (`27A266a`), iOS 27.0, dedicated iPhone 18 Pro Simulator
`53408DA2-E0E9-4780-BB2F-965B126195A2`.

The focused lane executed 12 cases: **9 passed, 3 strict expected failures,
0 unexpected failures, 0 skips**. XCTest and the wrapper both returned success.
The wrapper checked the xcresult case count rather than relying on exit status.

| Real tool | Version | Verified scenario |
| --- | --- | --- |
| tmux | 3.7b | Unicode command roundtrip, output after PTY resize, original shell variable retained across client disconnect/reattach |
| Zellij | 0.44.3 | Same scenario |
| Herdr | 0.9.5 | Same scenario |

The host records executable SHA256 hashes. The Herdr binary came from its
official v0.9.5 macOS arm64 release and matched published SHA256
`fb77c2232a05a8035421382c894392f4174e4e38a18e48af3dd0290157c3a7e2`.
No tool was installed globally.

The other passing cases cover real SSH delivery of legacy prefixes and arrows,
keyboard/cursor query replies, alternate-screen transitions and grapheme-aware
Unicode text, exact paste framing, resize, background/resume of the same PTY
without input replay, first-use trust ordering, and rejection of changed server
keys before password authentication.

## Known defects reproduced, not fixed

| ID | Strict expected failure |
| --- | --- |
| TC-RESET-01 | iOS replacement PTY inherits alternate screen, cursor, paste, mouse, and enhanced keyboard modes |
| TC-KEY-01 | Toolbar Escape sends legacy bytes while enhanced keyboard mode is negotiated |
| TC-KEY-02 | A quick-action prefix sends legacy bytes while enhanced keyboard mode is negotiated |

Each expectation is strict: an unexpectedly fixed assertion makes its test fail
until the marker is removed. This result does not establish complete tool support.

## Scope and isolation

- The actual app SSH owner, terminal controller, and pinned SwiftTerm renderer
  run inside Simulator. Real host binaries run behind a loopback-only Paramiko
  SSH server using an in-memory test key and generated password, not macOS Remote
  Login or a user SSH account.
- The host launches/reattaches each tool on the shell request. Product session
  discovery and automatic attachment remain planned.
- Live-tool cases focus the terminal, open the software keyboard, and wait for
  prompt/layout/capability negotiation. They explicitly reset the renderer
  before replacement SSH to isolate remote persistence from TC-RESET-01.
- Test-owned Bash shells disable user startup files and history. Configuration,
  data, runtime directories, multiplexer session names and tmux socket are private
  to each run. No user multiplexer session or SSH configuration is changed.
- All three exact-session cleanup commands succeeded. The report confirms no
  remaining client processes or bridge threads, and no transport error types.
  The generated host descriptor/password was retired. Test roots, evidence,
  binaries and build caches remain for review.
- No physical-device, hardware-keyboard, glyph-pixel, mouse/copy-mode, nested
  editor, graphics, macOS clipboard, or visionOS acceptance is claimed.

## Evidence and reproduction

The repeatable runner is `scripts/verify_terminal_compatibility_simulator.py`;
setup and boundaries are in `Experiments/TerminalCompatibilityQA/README.md`.
The only golden corpus is manifest-indexed
`spec/fixtures/terminal-compatibility-v1.json`.

Local evidence root:
`/private/tmp/maccompanion-terminal-compatibility-20261020/iphone-integration-6/`.
It contains `run-summary.json`, `xctest-summary.json`, `tool-host-report.json`
and `runner.log`. The result bundle is:

`/private/tmp/maccompanion-terminal-compatibility-20261020/build/QA/Results-1792506315644866000.xcresult`.

`bash scripts/validate.sh` passed on the same stable Xcode toolchain. Its retained
evidence is under
`/private/tmp/maccompanion-terminal-compatibility-20261020/validation/runs/20261020T140911Z-1413f4274e75/`.
The final manifest validation passed with 138 indexed JSON fixtures; Python
compilation and `git diff --check` also passed.

# Terminal compatibility implementation plan

Date: 2026-10-20. Initial baseline: `61c78ca`; PR integration base: `967e16e`. Scope: the direct SSH clients, with
iOS Simulator integration coverage first. This plan does not activate the
legacy Agent or change Observe, Act, Control, SSH trust, or credential grants.

Stage 1 has been executed: [Simulator evidence](evidence/2026-10-20-terminal-compatibility-simulator.md)
records nine passes and three strict expected failures across twelve cases,
including real tmux, Zellij and Herdr. The first iOS implementation milestone is
now verified in [the implementation evidence](evidence/2026-10-20-terminal-compatibility-implementation.md):
23 passing cases on both iPhone and iPad (18 terminal and five existing UI regressions), with no expected failures or skips, after independent review and main integration.
The fresh-PTY reset and explicit-key encoding portions of stage 2 are implemented.
macOS clipboard work and stages 3–5 remain future work.

## Outcome

A user can open a terminal on their Mac, operate a multiplexer or full-screen
tool with touch or a hardware keyboard, and deliberately return to an existing
remote workspace after losing the client connection. A fresh shell must start
with fresh emulator state. Background resume of the same shell must retain it.

## Delivery sequence

### 1. Establish repeatable integration evidence — this change

- Use the real iOS `DirectTerminalSession`, `TerminalController`, pinned
  SwiftTerm renderer, and authenticated loopback SSH; never replace those with
  mocked input encoders or decoded text transport.
- Keep all golden protocol bytes in `spec/fixtures/terminal-compatibility-v1.json`,
  indexed only by `spec/fixtures/manifest.json`.
- Verify legacy multiplexer prefixes, application arrows, terminal queries,
  alternate-screen transitions, Unicode output, resize propagation, paste, and
  same-PTY background resume without input replay.
- Reproduce fresh-shell mode inheritance and negotiated-key encoding gaps as
  strict XCTest expected failures. A passing audit suite with expected failures
  is not a compatibility pass. Remove each marker with its production fix.
- Offer opt-in real tmux and Zellij sessions behind a loopback-only test host,
  using a fresh in-memory SSH identity and generated test credentials. Report a
  missing Herdr binary as a skip, not support. No user SSH configuration,
  multiplexer sockets, or existing sessions may be used.
- Read displayed text through the renderer's grapheme-aware selection API;
  raw cell dumps contain wide-cell padding and cannot qualify Unicode rendering.
- Run the hosted suite on a booted iPhone Simulator with stable Xcode. Retain
  logs and xcresult outside Git. Run the repository validator.
- Include the existing first-trust/ordered-PTY/lifecycle and changed-key rejection
  regressions when running the full real-tool lane.

### 2. Fix compatibility boundaries

1. **Implemented and Simulator-verified on iOS.** Use a surface-visible PTY generation. Reset emulator/parser modes exactly
   once before rendering the first output of a replacement shell. Do not reset
   on palette changes, keyboard resize, foreground resume, or reattachment to
   the same live PTY. Retire old output and input callbacks before replacement.
   Install a fresh frontend to clear its private state; the renderer's RIS API
   intentionally retains some fields. Forward a preparation-time grid change
   when the writer becomes ready, ahead of fresh input.
2. **Implemented and Simulator-verified for explicit iOS input.** Route toolbar
   keys, quick actions and software-modified input through a policy using the
   same negotiated state as the pinned hardware frontend. Respect keyboard flags,
   cursor/keypad modes and modifier combinations. Preserve native hardware/IME
   delivery and one-shot/locked modifiers; physical keyboard qualification remains
   in stage 5. SwiftTerm's internal encoder is not a public app API. Include Escape, Enter, Tab, Backspace, function keys, and modified
   text; test press/release balance where requested. Do not change the pinned
   renderer merely to make a test green.
3. **Pending separate macOS work.** Add bounded, user-confirmed OSC 52 copying to macOS with the same admission
   and lifecycle fences as other local actions. Keep remote clipboard reads
   denied. Test cancellation, oversized requests, lock, and stale prompts.
4. **Completed for this iOS milestone; repeat for later behavior changes.** Update the normative direct-client specification and indexed golden vectors
   before shipping wire or security behavior changes. Convert expected failures
   into normal assertions and pass both iPhone and iPad Simulator lanes.

### 3. Make persistent workspaces easy to return to

- Save an explicit per-Mac terminal destination: plain shell or a named tmux,
  Zellij, or Herdr session. Default remains plain shell.
- Separate listing/attaching an existing session from creating a new session.
  Validate names and build tool-specific argv without interpolating untrusted
  terminal output into shell commands. Configure a custom tool path when needed.
- On transport loss, offer an explicit reattach action after normal SSH host
  verification and login. Never replay previous keystrokes, pasted commands, or
  arbitrary startup snippets. Missing tools and missing sessions remain visible.
- Distinguish Detach, Disconnect, and End Remote Session. Detach/disconnect must
  not be implemented by killing the remote multiplexer server. Ending a remote
  workspace is a separate explicit action with its scope visible.
- Test attach from a second client, detach/reconnect, a missing tool/session,
  spaces and punctuation in names, authentication failure, and changed host keys.

### 4. Improve phone interaction

- Provide a discoverable local text-selection mode alongside remote mouse
  interaction; test taps, drags, wheel events, copy, and leaving that mode.
- Expose in-memory terminal history search and Jump to Latest. Identify local
  history versus a multiplexer pane's remote history so search scope is clear.
- Add adjustable iOS terminal text size with per-Mac retention and stable grid
  resize. Verify CJK, combining marks, emoji, box drawing, and fallback glyphs;
  evaluate an appropriately licensed optional symbol font before bundling it.
- Offer editable multiplexer key presets. Respect user-defined prefixes and
  bindings, keep general terminal keys available, and avoid screen-text-based
  automatic tool detection. Actions use the common encoding policy from stage 2.
- Offer optional compact-layout guidance; do not rewrite remote configuration.

### 5. Qualify performance and publish support boundaries

- Exercise bounded output queues and scrollback under continuous build logs,
  frequently redrawing TUIs, slow readers, and stalled UI rendering. Bound memory
  and batch presentation work without dropping escape-sequence bytes.
- Audit truthful `TERM`, UTF-8 locale, true-color discovery, keyboard, focus,
  mouse, graphics, and passthrough capability replies. Claim only tested features.
- Add content-free diagnostics: app/renderer/tool version, PTY grid, active
  modes, connection phase, last peer evidence, and known qualification gaps.
  Do not export terminal output, input, paths, titles, or clipboard contents.
- Record versions separately for tmux, Zellij, Herdr, GNU screen/Byobu,
  Vim/Neovim/Helix, fzf/lazygit, top/htop/btop, and Yazi. Image previews require
  separate graphics and nested-multiplexer qualification.
- Keep physical iPhone/iPad hardware-keyboard, IME, sleep/lock, and network-route
  testing separate from Simulator evidence. macOS and visionOS need their own
  acceptance lanes; iOS results do not qualify their clipboard/focus behavior.

## Test commands

Build through `scripts/build_vnc_ios_development.py` as documented in
`docs/build-cache-workflow.md`, then run:

```sh
python3 scripts/verify_terminal_pro_simulator.py \
  --build /private/tmp/<terminal-build-evidence> --simulator <booted-UUID> \
  --only-testing DirectClientTests/TerminalCompatibilityTests

python3 scripts/verify_terminal_compatibility_simulator.py \
  --build /private/tmp/<terminal-build-evidence> --simulator <booted-UUID> \
  --output /private/tmp/<terminal-test-evidence>

bash scripts/validate.sh
```

The real-tool runner requires the test-only dependency in
`Experiments/TerminalCompatibilityQA/requirements.txt`. Pass `--herdr` when a
reviewed Herdr binary is available; the runner never downloads or installs tools.
Missing tmux or Zellij is an error. Synthetic protocol integration runs without
the external host; real-tool cases explicitly skip unless the runner supplies it.

## Completion criteria

- No unexplained failures, strict expected failures, or required-tool skips in a
  claimed support lane; enumerate remaining exceptions in the handoff.
- Exact source revision, toolchain, Simulator/runtime, tool versions, and
  synthetic test scope recorded with the result bundle.
- Test-owned SSH listeners, child processes, and exact multiplexer sessions are
  closed after success, failure, and interruption. No cache/evidence deletion.
- The complete stable-Xcode repository validation passes. Physical acceptance
  and store/release status are reported separately.

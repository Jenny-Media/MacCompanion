# iOS terminal compatibility implementation

Date: 2026-10-20. Initial baseline: `61c78ca`, on
`codex/terminal-compatibility-plan-tests`. The initial audit evidence is retained
in [the earlier report](2026-10-20-terminal-compatibility-simulator.md).

## PR review and main integration

The candidate is integrated onto `main` at `967e16e`. Three independent reviews
covered key encoding/native input, PTY lifecycle, and the integration harness.
After repairs, all three reported no remaining actionable findings. Existing
main-branch login, composer, haptic feedback and custom-input admission behavior
are preserved. Retired surfaces also revoke their direct custom-input admission.

Review repairs preserve marked composition, multi-character and non-ASCII native
commits; a hardware press clears software modifiers before the pinned frontend
handles its actual modifiers, repeat and release. This prevents IME text becoming
shortcuts and avoids a synthetic release on top of the hardware release. The
encoder retains uppercase Alt identity and completes Ctrl-/ and Ctrl-~ mapping
in partial enhancement modes. The authoritative fixture now has 41 encoding
vectors plus native-input scenarios. The existing Alt shortcut vectors include
the requested release for discrete synthetic actions.

The test host resolves executable paths before changing its working directory.
Teardown attempts every generated session after timeout or launch errors,
retires its credential descriptor and writes sanitized failure evidence. Five
deterministic host regressions verify these failure paths without real sessions.

Fresh stable-Xcode verification after review:

| Lane | Result |
| --- | --- |
| iPhone 18 Pro | 23 passed, 0 expected failures, 0 failures, 0 skips |
| iPad Pro 13-inch (M5) | 23 passed, 0 expected failures, 0 failures, 0 skips |
| Host failure-path regressions | 5 passed |
| Adjacent SSH, shortcut and haptic regressions | 57 passed, 1 saved-login scenario failed, 0 skips |

Each 23-case lane includes 13 protocol/native-input regressions, three real-tool
cases, two existing SSH trust/lifecycle cases and five existing UI checks. Both
tool hosts verify descriptor retirement, all exact-session cleanup commands,
zero remaining clients/bridge threads and no transport errors. The production
build hashes match all three changed Terminal sources.

The first reviewed iPhone pass exposed a keyboard-observation test defect:
the first palette assertion had an uninitialized notification frame while
later palette changes supplied it. Its isolated reproduction is retained. The
test now observes both keyboard presentation and frame changes and waits for
settled notification-derived geometry. Its original visibility, exact dock
position, responder, controller and preserved-output assertions remain intact.
Compatibility teardown ends editing before hiding its window.

The adjacent run contains all 24 non-capture haptic checks, three shortcut
checks and 31 existing SSH cases. The saved-login/Pro scenario first failed to
load its synthetic StoreKit product. An isolated diagnostic prepared StoreKit
before UI, waited for trust presentation/dismissal and inspected the actual
controller tree. StoreKit then became ready, but the hosted NavigationStack
remained empty after authentication. The identical strengthened diagnostic
reproduced this blank-controls failure using all three Terminal production
sources from `main` at `967e16e`, with their hashes independently checked against
Git and both test/source preservation recorded. This is a baseline Simulator UI
limitation. The original saved-login test is unchanged in the PR, and no skip or
expected-failure marker hides it. Failed diagnostic results are retained.

A first-frontend-adoption experiment also reproduced the failure and was fully
reverted. The final product retains the reviewed replacement policy. The
diagnostic runner, variant sources, screenshots and strengthened test copy remain
outside the committed changes. Physical acceptance and the saved-login/Pro
Simulator journey remain separately unqualified.

Reviewed evidence root: `/private/tmp/maccompanion-terminal-review-20261020/`.

- Production build: `build/runs/20261020T160435Z-9a599dba2c5a/`.
- iPhone: `iphone-2/run-summary.json`, `xctest-summary.json`, `tool-host-report.json`.
- iPhone xcresult: `build/QA/Results-1792512686495430000.xcresult`.
- iPad: `ipad/`, with the same report names.
- iPad xcresult: `build/QA/Results-1792512756659154000.xcresult`.
- Host failure-path regression log: `host-regressions.log`.
- Adjacent run: `adjacent-regressions/run-summary.json`, `xctest-summary.json`;
  xcresult `build/QA/Results-1792512838543323000.xcresult`.
- Controlled main-source baseline: `baseline-saved-login/baseline-report.json`,
  `baseline-source-verification.json`, `source-preservation.json`,
  `xctest-summary.json`, `test.log` and synthetic attachments. Its xcresult is
  `build-adopt/QA/Results-1792513969340025000.xcresult`.
- Stable repository validation: `validation-final/runs/20261020T161349Z-cd764ad5faa5/`;
  status passed, 139 indexed fixtures.
- Initial 22/23 run and isolated keyboard-observation failure: `iphone/` and
  `keyboard-layout-isolation.log`; their failed results are preserved.

The sections below retain the original implementation and screenshot evidence
before PR review and main integration. Their 21-case counts and screenshots
describe that earlier source state.

## Original implementation

- The SSH owner publishes the replacement PTY generation before admitting input
  or rendering its first output. The iOS controller installs a fresh pinned
  SwiftTerm frontend and keyboard bar once for that generation. This resets
  parser/UTF-8 state, buffers, cursor visibility, cursor/keypad, mouse protocol,
  paste and enhanced keyboard modes, preedit and pending physical-key state.
  The renderer dependency and SSH authentication are unchanged.
- The retired frontend loses its delegate and focus callback before native
  responder/composition cleanup. Input, link and clipboard callbacks
  require the current view and connection generation; resize rejects retired views. Consent actions also
  recheck the generation and unlock state. Old queued writes and composer
  completions retain the SSH owner's existing rejection fences.
- Palette changes, resize and same-PTY background/foreground keep the frontend,
  modes and shell. They do not install a replacement or replay input.
- Explicit toolbar/menu keys, saved shortcut chords and software-modified
  text/deletion use one policy driven by the renderer's negotiated flags and
  application cursor mode. It covers legacy keys, disambiguation, event pairs,
  alternate values and associated text. Physical key delivery and IME bookkeeping
  remain in the pinned frontend. Literal paste/snippets retain their own framing.
- Normative direct-client requirements and manifest-indexed byte vectors were
  updated before production encoding changes. The three expected-failure markers
  and the real-tool harness reset were removed.

## Original verification

Stable Xcode 27.0 (`27A266a`), iOS 27.0. Test commands use the managed compiler
workspace; evidence and test host resources stay outside Git. `bash scripts/validate.sh`
passed on the final implementation, with 138 indexed fixtures. The saved build's
input hashes match all three changed production Terminal sources. Python
compilation and `git diff --check` also passed.

| Lane | Result |
| --- | --- |
| iPhone 18 Pro | 21 passed, 0 expected failures, 0 failures, 0 skips |
| iPad Pro 13-inch (M5) | 21 passed, 0 expected failures, 0 failures, 0 skips |

The combined lane has 16 terminal cases (all original 12 and four added
regression cases), plus five existing toolbar, number-row, palette and native
editing checks. The number-row harness now waits for UIKit transition completion
and the resulting action rather than relying on fixed animation delays.
The negotiated-key test exercises 36 indexed byte vectors, including individual
and combined enhancement flags, modifier combinations, function/navigation keys,
press/release pairs, uppercase and expanding Shift text, and the real session
menu handler. Lifecycle regressions cover incomplete CSI/OSC/DCS/APC/UTF-8,
composition discard, retired view/callback rejection, stale queued input and
composer rejection, plus preservation of the live frontend on palette/resume.
Fresh-mode query replies verify visible cursor and cleared focus/mouse protocols.
The replacement case also verifies a grid changed during surface preparation is
forwarded once the writer exists. This race was reproduced against the preceding
build before the owner was corrected; its failure is retained in
`build/QA/Results-1792508667059964000.xcresult`. The ready callback now also
rechecks the generation after surface preparation, before publishing the writer.

Real-tool cases run tmux 3.7b, Zellij 0.44.3 and Herdr 0.9.5 through the app's
SSH owner and renderer. They check Unicode shell execution, output after resize
and retained shell state after explicit disconnect/reattach. There is no manual
renderer reset. Each lane owns private loopback credentials, sockets, session
names, configurations and history-disabled pane shells; it uses no user SSH
account or existing multiplexer session. Tool reports retain executable hashes.
Both tool reports verify all exact-session cleanup commands succeeded, no
remaining clients or bridge threads, and no transport errors.

## Local evidence

Root: `/private/tmp/maccompanion-terminal-compatibility-20261020/`.

- Production build: `build/runs/20261020T150751Z-4047efd944ab/`.
- iPhone: `implementation-iphone-2/run-summary.json`, `xctest-summary.json`,
  `tool-host-report.json`, and `runner.log`.
- iPhone xcresult: `build/QA/Results-1792508996736897000.xcresult`.
- iPad: `implementation-ipad-2/`, with the same four report/log names.
- iPad xcresult: `build/QA/Results-1792509280092945000.xcresult`.
- iPhone Simulator: `53408DA2-E0E9-4780-BB2F-965B126195A2`.
- iPad Simulator: `C718A088-9E5D-49FA-9717-F1EE5F0EAA96`.
- Repository validation: `implementation-validation-final-2/runs/20261020T150911Z-12512d5a06bb/`.

## Prior-stage screenshot review

Six unedited whole-Simulator PNGs were captured with `simctl io screenshot`
after the real-tool tests verified disconnect/reattach and `MCQA_PERSIST_kept`.
The terminal controller, renderer, dock and system keyboard are live. Test
content and sessions are synthetic; the tool binaries are real. The optional
test-only capture pause does not change production sources. Screenshots remain
outside Git. They show the rendered result; byte encoding and rejection of
stale input are established by the test assertions rather than by pixels.

| Tool | iPhone 18 Pro | iPad Pro 13-inch (M5) |
| --- | --- | --- |
| tmux 3.7b | [Screenshot](/private/tmp/maccompanion-terminal-compatibility-20261020/screenshots-iphone/images/iphone-tmux-reattached.png) | [Screenshot](/private/tmp/maccompanion-terminal-compatibility-20261020/screenshots-ipad/images/ipad-tmux-reattached.png) |
| Zellij 0.44.3 | [Screenshot](/private/tmp/maccompanion-terminal-compatibility-20261020/screenshots-iphone/images/iphone-zellij-reattached.png) | [Screenshot](/private/tmp/maccompanion-terminal-compatibility-20261020/screenshots-ipad/images/ipad-zellij-reattached.png) |
| Herdr 0.9.5 | [Screenshot](/private/tmp/maccompanion-terminal-compatibility-20261020/screenshots-iphone/images/iphone-herdr-reattached.png) | [Screenshot](/private/tmp/maccompanion-terminal-compatibility-20261020/screenshots-ipad/images/ipad-herdr-reattached.png) |

Capture runs each passed all three tool cases, with zero expected failures,
failures or skips. Both hosts verified exact-session cleanup and zero remaining
clients/bridge threads. Under the evidence root, `screenshots-iphone/` and
`screenshots-ipad/` each contain `capture-manifest.json` (UTC timestamps, device
IDs, PNG SHA-256 hashes and result-bundle path), `xctest-summary.json`,
`tool-host-report.json` and `runner.log`. Their xcresults are respectively
`build/QA/Results-1792510278487384000.xcresult` and
`build/QA/Results-1792510453250786000.xcresult`.

`bash scripts/validate.sh` passed again after adding the opt-in capture hook:
`screenshot-validation/runs/20261020T153125Z-3648f87ecd77/`.

## Acceptance boundary

This is Simulator evidence with a dedicated loopback test host. It does not
qualify physical iPhone/iPad hardware keyboards, real IME keyboards/dictation,
sleep/lock/network changes on hardware, built-in macOS Remote Login acceptance,
glyph pixels, mouse/copy mode, nested editors, graphics or arbitrary tool configs.
No macOS/visionOS compatibility claim follows from these iOS results. macOS OSC 52
copy and named persistent workspace UX remain later milestones. Test-owned
Simulator devices, caches and evidence are retained for review; none were deleted.

Reproduce the final combined lane with the temporary test-host Python environment:

```sh
/private/tmp/<venv>/bin/python scripts/verify_terminal_compatibility_simulator.py \
  --build /private/tmp/<managed-build-evidence> \
  --simulator <booted-iPhone-or-iPad-UUID> \
  --output /private/tmp/<new-evidence-directory> \
  --herdr /path/to/reviewed/herdr --include-ui-regressions
```

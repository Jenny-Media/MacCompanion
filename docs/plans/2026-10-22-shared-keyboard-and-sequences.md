# Shared iOS keyboard controls and shortcut sequences

## Outcome

Use one compact keycap design and one customization editor across Terminal,
Screen Sharing, and Trackpad & Keyboard. Keep two device-local layouts: Terminal,
and Remote Mac (shared by both desktop modes). Existing Terminal controls and
saved content retain their identity and placements.

## Implementation order

1. Extend the saved-shortcut model with bounded, ordered key/chord/text steps.
   A missing steps field continues to mean the existing single chord. Guard the
   new format against older writers without discarding saved definitions.
2. Add a device-local Remote Mac profile and capability context to the existing
   editor. Reuse row placement, drag/drop, alignment, scroll-start, undo, and
   favorites behavior. Screen Sharing and Trackpad load the same profile.
3. Share the actual UIKit keyboard bar with both session adapters and its editor
   preview. Use soft backgrounds, blue glyphs, 44-point minimum targets, strong
   active modifier fill, and an underline for held modifiers.
4. Give remote modifiers the same tap/long-press behavior as Terminal. Add
   Keypad → Send Modifier Alone with explicit Control, Option, Shift, and Command
   actions; these send balanced independent events and can be pinned.
5. Extend the existing shortcut editor with Add Step, tap-to-edit, drag reorder,
   duplicate/remove, and a readable keycap sequence preview. Keep one-step
   creation simple and Saved Text in its separate library. Inline text steps
   do not create another saved-text definition. Add complete tool actions beside
   individual tmux/Zellij/Herdr prefix and mode presets.
6. Execute a preflighted sequence through the session's existing ordered input
   owner. Review the entire sequence before sending any text-containing step.
   Return is explicit. Chords release their own modifiers and preserve the user's
   armed/held controls. Prevent competing user input while sending, cancel on
   lock/background/disconnect/generation change, and never resume in a new session.
7. Add regression coverage, exercise the editor and runtime flows on dedicated
   iPhone/iPad Simulators, inspect screenshots, and repair discovered issues.
8. Run repository validation and native checks on one unchanged source state,
   then use fresh independent two-stage review, repairing accepted findings and
   revalidating within the review skill's four-round limit.

## Acceptance and limits

- One shared visual representation in live bars, pickers, and layout previews.
- Remote Mac includes Command and modifier-alone actions; Terminal rejects
  unsupported encodings before any part of a shortcut is sent.
- Shortcuts contain 1–32 steps with bounded text and encoded output. Editing
  never sends input. Unsupported steps reject the whole operation before start.
- Sequence cancellation and queue ordering use connection-owned admission,
  with no replay and no implicit Return or arbitrary delay/condition steps.
- Saved Terminal layouts, snippets, shortcuts, duplicate placements, and their
  identifiers survive the model extension.
- Required checks: `bash scripts/validate.sh`, the managed iOS Simulator source
  build, native DirectClientTests, focused new-runtime regression checks, and
  interactive iPhone/iPad journeys with screenshot evidence. Use Xcode.app and
  the managed stable compiler caches throughout.
- Simulator proof does not establish physical haptics or real remote-tool
  acceptance. These remain separately reported limits.

This work does not diagnose the deferred intermittent Common Shortcuts picker
issue, redesign macOS/visionOS, change authentication or the wire protocol, add
cloud settings, or publish/install a release. The implementation workflow keeps
the protected baseline, complete check manifest, stable source fingerprints,
and review ledger in external working evidence; screenshots are never committed.

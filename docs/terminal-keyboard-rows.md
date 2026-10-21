# Terminal keyboard rows and All Keys

The terminal keeps the same configured controls when the native keyboard is
shown, hidden, or rotated. These are shared settings for all Macs on this device.

- Main is always available, with the keyboard toggle fixed at the left and the
  floating menu at the right. Esc, Tab, Ctrl, Option and Shift use compact symbols.
  Quick up/down arrows are enabled by default. Command is optional and requires
  negotiated support from the remote application; existing saved Command chords
  retain their original definition.
- Numbers have an independent 1–0 row above Main by default. The number toggle
  shows/hides this row. Whole rows can be reordered in Customize Controls.
- Expand Rows explicitly reveals Navigation and any configured custom row.
  Up to two extra rows can be configured. Expansion is saved and does not depend
  on the native keyboard’s visibility. Removing a row removes its placements,
  keeping saved definitions and floating-menu placements.
- Keypad opens the built-in All Keys catalog at the native medium sheet height;
  drag the grabber to expand. Accessibility text sizes start at full height and
  use a menu picker. Searching on a regular-width window expands the keypad
  and retains that height through keyboard dismissal. Search keys or groups including Essentials,
  Navigation, Function Keys, Common Shortcuts, Symbols and Numbers. Every built-in
  key is usable without Pro or customization. Tap sends once and leaves the
  sheet open. Modifier buttons expose Off, Next Key and Locked states.
- Hold a key for optional Pin to Keyboard Bar / Pin to Floating Menu. Pinning
  requires Pro, sends nothing and reuses the same saved definition. The visual
  editor selects items for editing without acquiring session input.
- Shortcuts and Text remain separate floating-menu entries and use the same
  collection as the keypad’s saved-item tabs. Saved text opens the composer for
  review. Explicit Send Text adds no Return, and line breaks/tabs require
  confirmation. An unsent draft is kept unless replacement is confirmed.

## Regression coverage

`TerminalControlsProfileTests` covers old v1 records and per-Mac snippet migration,
row order/placement round trips, shared identities and Command preservation,
invalid layouts, optimistic saves and write failures. `TerminalControlsUITests`
covers fixed controls, independent number/extra rows, negotiated Command, pinning
without input and stale presentation rejection. Terminal encoding assertions use
`spec/fixtures/terminal-compatibility-v1.json`, including Insert and modified Insert.

`Experiments/TerminalControlsQA/TerminalControlsJourneyTests.swift` drives native
phone/tablet UI against a synthetic loopback SSH host. It captures compact and
expanded bars with native keyboard shown/hidden, All Keys at medium/large sheet
heights, search, modifier states, context-menu pinning, text review, row editing,
Save/Cancel, rotation and accessibility text sizes. The harness is not linked into
release targets. Screenshots and xcresult bundles remain outside Git.

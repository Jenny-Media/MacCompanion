# App and Window Focus: local owner check

Date: 2026-09-23

## Change

The menu-owned Accessibility reader now obtains the focused element's local
process ID before treating a focus sample as verified. While the selected
surface is one application or window, the menu compares that ID with the
locally retained capture target owner. A focused region derived from an app or
window retains this check. Missing or different IDs produce a Desktop focus
recommendation without a focus token. The same check runs again when a
focused-region replacement is resolved, so an intervening cross-app focus
change cannot claim the old target.

No process ID enters the Agent, iPhone, focus event, audit, or persisted
record. The policy and its eleven cases are recorded in the normative focus
event specification and the single indexed fixture corpus. The cross-app
confusion case is recorded in the project threat model for security review.

## Local verification and remaining evidence

The authoritative fixture validator passed with 90 indexed JSON fixtures.
The focused package test and the focus-related test filter passed with the
normal macOS toolchain. `bash scripts/validate.sh` passed the fixture,
repository-material, dependency, target, privacy, and signing-policy stages,
then stopped at the fixed missing
`/Applications/Xcode-beta.app/Contents/Developer/usr/bin/stapler` path.
The gate was not changed or waived.

This is a local fallback fix. On 2026-09-23, a signed development build
containing this change was installed into the normal Mac app and embedded
Agent. Both processes launched from the updated installation. A physical
cross-app modal has not yet been exercised. AX timeout, secure-field,
custom-drawn-app, and compatibility acceptance remain open.
The security-focused review required for focus/privacy changes is also open.

# Credential-form lifecycle audit and fixes

Scope: macOS, iOS/iPadOS and visionOS direct clients on main 876be88 plus
this branch's Terminal/Files changes. No real credentials were read for tests.

## Expected behavior

After an established password session ends, Remember on restores the same saved
account/password while active and unlocked. Remember off returns to blank
password-account and password fields. Returning to sign-in never opens a
replacement connection. Unchecking during entry preserves credentials needed
for that pending attempt. Failed/cancelled initial sign-in preserves its draft.
Manual edits/clears must not be overwritten by incidental refresh. Privacy
suspension clears visible secrets and defers saved reads until access is allowed.
SSH key account associations and one-connection passphrases are separate from
password retention.

## Resolved findings

| Interface | Change |
| --- | --- |
| macOS Terminal | Shared draft restores remembered fields after disconnect, clears unsaved password accounts, and preserves edits over lock/wake and incidental refresh. A same-key refresh no longer resets an edited key account. |
| macOS standalone Files | Only an established independent login triggers unsaved-field cleanup on disconnect. Borrowed Files has no form; authenticated account and completed/retry transfer ownership remain intact. |
| Retained macOS embedded Screen Sharing view | The same draft restores saved or clears unsaved fields after disconnect. Initial one-shot auto-connect remains separate from passive form restoration. Apple's external Screen Sharing app owns the shipping action's login UI. |
| iOS/iPadOS Terminal | Shared draft clears the displayed successful-login secret and restores saved or clears unsaved fields after an unexpected shell end. Paused reads and the live SSH shell remain owned by the existing session. Normal shell exit still navigates out; no replacement shell is opened automatically. |
| iOS/iPadOS Screen Sharing and Trackpad | `DirectDesktopLoginState` separates form state from private attempt/recovery credentials. One bounded automatic resume/replacement can use its active owner's credentials even after the visible secret is cleared. Final failure, explicit exit, and login replacement retire recovery material. |
| visionOS Screen Sharing and Terminal | Preserve method/account and non-secret saved provenance; restore after unexpected disconnect or unlock. Explicit disconnect and unexpected end share the same policy without auto-connect. |
| Password/key switching | Accounts are isolated per method, including empty accounts and removed keys. Successful key authentication preserves only an unedited saved password's restoration provenance. Unsaved or explicitly cleared secrets cannot reappear. |

Cancelling Login & Access no longer reloads the saved profile into an unsaved
session draft. Only a successful Save/Forget notifies the Terminal or desktop
form; failed/stale saves and privacy dismissal do not.

## Validation boundary

Canonical form-return journeys are indexed only in `spec/fixtures/direct-files-v1.json`
and run in native Mac, iOS and visionOS hosted tests. Native Mac tests additionally
mount real credential fields and exercise loopback SSH/SFTP. iOS tests exercise
the actual viewer's bounded replacement, form cleanup, and the hosted Terminal's
same-shell pause and unexpected-end behavior. Existing shared access, borrowed
Files, shell completion, input ordering, and interrupted-composer tests remain
part of the targeted regression run. Exact results are retained in the task's
build/test evidence. Physical Mac/iPhone acceptance follows installation;
no physical Vision Pro was used.

Final stable-Xcode run: 47 native Mac, 70 iPhone simulator, 23 iPad simulator,
and 19 visionOS simulator tests passed (159 total), plus `bash scripts/validate.sh`.
The iOS Terminal regression inspects the actual view-bound observable form owner
through successful authentication, same-shell pause/resume, and an unexpected
transport end; it does not depend on SwiftUI's private UITextField hierarchy.
The signed Mac development app and iPhone development build 1.0 (73) were
installed and launched. Physical credential/recovery acceptance remains with the
user. Detailed run records are under
`/private/tmp/maccompanion-credential-forms-20261015`; a compact copy is in the
chat's `maccompanion-credential-forms-20261015` evidence attachment directory.

## Interfaces with different semantics

- Login & Access is a management editor for the authoritative retained profile,
  rather than a session-return form. It deliberately displays retained data.
- Files opened from a live session borrows that connection without another login.
- Key setup has a one-off bootstrap password and no Remember contract. Disk-key
  passphrases are never restored for a new connection.
- Apple's external Screen Sharing app owns its own credentials.

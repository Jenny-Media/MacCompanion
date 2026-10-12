# Files acceptance checklist

Files is a free companion to existing sessions on iOS and macOS. It uses the
saved Mac's Remote Login port, SSH host trust, account and key selection. It does
not introduce a connection mode or require a Mac Companion helper.

## Physical device and Mac checks

- Open Browse Files from a saved Mac, and Files from Desktop or Terminal.
  On iOS also check Trackpad & Keyboard. Verify the Mac and SSH account are clear.
- With Screen Sharing enabled and Remote Login disabled, open Files. The Desktop
  must continue working; Files must explain the Remote Login requirement without
  claiming every network failure means it is disabled.
- Test password autofill, a saved Terminal password, an existing named SSH key,
  and on macOS a key referenced directly from disk, including a passphrase.
  Turn Save SSH Login off after saving a password. The old login must be removed
  while the Mac's SSH host trust and keys remain available.
  Sign in with a named key and a newly entered or changed account. Close Files,
  then open fresh Files and Terminal views: the successful account must appear.
  Rejected sign-ins must not save the account. Change or remove the selected key,
  or edit its saved account in another window during connection; the newer setting
  must remain after the pending connection completes.
  Before connecting with a selected SSH key, edit Files' account, open the key
  chooser and rename a key or choose the free key. The displayed name must refresh
  while the edited account remains. Selecting a different key or Use Password Login
  must still update the sign-in selection. Repeat on iPhone and Mac.
  Repeat with a macOS key referenced from disk in both Files and Terminal. While
  trust or authentication is pending, edit its saved account, reselect its file,
  switch keys or remove the selection in another window. The connection may
  finish using its original login, but newer settings must remain and no disk key
  may be imported into Keychain. Reconnect explicitly with a second account and
  verify it is retained when no newer edit occurs. Cancelled and rejected logins
  must leave the saved account unchanged.
  Keep Files open through a successful saved-password connection, Disconnect and
  network loss. The saved password must be available for explicit reconnect in
  that same view. Edit the retry account/password, then cancel or fail a connection:
  the draft must remain. On iPhone, backgrounding must defer restoration until
  the app is active and unlocked. Removing the saved login must prevent restoration.
  With App Unlock off, background and return both before the first connection
  and after Disconnect. The remembered password must refill without re-entry or
  automatic connection. Repeat the round trip twice in the same Files sheet.
  Repeat with App Unlock on: secrets must remain cleared until active and
  unlocked, then restore only an unchanged remembered login. Edited accounts,
  Password/Key selection and an off Save Login choice must survive unlock.
  An edited or explicitly cleared password must not be replaced with an older
  saved password. Removing the saved credential while suspended prevents refill.
  Edit the account, Password/Key method and Save Login choice, hide retained Files
  with Done or swipe, then reopen from Desktop, Trackpad or Terminal. Repeat twice:
  non-secret choices must survive and saved defaults must not replace them.
  Repeat with named keys and a referenced Mac key file. A different Files owner
  must keep independent choices. Hide during a saved-password connection and
  reopen after it completes; Disconnect must restore that successfully saved
  login without restoring an older password after a failed save or newer edit.
  Inject a local credential-write failure after successful SSH/SFTP admission:
  an unchanged, already saved password must remain available after Disconnect.
  An edited password must not restore the older stored password. Repeat with
  Files hidden during authentication and with the saved login removed before
  returning. Failed/cancelled authentication and newer edits must keep their draft.
  With App Unlock off, let the Mac display sleep while the app stays active.
  Display/session wake must enable explicit Files reconnect without switching
  apps. Repeat while locked: credentials must wait for unlock. Closing the owner
  must clear its transient draft and secret restoration context.
  On Mac, type a disk-key passphrase, then select a different key or remove the
  selection before Connect. The previous passphrase must clear. Reopening the
  chooser with the same key must preserve it and any edited password draft.
  Repeat selection/removal from another Mac window with Files already open,
  including during key preparation, connection and an already connected session.
  After cancellation/failure or Disconnect, the current selection must appear without
  restoring an old password or saved-login choice; the old key must not connect.
- Check first-use SSH fingerprint approval, rejection, and a changed fingerprint.
  Authentication rejection must not send credentials to a fallback address.
- Browse Home, nested folders and Up. Create a folder and refresh. Check denied
  directories, an empty directory, and a directory beyond the 10,000-entry limit.
  Listings beyond the aggregate 16-MiB UTF-8 metadata budget must be rejected,
  including oversized longnames and extended attributes in otherwise valid packets.
  A slow listing that continues responding must remain connected; a stalled
  response must time out and offer an explicit reconnect.
- Upload individual files from local Files and iCloud Drive on iPhone. On Mac,
  check the file chooser and drag and drop. A folder or symbolic link must be
  rejected. Review the Mac, account, folder and filenames before uploading.
- Change the upload destination after selecting files. The selected files should
  remain ready for review; cancel must not upload anything and must remove only
  its prepared local copies. Select a regular file followed by a folder or link:
  rejection must release the earlier copy and preserve the original. Replace a
  selection or disconnect while preparing/reviewing; abandoned copies must be
  released, while sources already adopted by transfer results remain for retry.
- Test new files, Keep Both, Replace and Cancel, including an empty file, a Unicode
  filename, a 255-byte filename and a large file. Confirm the original survives a failed replacement.
  Links and directories must not offer replacement.
  Also replace an existing file with an empty file in a long nested folder.
  Encoding valid paths must not crash, regardless of the transfer's byte count.
- Download a file and save it through the native chooser, including iCloud Drive.
  Cancel Save and confirm the download remains available. On Mac test replacing
  a local file and saving the same download again.
  Until Save or explicit Discard, another transfer must not replace the download.
  Discard must leave exported files and the user's original upload files intact.
  Change a listed regular file to a symbolic link on the Mac before downloading;
  Files must reject it without downloading the link's target.
- Interrupt a transfer with a network loss, explicit cancellation, app lock,
  iPhone backgrounding and window/session closure. Confirm explicit reconnect and
  retry are required, completed files are not replayed, and a partial download
  cannot be saved. A failed upload may leave its hidden temporary file on the Mac.
  Confirm Disconnect during a transfer keeps Files open with its Save/Retry
  results. Confirm Done warns before closing an independent Files owner with
  unsaved downloads or interrupted transfers. Cancel must keep them available.
  Swiping a standalone iPhone Files sheet or using the Mac window close control
  must be blocked while these results remain. Confirmed Done must still close.
  On Mac, one Done → Close Files confirmation must close that window immediately;
  Cancel must keep the download available, and another Files window must stay open.
- With a saved SSH password, edit Files' account/password and turn Save SSH login
  off. Open Setup Guide and dismiss it; the edited fields and off choice must stay.
- Leave Files open while editing the saved Mac's name, addresses or SSH port in
  another window. Its title, review and reconnect must keep the owner's original
  record. A newly opened Files owner must use the edited record.
  Remove the record locally or through sync with an unsaved Files download.
  All matching Desktop, Terminal and Files connections and pending logins must
  stop. Their windows/presentations close, except Files with unsaved completed
  downloads: it keeps its identity and offers only Save/Discard, then closes.
  Reconnect and Retry must be unavailable for both free and Pro users. Downloads
  already exported remain intact. Other Macs' sessions and My Macs stay open.
  Repeat from iPhone Desktop, Trackpad, Terminal and standalone Files, including
  a retained Files sheet hidden when removal arrives. Rejecting or failing library
  persistence must not publish removal or close sessions. Opening a new Files
  window for the missing record must show Mac unavailable.
- Stop only the SFTP subsystem while SSH remains connected. Files must show
  disconnected, retain pending downloads/retries and require explicit reconnect.
- Reconnect as a different account. Previous interrupted files must not retry
  under the new account; discard the old batch before a fresh reviewed upload.
- Keep a Desktop and Terminal connected during file transfers. Closing Files
  must leave those sessions usable. Test two independent Mac Files windows.
- Open first-use SSH identity prompts in two sessions for the same saved Mac.
  Approving a different key in the second session must make the older prompt
  fail without replacing the saved identity or sending its login credentials.
- Hide connected iPhone Files with Done, reopen it, then disconnect. Saved SSH
  login/key choices must appear for explicit reconnect. Further interruptions
  must preserve an edited sign-in draft.
- At normal and accessibility text sizes, check that account, path, progress,
  conflict choices and transfer results remain readable and controls reachable.

No uninterrupted iOS background transfers or automatic resume are promised.
Rename, delete and entire-folder transfers are deferred.

## Local automated coverage

`DirectFilesTests` checks the indexed path and wire vectors, chunked transfers,
close-before-publish ordering, failure cleanup, original preservation, truncated
and special-file downloads, fresh path/handle admission, and native staging
admission, standalone/retained dismissal, and owner-record presentation. The
local staging cases replace a regular path with a link or FIFO before opening,
and replace it with a link after opening: rejected batches roll back and admitted
copies keep reading the original descriptor. Named-key account cases preserve
newer key/account choices and removed associations without recreating keys. The
fixture is indexed only in `spec/fixtures/manifest.json`. Indexed Keep Both cases
cover exact UTF-8 spellings and suffix allocation, including full-length names,
emoji and composed/decomposed Unicode. Embedded-channel decoder cases cover
the extended metadata count bound and malformed counts below the packet-size cap.
Encoder vectors cover string-length prefixes at buffer-capacity boundaries and
the retained OPEN/CLOSE/replacement sequence of an empty upload.
Indexed loopback SFTP responses cover the aggregate metadata cap, exact UTF-8
boundaries, longnames and extended attributes. Directory handles must close on
both successful listings and budget rejection.

`DirectFilesIntegrationTests` uses a disposable loopback SSH test transport with
macOS's `/usr/libexec/sftp-server`. It exercises browsing, folder creation,
uploads, conflicts, atomic replacement, downloads, independent owners, interruption,
account-bound retry, pending-download preservation and discard,
local/synced record removal in a mounted window, full-length Keep Both collisions,
independent SFTP subsystem closure and explicit reconnect,
empty replacement in a boundary-length folder, distinct Disconnect/Done
behavior, confirmed pending-result cleanup, saved-password
removal, admission and missing-destination response activity, progressing and
stalled responses, stale-link rejection, app-lock/background retirement, host-pin
rejection, competing first-use approvals before authentication, SFTP startup after
authenticated SSH closure, deferred initial login in a reopened connected view,
successful named-key account retention in a freshly mounted Files view and
Terminal login selection, rejected key logins and changes while trust is pending,
and separate authentication/SFTP failure guidance. This transport exists
only in the hosted test target; neither release client includes a server or subprocess.
Indexed disk-key account cases run real SSH authentication through both Files and
Terminal. They cover first/changed accounts, repeated connections, rejection and
cancellation, plus account edits, changed file references, key switches, association
removal and key deletion during first-use trust. Newer settings remain intact and
successful disk-key connections never import private key material into Keychain.

`DirectFilesPresentationTests` captures normal and accessibility layouts on both
platforms and mounts Mac login fields to exercise external disk-key selection,
removal and unchanged-reference notifications while preserving edited drafts.
It also mounts the iPhone sign-in form during an owned pending SSH handshake to
verify saved credentials load when sign-in becomes available.
Both platforms also mount Files before its first saved-password connection and
verify same-view reconnect after Disconnect and authenticated network loss,
edited retry-draft preservation, and removal of a remembered login.
Each retained Files session owns a value-based `DirectFilesLoginDraft`, representing
empty, saved, edited and privacy-cleared secrets explicitly. Twenty-eight
manifest-indexed journeys cover
repeated suspension/recovery, active/unlocked admission, busy owners, changed
accounts and methods, Save Login choices, deleted credentials and verified
successful saving, hidden authentication completion and revision fencing of newer
edits. Additional tests check independent owners, early user edits,
key-reference cleanup and retry after a credential-read failure.
Mounted views on both platforms repeat background/return and lock/unlock before
authentication and after Disconnect. Injected observable admission exercises
inactive/locked transitions without invoking personal biometric settings;
edited retry accounts remain intact and old saved passwords cannot replace
privacy-cleared edits. These checks do not certify physical device unlocking.
Both platforms destroy and remount the actual Files presentation around the same
owner, preserving edited Password/Key accounts, methods and Save Login choices.
Real loopback SSH also finishes authentication while the presentation is hidden,
then verifies remembered-password restoration after remount and Disconnect.
Mac cases preserve a referenced-file identity across remount, exercise both
workspace wake notifications without app activation, and wait for unlock.
Closing an owner clears its draft; later activation cannot reload its credentials.
Authentication attempts now carry non-secret password provenance, account and
revision; typed retention outcomes distinguish successful storage, failed writes
and no requested write. The native suites inject failed writes after real loopback
SSH/SFTP admission on both platforms. Already saved and edited passwords are
checked in visible and hidden presentations, with current local Keychain contents
verified independently. Manifest-indexed journeys include redundant-save failure,
edited-save failure, later credential deletion, newer edits and Mac removal before
a late authentication result.
Scoped library-removal events retire owners synchronously after successful
persistence. Both native platforms check matching owners, unrelated Macs and
independent libraries, pending trust cancellation and prevention of late saving.
macOS mounts actual Desktop and Terminal windows to verify closure and preserves
an unsaved Files download after local/synced removal. Both platforms exercise
Save/Discard recovery through mounted Files; iOS also mounts Desktop, Trackpad
and Terminal parents with hidden retained downloads. These checks simulate sync
application and native chooser completion; physical iCloud delivery and file-provider
interaction remain separate acceptance checks.
The retained-owner fixes passed 73 focused macOS tests and 29 iOS Simulator tests
with Xcode 27.1 RC (27A9275), with no failures or skips. Full repository validation
also passed, including all 136 indexed fixtures. These RC results remain
provisional until the stable Xcode lane passes for this update.
The credential-provenance and removal-lifecycle refactor is checked locally with
stable Xcode 27.0 (27A266a): the full macOS hosted run had 113 passes and one
native key-window focus skip. A final Files run covers 37 passing tests, including
the subsequently added persistence-failure case. The iOS 27.0 Simulator run covers
33 passing Files tests with no skips. Repository validation passes with all 136
indexed fixtures. Hosted focus, physical file-provider/biometric interaction and
signed cross-device iCloud delivery remain separate acceptance work.
On macOS the mounted Cancel Connection button exercises the shared action to
preserve both a loaded saved password and an edited retry account/password;
backgrounding still clears the visible secret. Hosted iOS tests do not expose
SwiftUI button accessibility nodes; actual iPhone Cancel interaction remains
part of native UI acceptance.
Native window automation and physical file-provider acceptance are
separate from hosted rendering and protocol tests.

`SettingsFeedbackUITests` exercises the actual macOS WindowGroup with a disposable
loopback SSH/SFTP fixture and an unsaved download. It checks blocked Command-W,
Cancel preserving the download, and one confirmed Done closing only its owning
window while another Files window and My Macs remain open.

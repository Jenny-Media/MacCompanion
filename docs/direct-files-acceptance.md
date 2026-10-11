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
- With a saved SSH password, edit Files' account/password and turn Save SSH login
  off. Open Setup Guide and dismiss it; the edited fields and off choice must stay.
- Leave Files open while editing the saved Mac's name, addresses or SSH port in
  another window. Its title, review and reconnect must keep the owner's original
  record. A newly opened Files owner must use the edited record.
  Remove the record locally or through sync with an unsaved Files download.
  The existing window must keep its original identity and Save/Discard results;
  opening a new Files window for the missing record must show Mac unavailable.
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
fixture is indexed only in `spec/fixtures/manifest.json`. Indexed Keep Both cases
cover exact UTF-8 spellings and suffix allocation, including full-length names,
emoji and composed/decomposed Unicode. Embedded-channel decoder cases cover
the extended metadata count bound and malformed counts below the packet-size cap.
Encoder vectors cover string-length prefixes at buffer-capacity boundaries and
the retained OPEN/CLOSE/replacement sequence of an empty upload.

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
and separate authentication/SFTP failure guidance. This transport exists
only in the hosted test target; neither release client includes a server or subprocess.

`DirectFilesPresentationTests` captures normal and accessibility layouts on both
platforms and mounts Mac login fields to exercise external disk-key selection,
removal and unchanged-reference notifications while preserving edited drafts.
It also mounts the iPhone sign-in form during an owned pending SSH handshake to
verify saved credentials load when sign-in becomes available.
Native window automation and physical file-provider acceptance are
separate from hosted rendering and protocol tests.

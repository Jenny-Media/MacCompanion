# Direct Files companion feature v1

Decision: 2026-10-10. Files is free within the existing saved-Mac and SSH-key
limits. It is not a connection mode. Both native clients expose Browse Files
from saved Macs and Files from their existing session controls. No host helper,
paired protocol, relay, shell command, or additional listening port is used.

## Connection and identity

Files MUST own an independent SSH/SFTP connection to the selected Mac's saved
SSH port and ordered private endpoints, using the existing numeric-address
validation and first-successful-TCP policy. Authentication failure MUST NOT
retry credentials against another address. Reuse the Mac UUID's existing SSH
host pin and Terminal login/key selection; never infer a login from Desktop.
First-use host trust requires explicit fingerprint approval. Changed pins fail
closed. Logins, pins and private keys remain in the existing device-only stores.
Show the selected Mac, account and Remote Login requirement before connection.
Do not claim a failed TCP connection proves Remote Login is disabled.
The Files owner retains one Mac-record snapshot. Its title, sign-in, upload
review and reconnect MUST use that same record. Reopen Files to adopt edits to
the saved Mac; do not relabel an existing connection with a different endpoint.
Removing a saved Mac, including through sync, MUST NOT close an already open
Files window or discard its pending results. A new Files window for a missing
record shows Mac unavailable; existing owners keep their original snapshot.
Opening or dismissing help or purchase sheets MUST NOT reload a saved password,
replace an edited account, or change the user's saved-login choice. Explicit key
selection may refresh the selected key/account without reloading the password.
A disk-key passphrase is bound to that file reference. Clear it when the selected
reference changes or is removed; keep the same-reference login draft intact.
This includes changes made in another window. Retire any unfinished key-file
preparation when its selection changes; it MUST NOT authenticate with the old key.
Changes received while connecting or connected MUST be reconciled when sign-in
becomes available again. A stale selection detected during Connect MUST refresh
the selection or present recovery guidance rather than silently doing nothing.

The SSH handshake including trust approval is bounded to 60 seconds. SFTP v3
subsystem admission and each idle operation are bounded to 30 seconds. Cancelling,
locking, backgrounding on iOS, or closing Files retires only its owned socket and
channel, cancels prompts and prevents late callbacks from updating a replacement
connection. Reconnect and retry are explicit; no transfer replay or resume.
Each completed SFTP response for the owned operation resets its idle deadline;
the total duration of a progressing listing or transfer is not an idle timeout.
This includes received error statuses such as a normal missing upload destination,
but not transport failures. Successful subsystem admission starts a fresh idle
deadline for the first directory request. After every metadata await, including
missing paths, validate the owner and operation before accessing transfer state.
Conflict prompts suspend that deadline. Responses from a retired connection
cannot reset a replacement connection's deadline.
SFTP subsystem-channel closure MUST retire the owned Files connection even if
the SSH transport remains open. Preserve pending results and require explicit
reconnect; do not leave a closed subsystem presented as Ready.
SFTP packets are limited to 1 MiB. Each file-attribute block accepts at most 128
extended metadata pairs, with at least eight encoded bytes available per declared
pair before decoding. Reject malformed or excessive counts. Accumulate metadata
in linear time instead of repeatedly copying the previously decoded pairs.
Encoding valid paths MUST grow the buffer before writing each SSH-string length
and payload, including when a length prefix crosses the current buffer capacity.
The existing SFTP v3 and OpenSSH replacement wire bytes remain unchanged.

## Browser and transfers

Browse from the account's canonical home directory. Resolve paths using SFTP,
not local filesystem rules or shell interpolation. Directory listings are bounded
to 10,000 entries and directory handles MUST close on success and failure.
Accept valid single filenames only; reject dot entries, slash, NUL, control
characters and overlong names. Full paths are bounded to 4096 UTF-8 bytes.
Use LSTAT for filename conflicts so symbolic links are not offered for replacement.
Only regular files transfer in v1. Directories can be browsed and created;
symlinks, special files, rename, delete and recursive transfers are not offered.
Before downloading a listed file, obtain fresh LSTAT attributes for its path and
reject a missing path, link or special file before OPEN. Also check FSTAT on the
opened handle. These checks reject stale listed links; SFTP v3 does not guarantee
an atomic no-follow open or an unchanged remote filesystem between requests.

Choose the remote destination before selecting local files. The native picker
provides user-selected local files; copy regular files into protected temporary
storage off the main thread, balancing security-scoped access. Review the files,
Mac, account and remote folder before upload. Limit a batch to 32 files and stream
one file at a time in 32-KiB chunks with bounded memory.
The Files owner explicitly owns at most one prepared upload batch. Roll back all
copies if any item fails staging. Release unadopted copies when review is cancelled,
superseded or invalidated, or the connection is retired. Transfer results take
ownership of adopted copies and keep them for explicit retry until discarded or
the owner closes. Cleanup MUST preserve picker originals and other result files.

Upload into a random, exclusively created, mode-0600 temporary file in the target
directory. A successful CLOSE and final RENAME are required before reporting
success. Never truncate an existing destination to begin an upload. Collisions
require Keep Both, Replace or Cancel. Keep Both and new files use non-replacing
SFTP v3 rename. Keep Both reserves space for its numbered suffix within the
255-byte filename limit, shortening the original stem at a UTF-8 scalar boundary
without normalizing it. Preserve the extension when it leaves room for the stem;
otherwise shorten the whole original name before adding the suffix.
Replace uses only the advertised OpenSSH
`posix-rename@openssh.com` extension; unsupported replacement fails safely.
Never remove the destination as a fallback. Cleanup may remove only the temporary
file owned by that upload, and failure to clean up must not imply successful
delivery. Downloads stream into private temporary files and require a user-selected
native export destination. Failed or cancelled downloads are not exported.

Progress and per-file results remain visible. Files' Done and Disconnect controls
require confirmation when they would stop an active transfer. Hiding a Files
sheet within a session may keep work running only while the app is in the foreground;
closing the parent session retires its Files owner. Interrupted work offers explicit retry;
completed files in a batch are not replayed. Queued retries remain bound to their
original SSH account. A different account requires a new, reviewed transfer.
Temporary local content is never synced, logged or committed, and is removed
when its Files owner closes. No
uninterrupted iOS background-transfer guarantee is made.
Files retains one pending batch. Unsaved downloads and interrupted transfers
must be saved, retried or explicitly discarded before a new batch replaces them.
Successfully exported downloads and completed uploads do not block a new batch.
Disconnect preserves the Files owner and its Save/Retry results. Files' Done
control requires an explicit warning if closing its owner will lose private
unsaved downloads or retries.
Standalone sheet swipes and native window-close controls MUST be disabled while
that warning is required; Done provides the explicit Close/Discard confirmation.
Retained Files sheets may still be hidden without discarding the owner's results.
Password-based Files login follows Terminal retention: disabling saved login
removes the existing saved password before connecting, without removing keys or
server trust.

The indexed `direct-files-v1.json` cases are authoritative for path admission and
the OpenSSH replacement packet. Existing transport, signing, Keychain and release
gates still apply. References: [SFTP v3](https://datatracker.ietf.org/doc/html/draft-ietf-secsh-filexfer-02)
and [OpenSSH extensions](https://github.com/openssh/openssh-portable/blob/master/PROTOCOL).

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
After approval, recheck shared trust and install an absent pin atomically. A
concurrent approval of the same key is compatible; a different key MUST remain
stored and fail the pending connection before authentication. This applies to
all direct SSH consumers sharing the Mac UUID, including Terminal and Desktop.
Show the selected Mac, account and Remote Login requirement before connection.
Do not claim a failed TCP connection proves Remote Login is disabled.
The Files owner retains one Mac-record snapshot. Its title, sign-in, upload
review and reconnect MUST use that same record. Reopen Files to adopt edits to
the saved Mac; do not relabel an existing connection with a different endpoint.
Removing a saved Mac, including through sync, MUST retire all related Desktop,
Terminal and Files connections and unfinished authentication attempts. Related
windows/presentations close. A Files owner with unsaved completed downloads stays
open solely for Save or explicit Discard, retaining its original identity; it
MUST NOT connect, retry or read credentials again. Close it once those downloads
are saved or discarded. Other Macs' owners remain independent. Publish removal
only after the updated library is successfully persisted, scoped to that library.
A missing record MUST fail connection admission independently of Pro access.
Opening or dismissing help or purchase sheets MUST NOT reload a saved password,
replace an edited account, or change the user's saved-login choice. Explicit key
selection may refresh the selected key/account without reloading the password.
Key-chooser updates that leave the selected key unchanged, including renaming a
key or choosing the free key, MUST preserve the edited sign-in account and method.
Refresh the displayed key name without restoring its saved account.
After a successful password connection clears its sign-in secret, returning to
sign-in in the same view MUST make the remembered password available again for
explicit reconnect. Restore only that cleared credential, for the same account,
while saved login remains enabled; preserve edited drafts and never reconnect
automatically. On iOS defer reading it until the app is active and unlocked.
Each Files owner MUST keep its own login draft with explicit empty, saved,
edited and privacy-cleared password states. Backgrounding, locking and retained
view suspension clear visible secrets, preserving only non-secret restoration
context for an unedited remembered password. On returning to eligible sign-in,
restore that password only while its account, Password method and Save Login
choice still match and the saved credential still exists. Repeated suspension
and return cycles MUST remain recoverable. User-cleared or edited passwords
MUST NOT be replaced with an older saved password. Successful authentication
may make an edited password restorable only if that exact login was saved.
Unlocking MUST NOT reset edited accounts, login methods or Save Login choices.
Initialization and restoration wait for active, allowed sign-in; help/key-label
refresh and connection cancellation preserve drafts. Independent owners MUST
not share mutable credential state.
The draft belongs to the retained Files connection owner, including while its
sheet is hidden. Recreating a presentation MUST preserve its account, method,
Save Login choice and selected-key identity instead of reapplying defaults.
Authentication attempts carry non-secret password provenance, account and draft
revision. Authentication success and credential-retention outcomes are separate
events. A failed write of an unchanged, already saved password MUST preserve its
restoration eligibility; restoration still reads the current device-only store
and requires the credential to exist. An edited password becomes restorable only
after that attempt successfully stores it. These rules also apply while hidden.
A later user edit invalidates that attempt's draft revision. Failed/cancelled
authentication never establishes new restoration eligibility. Removal invalidates
the owner and its entire draft before any late result can retain credentials.
Closing the owner clears its draft and secrets; later presentation or activation
callbacks MUST NOT reload that closed owner's login. On macOS, display and user-session
wake MUST restore eligible sign-in without depending on application activation;
locked wake cannot restore secrets, and wake never reconnects automatically.
A disk-key passphrase is bound to that file reference. Clear it when the selected
reference changes or is removed; keep the same-reference login draft intact.
This includes changes made in another window. Retire any unfinished key-file
preparation when its selection changes; it MUST NOT authenticate with the old key.
Changes received while connecting or connected MUST be reconciled when sign-in
becomes available again. A stale selection detected during Connect MUST refresh
the selection or present recovery guidance rather than silently doing nothing.
After successful named-key authentication and SFTP admission, retain the SSH
account on that Mac's existing key association. Update only the association used
by the login, if its key identity and prior account still match. A newer selection,
account edit or removed association MUST NOT be overwritten or recreated.
For macOS keys referenced from disk, snapshot the full file reference and saved
account when starting authentication. Files and Terminal MUST retain a successful
account only while that reference and prior account still match. A newer account
edit, reselected reference, different key or removed association skips retention
without importing the disk key or failing an otherwise successful connection.
Each explicit reconnect captures a fresh selection; rejected or cancelled logins
MUST NOT retain an account.

The SSH handshake including trust approval is bounded to 60 seconds. SFTP v3
subsystem admission and each idle operation are bounded to 30 seconds. Cancelling,
locking, backgrounding on iOS, or closing Files retires only its owned socket and
channel, cancels prompts and prevents late callbacks from updating a replacement
connection. Reconnect and retry are explicit; no transfer replay or resume.
SFTP admission failure, including SSH closure before child-channel creation,
MUST settle its internal asynchronous work and report failure without crashing.
Each completed SFTP response for the owned operation resets its idle deadline;
the total duration of a progressing listing or transfer is not an idle timeout.
This includes received error statuses such as a normal missing upload destination,
but not transport failures. Successful subsystem admission starts a fresh idle
deadline for the first directory request. After every metadata await, including
missing paths, validate the owner and operation before accessing transfer state.
Conflict prompts suspend that deadline. Responses from a retired connection
cannot reset a replacement connection's deadline.
Cancelled or superseded idle timers MUST NOT disconnect Files, including when
their wait has completed and their callback is already queued.
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
to 10,000 entries and 16 MiB of aggregate decoded UTF-8 string metadata, including
filenames, longnames and extended-attribute keys and values. Enforce the byte
budget before retaining each response, even when every packet fits the 1-MiB
packet limit and continues arriving within the idle deadline. Directory handles
MUST close on success and failure, including budget rejection.
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
Local staging MUST open the coordinated source without following a final-component
symlink, reject non-regular files using metadata from the opened descriptor, and
copy from that same descriptor without reopening the path. Reject an already
non-regular source before file coordination; descriptor admission MUST NOT block
on a FIFO. Replacing the path after admission MUST NOT redirect the
copy to the replacement's contents.
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
On macOS, accepting Close Files MUST close only the owning native window on the
first confirmation, even while its last rendered dismissal policy is disabled.
Cancelling the warning MUST preserve the owner and pending results.
Retained Files sheets may still be hidden without discarding the owner's results.
Password-based Files login follows Terminal retention: disabling saved login
removes the existing saved password before connecting, without removing keys or
server trust.

The indexed `direct-files-v1.json` cases are authoritative for path admission and
the OpenSSH replacement packet. Existing transport, signing, Keychain and release
gates still apply. References: [SFTP v3](https://datatracker.ietf.org/doc/html/draft-ietf-secsh-filexfer-02)
and [OpenSSH extensions](https://github.com/openssh/openssh-portable/blob/master/PROTOCOL).

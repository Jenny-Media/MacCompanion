# Error and recovery UX review

Date: 2026-10-06. Status: **approved design implemented and validated**.
The findings and mockup verification below record the pre-implementation review.
See [native implementation evidence](../evidence/2026-10-06-error-recovery.md)
for the completed changes, Simulator verification and internal delivery status.

## Current SSH key installation button

This section records the original placement. The implemented entry is now
My Macs → the Mac's menu → Mac Settings → **Terminal Access → Set Up Key on This Mac**.
Terminal login also offers setup beside the selected key and after confirmed key
rejection. Both entry points show the Pro requirement and a free manual route.

My Macs → the Mac's ellipsis menu → Mac Settings → Saved Logins & Server Trust
→ **Install Key on This Mac**.

It exists for saved Macs, remains visible without Pro and opens the Pro screen
when Pro/trial access is unavailable. Invalid name/address/port drafts disable
it. A new unsaved Mac does not have this section. Terminal's **Manage SSH Key**
opens only the local key library; it has no installation entry. Automatic
installation requires Pro or an active trial. Free users can already copy/export
the public key and configure the Mac manually.

Sources: Native/VNC/DirectMacLibraryV1.swift:361,
Native/Terminal/DirectTerminalView.swift:55,
Native/Terminal/TerminalKeySettings.swift:16,
Native/Terminal/TerminalKeyInstallView.swift:55.

## Findings

1. **The screenshot does not identify a missing public key.** The generic catch
   in DirectTerminalSession.swift:143 collapses network, negotiation, login,
   shell creation and other errors into one sentence. Its dial function also
   discards the address-resolution/connect failure code. Authentication rejection
   establishes that a login was not accepted; it cannot prove whether the public
   key was absent, account/permissions were wrong or server policy rejected it.
2. **Actions are distant from the problem.** Installation is beside destructive
   credential-removal actions. Terminal exposes only key management. Installation
   has no visible Pro indication.
3. **Untyped strings mix progress, success and failure.** Terminal uses one body
   Text for every state. iCloud/Pro likewise share message properties. Pending
   purchases, cancellation, unavailable data and failed connections need
   different presentations.
4. **Desktop exposes implementation words.** ARD hashing/encryption/allocation
   and input queue failures need a short summary and expandable bounded details.
5. **Some messages imply an unproven remedy.** Unlocking cannot repair malformed
   stored data. A network timeout does not prove Remote Login is off. An import
   decryption failure may be a wrong passphrase or damaged file.
6. **Uncertain outcomes need a distinct result.** Setup timeout/cancellation may
   leave a public key installed. Acknowledged installation followed by failed
   verification differs from failure before any command was sent. Purchase
   uncertainty should offer restore/history rather than buy again.
7. **Disabled actions lack explanations.** Field limits, Pro limits, invalid
   imports and unreadable storage need nearby guidance while keeping drafts.
8. **Failed reads look empty.** Saved Macs/keys need an unavailable state rather
   than a welcome screen suggesting there was never any saved data.

The [source message inventory](2026-10-06-error-message-inventory.md) records 115
error/status/confirmation literals across 14 files. Disabled controls, silent read
fallbacks and system authentication/file-picker cancellation were also inspected.
Inactive legacy pairing, Mac-host and streaming-engine views are outside the
current direct client.

## Shared presentation system

| Situation | Presentation | Interaction |
| --- | --- | --- |
| Invalid field | Error under that field | Keep draft; explain disabled Save/Connect |
| Login/connection failure | Compact card in the current screen | One main action, relevant alternative, expandable details |
| Desktop disconnect | Bottom recovery panel; last frame visibly inactive | Explicit Reconnect; preserve valid viewport; never replay input |
| Terminal disconnect/background | Shell-closed state | Open a new shell; do not promise to restore the old one |
| First/changed SSH identity | Verification sheet/blocking warning | Check fingerprint independently; trust remains explicit |
| Unreadable saved data | Unavailable card in the owning screen | Retry and help; preserve data |
| Key installation | Setup sheet with stages | Verify server, authenticate, add public key, test key login |
| Uncertain installation | Persistent result card | Test key login first; no automatic repeat |
| iCloud/store failure | Card in the relevant Settings section | Targeted Retry/Restore; local/free use continues |
| Normal cancellation/pending | Neutral state | Return to prior screen; no failure alert |
| Display fallback | Brief informational banner | Keep session usable; explain All Displays |

Failures need a stable reason, title, short explanation, actions, severity,
origin and outcome certainty. Keep these separate from raw technical strings.
Use consistent spacing/type, icon plus text, 44-point touch targets, Dynamic Type,
VoiceOver and Light/Dark/System appearance. Large text scrolls and actions stay
above the keyboard. Announce failures once, not every progress update.

Optional connection details show bounded phase/settings information locally.
Passwords, private keys, input, screen content and raw vendor output must not
enter telemetry or shared diagnostics. This proposal enables no extra logging.

## Copy and recovery by family

| Family | Proposed title | Main action / alternative | Evidence boundary |
| --- | --- | --- | --- |
| Unknown SSH failure | Couldn't connect to Terminal | Try Again / Connection Details | Use when phase is unknown |
| Confirmed key login rejection | SSH key wasn't accepted | Use Password / Set Up Key on Mac | Public key may need adding; do not assert it is absent |
| Confirmed password rejection | Mac login wasn't accepted | Edit Login / Details | May be password or account policy |
| No key selection | Choose an SSH key | Choose Key / Use Password | Selection is not installation |
| DNS failure | Address couldn't be found | Edit Addresses / Try Again | Cannot infer VPN is off |
| TCP timeout/refusal | Couldn't reach this Mac | Try Again / Connection Settings | Service and port are checks, not known causes |
| Unsupported protocol/server | This connection isn't supported | Setup Guide / Details | Preserve actual protocol category |
| Desktop handshake/ARD/allocation/size | Couldn't open the desktop | Try Again / Details | Keep fixed reason and size-limit detail; no weaker authentication |
| Desktop/shell write/resize/drop | Desktop disconnected / Terminal disconnected | Reconnect / Done | No prior shell or pending input restoration claim |
| Input saturation/not ready | Input paused | Reconnect if disconnected / wait if resuming | Never replay a possibly sent command/click |
| First SSH identity | Verify this Mac | Trust & Connect / Cancel | Independently check fingerprint |
| Changed SSH identity | This Mac's identity changed | How to Verify / Back to Macs | Authentication stays blocked |
| Rejected server trust | Connection cancelled | Return to login | Neutral; no login sent |
| Setup failed before command | Key setup didn't finish | Correct Login or Connection / Cancel | No key-added claim |
| Setup timeout/cancel after send | Key setup wasn't verified | Test Key Login / Manual Steps | Public key may already be added |
| Installation acknowledged, login fails | Key was added; login wasn't verified | Test Key Login / Review Account | Only after an installation acknowledgment |
| Verified installation | Public key installed | Connect to Terminal / Done | Fresh key-only login and durable association required |
| Saved Macs/keys/logins fail to read | Saved data unavailable | Retry / Help | Distinguish locked device from invalid data |
| Save/remove failure | Couldn't save/remove this change | Retry / Keep Editing | Don't promise rollback of multi-step credential removal |
| Invalid field/capacity | Specific field guidance | Correct Field / select free item | Blank ports use defaults |
| Import format/size/work limit | Key couldn't be imported | Choose Another File / Requirements | Ed25519 OpenSSH ≤32 KiB; show actual supported limits |
| Import decrypt failure | Key couldn't be unlocked | Re-enter Passphrase / Another File | Wrong passphrase or damaged file; nothing saved |
| File-picker cancellation | No error | Return to form | Separate cancellation from file failure |
| Private export auth cancelled | Export cancelled | Try Export Again / Done | Neutral; original key preserved |
| Export preparation/write failure | Backup wasn't exported | Try Again / Done | Don't claim target file exists |
| Quick actions/keyboard prefs | Saved controls unavailable | Retry / standard controls where safe | Preserve saved custom data and drafts |
| iCloud history/identity/read/write/removal | iCloud Sync unavailable | Retry Sync / Sync Help | Local data retained; submission isn't delivery |
| Store offline/product missing | App Store unavailable | Reload Store / Keep Using Free | No invented price for unavailable product |
| Purchase pending | Purchase awaiting approval | Done | Neutral; don't encourage repurchase |
| Unverified/uncertain purchase | Purchase couldn't be confirmed | Restore / History instructions | Don't assert whether Apple charged |
| Restore failure/no purchase | Couldn't restore Pro / No Pro purchase found | Restore Again / Account guidance | Keep verified access and data |
| Trial expiry/Pro gate | This feature requires Pro | Trial/Upgrade / free alternative | Not an error; keep records and sessions |
| Face ID cancel/passcode missing | Unlock Mac Companion / Set up a passcode | Unlock / Settings guidance | Keep opaque privacy cover |
| Missing display metadata/layout change | Showing all displays | Choose Display when supported / dismiss | Never infer display positions |
| Clipboard/link requests and deletion | Named contextual confirmation | Cancel / explicit action | Preserve existing security intent |

## Key setup discoverability

1. Rename local key selection to **Choose or Manage Key**.
2. Put **Set Up Key on This Mac** beneath the selected Terminal login key and
   on a confirmed key-rejection card.
3. Add **Terminal Access** to Mac Settings with account, selected key and
   **Install Public Key on Mac**. Move destructive login/trust removal lower.
4. Show a Pro badge on automatic setup. Keep **Manual Setup** accessible using
   the existing free public-key copy/export.
5. Explain that import/selection stores the key on the iPhone; installation
   adds its public key to a Mac account. The private key stays on the iPhone.

## Review

Open [the interactive mockups](error-recovery-mockups/index.html).
All accounts, Macs, addresses, fingerprints and terminal output are synthetic.
Actions demonstrate navigation and states without network, Keychain, settings,
purchase, clipboard or remote-command effects.

Start with key-rejected login, Mac Settings and setup. The 29-state scenario selector
also covers representative connection, trust, storage, import/export, privacy,
sync, purchase and display states. Light/Dark and large-text controls are
available. Mockups requiring classified failures are explicitly identified:
the current generic catch cannot deliver those diagnoses yet.

## Verification

- Browser-rendered all 29 scenarios at standard text size and at larger text
  with dark appearance. No horizontal content overflow; active product controls
  have at least 44-pixel touch targets after the details-control correction.
- Visually reviewed the light three-screen overview and dark uncertain-setup
  screen. Confirmed the error-to-setup route, the Mac Settings entry and free
  manual-setup entry. Longer content scrolls within the phone.
- JavaScript syntax check and git whitespace check passed.
- Required bash scripts/validate.sh passed with stable Xcode 27.0 (27A266a).
  The first run needed normal compiler-cache access. A generated Xcode
  xcschememanagement.plist under the vendored dependency was preserved outside
  the source tree; dependency source hashes were unchanged.
- Screenshots were kept in the task visualization directory outside Git.
  This is HTML design verification, not native Simulator or device acceptance.

## Implementation after design review

1. Preserve typed reasons and connection phases. Citadel exposes authentication
   and channel failures; verify mapping with synthetic faults, not string matching.
2. Add a shared presentation model, recovery actions, correct cancellation and
   explicit uncertain outcomes.
3. Add setup entry points and reorganize Mac Settings while retaining Pro/free
   entitlement and SSH trust behavior.
4. Apply this system to all audited families; retain drafts and one exit action.
5. Update authoritative spec/indexed vectors before any security/wire change.
   Verify classification, cancellation, no input replay and data preservation.
   Capture Simulator light/dark/large-text screens.
6. Run stable-Xcode validation and deliver one internal TestFlight update.
   Mockup approval and physical acceptance are separate.

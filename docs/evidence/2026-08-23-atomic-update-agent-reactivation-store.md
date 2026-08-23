# Atomic update Agent reactivation store

Date: 2026-08-23

Status: macOS platform construction and focused tests pass. Tests used private
temporary directories and injected faults; no live Application Support,
ServiceManagement, Agent, or updater action ran.

## Outcome

`AtomicFileMacUpdateAgentReactivationStoreV0` supplies the durable
compare-and-swap persistence required by the update Agent saga. Its system
location is the menu-app-owned private directory
`Application Support/media.jenny.maccompanion/Menu/update-v0`; callers may
inject a disposable directory for tests.

The store admits one canonical bounded JSON receipt containing only the frozen
profile, source build, candidate build, and `prepared` or `agentStopped` phase.
Decode re-encodes and byte-compares the value, rejecting whitespace, missing
newline, duplicate or unknown keys, changed profile, invalid phase, and
non-increasing builds.

Every operation takes one process-shared advisory lock. Replacement requires
the exact expected receipt, writes an exclusive random pending file, sets mode
0600, fsyncs it, atomically renames it, and fsyncs the mode-0700 directory.
Clear likewise requires the exact receipt, unlinks it, and fsyncs the directory.
Reads use `open(O_NOFOLLOW)` and authoritative `fstat` type, mode, and size
facts before reading; symlinks, special files, unexpected entries, unsafe
modes, oversized data, and malformed bytes fail closed.

The focused fault audit found and corrected one subtle metadata issue. A stable
destination `URL` can retain a cached `fileSize` after atomic replacement with
differently sized bytes. The store therefore does not combine cached
`URLResourceValues` with a fresh descriptor. The descriptor's `fstat` and exact
read length are the sole record-size authority.

## Verification

Eight tests cover canonical/closed encoding, insert, phase advance, reopen,
clear, exact compare-and-swap, pre-rename failure, post-rename readback,
post-clear readback, symlink and unexpected-entry rejection, private modes, and
two-store concurrent insertion with exactly one winner.

The complete repository gate passes 73 authoritative fixtures, 35 update-policy
fixtures, 3 privacy manifests, 12 privacy fixtures, 16 required-reason source
records, 1,142 repository files and 1,936 historical blob paths, every
supply-chain, privacy, SBOM, signing, packaging, and release-evidence validator,
1,560 MacCompanionKit tests, 8 platform-probe tests, and every permanent target
and supported cross-platform compile on Xcode 27 beta.

## Deliberate non-claims

The containing app does not construct this store yet, map it into
`MacUpdateAgentReactivationDependenciesV0`, bind the real converging
ServiceManagement owner or authenticated Agent-build observer, run startup
repair, or enable Sparkle installation. The store proves durable local
semantics only; no live update authority is open.

# Protected notarytool execution construction

Date: 2026-08-22

Status: injected non-network construction evidence. No Apple account was
accessed and no artifact was submitted.

## Construction

`platform_notarytool_execution.py` supplies the protected execution boundary
behind the two-phase notarization profile:

- admit only the fixed stable/beta Xcode `notarytool` binary;
- pin the exact `.zip` or `.dmg` through no-follow descriptors into a private
  work root;
- publish the copy only after fsync as a mode-`0400`, single-link, owner-only
  file;
- bind device, inode, mode, modification time, size, and SHA-256;
- use shell-free fixed submit, info, and log calls;
- submit without a long blocking wait, retaining only the successful upload
  UUID before a later status/log retrieval;
- rehash the upload before execution, after process exit, and after reopening
  raw evidence;
- retain bounded mode-`0600` stdout/stderr by exact path, size, and hash;
- remove both the Keychain profile and absolute private upload path from the
  public invocation record; and
- feed only the exact submitted UUID and upload binding into the accepted
  info/log correlation parser.

The actual Keychain profile is a runtime-only value. Passwords, API keys,
temporary upload credentials, Apple account metadata, and the profile name do
not enter retained evidence.

## Verification

```text
python3 scripts/validate_platform_notarytool_execution.py
```

The validator uses the installed Xcode 27 beta `notarytool` identity but
injects every process result. It proves private exact-byte pinning, fixed argv,
successful upload parsing, Accepted info/log composition, upload hash and UUID
correlation, credential/path redaction, issue rejection, source substitution
rejection, mid-call upload mutation detection, invalid-profile rejection, and
symlink refusal. It is part of `scripts/validate.sh`.

## Remaining boundary

The successful JSON grammar is based on the installed tool help plus Apple's
documented status/log contract, not a real Mac Companion submission. A release
run must explicitly authorize each upload, use controlled credentials, retain
the real raw results, and re-run correlation before any acceptance claim.
Application and DMG stapling, post-staple byte correlation, final Gatekeeper
assessment, packaging equivalence, stable Xcode 26.6, and physical/promotion
evidence remain open.


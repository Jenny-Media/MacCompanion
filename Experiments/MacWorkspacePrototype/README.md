# Mac workspace prototype

Disposable feasibility app: **Open Workspace** opens Apple Screen Sharing and
Mac Companion's existing SSH Terminal for the same saved Mac. Desktop and
Terminal remain separate windows in separate applications. This experiment is
not linked into any shipping target.

The purpose is to evaluate whether a shared Mac list and one workspace action
are useful enough to keep a small macOS companion. It is not a replacement
Screen Sharing implementation. The existing native code and dependencies remain
compiled for reuse; this does not demonstrate a smaller application binary.

## Build and checks

Use the stable Xcode lane and the managed workflow in
`docs/build-cache-workflow.md`. First build the normal native Mac client with
`scripts/build_direct_macos.py` and its repository-pinned dependencies. Then:

```sh
python3 Experiments/MacWorkspacePrototype/build.py \
  --normal-build /outside-checkout/normal-mac-build \
  --output /outside-checkout/workspace-prototype-build
```

The prototype builder leases the verified normal compiler workspace, creates a
separate managed project, reuses the pinned packages/static libraries and checks
their provenance. It excludes the shipping application entry point and adds only
this experiment's sources. It never edits the normal generated project. Both
compiler caches and immutable evidence remain outside the checkout. There is no
cache-deletion or release/install/upload step.

Every prototype build compiles the actual coordinator into a headless native
test executable. The tests read `spec/fixtures/native-macos-client-v1.json`
through the existing fixture manifest; there is no second fixture corpus.
Coverage includes private IPv4/IPv6 URL admission, credential/query injection,
Desktop failures, duplicate clicks, Terminal reuse/close, lock/removal/edits,
replacement requests, timeouts and late callbacks. No GUI, credentials or remote
connection is needed. Also run `bash scripts/validate.sh` before handoff.

The default local app uses a temporary bundle ID
`dev.maccompanion.workspaceprototype` and ad-hoc signing. This proves compilation
and launch, not permission to access the protected Keychain. Existing native
SSH credential storage/host-trust operations may require an already authorized
Apple development identity/profile for this temporary bundle. Do not create a
permanent app ID, new Keychain sharing group or provisioning profile for this
experiment. Do not weaken host-key verification to bypass a signing limitation.
An already authorized development profile can be selected with
`--signing-identity SHA1 --team TEAM --profile /outside-checkout/profile`.
The builder verifies its existing claims and requests only this temporary app's
own Keychain group, without the shipping app's shared group. No registration,
profile download or certificate creation is enabled.

## Review the workflow

1. Open the generated **Mac Workspace Prototype.app** alongside the installed
   app. It uses a separate Mac list in Application Support's
   `MacCompanionWorkspacePrototype` directory and process-local SSH metadata.
   No production list, passwords, key selections or cloud preferences are
   imported; cloud sync is not started. Existing free-Mac admission still
   applies, so start with one Mac.
2. Add a Mac with Screen Sharing and Remote Login enabled. Enter only its local
   or private VPN address and configured ports in Connection Settings.
3. Choose **Open Workspace**. Enter Desktop credentials privately in Apple's
   window and SSH credentials privately in Terminal. The two apps authenticate
   independently. No credentials are passed in the VNC URL.
4. Confirm both windows target the intended Mac. Repeat the action: Terminal
   should focus its existing window; close Terminal and reopen to create a new
   window. Apple owns whether it reuses its Desktop window.
5. Cancel Desktop login and check Terminal remains usable. Retry **Desktop**
   independently. Editing/removing a Mac or locking this app during address
   resolution should retire the pending handoff.

Hostnames resolve away from the UI actor; only numeric endpoints accepted by
the existing local/private endpoint policy are handed to Apple's app. The
prototype chooses the first admitted address; it does not probe credentials or
try another endpoint after a failed Desktop connection. A ten-second handoff
timeout retires late results. It cannot undo an external window already opened.

**Opened in Screen Sharing** means macOS accepted the URL, not that a Desktop
connection succeeded. Apple owns Desktop login, status, window and lifetime.
Locking or quitting this prototype does not lock or end the external Desktop
session. Avoid interpreting its status as a remote-session monitor.

## Decision after trying it

Continue only if the shared Mac list, native Terminal and one-action handoff
save meaningful effort over opening Screen Sharing and Terminal separately.
Evaluate actual focus/window reuse and the desktop connection on the intended
network manually. If keeping Desktop and Terminal inside one app is essential,
this external-app approach does not satisfy it. Do not add password injection,
Accessibility scripting, private APIs or an embedded external window to hide
that boundary.

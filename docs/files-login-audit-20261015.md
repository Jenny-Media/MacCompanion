# Files login and connection audit

Audited source based on main 876be88, with the macOS Terminal reuse fix applied.
No host credentials or live screen/input content were collected.

| Platform / entry | Authentication source | Result |
| --- | --- | --- |
| iOS/iPadOS Terminal → Files | `DirectTerminalView` supplies `session.filesContext`; SFTP opens on that authenticated SSH client | Already reuses the live account, including unsaved password/key logins. No independent credential form. |
| iOS/iPadOS Screen Sharing → Files | `VNCRemoteDesktopView.Coordinator.showFiles` supplies the active desktop SSH tunnel client/account/generation | Already reuses the live account. SFTP does not require another SSH or Screen Sharing login. |
| iOS/iPadOS Trackpad & Keyboard → Files | Same viewer/coordinator and SSH tunnel as Screen Sharing | Same reuse behavior. |
| iOS/iPadOS My Macs → Browse Files | `DirectFilesWorkspace` plus the canonical Login & Access profile | No parent transport is supplied. Authenticates SSH using saved settings; the optional Terminal-sign-in choice selects an explicitly configured override, not a third login. |
| macOS Terminal → Files | Previously passed only the Mac UUID, creating an independent login. Now resolves a secret-free, generation-pinned Terminal-window request | Fixed here. One authenticated transport, distinct shell and SFTP channels; Files close/failure cannot close the shell. |
| macOS My Macs → Browse Files | Independent SSH/SFTP connection using saved Terminal settings | Still presents the existing standalone login form. There is no originating authenticated Terminal to borrow. This is separate from the fixed session entry point; simplifying this saved-login form is a possible follow-up. |
| macOS Apple Screen Sharing | External Apple application owns its own VNC authentication and transport | Mac Companion cannot borrow that application's connection. Files uses its own Remote Login connection through Browse Files. |
| macOS legacy embedded Screen Sharing source | Old `MacDirectDesktopView` still has an independent Files-window action | Not reachable through the shipping Screen Sharing action; retained compatibility/test source only. |
| visionOS | No remote Files-browser or SFTP entry point in the native scene | No duplicate Files login flow to fix. The system Files importer for SSH keys is unrelated. |

## Boundaries checked

Terminal requests select one window, not whichever Terminal for the same Mac was
last active. The registry keeps weak session references and is scoped to the
saved-Mac library. Requests contain no password/private key and cannot adopt a
replacement shell after disconnect or process restoration. Endpoint edits cannot
mislabel the borrowed connection. A stale request shows reconnect guidance
without falling back to another login. Downloads remain bound to their original
account. Shared SFTP wire/authentication bytes and host-key validation are unchanged.

## Validation

Native loopback tests cover password/key reuse without another authentication,
continued shell input after Files closes, failed/cancelled subsystem opening,
parent closure and download retention, stale in-flight opens, indexed ownership
routing, legacy request decoding and absence of a separate credential form.
Existing iOS shared-access and Files presentation tests are rerun for regressions.
Exact run results are retained outside the repository with the build evidence.

# iOS settings interaction audit — 2026-10-15

Scope: My Macs and its presented/nested Mac editor, Login & Access, App Settings, appearance/control/security pages, SSH-key management, setup help, Pro, and Files. Source inspection covers refresh actions, visible account labels, sign-in terminology, and whether help names real destinations. Runtime coverage focuses on native refresh ownership and populated account-form layout. This is not a claim of a complete accessibility or every-device audit.

| Finding | User impact | Resolution |
| --- | --- | --- |
| Discovery refresh is outside the Mac list’s sheet modifiers | Pulling settings, sign-in, help, or Files forms can start an unrelated local-network discovery scan and spinner | Contain the refresh environment in the My Macs list component; presentations keep their own behavior |
| Login & Access explains “one login,” Keychain storage organization, and an “SSH override” | Users must infer what to enter and what Save changes | Explain the Mac account to enter, future connections, and that saving does not change the Mac password; label the optional method Terminal Sign-In |
| Account/password fields rely on placeholders | Labels disappear for populated fields; a blank password row has no visible identity | Keep visible Username and Password labels for Mac and alternate Terminal accounts |
| Standalone Files calls its account choice “Use SSH override” | An internal configuration term obscures which account opens Files | Call the choice Use Terminal Sign-In; retain Files’ existing actual-account display |
| SSH-key help names removed Terminal Access settings and says to select keys in a library that now routes elsewhere | Directions do not match the current controls | Point to Mac Settings → Set Up Key on This Mac, and Login & Access for key selection |
| Mac Settings describes the shared-login architecture | The management entry does not say what users can accomplish | Describe choosing how to sign in and setting up a Terminal key |

Explicit Refresh Details still refreshes discovered Mac metadata. Files’ explicit Refresh still reloads the current remote folder. Neither is removed or repurposed. Credential storage, migration, authentication, active-connection guards, and transfer ownership are unchanged.

Regression coverage: the native My Macs list retains a callable refresh action; presented Login & Access, Mac Settings, App Settings, SSH Keys, Setup Guide, Pro, and Files do not inherit it or expose an unrelated native refresh control; populated account fields render at narrow width and normal/accessibility text sizes without changing saved data. Simulator snapshots are synthetic and remain in external test evidence.

# iOS 1.1 development preparation

Version 1.0 (157) and its submitted App Store record remain unchanged. The iOS Cloud app and Live Activity extension now target marketing version 1.1 for future builds.

Two independent feature branches are based on main at `370b9194d70df7e53d6d1ab02c471f1c95ae0006`: keyboard layout sync and keypress previews. Each PR includes the same version-only preparation so it can be reviewed and built independently; combine both before a 1.1 release candidate. No build upload, tester assignment, App Store metadata change, submission or publication is part of this development work.

The 1.0 metadata, screenshots and acceptance evidence remain archived under `../1.0/`. Fresh 1.1 release text, screenshots and physical-device acceptance must describe the final combined candidate. Synthetic transport tests and Simulator layouts do not establish delivery through a signed iCloud account or physical Duo acceptance.

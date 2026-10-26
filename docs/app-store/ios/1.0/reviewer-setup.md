# iOS 1.0 reviewer rehearsal

Use `en-US/app-review-notes.txt` as the paste-ready App Review Notes. Preserve the existing review contact. The app has no vendor sign-in or vendor demo account; the reviewer supplies an authorized Mac account. Do not enter a Mac password in the App Store Connect demo-account fields.

1. Use the selected **1.0 (157)** iOS candidate, source `35a060ed36b7e2a7d77570a07d7e044d24d2a2fb`, on a clean iPhone and iPad. Record the build number, device, OS, Mac OS and result locally. The current-source Simulator captures do not establish physical acceptance of this candidate.
2. Follow the numbered notes using the Mac's built-in Remote Login and Screen Sharing. Use an awake Mac with the lid open, a trusted LAN and a blank test document. Verify the SSH key on the Mac; stop on a mismatch. Setup requires no Mac Companion download, QR pairing or camera access.
3. Verify desktop rendering, actual text consumption in the blank document, pointer click/drag/scroll, Compose Text Send/Close, Terminal login/exit, and Trackpad & Keyboard. Terminal uses the saved Mac login by default; separately configured SSH passwords or keys override it. Check both paths where configured, plus Done, Cancel, brief background/foreground, reconnect and wrong-password recovery. Keep all real input and network details outside Git.
4. Check iPad portrait/landscape and resized layouts. Check Pro/trial/restore with the review environment; no purchase is needed for core connections. Check Files with disposable individual files on the free saved Mac.
5. Keep owner-confirmed ordinary iPhone live-input evidence separate from native Duo Simulator fold evidence. Neither proves physical Duo live-session continuity. **Future physical Duo tests use TestFlight**, after a separately authorized upload and assignment. Do not install a development build as part of this task.
6. Rehearse the final notes without private engineering knowledge. Resolve any missing step before submission. Check current privacy/export answers, IAP review status and links. Preserve the standing France exclusion and manual release setting.

For native Duo Book/Tabletop comparisons and prior rejected results use `/Users/yihong/work/iphone-duo-compatibility/reports/mac-companion/`. Retain source identities; do not relabel older physical images as acceptance of the current candidate.

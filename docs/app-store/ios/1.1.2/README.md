# Mac Companion iOS 1.1.2 release preparation

Prepared from main at `de2989e00fb5e9378b31615387f1c72aa3f311c0`, including the active connection address indicator in PR 62, direct Mirror Mac Screen and Virtual Display shortcuts in PR 63, and Compose Text delivery in PR 64.

App Store Connect shows iOS 1.1.1 (172) Ready for Distribution on November 10, 2026. Uploads 173 and 174 failed because the 1.1.1 train is closed. The app and Live Activity therefore advance together to 1.1.2. Xcode Cloud supplies the next fresh build number.

The owner confirmed the features on iPhone 18 Pro Max and confirmed exact Compose Text output over mobile data using development build 1.1.1 (172.6). That acceptance applies to the merged application behavior. The 1.1.2 distribution candidate needs its own build and TestFlight check.

The English release copy is under [en-US](en-US/). The concise [update notes](en-US/whats-new.txt) describe the three changes. [Review notes](en-US/app-review-notes.txt) and [TestFlight checks](en-US/testflight-notes.txt) use disposable input on a reviewer-controlled Mac. Name, subtitle, description and keywords use the released 1.1.1 copy.

The draft reuses the reviewed [1.1 artwork](../1.1/artwork-manifest.json). The screenshot composition list carries those existing scenes forward. Original capture and reuse provenance is retained in that archive.

[Release metadata](metadata.json) records the source, manual release choice and current service checkpoint. Preparation includes the version configuration and App Store draft. Building the distribution candidate, attaching it and App Review submission are later checkpoints.

The 1.1.2 draft is saved in App Store Connect as Prepare for Submission. Update notes, promotional text and reviewer notes were verified after reload, and manual release is selected. The distribution build and App Review submission are pending.

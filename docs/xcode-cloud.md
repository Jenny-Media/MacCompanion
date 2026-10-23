# iOS Xcode Cloud delivery

`Native/iOSCloud/MacCompanionCloud.xcodeproj` is the persistent, checked-in
project for iOS TestFlight automation. Open it in Xcode.app, select the
`MacCompanionIOS` shared scheme, and use Reports → Cloud to manage workflows.
It builds the same direct-client app and Live Activity extension as the normal
managed builder. No experimental app sources or legacy Mac helper targets enter
the archive. Synchronized source folders include newly added production files
without regenerating the project during a cloud build.

The intended workflow is **iOS Main → Internal TestFlight**:

- Start on every change to the `main` branch, with no file-path filter.
- Archive `MacCompanionIOS` for iOS using the latest stable Xcode supported by
  the project, with automatic signing.
- Distribute successful builds to the existing **Internal Testing** group.
- Use Xcode Cloud's next-build-number setting above all existing uploaded builds.
  Future manual uploads must also use a fresh number above the latest cloud build.
- Public Beta distribution remains an explicit release step. Configure no public
  group or App Store release action in this automatic internal workflow.

`ci_scripts/ci_post_clone.sh` lives beside the project, as required by Xcode
Cloud. It prepares the ignored `CloudSigning.xcconfig` from `CI_TEAM_ID`, installs
missing CMake/XcodeGen tools, downloads the production-locked OpenSSL source,
verifies its SHA-256 and builds it for iOS. It checks out the exact recorded
LibVNCClient revision and calls the normal managed builder's `--prepare-only`
mode, including its patch, source and provenance checks. Native outputs stay
outside the repository; `.cloud` only links to those outputs. This preparation
does not sign an app, upload it, publish a successful app-build report, or modify
the checked-in Xcode project.

Before `xcodebuild`, the pre-build hook verifies the actual resolved source
trees against every admitted package pin. It compiles the unmodified SwiftTerm
host generator and records approval for only `SwiftTermBuildInfoPlugin` at the
locked revision, using Xcode's per-plugin approval file on the disposable cloud
worker. It does not disable plugin or macro validation globally. The post-build
hook verifies that the resolved package sources remained unchanged.

For a local archive check, create ignored `CloudSigning.xcconfig` containing
`MACCOMPANION_DEVELOPMENT_TEAM = <your existing team>` and prepare dependencies:

```sh
python3 scripts/build_cloud_ios_dependencies.py --workspace /path/outside/checkout
```

Build through the managed compiler lease. Local unsigned archive success does
not confirm hosted signing, upload, processing, or tester-group delivery; verify
those gates in Xcode Cloud and App Store Connect.

`project.json` is the XcodeGen source for deliberate project-setting changes.
After editing it, regenerate and commit the project:

```sh
xcodegen generate --spec Native/iOSCloud/project.json --project Native/iOSCloud
python3 scripts/verify_xcode_cloud.py
bash scripts/validate.sh
```

The direct-client dependency policy also records the exact project/spec hashes
in `spec/dependency-policy/v0/direct-client-development.json`. Review and update
those hashes for an intentional project change before running validation.
The cloud lockfile may omit the unused historical ColorizeSwift pin; every
remaining pin must equal the normal direct-client lockfile. Other checked-in
projects retain their existing closed dependency policy.

Do not commit the local signing config, native binaries, provisioning profiles,
account tokens, build evidence, screenshots, or Xcode user state. The dependency
workspaces preserve previous generations; this workflow does not clean caches.

References: [Apple's project requirements](https://developer.apple.com/documentation/xcode/setting-up-your-project-to-use-xcode-cloud),
[custom build scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts),
and [TestFlight distribution](https://developer.apple.com/documentation/xcode/distributing-your-xcode-cloud-builds-through-testflight).

# Platform Authority Probe

This is a disposable Stage 0 harness. It proves API availability and records current preflight state without becoming a product target. Nothing under `Experiments/` may be linked into a release configuration.

The default path and `--preflight` inspect existing Screen Recording,
Accessibility, and containing-app service status. They do not request
permission or post input. `--enumerate-shareable-content` and
`--capture-encode-smoke` are explicit TCC-sensitive actions and must be run
only on a designated test account where the result can be recorded against the
exact provisional executable identity.

Build:

```sh
swift test --package-path Experiments/PlatformAuthorityProbe
```

Run the non-prompting preflight:

```sh
swift run --package-path Experiments/PlatformAuthorityProbe platform-authority-probe --preflight
```

Run the explicit first-frame smoke only after Screen Recording is already
granted manually in System Settings:

```sh
swift run --package-path Experiments/PlatformAuthorityProbe platform-authority-probe --capture-encode-smoke
```

The smoke command calls `CGPreflightScreenCaptureAccess()` first. When access is
absent it does not request permission, enumerate content, construct a stream,
or allocate an encoder. When access is present it selects only the display
matching `CGMainDisplayID()`, constructs the production Desktop capture and
VideoToolbox owners at 1,920×1,200/30 fps, requires one clean validated H.264
sample within five seconds, and tears down. Its closed JSON contains no pixels,
encoded bytes, byte counts, display identifiers, application/window metadata,
bundle identifiers, paths, raw timestamps, or framework error descriptions.

Repository validation runs the injected command/parser/timeout/cleanup tests
but never invokes a TCC-sensitive command. The source still compile-checks an
unposted pointer event; no CLI route posts input. A live smoke success would be
provisional evidence only: it would not prove final-app TCC attribution,
persistent capture entitlement, hardware encoder selection, lock behavior,
iPhone decode/render, peer identity, or release readiness.

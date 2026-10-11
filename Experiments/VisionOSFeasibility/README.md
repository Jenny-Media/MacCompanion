# Native visionOS feasibility

Disposable native application; never included in the client target. It links
the pinned LibVNCClient/OpenSSL, Citadel/NIOSSH and SwiftTerm together, displays
the native UIKit terminal, and probes public selection/drag input. No Mac,
credentials, camera, hand tracking entitlement or physical device is required.

Build with stable Xcode and the exact sources/archive admitted by the existing
development dependency policy:

```sh
python3 scripts/build_direct_visionos.py --probe --sdk xrsimulator \
  --source /absolute/path/to/clean/pinned/libvncserver \
  --openssl-archive /absolute/path/to/openssl-3.5.8.tar.gz \
  --output /private/tmp/maccompanion-visionos-probe-sim
```

Use `--sdk xros` with a different output directory for unsigned device-SDK
compilation. This does not install or contact hardware. Run the generated
`VisionOSDependencyProbe` scheme on an Apple Vision Pro Simulator for input
verification. Build outputs, logs and captures remain outside Git.

The native client must pass its own transport, input isolation and lifecycle
tests; this probe does not constitute client or physical acceptance. Apple
currently exposes no public system curved-window API for third-party apps.
Wide/ultrawide framebuffer support uses standard windows and preserves the
existing framebuffer bounds. The native input contract is indexed in the
single authoritative fixture manifest.

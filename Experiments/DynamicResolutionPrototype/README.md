# Screen resolution benchmark wrapper

The isolated Screen Resolution Lab originally established that the current
SSH/ARD path can request a virtual display from this Mac. The tested adapter now
lives in Native/VNC; no experiment source is linked into the normal application.
This wrapper retains its separate container and numeric benchmark sampler.
Normal testing and everyday use now happen in **Mac Companion** itself.

## Build and test

Build the normal client using its managed builder, then optionally build this
benchmark wrapper with `build.py --base <normal-build> --output <evidence> --sdk
iphonesimulator` (or iphoneos). `verify.py` checks indexed golden vectors,
numeric analysis and instrumentation preparation. The wrapper inherits the
normal **View & Display → Advanced** controls; the former Fit Phone menu is gone.

Desktop sizes are landscape and remain unchanged by rotation, keyboard, composer,
Fit or Zoom. See the normative [product contract](../../spec/capability-protocol/v0/ios-desktop-size.md).
A host refusal or different size never counts as acceptance. No new Apple
authentication, encrypted record layer, high-performance video or helper is added.
The first successful physical test does not establish compatibility with all Macs.
Reconnect need not restore the physical desktop.

## Repeatable numeric measurements

While the viewer is visible and active, the prototype samples once per second
and at numeric request/connection-state transitions, including immediate closure.
The fresh adapter snapshot includes monotonic uptime before asynchronous SSH
counter collection. An explicit allowlist removes all strings and arbitrary
nested fields. Serial off-main I/O writes
`Library/Caches/ScreenTransportBenchmark-v1.jsonl`. Owner tokens distinguish
reconnects and foreground sampling periods. One write may be in flight; further
samples are dropped rather than queued. Recording stops at 4 MiB without deleting
or overwriting prior evidence.

After exporting that one file, use:

```sh
python3 Experiments/DynamicResolutionPrototype/summarize.py \
  /private/tmp/exported-journal.jsonl --output /private/tmp/summary.json
```

Rates use only monotonic, adjacent, input-ready, same-owner/same-framebuffer
intervals, excluding resizes and sampling gaps. They measure UIKit delivery and
payload/copy/decoder counters, not physical screen or complete interaction
latency. Use the same output size, encoding and workload for application
comparisons; compare text quality separately.

The normative experiment contract and all golden vectors are in the existing
`spec/capability-protocol/v0/` and sole `spec/fixtures/manifest.json` index.

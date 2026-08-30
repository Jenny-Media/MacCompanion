# Performance acceptance profile v0.1

This directory freezes the performance claims that may be made before and
after physical acceptance. The canonical machine-readable profile is
[`profile.json`](profile.json). It does not turn a Debug Simulator observation
into an iPhone, Mac battery, energy, radio, thermal or release-build result.

## What is already numeric

The profile carries forward the existing product gates without weakening them:

- revocation closes a healthy local authenticated session within 1 second;
- Observe reconnect reaches a current snapshot at p95 within 3 seconds;
- Control reaches its first current frame at p95 within 2.5 seconds;
- glass latency is at most 150 ms p50 and 300 ms p95;
- pointer-to-visible response is at most 180 ms p50 and 350 ms p95;
- app/window selection, Smart Zoom and fallback are at most 1,000, 300 and
  500 ms p95;
- encoded video remains within 1920x1200, 2,304,000 pixels, 30 fps, an
  8-Mbit/s target and one waiting unencoded frame;
- the detailed audit remains within 16 MiB, 50,000 rows and 30 days, durable
  terminal operations retain for 30 days, and sanitized diagnostics retain
  only 256 events;
- the automated campaign requires seven distinct UTC dates, at least 518,400
  elapsed seconds and source binding.

Percentile gates require at least 40 valid raw monotonic samples for each exact
candidate/hardware/route profile. Revocation's maximum gate requires at least
20. Invalid, retried and excluded observations remain in the evidence with a
reason; they cannot simply disappear from the denominator.

The one-hour Control growth gate is now operational rather than the ambiguous
phrase “no unbounded growth”: after a ten-minute warm-up, compare ten-minute
windows, allow no more than 32 MiB median RSS growth and no more than 1 MiB per
minute fitted RSS slope. This is an early leak/growth rejection gate, not an
absolute RSS allowance.

## What still needs physical evidence

Absolute process CPU and RSS allowances, energy/battery impact, idle and
Observe network cost, complete installed log/database growth, pairing time and
text-session termination latency do not have an evidence-backed physical
baseline. They remain closed `requiresPhysicalMeasurementAndApproval` decisions
in the profile. Promotion must replace each status through an approved profile
revision or ADR after measuring the exact signed candidate. Missing numbers may
not be interpreted as unlimited use or a pass.

The pre-physical `ps` baseline remains useful for detecting gross Debug/
Simulator regressions, but Apple notes that device profiling is higher fidelity
than Simulator profiling. The physical lane uses Xcode performance tests and
the relevant Instruments templates: Time Profiler, Allocations/Leaks, Power
Profiler, Network and File Activity. Apple’s current primary guidance is:

- [Testing and performance](https://developer.apple.com/documentation/technologyoverviews/testing-and-performance)
- [Improving your app’s performance](https://developer.apple.com/documentation/xcode/improving-your-app-s-performance)
- [Analyzing your app’s battery use](https://developer.apple.com/documentation/xcode/analyzing-your-app-s-battery-use)
- [Performance and metrics](https://developer.apple.com/documentation/xcode/performance-and-metrics)

ETTrace is not wired into the active harness while the seven-date campaign is
running: temporary app-target instrumentation would change the campaign source
fingerprint. A later focused trace must bind one visible flow, the exact built
app and matching dSYMs, and remains diagnostic rather than physical power or
battery evidence.

Run the closed validator with:

```sh
python3 scripts/validate_performance_acceptance.py
```

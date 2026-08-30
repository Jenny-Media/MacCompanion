# Closed performance acceptance profile

Date: 2026-08-29

## Outcome

The remaining pre-physical performance ambiguity is now machine-checkable.
[`profile.json`](../../spec/performance-acceptance/v0/profile.json) freezes ten
existing latency gates, seven media caps, bounded one-hour RSS growth, the
source-bound seven-date soak, audit/operation/diagnostic caps, and eight exact
measurements that genuinely need physical evidence and approval. Missing
absolute resource numbers cannot be read as unlimited budgets or a pass.

The profile validator rejects weakened latency/media/growth/storage values,
unknown or missing fields, duplicate JSON keys, an overstated Simulator report,
a substituted source fingerprint, a physical-only decision labeled passed,
production-source cap drift and missing normative documentation links. It is
part of `scripts/validate.sh`. The focused exact-current command passed:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 scripts/validate_performance_acceptance.py
```

Result: 10 latency gates, 7 media caps, bounded growth/soak, durable caps and 8
closed physical-only decisions validated.

The complete exact-current gate then passed with this validator integrated:
1,769 Swift tests across 42 runs, 78 indexed JSON fixtures, 1,315 repository
files, all dependency/privacy/SBOM/signing/packaging/update/rollback/release
checks, production cross-builds and eight platform probes. The retained
temporary log is 340,700 bytes with SHA-256
`613df08c4da77915fcaedf07831bffc81675629c8deb6c14b0333d825bd459a3`.
The refreshed v0.2 `unsignedConstruction` manifest validates with SHA-256
`cb3790fbe7e74e8ef30e8131b02e7b0350263fa128c83aa403c05ded651f8c98`;
its artifact/executable lists are empty and promotion remains null.

## Measurement method

Percentiles require raw monotonic observations bound to one exact signed
candidate, hardware profile and healthy private LAN route. Each percentile has
at least 40 valid samples; the one-second revocation maximum has at least 20.
Excluded and failed observations remain in evidence with a reason.

The existing one-hour “no unbounded memory growth” requirement now rejects a
candidate when, after ten minutes of warm-up, comparable ten-minute windows
grow by more than 32 MiB median RSS or the fitted slope exceeds 1 MiB/minute.
This detects growth; it does not define the still-physical absolute RSS budget.

Apple recommends a baseline-and-comparison performance cycle, says device
profiling is higher fidelity than Simulator profiling, and routes CPU, memory,
power, file and network questions to the matching Xcode performance-test and
Instruments facilities. The profile records only current Apple primary sources:

- [Testing and performance](https://developer.apple.com/documentation/technologyoverviews/testing-and-performance)
- [Improving your app’s performance](https://developer.apple.com/documentation/xcode/improving-your-app-s-performance)
- [Analyzing your app’s battery use](https://developer.apple.com/documentation/xcode/analyzing-your-app-s-battery-use)
- [Performance and metrics](https://developer.apple.com/documentation/xcode/performance-and-metrics)

## ETTrace and source custody

The iOS performance workflow was reviewed for a focused symbolicated Simulator
trace. It requires temporarily linking ETTrace into the exact app target and
matching its dSYMs. Doing that now would change `Experiments/ClientUIHarness`
and reset the active source-bound seven-date campaign. No broad or
unsymbolicated trace was taken. A later trace must target one visible flow and
remains diagnostic; physical Power Profiler, energy, battery, radio and thermal
evidence cannot be replaced by ETTrace.

## Remaining physical decisions

The exact unresolved set is Mac absolute CPU and RSS, iOS absolute CPU and RSS,
Mac/iOS energy and battery impact, idle/Observe network bytes, complete
installed log/security/operation-store disk growth, pairing time and
text-session termination latency. Each must be measured against the stable
signed candidate and closed through a reviewed profile revision or ADR before
promotion.

No physical device, installed product, production credential or permission,
external account, upload or publication was used for this checkpoint.

#!/usr/bin/env python3
"""Check that missing, skipped, failed, or non-Simulator evidence cannot pass."""
from copy import deepcopy
from report_simulator_run import executions_match, verified_counts

baseline = {
    "totalTestCount": 3, "passedTests": 3, "failedTests": 0,
    "skippedTests": 0, "expectedFailures": 0,
    "devicesAndConfigurations": [{"device": {"platform": "iOS Simulator"}}],
}
assert verified_counts(baseline, 0)[1]
assert not verified_counts(baseline, 1)[1]
cases = [
    {"totalTestCount": 0, "passedTests": 0},
    {"passedTests": 2, "failedTests": 1},
    {"skippedTests": 1}, {"expectedFailures": 1},
    {"devicesAndConfigurations": []},
    {"devicesAndConfigurations": [{"device": {"platform": "iOS"}}]},
]
for changes in cases:
    assert not verified_counts(baseline | changes, 0)[1]
for invalid in (True, -1, "3", None):
    try:
        verified_counts(baseline | {"passedTests": invalid}, 0)
    except ValueError:
        pass
    else:
        raise AssertionError("Malformed count was accepted")
missing = deepcopy(baseline)
del missing["passedTests"]
try:
    verified_counts(missing, 0)
except KeyError:
    pass
else:
    raise AssertionError("Missing count was accepted")
assert executions_match("full", 1, 16)
assert not executions_match("full", 1, 15)
assert executions_match("journey-renewal", 3, 3)
assert not executions_match("journey-renewal", 3, 1)
assert executions_match("journey", 3, 3)
assert not executions_match("journey", 3, 1)
assert executions_match("semantic", 1, 1)
assert not executions_match("semantic", 1, 0)
assert not executions_match("journey", 0, 0)
assert not executions_match("unknown", 1, 1)
print("Validated 23 Simulator report pass/fail cases")

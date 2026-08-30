#!/usr/bin/env python3
"""Validate the closed Mac Companion performance acceptance profile."""
from __future__ import annotations

import copy
import json
from pathlib import Path
import re
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT / "spec/performance-acceptance/v0/profile.json"

EXPECTED_LATENCY = {
    "observe.revocationClosure.maximum": ("maximum", 1000, 20),
    "observe.reconnectCurrentSnapshot.p95": ("p95", 3000, 40),
    "control.firstCurrentFrame.p95": ("p95", 2500, 40),
    "control.glassLatency.p50": ("p50", 150, 40),
    "control.glassLatency.p95": ("p95", 300, 40),
    "control.pointerVisibleResponse.p50": ("p50", 180, 40),
    "control.pointerVisibleResponse.p95": ("p95", 350, 40),
    "surface.selectionKeyframe.p95": ("p95", 1000, 40),
    "surface.focusSmartZoom.p95": ("p95", 300, 40),
    "surface.fallback.p95": ("p95", 500, 40),
}
EXPECTED_PHYSICAL_DECISIONS = {
    "mac.absoluteIdleAndActiveCPU",
    "mac.absoluteServiceAndUIResidentMemory",
    "ios.absoluteClientCPUAndResidentMemory",
    "macAndIOS.energyAndBatteryImpact",
    "idleAndObserve.networkBytes",
    "installedLogsSecurityStoreAndOperationStore.diskGrowth",
    "pairing.timeToReady",
    "textSession.terminationLatency",
}
EXPECTED_SOURCES = {
    "https://developer.apple.com/documentation/technologyoverviews/testing-and-performance",
    "https://developer.apple.com/documentation/xcode/improving-your-app-s-performance",
    "https://developer.apple.com/documentation/xcode/analyzing-your-app-s-battery-use",
    "https://developer.apple.com/documentation/xcode/performance-and-metrics",
}


class DuplicateKeyError(ValueError):
    pass


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKeyError(f"duplicate key: {key}")
        result[key] = value
    return result


def exact_keys(value: Any, expected: set[str], name: str) -> None:
    if not isinstance(value, dict) or set(value) != expected:
        raise ValueError(f"{name} has unknown or missing fields")


def load_json(path: Path) -> dict[str, Any]:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 128 * 1024:
        raise ValueError(f"unsafe JSON file: {path}")
    value = json.loads(path.read_text(), object_pairs_hook=unique_object)
    if not isinstance(value, dict):
        raise ValueError(f"JSON root is not an object: {path}")
    return value


def validate(value: dict[str, Any], root: Path = ROOT) -> None:
    exact_keys(value, {
        "schemaVersion", "profileID", "status", "measurementMethod",
        "latencyGates", "mediaCaps", "boundedGrowthGates", "durableCaps",
        "prePhysicalBaseline", "physicalOnlyDecisions",
        "officialMeasurementSources",
    }, "profile")
    if value["schemaVersion"] != 1 \
            or value["profileID"] != "maccompanion.performance-acceptance.v0.1" \
            or value["status"] != "prePhysicalFrozen":
        raise ValueError("invalid profile identity or status")

    method = value["measurementMethod"]
    exact_keys(method, {
        "candidateBindingRequired", "cleanStableToolchainRequiredForPromotion",
        "healthyLANDefinition", "minimumLatencySamplesPerPercentile",
        "rawMonotonicTimestampsRequired", "simulatorEvidenceClassification",
        "physicalInstruments",
    }, "measurementMethod")
    if method["candidateBindingRequired"] is not True \
            or method["cleanStableToolchainRequiredForPromotion"] is not True \
            or method["minimumLatencySamplesPerPercentile"] != 40 \
            or method["rawMonotonicTimestampsRequired"] is not True \
            or method["simulatorEvidenceClassification"] != "diagnosticOnly" \
            or len(method["physicalInstruments"]) != 6:
        raise ValueError("invalid measurement method")

    gates = value["latencyGates"]
    if not isinstance(gates, list) or len(gates) != len(EXPECTED_LATENCY):
        raise ValueError("invalid latency gate count")
    seen: set[str] = set()
    for gate in gates:
        exact_keys(gate, {
            "id", "metric", "percentile", "maximumInclusiveMilliseconds",
            "minimumSamples",
        }, "latency gate")
        identifier = gate["id"]
        if identifier in seen or identifier not in EXPECTED_LATENCY:
            raise ValueError("unknown or duplicate latency gate")
        seen.add(identifier)
        expected = EXPECTED_LATENCY[identifier]
        if (gate["percentile"], gate["maximumInclusiveMilliseconds"],
                gate["minimumSamples"]) != expected \
                or not isinstance(gate["metric"], str) or not gate["metric"]:
            raise ValueError(f"changed latency gate: {identifier}")

    media = value["mediaCaps"]
    exact_keys(media, {
        "maximumEncodedWidthPixels", "maximumEncodedHeightPixels",
        "maximumEncodedPixelCount", "maximumFramesPerSecond",
        "targetBitrateBitsPerSecond", "maximumInitialKeyframeIntervalMilliseconds",
        "maximumWaitingUnencodedFrames",
    }, "mediaCaps")
    if media != {
        "maximumEncodedWidthPixels": 1920,
        "maximumEncodedHeightPixels": 1200,
        "maximumEncodedPixelCount": 2_304_000,
        "maximumFramesPerSecond": 30,
        "targetBitrateBitsPerSecond": 8_000_000,
        "maximumInitialKeyframeIntervalMilliseconds": 2_000,
        "maximumWaitingUnencodedFrames": 1,
    }:
        raise ValueError("media caps diverged from Interactive Control v0")

    growth = value["boundedGrowthGates"]
    exact_keys(growth, {
        "controlSessionDurationSeconds", "controlWarmupSeconds",
        "rssComparisonWindowSeconds", "maximumMedianRSSGrowthMiB",
        "maximumRSSSlopeMiBPerMinute", "adaptiveMetadataCacheMustRemainBounded",
        "sevenDayObserveDistinctUTCDates", "sevenDayObserveMinimumSpanSeconds",
        "minimumDailySoakRunSeconds", "sourceBindingRequired",
    }, "boundedGrowthGates")
    if growth != {
        "controlSessionDurationSeconds": 3600,
        "controlWarmupSeconds": 600,
        "rssComparisonWindowSeconds": 600,
        "maximumMedianRSSGrowthMiB": 32,
        "maximumRSSSlopeMiBPerMinute": 1,
        "adaptiveMetadataCacheMustRemainBounded": True,
        "sevenDayObserveDistinctUTCDates": 7,
        "sevenDayObserveMinimumSpanSeconds": 518_400,
        "minimumDailySoakRunSeconds": 180,
        "sourceBindingRequired": True,
    }:
        raise ValueError("invalid bounded-growth or soak gate")

    durable = value["durableCaps"]
    exact_keys(durable, {
        "auditLogicalBytes", "auditRows", "auditRetentionMilliseconds",
        "auditAppendAttemptsPerMinutePerBucket",
        "operationTerminalRetentionMilliseconds", "sanitizedDiagnosticEvents",
    }, "durableCaps")
    if durable != {
        "auditLogicalBytes": 16_777_216,
        "auditRows": 50_000,
        "auditRetentionMilliseconds": 2_592_000_000,
        "auditAppendAttemptsPerMinutePerBucket": 120,
        "operationTerminalRetentionMilliseconds": 2_592_000_000,
        "sanitizedDiagnosticEvents": 256,
    }:
        raise ValueError("invalid durable cap")

    baseline = value["prePhysicalBaseline"]
    exact_keys(baseline, {
        "path", "testedSourceSHA256", "budgetsEvaluated", "classification",
    }, "prePhysicalBaseline")
    baseline_path = root / baseline["path"]
    report = load_json(baseline_path)
    if baseline["classification"] != "diagnosticOnly" \
            or baseline["budgetsEvaluated"] is not False \
            or report.get("result") != "passed" \
            or report.get("environment") != "iOS Simulator" \
            or report.get("physicalDeviceUsed") is not False \
            or report.get("installedMacAppUsed") is not False \
            or report.get("budgetsEvaluated") is not False \
            or report.get("testedSourceSHA256") != baseline["testedSourceSHA256"]:
        raise ValueError("pre-physical baseline was overstated or substituted")

    decisions = value["physicalOnlyDecisions"]
    if not isinstance(decisions, list) \
            or {item.get("id") for item in decisions} != EXPECTED_PHYSICAL_DECISIONS:
        raise ValueError("physical-only decisions are incomplete")
    for item in decisions:
        exact_keys(item, {"id", "status"}, "physicalOnlyDecision")
        if item["status"] != "requiresPhysicalMeasurementAndApproval":
            raise ValueError("an unresolved physical budget was overstated")

    sources = value["officialMeasurementSources"]
    if not isinstance(sources, list) or set(sources) != EXPECTED_SOURCES \
            or len(sources) != len(EXPECTED_SOURCES):
        raise ValueError("official measurement sources changed")

    audit_source = (root / "Packages/MacCompanionKit/Sources/CompanionPersistence/SQLiteBoundedAuditStoreV0.swift").read_text()
    operation_source = (root / "Packages/MacCompanionKit/Sources/CompanionPersistence/SQLiteSecurityStore.swift").read_text()
    diagnostic_source = (root / "Packages/MacCompanionKit/Sources/CompanionAgent/AgentSanitizedDiagnosticsAuthorityV1.swift").read_text()
    required_source_patterns = (
        (audit_source, r"logicalByteLimit:\s*16 \* 1_024 \* 1_024"),
        (audit_source, r"retainedRowLimit:\s*50_000"),
        (audit_source, r"retentionMilliseconds:\s*30 \* 24 \* 60 \* 60 \* 1_000"),
        (audit_source, r"rateLimitAttempts:\s*120"),
        (operation_source, r"operationRetentionMilliseconds:\s*Int64 = 30 \* 24 \* 60 \* 60 \* 1_000"),
        (diagnostic_source, r"maximumRetainedEventCount = 256"),
    )
    if any(re.search(pattern, source) is None for source, pattern in required_source_patterns):
        raise ValueError("durable cap no longer matches production source")

    documentation_requirements = {
        "docs/mvp-plan.md": "spec/performance-acceptance/v0/profile.json",
        "docs/physical-acceptance-checklist.md": "requiresPhysicalMeasurementAndApproval",
        "docs/pre-physical-execution-plan.md": "closed performance profile",
        "docs/execution-status.md": "performance acceptance profile",
    }
    for relative, required_text in documentation_requirements.items():
        if required_text not in (root / relative).read_text():
            raise ValueError(f"performance profile is not reconciled in {relative}")


def self_test(value: dict[str, Any]) -> None:
    changed = copy.deepcopy(value)
    changed["latencyGates"][0]["maximumInclusiveMilliseconds"] = 1001
    try:
        validate(changed)
    except ValueError:
        pass
    else:
        raise AssertionError("weakened latency gate passed")

    overstated = copy.deepcopy(value)
    overstated["physicalOnlyDecisions"][0]["status"] = "passed"
    try:
        validate(overstated)
    except ValueError:
        pass
    else:
        raise AssertionError("unmeasured physical budget passed")

    substituted = copy.deepcopy(value)
    substituted["prePhysicalBaseline"]["testedSourceSHA256"] = "0" * 64
    try:
        validate(substituted)
    except ValueError:
        pass
    else:
        raise AssertionError("substituted baseline passed")


def main() -> int:
    try:
        profile = load_json(PROFILE)
        validate(profile)
        self_test(profile)
    except (OSError, ValueError, DuplicateKeyError, AssertionError, json.JSONDecodeError) as error:
        print(f"performance acceptance validation failed: {error}", file=sys.stderr)
        return 1
    print(
        "Validated performance acceptance profile: 10 latency gates, "
        "7 media caps, bounded growth/soak, durable caps, and 8 closed "
        "physical-only decisions."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

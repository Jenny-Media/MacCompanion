#!/usr/bin/env python3
"""Fail closed if the pre-physical completion audit overstates readiness."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "docs/evidence/prephysical-completion-audit.json"
SOAK_RUNNER = ROOT / "scripts/run_prephysical_soak.py"
EXPECTED_COMPLETED = {f"P{index}" for index in range(1, 8)} | {"P9", "P10"}
EXPECTED_REMAINING = {
    "P8-P11.elapsed-soak",
    "physical.iphone-hardware-custody",
    "physical.real-platform-effects",
    "physical.real-routes-and-permissions",
    "physical.performance-and-usability",
    "authorization.installed-product-and-system-state",
    "authorization.independent-review",
    "external.stable-toolchain-and-distribution",
    "external.apple-capture-disposition",
    "external.legal-privacy-trademark",
    "external.publication-and-market-evidence",
}
ALLOWED_COMPLETED = {
    "passedAutomated",
    "passedAutomatedWithPhysicalEffectSubstituted",
    "passedAutomatedWithPhysicalUXPending",
    "passedLocalConstructionOnly",
    "passedAutomatedReviewPendingAuthorization",
}
ALLOWED_REMAINING = {
    "elapsedTime", "physicalHardware", "freshAuthorization",
    "externalApprovalOrResource",
}


def load_soak_module():
    spec = importlib.util.spec_from_file_location("maccompanion_soak", SOAK_RUNNER)
    if spec is None or spec.loader is None:
        raise RuntimeError("soak runner module unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def require_evidence(paths: object) -> None:
    if not isinstance(paths, list) or not paths:
        raise ValueError("audit requirement lacks evidence")
    for value in paths:
        if not isinstance(value, str) or value.startswith("/") or ".." in Path(value).parts:
            raise ValueError("audit evidence path is not repository relative")
        location = ROOT / value
        if not location.is_file() or location.is_symlink():
            raise ValueError(f"audit evidence is unavailable or unsafe: {value}")


def main() -> int:
    audit = json.loads(AUDIT.read_text())
    if set(audit) != {
        "schemaVersion", "status", "objective", "sourceBinding",
        "completedRequirements", "remainingRequirements",
        "automatableRequiredPathFailures",
    }:
        raise ValueError("invalid completion-audit top-level shape")
    if audit["schemaVersion"] != 1 or audit["objective"] != "readinessForPhysicalAcceptanceTesting":
        raise ValueError("invalid completion-audit identity")
    if audit["automatableRequiredPathFailures"] != []:
        raise ValueError("completion audit contains an unresolved automatable failure")

    completed = audit["completedRequirements"]
    if not isinstance(completed, list) or {item.get("id") for item in completed} != EXPECTED_COMPLETED:
        raise ValueError("completion audit has incomplete or duplicate completed requirements")
    for item in completed:
        if set(item) != {"id", "status", "evidence"} or item["status"] not in ALLOWED_COMPLETED:
            raise ValueError(f"invalid completed requirement: {item.get('id')}")
        require_evidence(item["evidence"])

    remaining = audit["remainingRequirements"]
    if not isinstance(remaining, list) or {item.get("id") for item in remaining} != EXPECTED_REMAINING:
        raise ValueError("completion audit has incomplete or duplicate remaining requirements")
    for item in remaining:
        if set(item) != {"id", "classification", "reason", "evidence"}:
            raise ValueError(f"invalid remaining requirement: {item.get('id')}")
        if item["classification"] not in ALLOWED_REMAINING or not isinstance(item["reason"], str) \
                or len(item["reason"].strip()) < 40:
            raise ValueError(f"unjustified remaining requirement: {item.get('id')}")
        require_evidence(item["evidence"])

    binding = audit["sourceBinding"]
    if set(binding) != {
        "soakSourceSHA256", "ledger", "requiredDistinctUTCDates",
        "minimumElapsedSpanSeconds",
    }:
        raise ValueError("invalid audit source binding")
    ledger_path = ROOT / binding["ledger"]
    ledger = json.loads(ledger_path.read_text())
    if binding["requiredDistinctUTCDates"] != ledger.get("requiredDistinctUTCDates") \
            or binding["minimumElapsedSpanSeconds"] != ledger.get("minimumCampaignSpanSeconds"):
        raise ValueError("completion audit weakens the soak thresholds")
    bound_source = binding["soakSourceSHA256"]
    campaign = next(
        (item for item in ledger.get("campaigns", []) if item.get("sourceSHA256") == bound_source),
        None,
    )
    if campaign is None:
        raise ValueError("completion audit source has no soak campaign")

    soak = load_soak_module()
    current = soak.source_fingerprint()
    if bound_source != current:
        if audit["status"] != "supersededSource":
            raise ValueError(
                "completion audit does not bind the current soak source and "
                "is not marked superseded"
            )
        print(
            "Validated superseded pre-physical completion audit: the retained "
            "campaign remains source-bound historical evidence and makes no "
            "readiness claim for the current source."
        )
        return 0

    complete = campaign.get("status", {}).get("complete") is True
    expected_status = "readyForFinalReconciliation" if complete else "waitingElapsedSoak"
    if audit["status"] != expected_status:
        raise ValueError("completion-audit status disagrees with the soak ledger")
    print(
        "Validated pre-physical completion audit: 9 automated/local requirements, "
        "1 elapsed-time gate, 4 physical groups, 2 fresh-authority groups, "
        "and 4 external groups; no unresolved automatable required-path failure."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

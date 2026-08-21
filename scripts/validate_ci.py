#!/usr/bin/env python3

from __future__ import annotations

import re
from pathlib import Path


repository = Path(__file__).resolve().parents[1]
workflow_root = repository / ".github" / "workflows"
uses_pattern = re.compile(r"^\s*(?:-\s*)?uses:\s*([^\s#]+)")
commit_pattern = re.compile(r"^[0-9a-f]{40}$")
digest_pattern = re.compile(r"^sha256:[0-9a-f]{64}$")


def validate_reference(reference: str) -> str | None:
    reference = reference.strip("'\"")
    if reference.startswith("./"):
        return None
    if reference.startswith("docker://"):
        _, separator, digest = reference.rpartition("@")
        if separator and digest_pattern.fullmatch(digest):
            return None
        return "container actions must use an immutable sha256 digest"

    action, separator, revision = reference.rpartition("@")
    if not separator or not action or not commit_pattern.fullmatch(revision):
        return "remote actions must use a full 40-character lowercase commit SHA"
    return None


def main() -> int:
    failures: list[str] = []
    workflows = sorted(workflow_root.glob("*.yml")) + sorted(
        workflow_root.glob("*.yaml")
    )
    if not workflows:
        failures.append(".github/workflows: no workflow files found")

    for workflow in workflows:
        for line_number, line in enumerate(
            workflow.read_text(encoding="utf-8").splitlines(),
            start=1,
        ):
            match = uses_pattern.match(line)
            if match is None:
                continue
            reference = match.group(1)
            reason = validate_reference(reference)
            if reason is not None:
                relative = workflow.relative_to(repository)
                failures.append(
                    f"{relative}:{line_number}: {reason}: {reference}"
                )

    if failures:
        for failure in failures:
            print(failure)
        return 1

    print(f"validated {len(workflows)} workflow file(s): immutable action references")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

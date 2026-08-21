#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import uuid
from datetime import datetime
from pathlib import Path, PurePosixPath

from validate_sbom import validate_document


REPOSITORY = Path(__file__).resolve().parents[1]
POLICY_PATH = REPOSITORY / "spec" / "dependency-policy" / "v0" / "policy.json"


def command_output(command: list[str]) -> str:
    completed = subprocess.run(
        command,
        cwd=REPOSITORY,
        env=os.environ.copy(),
        text=True,
        capture_output=True,
        timeout=30,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip().splitlines()
        reason = detail[-1] if detail else f"exit {completed.returncode}"
        raise ValueError(f"command failed: {' '.join(command)}: {reason}")
    return completed.stdout.strip()


def safe_relative_path(value: str) -> bool:
    if not value or "\\" in value:
        return False
    path = PurePosixPath(value)
    return not path.is_absolute() and all(part not in {"", ".", ".."} for part in path.parts)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence-root", required=True, type=Path)
    parser.add_argument("--output", default="supply-chain/source-dependencies.spdx.json")
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--created", required=True)
    parser.add_argument("--targets", nargs="+", choices=("ios", "macos"), required=True)
    arguments = parser.parse_args()
    try:
        if re.fullmatch(r"[0-9A-Za-z][0-9A-Za-z.+-]{0,63}", arguments.version) is None:
            raise ValueError("version must be a bounded SPDX-compatible version string")
        if re.fullmatch(r"[1-9][0-9]{0,17}", arguments.build) is None:
            raise ValueError("build must be a positive decimal integer")
        if re.fullmatch(
            r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z",
            arguments.created,
        ) is None:
            raise ValueError("created must use exact UTC YYYY-MM-DDThh:mm:ssZ form")
        try:
            datetime.strptime(arguments.created, "%Y-%m-%dT%H:%M:%SZ")
        except ValueError as error:
            raise ValueError("created is not a real UTC calendar time") from error
        targets = sorted(set(arguments.targets))
        if len(targets) != len(arguments.targets):
            raise ValueError("targets must be unique")
        if not safe_relative_path(arguments.output):
            raise ValueError("output must be a safe relative POSIX path")
        evidence_root = arguments.evidence_root.resolve()
        if not evidence_root.is_dir():
            raise ValueError("evidence root must be an existing directory")
        output = (evidence_root / arguments.output).resolve()
        try:
            output.relative_to(evidence_root)
        except ValueError as error:
            raise ValueError("output escapes evidence root") from error
        if output.exists() or output.is_symlink():
            raise ValueError("output already exists")
        output.parent.mkdir(parents=True, exist_ok=True)
        try:
            output.parent.resolve().relative_to(evidence_root)
        except ValueError as error:
            raise ValueError("output parent escapes evidence root") from error

        command_output([sys.executable, str(REPOSITORY / "scripts" / "validate_dependency_policy.py")])
        policy_bytes = POLICY_PATH.read_bytes()
        policy = json.loads(policy_bytes)
        if any(
            policy.get(key) is not False
            for key in (
                "remoteDependenciesAllowed",
                "binaryTargetsAllowed",
                "buildToolPluginsAllowed",
            )
        ):
            raise ValueError("dependency policy does not prove a closed source graph")

        revision = command_output(["git", "rev-parse", "HEAD"])
        if re.fullmatch(r"[0-9a-f]{40}", revision) is None:
            raise ValueError("Git revision is not a full lowercase commit SHA")
        dirty = bool(command_output(["git", "status", "--porcelain=v1", "--untracked-files=normal"]))
        target_text = ",".join(targets)
        seed = "\n".join(
            [
                "maccompanion-source-sbom-v0.1",
                arguments.version,
                arguments.build,
                arguments.created,
                revision,
                str(dirty).lower(),
                target_text,
                hashlib.sha256(policy_bytes).hexdigest(),
            ]
        )
        namespace_id = uuid.uuid5(uuid.NAMESPACE_URL, seed)
        package_common = {
            "versionInfo": arguments.version,
            "supplier": "Organization: Jenny Media LLC",
            "downloadLocation": "NOASSERTION",
            "filesAnalyzed": False,
            "licenseConcluded": "NOASSERTION",
            "licenseDeclared": "NOASSERTION",
            "copyrightText": "NOASSERTION",
        }
        document = {
            "SPDXID": "SPDXRef-DOCUMENT",
            "spdxVersion": "SPDX-2.3",
            "dataLicense": "CC0-1.0",
            "name": f"Mac-Companion-{arguments.version}-{arguments.build}-source-dependencies",
            "documentNamespace": f"https://spdx.org/spdxdocs/mac-companion-{namespace_id}",
            "creationInfo": {
                "created": arguments.created,
                "creators": [
                    "Organization: Jenny Media LLC",
                    "Tool: Mac Companion source SBOM generator-0.1",
                ],
            },
            "documentDescribes": ["SPDXRef-Package-MacCompanion"],
            "comment": (
                f"Source dependency inventory for targets {target_text} at Git revision "
                f"{revision} (dirty={str(dirty).lower()}). This is not artifact "
                "composition or license evidence."
            ),
            "packages": [
                {
                    "SPDXID": "SPDXRef-Package-MacCompanion",
                    "name": "Mac Companion",
                    "primaryPackagePurpose": "APPLICATION",
                    "comment": "First-party release source graph; artifact composition is not asserted.",
                    **package_common,
                },
                {
                    "SPDXID": "SPDXRef-Package-MacCompanionKit",
                    "name": "MacCompanionKit",
                    "primaryPackagePurpose": "LIBRARY",
                    "comment": "First-party in-repository Swift package; no external package dependency.",
                    **package_common,
                },
            ],
            "relationships": [
                {
                    "spdxElementId": "SPDXRef-DOCUMENT",
                    "relationshipType": "DESCRIBES",
                    "relatedSpdxElement": "SPDXRef-Package-MacCompanion",
                },
                {
                    "spdxElementId": "SPDXRef-Package-MacCompanion",
                    "relationshipType": "CONTAINS",
                    "relatedSpdxElement": "SPDXRef-Package-MacCompanionKit",
                },
                {
                    "spdxElementId": "SPDXRef-Package-MacCompanionKit",
                    "relationshipType": "DEPENDS_ON",
                    "relatedSpdxElement": "NONE",
                },
            ],
        }
        failures = validate_document(document)
        if failures:
            raise ValueError(f"generated document failed validation: {','.join(failures)}")
        encoded = (json.dumps(document, indent=2, sort_keys=True) + "\n").encode("utf-8")
        temporary = output.with_name(f".{output.name}.{os.getpid()}.tmp")
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            with os.fdopen(descriptor, "wb") as handle:
                handle.write(encoded)
                handle.flush()
                os.fsync(handle.fileno())
            os.link(temporary, output, follow_symlinks=False)
            directory = os.open(output.parent, os.O_RDONLY)
            try:
                os.fsync(directory)
                temporary.unlink()
                os.fsync(directory)
            finally:
                os.close(directory)
        finally:
            if temporary.exists():
                temporary.unlink()
        print(output)
        print(hashlib.sha256(encoded).hexdigest())
        return 0
    except (OSError, ValueError, subprocess.SubprocessError, json.JSONDecodeError) as error:
        print(f"source SBOM generation failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

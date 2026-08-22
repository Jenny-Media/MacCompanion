#!/usr/bin/env python3

from __future__ import annotations

import copy
import hashlib
import os
import stat
import tempfile
from dataclasses import replace
from pathlib import Path
from typing import Any, Callable

from artifact_sbom import canonical_bytes
import platform_codesign_inspection as inspection_module
from platform_codesign_inspection import (
    MAX_CERTIFICATE_BYTES,
    PlatformCodesignInspectionError,
    _require_certificate_prefix_clear,
    _retain_extracted_certificates,
    execute_codesign_architecture_inspection_plans,
    validate_codesign_architecture_records,
)
from platform_codesign_verification import _composition_by_id, _rehash_subject
from platform_signing_fixed_tools import (
    FixedToolInvocation,
    inspect_fixed_tool,
    prepare_private_work_root,
)
from platform_signing_subjects import (
    derive_codesign_architecture_inspection_plans,
    derive_codesign_verification_plans,
    reconstruct_signing_subjects,
)
from signing_policy_fixture import generate_fixture_policy
from validate_platform_signing_subjects import TEAM_ID
from validate_signed_code_graph import write_fixture


CERTIFICATE = b"Mac Companion synthetic extracted leaf certificate"
CERTIFICATE_SHA256 = hashlib.sha256(CERTIFICATE).hexdigest()


def require_failure(operation: Callable[[], Any], expected: str) -> None:
    try:
        operation()
    except PlatformCodesignInspectionError as error:
        if expected not in str(error):
            raise RuntimeError(
                f"expected execution failure containing {expected!r}, got {error!r}"
            ) from error
    else:
        raise RuntimeError(
            f"expected execution failure containing {expected!r}"
        )


def write_private(path: Path, content: bytes, mode: int = 0o600) -> dict[str, Any]:
    descriptor = os.open(
        path,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
        mode,
    )
    try:
        cursor = 0
        while cursor < len(content):
            cursor += os.write(descriptor, content[cursor:])
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    return {
        "path": path.name,
        "bytes": len(content),
        "sha256": hashlib.sha256(content).hexdigest(),
    }


def invocation_result(
    invocation: FixedToolInvocation,
    work_root: Path,
    stdout: bytes,
    stderr: bytes,
    *,
    passed: bool = True,
) -> dict[str, Any]:
    stdout_reference = write_private(
        work_root / f"{invocation.invocation_id}.stdout",
        stdout,
    )
    stderr_reference = write_private(
        work_root / f"{invocation.invocation_id}.stderr",
        stderr,
    )
    return {
        "invocationID": invocation.invocation_id,
        "tool": invocation.tool.public_record(),
        "argv": [invocation.tool.path, *invocation.arguments],
        "environment": {
            "HOME": str(work_root),
            "TMPDIR": str(work_root),
            "LANG": "C",
            "LC_ALL": "C",
        },
        "timeoutSeconds": invocation.timeout_seconds,
        "outputLimitBytesPerStream": 1024 * 1024,
        "startedAt": "2026-08-22T12:00:00.000Z",
        "completedAt": "2026-08-22T12:00:01.000Z",
        "durationMilliseconds": 1000,
        "termination": "exited",
        "returnCode": 0 if passed else 1,
        "toolUnchanged": True,
        "stdout": stdout_reference,
        "stderr": stderr_reference,
        "passed": passed,
    }


def reference(label: str, value: dict[str, Any]) -> dict[str, Any]:
    content = canonical_bytes(value)
    return {
        "path": f"verification/{label}.json",
        "bytes": len(content),
        "sha256": hashlib.sha256(content).hexdigest(),
    }


def prepare(root: Path) -> dict[str, Any]:
    index, composition, release, graph = write_fixture(root, "mac", "none")
    work_root = root / "platform-signing-work"
    prepare_private_work_root(work_root)
    subjects = reconstruct_signing_subjects(
        index=index,
        composition=composition,
        graph=graph,
        evidence_root=root,
        work_root=work_root,
    )
    codesign = inspect_fixed_tool("apple.codesign", "/usr/bin/codesign")
    verification_plans = derive_codesign_verification_plans(
        graph=graph,
        reconstructed=subjects,
        team_id=TEAM_ID,
        codesign_tool=codesign,
    )
    plans = derive_codesign_architecture_inspection_plans(
        graph=graph,
        reconstructed=subjects,
        codesign_tool=codesign,
    )
    policy_release = copy.deepcopy(release)
    policy_release["release"]["channel"] = "beta"
    app_bundle_identifier = graph["artifacts"][0]["bundles"][0][
        "bundleIdentifier"
    ]
    for executable in policy_release["executables"]:
        if executable["id"] == "mac-app":
            executable.update({
                "role": "macApp",
                "platform": "macOS",
                "bundleIdentifier": app_bundle_identifier,
            })
        elif executable["id"] == "mac-agent":
            executable.update({
                "role": "agent",
                "platform": "macOS",
                "bundleIdentifier": f"{app_bundle_identifier}.agent",
            })
        else:
            raise RuntimeError("unexpected signing execution fixture executable")
    policy = generate_fixture_policy(
        release=policy_release,
        graph=graph,
        graph_reference=reference("signed-code-graph", graph),
        artifact_sbom_reference=graph["artifactSBOM"],
    )
    for signer in policy["officialSigners"]:
        signer["leafCertificateSHA256"] = CERTIFICATE_SHA256
    for artifact in policy["artifacts"]:
        for item in artifact["objects"]:
            for architecture in item["architectures"]:
                architecture["identity"][
                    "leafCertificateSHA256"
                ] = CERTIFICATE_SHA256
    entries_by_id = _composition_by_id(composition)
    subjects_by_id = {item.artifact_id: item for item in subjects}
    verification_records = []
    for plan in verification_plans:
        subject = subjects_by_id[plan.artifact_id]
        current = _rehash_subject(
            subject,
            entries_by_id[plan.artifact_id],
            work_root,
        )
        stderr = (
            f"{plan.owned_subject_path}: valid on disk\n"
            f"{plan.owned_subject_path}: satisfies its Designated Requirement\n"
            f"{plan.owned_subject_path}: explicit requirement satisfied\n"
        ).encode("utf-8")
        result = invocation_result(
            plan.invocation,
            work_root,
            b"",
            stderr,
        )
        verification_records.append({
            "artifactID": plan.artifact_id,
            "objectPath": plan.object_path,
            "subjectBefore": current,
            "invocation": result,
            "verification": {
                "status": "passed",
                "reason": None,
                "messages": [
                    "validOnDisk",
                    "satisfiesDesignatedRequirement",
                    "explicitRequirementSatisfied",
                ],
            },
            "subjectAfter": current,
        })
    return {
        "index": index,
        "releaseManifest": policy_release,
        "composition": composition,
        "graph": graph,
        "evidenceRoot": root,
        "workRoot": work_root,
        "subjects": subjects,
        "plans": plans,
        "policy": policy,
        "verificationRecords": verification_records,
    }


def policy_map(policy: dict[str, Any]) -> dict[tuple[str, str, int, int], dict[str, Any]]:
    return {
        (
            artifact["artifact"]["id"],
            item["path"],
            architecture["cpuType"],
            architecture["cpuSubtype"],
        ): architecture
        for artifact in policy["artifacts"]
        for item in artifact["objects"]
        for architecture in item["architectures"]
    }


def fake_embedded_inspector(context: dict[str, Any]):
    plans_by_key = {
        (
            str(plan.owned_source_path),
            plan.cpu_type,
            plan.cpu_subtype,
        ): plan
        for plan in context["plans"]
    }
    policies = policy_map(context["policy"])

    def inspect(*, object_path: Path, graph_architecture: dict[str, Any]) -> dict[str, Any]:
        plan = plans_by_key[
            (
                str(object_path),
                graph_architecture["cpuType"],
                graph_architecture["cpuSubtype"],
            )
        ]
        architecture = policies[
            (
                plan.artifact_id,
                plan.source_path,
                plan.cpu_type,
                plan.cpu_subtype,
            )
        ]
        identity = architecture["identity"]
        return {
            "cpuType": architecture["cpuType"],
            "cpuSubtype": architecture["cpuSubtype"],
            "sliceSHA256": architecture["sliceSHA256"],
            "signingIdentifier": identity["signingIdentifier"],
            "teamIdentifier": identity["teamIdentifier"],
            "codeDirectories": copy.deepcopy(identity["codeDirectories"]),
            "codeDirectoryVersion": 0x20500,
            "codeDirectoryFlags": 0x10000,
            "hardenedRuntime": architecture["signature"]["requireHardenedRuntime"],
            "designatedRequirementDataSHA256": identity[
                "designatedRequirementDataSHA256"
            ],
            "designatedRequirementBytes": 16,
            "entitlements": copy.deepcopy(architecture["entitlements"]),
            "entitlementBlobs": {"xmlSHA256": None, "derSHA256": None},
            "cmsSHA256": "a" * 64,
            "embeddedSignatureSHA256": "b" * 64,
            "signatureSuperBlobSHA256": "c" * 64,
            "signaturePaddingBytes": 0,
        }

    return inspect


def fake_runner(
    context: dict[str, Any],
    *,
    fail_identity: bool = False,
    partial_certificate: bool = False,
):
    by_invocation = {
        plan.identity_invocation.invocation_id: (plan, "identity")
        for plan in context["plans"]
    }
    by_invocation.update({
        plan.entitlements_invocation.invocation_id: (plan, "entitlements")
        for plan in context["plans"]
    })
    policies = policy_map(context["policy"])

    def run(invocation: FixedToolInvocation, work_root: Path) -> dict[str, Any]:
        plan, kind = by_invocation[invocation.invocation_id]
        architecture = policies[
            (
                plan.artifact_id,
                plan.source_path,
                plan.cpu_type,
                plan.cpu_subtype,
            )
        ]
        identity = architecture["identity"]
        if kind == "identity":
            if fail_identity:
                if partial_certificate:
                    write_private(
                        Path(f"{plan.certificate_prefix}0"),
                        CERTIFICATE,
                        0o644,
                    )
                return invocation_result(
                    invocation,
                    work_root,
                    b"candidate failure\n",
                    b"candidate failure\n",
                    passed=False,
                )
            write_private(
                Path(f"{plan.certificate_prefix}0"),
                CERTIFICATE,
                0o644,
            )
            requirement = (
                f'designated => identifier "{identity["signingIdentifier"]}" '
                "and anchor apple generic\n"
            ).encode("utf-8")
            code_directory = identity["codeDirectories"][0]
            lines = [
                f"Executable={plan.owned_source_path}",
                f"Identifier={identity['signingIdentifier']}",
                "Format=Mach-O fixture",
                "CodeDirectory v=20500 size=321 flags=0x10000(runtime) hashes=3+7 location=embedded",
                f"CandidateCDHashFull sha256={code_directory['codeDirectorySHA256']}",
                f"CDHash={code_directory['cdhash']}",
                "Signature size=9123",
                "Authority=Developer ID Application: Jenny Media LLC (ABCDE12345)",
                "Authority=Developer ID Certification Authority",
                "Authority=Apple Root CA",
                f"TeamIdentifier={identity['teamIdentifier']}",
            ]
            if architecture["signature"]["requireSecureTimestamp"]:
                lines.append("Timestamp=Aug 22, 2026 at 12:00:00 PM")
            lines.extend([
                "Sealed Resources=none",
                "Internal requirements count=1 size=172",
            ])
            return invocation_result(
                invocation,
                work_root,
                requirement,
                ("\n".join(lines) + "\n").encode("utf-8"),
            )
        if architecture["entitlements"] != {"mode": "absent"}:
            raise RuntimeError("execution fixture unexpectedly gained entitlements")
        return invocation_result(
            invocation,
            work_root,
            b"",
            f"Executable={plan.owned_source_path}\n".encode("utf-8"),
        )

    return run


def execute_with_fakes(
    context: dict[str, Any],
    *,
    fail_identity: bool = False,
    partial_certificate: bool = False,
) -> list[dict[str, Any]]:
    original_runner = inspection_module.run_fixed_tool_invocation
    original_inspector = inspection_module.inspect_embedded_signature
    inspection_module.run_fixed_tool_invocation = fake_runner(
        context,
        fail_identity=fail_identity,
        partial_certificate=partial_certificate,
    )
    inspection_module.inspect_embedded_signature = fake_embedded_inspector(context)
    try:
        return execute_codesign_architecture_inspection_plans(
            plans=context["plans"],
            reconstructed=context["subjects"],
            composition=context["composition"],
            graph=context["graph"],
            policy=context["policy"],
            verification_records=context["verificationRecords"],
            team_id=TEAM_ID,
            work_root=context["workRoot"],
        )
    finally:
        inspection_module.run_fixed_tool_invocation = original_runner
        inspection_module.inspect_embedded_signature = original_inspector


def validate_with_fake_inspector(
    context: dict[str, Any],
    records: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    original_inspector = inspection_module.inspect_embedded_signature
    inspection_module.inspect_embedded_signature = fake_embedded_inspector(context)
    try:
        return validate_codesign_architecture_records(
            plans=context["plans"],
            records=records,
            reconstructed=context["subjects"],
            composition=context["composition"],
            graph=context["graph"],
            policy=context["policy"],
            verification_records=context["verificationRecords"],
            team_id=TEAM_ID,
            work_root=context["workRoot"],
        )
    finally:
        inspection_module.inspect_embedded_signature = original_inspector


def certificate_cases() -> None:
    with tempfile.TemporaryDirectory(prefix="maccompanion-certificate-files-") as value:
        root = Path(value) / "work"
        prepare_private_work_root(root)
        prefix = root / "certificate-"
        write_private(Path(f"{prefix}0"), CERTIFICATE, 0o644)
        references = _retain_extracted_certificates(prefix, root)
        if (
            references != [{
                "path": "certificate-0",
                "bytes": len(CERTIFICATE),
                "sha256": CERTIFICATE_SHA256,
            }]
            or stat.S_IMODE((root / "certificate-0").stat().st_mode) != 0o600
        ):
            raise RuntimeError("certificate retention did not preserve private exact evidence")
        require_failure(
            lambda: _require_certificate_prefix_clear(prefix, root),
            "already exists",
        )

    def malformed(builder: Callable[[Path, Path], None], expected: str) -> None:
        with tempfile.TemporaryDirectory(prefix="maccompanion-certificate-invalid-") as value:
            root = Path(value) / "work"
            prepare_private_work_root(root)
            prefix = root / "certificate-"
            builder(root, prefix)
            require_failure(
                lambda: _retain_extracted_certificates(prefix, root),
                expected,
            )

    def world_writable(root: Path, prefix: Path) -> None:
        path = Path(f"{prefix}0")
        write_private(path, CERTIFICATE)
        path.chmod(0o666)

    malformed(
        lambda root, prefix: write_private(Path(f"{prefix}1"), CERTIFICATE),
        "contiguous and bounded",
    )
    malformed(
        lambda root, prefix: os.symlink("target", Path(f"{prefix}0")),
        "without following links",
    )
    malformed(
        lambda root, prefix: write_private(
            Path(f"{prefix}0"),
            b"x" * (MAX_CERTIFICATE_BYTES + 1),
        ),
        "unsafe filesystem facts",
    )
    malformed(
        world_writable,
        "unsafe filesystem facts",
    )


def main() -> int:
    certificate_cases()

    with tempfile.TemporaryDirectory(prefix="maccompanion-inspection-execution-") as value:
        context = prepare(Path(value))
        records = execute_with_fakes(context)
        if len(records) != len(context["plans"]):
            raise RuntimeError("architecture execution omitted a fixed plan")
        for record in records:
            if (
                record["status"] != "passed"
                or record["platformAcceptanceEligible"] is not False
                or record["subjectBefore"] != record["subjectAfterIdentity"]
                or record["subjectBefore"] != record["subjectAfter"]
                or record["verificationPrerequisite"]["status"] != "passed"
                or record["correlation"]["leafCertificateSHA256"]
                != CERTIFICATE_SHA256
                or record["policyComparison"]["policyMatched"] is not True
                or record["policyComparison"]["platformAcceptanceEligible"] is not False
                or len(record["certificateFiles"]) != 1
            ):
                raise RuntimeError("architecture execution record is incomplete")
        summaries = validate_with_fake_inspector(context, records)
        if (
            len(summaries) != len(records)
            or any(
                summary["status"] != "passed"
                or summary["policyMatched"] is not True
                or summary["platformAcceptanceEligible"] is not False
                or summary["wholeVerification"]["status"] != "passed"
                for summary in summaries
            )
        ):
            raise RuntimeError("architecture record reinspection is incomplete")

    with tempfile.TemporaryDirectory(prefix="maccompanion-inspection-record-mutation-") as value:
        context = prepare(Path(value))
        records = execute_with_fakes(context)
        changed = copy.deepcopy(records)
        changed[0]["policyComparison"]["policyMatched"] = False
        require_failure(
            lambda: validate_with_fake_inspector(context, changed),
            "did not pass unchanged",
        )

    with tempfile.TemporaryDirectory(prefix="maccompanion-inspection-certificate-mutation-") as value:
        context = prepare(Path(value))
        records = execute_with_fakes(context)
        certificate = context["workRoot"] / records[0]["certificateFiles"][0]["path"]
        certificate.write_bytes(b"substituted certificate")
        require_failure(
            lambda: validate_with_fake_inspector(context, records),
            "certificate",
        )

    with tempfile.TemporaryDirectory(prefix="maccompanion-inspection-record-omission-") as value:
        context = prepare(Path(value))
        records = execute_with_fakes(context)
        require_failure(
            lambda: validate_with_fake_inspector(context, records[:-1]),
            "coverage is incomplete",
        )

    with tempfile.TemporaryDirectory(prefix="maccompanion-inspection-plan-") as value:
        context = prepare(Path(value))
        changed = list(context["plans"])
        changed[0] = replace(changed[0], source_path="substituted")
        context["plans"] = changed
        require_failure(
            lambda: execute_with_fakes(context),
            "differ from exact rederivation",
        )

    with tempfile.TemporaryDirectory(prefix="maccompanion-inspection-prerequisite-") as value:
        context = prepare(Path(value))
        context["verificationRecords"] = context["verificationRecords"][:-1]
        require_failure(
            lambda: execute_with_fakes(context),
            "record set is incomplete",
        )

    with tempfile.TemporaryDirectory(prefix="maccompanion-inspection-failed-prerequisite-") as value:
        context = prepare(Path(value))
        context["verificationRecords"][0]["verification"]["status"] = "failed"
        require_failure(
            lambda: execute_with_fakes(context),
            "did not pass unchanged",
        )

    with tempfile.TemporaryDirectory(prefix="maccompanion-inspection-raw-mutation-") as value:
        context = prepare(Path(value))
        invocation = context["verificationRecords"][0]["invocation"]
        stderr_path = context["workRoot"] / invocation["stderr"]["path"]
        raw = stderr_path.read_bytes()
        stderr_path.write_bytes(b"x" + raw[1:])
        require_failure(
            lambda: execute_with_fakes(context),
            "verification evidence failed reinspection",
        )

    with tempfile.TemporaryDirectory(prefix="maccompanion-inspection-policy-") as value:
        context = prepare(Path(value))
        context["policy"]["artifacts"][0]["objects"] = context["policy"][
            "artifacts"
        ][0]["objects"][:-1]
        require_failure(
            lambda: execute_with_fakes(context),
            "coverage differ",
        )

    with tempfile.TemporaryDirectory(prefix="maccompanion-inspection-policy-identity-") as value:
        context = prepare(Path(value))
        substituted = hashlib.sha256(b"substituted certificate").hexdigest()
        for signer in context["policy"]["officialSigners"]:
            signer["leafCertificateSHA256"] = substituted
        for artifact in context["policy"]["artifacts"]:
            for item in artifact["objects"]:
                for architecture in item["architectures"]:
                    architecture["identity"][
                        "leafCertificateSHA256"
                    ] = substituted
        require_failure(
            lambda: execute_with_fakes(context),
            "differs from signing policy",
        )

    with tempfile.TemporaryDirectory(prefix="maccompanion-inspection-subject-") as value:
        context = prepare(Path(value))
        subject = context["subjects"][0]
        entries = context["composition"]["artifacts"][0]["entries"]
        entry = next(item for item in entries if item["type"] == "regularFile")
        path = subject.artifact_root / entry["path"]
        path.write_bytes(path.read_bytes() + b"mutation")
        require_failure(
            lambda: execute_with_fakes(context),
            "verification evidence failed reinspection",
        )
        if list(context["workRoot"].glob("codesign-inspect-*.stdout")):
            raise RuntimeError("mutated subject reached an inspection invocation")

    with tempfile.TemporaryDirectory(prefix="maccompanion-inspection-partial-") as value:
        context = prepare(Path(value))
        require_failure(
            lambda: execute_with_fakes(
                context,
                fail_identity=True,
                partial_certificate=True,
            ),
            "failed identity inspection produced certificate files",
        )

    with tempfile.TemporaryDirectory(prefix="maccompanion-inspection-failed-") as value:
        context = prepare(Path(value))
        records = execute_with_fakes(context, fail_identity=True)
        if any(
            record["status"] != "failed"
            or record["reason"] != "nonzeroExit"
            or record["certificateFiles"]
            or record["correlation"] is not None
            or record["policyComparison"] is not None
            or record["platformAcceptanceEligible"] is not False
            for record in records
        ):
            raise RuntimeError("failed identity execution was interpreted as acceptance")

    print(
        "Validated protected per-architecture execution, passed whole-subject "
        "prerequisites, private contiguous certificate retention, immutable subject "
        "reinspection, and fail-closed policy correlation."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

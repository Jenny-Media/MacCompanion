#!/usr/bin/env python3

from __future__ import annotations

import copy
import ctypes
import os
import tempfile
from pathlib import Path

from platform_signing_fixed_tools import (
    inspect_fixed_tool,
    prepare_private_work_root,
)
from platform_signing_subjects import (
    CODESIGN_REQUIREMENT_PREFIX,
    DARWIN_XATTR_NOFOLLOW,
    PlatformSigningSubjectError,
    _list_extended_attributes,
    _private_root_provenance,
    _require_permitted_extended_attributes,
    derive_codesign_architecture_inspection_plans,
    derive_codesign_verification_plans,
    reconstruct_signing_subjects,
)
from validate_signed_code_graph import write_fixture


TEAM_ID = "ABCDE12345"
FIXTURE_XATTR = "com.jenny.maccompanion.fixture"


def require_failure(operation, expected: str) -> None:
    try:
        operation()
    except PlatformSigningSubjectError as error:
        if expected not in str(error):
            raise RuntimeError(
                f"expected subject failure containing {expected!r}, got {error!r}"
            ) from error
    else:
        raise RuntimeError(f"expected subject failure containing {expected!r}")


def prepare(root: Path, platform: str = "mac", operation: str = "none"):
    index, composition, _, graph = write_fixture(root, platform, operation)
    work_root = root / "platform-signing-work"
    prepare_private_work_root(work_root)
    return index, composition, graph, work_root


def reconstruct(root: Path, platform: str = "mac", operation: str = "none"):
    index, composition, graph, work_root = prepare(root, platform, operation)
    subjects = reconstruct_signing_subjects(
        index=index,
        composition=composition,
        graph=graph,
        evidence_root=root,
        work_root=work_root,
    )
    return index, composition, graph, work_root, subjects


def mutation_case(mutator, expected: str) -> None:
    with tempfile.TemporaryDirectory(prefix="maccompanion-signing-subject-") as value:
        root = Path(value)
        index, composition, graph, work_root = prepare(root)
        mutator(root, index, composition, graph, work_root)
        require_failure(
            lambda: reconstruct_signing_subjects(
                index=index,
                composition=composition,
                graph=graph,
                evidence_root=root,
                work_root=work_root,
            ),
            expected,
        )


def write_extended_attribute(path: Path, name: str, value: bytes) -> None:
    library = ctypes.CDLL(None, use_errno=True)
    function = library.setxattr
    function.argtypes = [
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.c_void_p,
        ctypes.c_size_t,
        ctypes.c_uint32,
        ctypes.c_int,
    ]
    function.restype = ctypes.c_int
    buffer = ctypes.create_string_buffer(value)
    ctypes.set_errno(0)
    result = function(
        os.fsencode(path),
        os.fsencode(name),
        buffer,
        len(value),
        0,
        DARWIN_XATTR_NOFOLLOW,
    )
    if result != 0:
        error_number = ctypes.get_errno()
        raise OSError(error_number, os.strerror(error_number))


def main() -> int:
    codesign = inspect_fixed_tool("apple.codesign", "/usr/bin/codesign")
    with tempfile.TemporaryDirectory(prefix="maccompanion-signing-subject-valid-") as value:
        root = Path(value)
        _, _, graph, work_root, subjects = reconstruct(root, "combined")
        if [item.artifact_id for item in subjects] != [
            "ios-archive",
            "mac-application",
        ]:
            raise RuntimeError("reconstruction did not preserve graph artifact order")
        for subject in subjects:
            if not subject.subject_path.is_dir() or subject.entry_count <= 0:
                raise RuntimeError("reconstructed distribution subject is absent")
            if len(subject.composition_sha256) != 64:
                raise RuntimeError("reconstructed composition digest is invalid")
            if subject.provenance_path_count < 0:
                raise RuntimeError("reconstructed provenance count is invalid")
            if (
                subject.provenance_sha256 is not None
                and len(subject.provenance_sha256) != 64
            ):
                raise RuntimeError("reconstructed provenance digest is invalid")

        plans = derive_codesign_verification_plans(
            graph=graph,
            reconstructed=subjects,
            team_id=TEAM_ID,
            codesign_tool=codesign,
        )
        if not plans:
            raise RuntimeError("codesign verification plans are absent")
        grouped: dict[str, list[int]] = {}
        for plan in plans:
            grouped.setdefault(plan.artifact_id, []).append(plan.source_depth)
            arguments = plan.invocation.arguments
            expected_requirement = CODESIGN_REQUIREMENT_PREFIX + f'"{TEAM_ID}"'
            if arguments[:5] != (
                "--verify",
                "--strict",
                "--all-architectures",
                "--verbose=4",
                "--test-requirement",
            ):
                raise RuntimeError("codesign plan changed the fixed option order")
            if arguments[5] != expected_requirement:
                raise RuntimeError("codesign plan changed the fixed trust requirement")
            if Path(arguments[6]) != plan.owned_subject_path:
                raise RuntimeError("codesign plan lost its owned subject path")
            if not plan.owned_subject_path.exists() or plan.owned_subject_path.is_symlink():
                raise RuntimeError("codesign plan selected an unsafe subject")
        if any(depths != sorted(depths, reverse=True) for depths in grouped.values()):
            raise RuntimeError("codesign plans are not deepest-first")
        if list(work_root.glob("*.stdout")) or list(work_root.glob("*.stderr")):
            raise RuntimeError("plan construction executed a platform tool")

        inspection_plans = derive_codesign_architecture_inspection_plans(
            graph=graph,
            reconstructed=subjects,
            codesign_tool=codesign,
        )
        expected_architectures = sum(
            len(item["machO"]["architectures"])
            for artifact in graph["artifacts"]
            for item in artifact["machOObjects"]
            if item["inDistributionSubject"] is True
        )
        if len(inspection_plans) != expected_architectures:
            raise RuntimeError("codesign inspection plans omit graph architectures")
        for plan in inspection_plans:
            selector = f"{plan.cpu_type},{plan.cpu_subtype}"
            identity = plan.identity_invocation.arguments
            entitlements = plan.entitlements_invocation.arguments
            if identity[:5] != (
                "--display",
                "--verbose=4",
                "--requirements",
                "-",
                "--extract-certificates",
            ):
                raise RuntimeError("identity inspection plan changed fixed option order")
            if identity[5] != str(plan.certificate_prefix):
                raise RuntimeError("identity inspection plan lost its certificate prefix")
            if identity[6:8] != ("--architecture", selector):
                raise RuntimeError("identity inspection plan lost its exact CPU tuple")
            if Path(identity[8]) != plan.owned_subject_path:
                raise RuntimeError("identity inspection plan lost its owned subject")
            if entitlements[:6] != (
                "--display",
                "--entitlements",
                "-",
                "--xml",
                "--architecture",
                selector,
            ):
                raise RuntimeError("entitlement inspection plan changed fixed arguments")
            if Path(entitlements[6]) != plan.owned_subject_path:
                raise RuntimeError("entitlement inspection plan lost its owned subject")
            if not plan.owned_source_path.is_file() or plan.owned_source_path.is_symlink():
                raise RuntimeError("inspection plan selected an unsafe Mach-O source")
        if list(work_root.glob("codesign-inspect-*")):
            raise RuntimeError("inspection plan construction executed a platform tool")

    with tempfile.TemporaryDirectory(prefix="maccompanion-signing-subject-implicit-") as value:
        root = Path(value)
        _, _, _, _, subjects = reconstruct(root, "mac", "implicitFrameworkDirectory")
        expected = "Mac Companion.app/Contents/Frameworks/Fixture.framework"
        if expected not in subjects[0].synthetic_directories:
            raise RuntimeError("implicit archive directory was not explicitly recorded")

    def archive_symlink(root, index, _composition, _graph, _work):
        path = root / index["artifacts"][0]["path"]
        saved = path.with_suffix(".saved")
        path.rename(saved)
        path.symlink_to(saved.name)

    mutation_case(archive_symlink, "archive path contains a link")

    def archive_mutation(root, index, _composition, _graph, _work):
        path = root / index["artifacts"][0]["path"]
        path.write_bytes(path.read_bytes() + b"mutation")

    mutation_case(archive_mutation, "differs from its SBOM binding")

    def digest_mutation(_root, _index, composition, _graph, _work):
        entry = next(
            item
            for item in composition["artifacts"][0]["entries"]
            if item["type"] == "regularFile"
        )
        entry["sha256"] = "0" * 64

    mutation_case(digest_mutation, "digest differs from composition")

    def subject_escape(_root, _index, _composition, graph, _work):
        graph["artifacts"][0]["subjectRoot"] = "../escape"

    mutation_case(subject_escape, "unsafe")

    def writable_entry(_root, _index, composition, _graph, _work):
        entry = next(
            item
            for item in composition["artifacts"][0]["entries"]
            if item["type"] == "regularFile"
        )
        entry["mode"] = "0666"

    mutation_case(writable_entry, "writable contamination")

    def special_mode(_root, _index, composition, _graph, _work):
        entry = next(
            item
            for item in composition["artifacts"][0]["entries"]
            if item["type"] == "regularFile"
        )
        entry["mode"] = "4755"

    mutation_case(special_mode, "special permission bits")

    def malformed_composition(_root, _index, composition, _graph, _work):
        composition["artifacts"][0]["entries"][0] = []

    mutation_case(malformed_composition, "artifact reconstruction failed")

    def duplicate_graph_artifact(_root, _index, _composition, graph, _work):
        graph["artifacts"].append(copy.deepcopy(graph["artifacts"][0]))

    mutation_case(duplicate_graph_artifact, "artifact set differs")

    def preexisting_subjects(_root, _index, _composition, _graph, work_root):
        (work_root / "subjects").mkdir(mode=0o700)

    mutation_case(preexisting_subjects, "subjects root already exists")

    def release_mismatch(_root, _index, _composition, graph, _work):
        graph["release"]["buildNumber"] = "999"

    mutation_case(release_mismatch, "release or source differs")

    def source_mismatch(_root, _index, _composition, graph, _work):
        graph["source"]["revision"] = "f" * 40

    mutation_case(source_mismatch, "release or source differs")

    def primary_coverage(_root, index, _composition, _graph, _work):
        sparkle = next(
            item for item in index["artifacts"]
            if item["kind"] == "sparkleArchive"
        )
        sparkle["kind"] = "macApplication"

    mutation_case(primary_coverage, "artifact set differs")

    def contaminated_private_root(_root, _index, _composition, _graph, work_root):
        write_extended_attribute(work_root, FIXTURE_XATTR, b"fixture")

    mutation_case(contaminated_private_root, "private root contains")

    with tempfile.TemporaryDirectory(prefix="maccompanion-signing-xattr-") as value:
        root = Path(value)
        work_root = root / "work"
        prepare_private_work_root(work_root)
        path = work_root / "owned"
        path.write_bytes(b"fixture")
        provenance = _private_root_provenance(work_root)
        _require_permitted_extended_attributes(path, provenance)
        write_extended_attribute(path, FIXTURE_XATTR, b"fixture")
        require_failure(
            lambda: _require_permitted_extended_attributes(path, provenance),
            "extended-attribute contamination",
        )
        if FIXTURE_XATTR not in _list_extended_attributes(path):
            raise RuntimeError("xattr rejection deleted unknown contamination")

    with tempfile.TemporaryDirectory(prefix="maccompanion-signing-plan-") as value:
        root = Path(value)
        _, _, graph, _, subjects = reconstruct(root)
        require_failure(
            lambda: derive_codesign_verification_plans(
                graph=graph,
                reconstructed=subjects,
                team_id='ABCDE1234"',
                codesign_tool=codesign,
            ),
            "Team ID",
        )

        changed_status = copy.deepcopy(graph)
        verify_step = next(
            step
            for step in changed_status["artifacts"][0]["verificationPlan"]
            if step["action"] == "verifyObjectAllArchitectures"
        )
        verify_step["status"] = "passed"
        require_failure(
            lambda: derive_codesign_verification_plans(
                graph=changed_status,
                reconstructed=subjects,
                team_id=TEAM_ID,
                codesign_tool=codesign,
            ),
            "not fixed and inert",
        )

        invalid_object = copy.deepcopy(graph)
        invalid_object["artifacts"][0]["machOObjects"][0] = []
        require_failure(
            lambda: derive_codesign_verification_plans(
                graph=invalid_object,
                reconstructed=subjects,
                team_id=TEAM_ID,
                codesign_tool=codesign,
            ),
            "Mach-O object is not an object",
        )

        reordered = copy.deepcopy(graph)
        verification_plan = reordered["artifacts"][0]["verificationPlan"]
        indices = [
            index
            for index, step in enumerate(verification_plan)
            if step["action"] == "verifyObjectAllArchitectures"
        ]
        verification_plan[indices[0]], verification_plan[indices[1]] = (
            verification_plan[indices[1]],
            verification_plan[indices[0]],
        )
        require_failure(
            lambda: derive_codesign_verification_plans(
                graph=reordered,
                reconstructed=subjects,
                team_id=TEAM_ID,
                codesign_tool=codesign,
            ),
            "order differs",
        )

        wrong_tool = copy.copy(codesign)
        object.__setattr__(wrong_tool, "tool_id", "apple.spctl")
        require_failure(
            lambda: derive_codesign_verification_plans(
                graph=graph,
                reconstructed=subjects,
                team_id=TEAM_ID,
                codesign_tool=wrong_tool,
            ),
            "pinned absolute Apple tool",
        )

        changed_inspection = copy.deepcopy(graph)
        report_step = next(
            step
            for step in changed_inspection["artifacts"][0]["verificationPlan"]
            if step["action"] == "reportIdentityAndRequirements"
        )
        report_step["architectureSelector"]["cpuSubtype"] += 1
        require_failure(
            lambda: derive_codesign_architecture_inspection_plans(
                graph=changed_inspection,
                reconstructed=subjects,
                codesign_tool=codesign,
            ),
            "inspection order differs",
        )

    print(
        "Validated descriptor-bound exact artifact reconstruction, private "
        "filesystem topology, and deepest-first fixed codesign planning."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

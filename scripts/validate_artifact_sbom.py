#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import hashlib
import copy
import io
import stat
import tempfile
import zipfile
from pathlib import Path
from typing import Any

from artifact_sbom import ArtifactSBOMError, atomic_write_set, canonical_bytes, generate, load_json, validate_bundle, validate_release_binding
from signed_code_graph import MAX_GRAPH_BYTES, generate_graph
from signing_policy import MAX_POLICY_BYTES
from signing_policy_fixture import write_fixture_policy


REPOSITORY = Path(__file__).resolve().parents[1]
FIXTURE_ROOT = REPOSITORY / "Tests" / "System" / "ArtifactSBOM"


def write_layout_archive(path: Path, layout: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    class NonSeekableBuffer(io.BytesIO):
        def seekable(self) -> bool:
            return False

        def seek(self, *args: Any, **kwargs: Any) -> int:
            raise io.UnsupportedOperation("fixture forces ZIP data descriptors")

    buffer = NonSeekableBuffer() if layout.get("dataDescriptor") is True else None
    destination: Path | io.BytesIO = buffer if buffer is not None else path
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for entry in layout["entries"]:
            info = zipfile.ZipInfo(entry["path"])
            info.create_system = 3
            info.compress_type = zipfile.ZIP_DEFLATED
            kind = entry["type"]
            permissions = int(entry["mode"], 8)
            if kind == "directory":
                info.external_attr = (stat.S_IFDIR | permissions) << 16
                content = b""
            elif kind == "regularFile":
                info.external_attr = (stat.S_IFREG | permissions) << 16
                if "contentHex" in entry:
                    content = bytes.fromhex(entry["contentHex"])
                else:
                    content = entry["content"].encode("utf-8")
            elif kind == "symlink":
                info.external_attr = (stat.S_IFLNK | permissions) << 16
                content = entry["target"].encode("utf-8")
            elif kind == "fifo":
                info.external_attr = (stat.S_IFIFO | permissions) << 16
                content = b""
            else:
                raise ValueError(f"unknown fixture entry type: {kind}")
            archive.writestr(info, content)
    if buffer is not None:
        path.write_bytes(buffer.getvalue())


def fixture_candidate(layouts: list[tuple[str, str, dict[str, Any]]]) -> dict[str, Any]:
    artifacts = [{"id": identifier, "kind": kind, "path": f"artifacts/{identifier}.zip"} for identifier, kind, _ in layouts]
    targets = sorted({"iOS" if kind == "iosArchive" else "macOS" for _, kind, _ in layouts})
    return {
        "schemaVersion": "maccompanion.artifact-sbom.v0.1", "product": "Mac Companion",
        "release": {"version": "1.0.0-beta.1", "buildNumber": "100", "targets": targets},
        "source": {"revision": "0123456789abcdef0123456789abcdef01234567", "dirty": False},
        "created": "2026-08-21T12:00:00Z", "artifacts": artifacts,
    }


def write_signed_code_fixture(
    root: Path,
    release: dict[str, Any],
    composition: dict[str, Any],
) -> str:
    index = load_json(root / "supply-chain" / "artifact-sbom-index.json")
    graph = generate_graph(
        index=index,
        composition=composition,
        release_manifest=release,
        artifact_sbom_reference=copy.deepcopy(release["sbom"]["document"]),
        evidence_root=root,
        created="2026-08-21T12:05:00Z",
    )
    graph_raw = canonical_bytes(graph)
    graph_relative_path = "verification/signed-code-graph.json"
    graph_path = root / graph_relative_path
    graph_path.parent.mkdir(parents=True, exist_ok=True)
    graph_path.write_bytes(graph_raw)
    release["validation"] = [
        record
        for record in release["validation"]
        if record.get("id") != "signed-code-graph-construction"
    ]
    release["validation"].append({
        "id": "signed-code-graph-construction",
        "status": "passed",
        "evidence": {
            "path": graph_relative_path,
            "sha256": hashlib.sha256(graph_raw).hexdigest(),
            "bytes": len(graph_raw),
        },
    })
    composition_by_id = {
        artifact["id"]: {entry["path"]: entry for entry in artifact["entries"]}
        for artifact in composition["artifacts"]
    }
    for executable in release["executables"]:
        member = composition_by_id[executable["artifactID"]][executable["relativePath"]]
        evidence: dict[str, dict[str, Any]] = {}
        for label in (
            "designatedRequirement",
            "entitlements",
            "codesignVerification",
            "platformAssessment",
        ):
            content = f"{executable['id']} {label} fixture evidence\n".encode("utf-8")
            relative_path = f"verification/{executable['id']}/{label}.txt"
            path = root / relative_path
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
            evidence[label] = {
                "path": relative_path,
                "sha256": hashlib.sha256(content).hexdigest(),
                "bytes": len(content),
            }
        bundle = {
            "schemaVersion": "maccompanion.signed-code-verification.v0.1",
            "evidenceLevel": "constructionCorrelation",
            "product": "Mac Companion",
            "release": {
                "version": release["release"]["version"],
                "buildNumber": release["release"]["buildNumber"],
                "targets": sorted(release["release"]["targets"]),
            },
            "source": {
                "revision": release["source"]["revision"],
                "dirty": release["source"]["dirty"],
            },
            "created": "2026-08-21T12:10:00Z",
            "artifactSBOM": copy.deepcopy(release["sbom"]["document"]),
            "artifact": {
                **copy.deepcopy(
                    next(
                        artifact
                        for artifact in release["artifacts"]
                        if artifact["id"] == executable["artifactID"]
                    )
                ),
                "platform": executable["platform"],
            },
            "executable": {
                key: executable[key]
                for key in (
                    "id", "role", "platform", "bundleIdentifier", "artifactID", "relativePath",
                )
            },
            "artifactMember": {
                key: member[key]
                for key in ("path", "type", "mode", "bytes", "sha1", "sha256", "symlinkTarget")
            },
            "codeIdentity": {
                "signingIdentifier": executable["bundleIdentifier"],
                "teamIdentifier": "ABCDE12345",
                "cdhash": hashlib.sha1(f"{executable['id']} cdhash".encode("utf-8")).hexdigest(),
                "certificateSHA256": hashlib.sha256(
                    f"{executable['id']} certificate".encode("utf-8")
                ).hexdigest(),
            },
            "reportedChecks": {
                "codesignVerify": True,
                "platformAssessment": (
                    "gatekeeperAccepted"
                    if executable["role"] == "macApp"
                    else "embeddedNotApplicable"
                    if executable["platform"] == "macOS"
                    else "iosProvisioningReported"
                ),
            },
            "evidence": evidence,
        }
        raw = canonical_bytes(bundle)
        relative_bundle_path = f"verification/{executable['id']}/signed-code-verification.json"
        (root / relative_bundle_path).write_bytes(raw)
        executable["verificationBundle"] = {
            "path": relative_bundle_path,
            "sha256": hashlib.sha256(raw).hexdigest(),
            "bytes": len(raw),
        }
    return write_fixture_policy(
        root,
        release,
        graph,
        next(
            record["evidence"]
            for record in release["validation"]
            if record["id"] == "signed-code-graph-construction"
        ),
    )


def run_case(case: dict[str, Any], temporary_root: Path) -> None:
    layouts: list[tuple[str, str, dict[str, Any]]] = []
    for artifact in case["artifacts"]:
        layout = load_json(FIXTURE_ROOT / artifact["layout"])
        layouts.append((artifact["id"], artifact["kind"], layout))
        write_layout_archive(temporary_root / "artifacts" / f"{artifact['id']}.zip", layout)
    first_archive = temporary_root / "artifacts" / f"{case['artifacts'][0]['id']}.zip"
    if case.get("archiveMutation") == "suffix":
        first_archive.write_bytes(first_archive.read_bytes() + b"UNINVENTORIED-POLYGLOT-BYTES")
    elif case.get("archiveMutation") in {"encrypted", "unsupportedMethod", "descriptorSignature", "descriptorFacts"}:
        raw = bytearray(first_archive.read_bytes())
        central = raw.find(b"PK\x01\x02")
        if central < 0:
            raise ArtifactSBOMError("fixture central directory is missing")
        if case["archiveMutation"] == "encrypted":
            raw[6] |= 0x01
            raw[central + 8] |= 0x01
        elif case["archiveMutation"] == "unsupportedMethod":
            raw[8:10] = (99).to_bytes(2, "little")
            raw[central + 10:central + 12] = (99).to_bytes(2, "little")
        else:
            descriptor = raw.find(b"PK\x07\x08")
            if descriptor < 0:
                raise ArtifactSBOMError("fixture data descriptor is missing")
            if case["archiveMutation"] == "descriptorSignature":
                raw[descriptor:descriptor + 4] = b"XXXX"
            else:
                raw[descriptor + 4] ^= 0x01
        first_archive.write_bytes(raw)
    candidate = fixture_candidate(layouts)
    if case.get("dirty") is True:
        candidate["source"]["dirty"] = True
    index, composition, spdx = generate(candidate, temporary_root)
    repeated = generate(candidate, temporary_root)
    if tuple(canonical_bytes(value) for value in repeated) != tuple(canonical_bytes(value) for value in (index, composition, spdx)):
        raise ArtifactSBOMError("generation is not deterministic")
    release_manifest = {
        "release": candidate["release"],
        "source": candidate["source"],
        "artifacts": [dict(binding) for binding in index["artifacts"]],
        "executables": [],
    }
    for artifact in composition["artifacts"]:
        binding = next(item for item in index["artifacts"] if item["id"] == artifact["id"])
        if binding["kind"] in {"macApplication", "iosArchive"}:
            executable = next(
                entry
                for entry in artifact["entries"]
                if entry["type"] == "regularFile" and int(entry["mode"], 8) & 0o111
            )
            release_manifest["executables"].append({"artifactID": artifact["id"], "relativePath": executable["path"]})
    if case.get("bindingMutation") == "releaseVersion":
        release_manifest["release"] = dict(release_manifest["release"])
        release_manifest["release"]["version"] = "2.0.0"
    elif case.get("bindingMutation") == "artifactHash":
        release_manifest["artifacts"][0]["sha256"] = "1" * 64
    elif case.get("bindingMutation") == "missingExecutable":
        release_manifest["executables"][0]["relativePath"] = "missing/executable"
    elif case.get("bindingMutation") == "nonExecutable":
        executable_path = release_manifest["executables"][0]["relativePath"]
        for artifact in composition["artifacts"]:
            for entry in artifact["entries"]:
                if entry["path"] == executable_path:
                    entry["mode"] = "0644"
    elif case.get("bindingMutation") == "sparklePayload":
        sparkle = next(artifact for artifact in composition["artifacts"] if artifact["id"] == "sparkle-archive")
        next(entry for entry in sparkle["entries"] if entry["type"] == "regularFile")["sha256"] = "2" * 64
    validate_release_binding(release_manifest, index, composition)
    output = temporary_root / "sbom"
    output.mkdir()
    (output / "artifact-composition.json").write_bytes(canonical_bytes(composition))
    (output / "artifact-sbom.spdx.json").write_bytes(canonical_bytes(spdx))
    (output / "artifact-sbom-index.json").write_bytes(canonical_bytes(index))
    if case.get("mutation") == "archiveBytes":
        archive_path = temporary_root / candidate["artifacts"][0]["path"]
        archive_path.write_bytes(archive_path.read_bytes() + b"x")
    elif case.get("mutation") == "spdxChecksum":
        spdx["files"][0]["checksums"][0]["checksumValue"] = "0" * 64
        (output / "artifact-sbom.spdx.json").write_bytes(canonical_bytes(spdx))
        index["spdx"]["sha256"] = __import__("hashlib").sha256(canonical_bytes(spdx)).hexdigest()
        index["spdx"]["bytes"] = len(canonical_bytes(spdx))
        (output / "artifact-sbom-index.json").write_bytes(canonical_bytes(index))
    elif case.get("mutation") == "nonCanonicalIndex":
        (output / "artifact-sbom-index.json").write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")
    validate_bundle(output / "artifact-sbom-index.json", evidence_root=temporary_root, verify_archives=True)


def validate_fixtures() -> int:
    manifest = load_json(FIXTURE_ROOT / "manifest.json")
    if not isinstance(manifest, dict) or set(manifest) != {"profile", "cases"} or manifest["profile"] != "maccompanion.artifact-sbom-fixtures.v0.1" or not isinstance(manifest["cases"], list):
        raise ArtifactSBOMError("invalid artifact SBOM fixture manifest")
    failures: list[str] = []
    seen: set[str] = set()
    for case in manifest["cases"]:
        identifier = case.get("id")
        if not isinstance(identifier, str) or identifier in seen:
            failures.append("duplicate or invalid fixture ID")
            continue
        seen.add(identifier)
        expected = case.get("expect")
        error_text: str | None = None
        try:
            with tempfile.TemporaryDirectory(prefix="maccompanion-artifact-sbom-") as temporary:
                run_case(case, Path(temporary))
            valid = True
        except (ArtifactSBOMError, OSError, ValueError, zipfile.BadZipFile, json.JSONDecodeError) as error:
            valid = False
            error_text = str(error)
        if (expected == "valid") != valid:
            failures.append(f"{identifier}: expected {expected}, got {'valid' if valid else 'invalid'}")
        if expected not in {"valid", "invalid"}:
            failures.append(f"{identifier}: invalid expectation")
        expected_error = case.get("errorContains")
        if expected_error is not None and (valid or not isinstance(expected_error, str) or expected_error not in (error_text or "")):
            failures.append(f"{identifier}: expected error containing {expected_error!r}, got {error_text!r}")
    if failures:
        for failure in failures:
            print(failure)
        return 1
    print(f"validated {len(seen)} artifact-SBOM fixture(s)")
    return 0


def validate_release_integration() -> int:
    from validate_release_evidence import referenced_files, validate_manifest, verify_files

    with tempfile.TemporaryDirectory(prefix="maccompanion-verified-release-") as temporary:
        root = Path(temporary)
        release = load_json(REPOSITORY / "Tests" / "System" / "ReleaseEvidence" / "valid-signed-mac-candidate.json")
        next(
            item for item in release["executables"] if item["role"] == "macApp"
        )["bundleIdentifier"] = "example.maccompanion.fixture"
        layout = load_json(FIXTURE_ROOT / "valid-mac-app.json")
        for artifact in release["artifacts"]:
            path = root / artifact["path"]
            if artifact["kind"] in {"macApplication", "sparkleArchive"}:
                write_layout_archive(path, layout)
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"fixture disk image")
            artifact["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
            artifact["bytes"] = path.stat().st_size

        candidate = {
            "schemaVersion": "maccompanion.artifact-sbom.v0.1",
            "product": "Mac Companion",
            "release": {
                "version": release["release"]["version"],
                "buildNumber": release["release"]["buildNumber"],
                "targets": release["release"]["targets"],
            },
            "source": release["source"],
            "created": "2026-08-21T12:00:00Z",
            "artifacts": [
                {"id": artifact["id"], "kind": artifact["kind"], "path": artifact["path"]}
                for artifact in sorted(release["artifacts"], key=lambda item: item["id"])
                if artifact["kind"] in {"macApplication", "sparkleArchive", "iosArchive"}
            ],
        }
        index, composition, spdx = generate(candidate, root)
        supply_chain = root / "supply-chain"
        composition_content = canonical_bytes(composition)
        spdx_content = canonical_bytes(spdx)
        index_content = canonical_bytes(index)
        output_files = {
            "artifact-composition.json": composition_content,
            "artifact-sbom.spdx.json": spdx_content,
            "artifact-sbom-index.json": index_content,
        }
        atomic_write_set(supply_chain, output_files)
        if any(stat.S_IMODE(path.stat().st_mode) != 0o600 for path in supply_chain.iterdir()):
            print("verified release integration: generated evidence mode is not 0600")
            return 1
        try:
            atomic_write_set(supply_chain, output_files)
        except ArtifactSBOMError:
            pass
        else:
            print("verified release integration: generator overwrote an evidence set")
            return 1
        release["sbom"]["document"] = {
            "path": "supply-chain/artifact-sbom-index.json",
            "sha256": hashlib.sha256(index_content).hexdigest(),
            "bytes": len(index_content),
        }
        signing_policy_pin = write_signed_code_fixture(root, release, composition)
        for reference in referenced_files(release):
            path = root / reference["path"]
            if path.exists():
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"x")
            reference["sha256"] = hashlib.sha256(b"x").hexdigest()
            reference["bytes"] = 1
        manifest_path = root / "release-evidence.json"
        manifest_path.write_bytes(canonical_bytes(release))
        if validate_manifest(release) or verify_files(
            release,
            manifest_path,
            expected_signing_policy_sha256=signing_policy_pin,
        ) != {
            "missingMacPackagingEquivalence",
            "signedCodePlatformVerificationRequired",
        }:
            print("verified release integration: macOS packaging-equivalence gate did not fail closed exactly")
            return 1

        no_pin_errors = verify_files(release, manifest_path)
        if (
            "signingPolicyDigestPinRequired" not in no_pin_errors
            or "signedCodePlatformVerificationRequired" in no_pin_errors
        ):
            print("verified release integration: candidate-selected policy reached the platform gate")
            return 1

        wrong_pin_errors = verify_files(
            release,
            manifest_path,
            expected_signing_policy_sha256=hashlib.sha256(b"different protected policy").hexdigest(),
        )
        if (
            "signingPolicyDigestMismatch" not in wrong_pin_errors
            or "signedCodePlatformVerificationRequired" in wrong_pin_errors
        ):
            print("verified release integration: wrong independent policy pin reached the platform gate")
            return 1

        missing_policy_release = copy.deepcopy(release)
        missing_policy_release["validation"] = [
            record for record in missing_policy_release["validation"]
            if record["id"] != "signing-policy-contract"
        ]
        missing_policy_errors = verify_files(
            missing_policy_release,
            manifest_path,
            expected_signing_policy_sha256=signing_policy_pin,
        )
        if (
            "missingSigningPolicy" not in missing_policy_errors
            or "signedCodePlatformVerificationRequired" in missing_policy_errors
        ):
            print("verified release integration: missing signing policy reached the platform gate")
            return 1

        policy_record = next(
            record for record in release["validation"]
            if record["id"] == "signing-policy-contract"
        )
        policy_path = root / policy_record["evidence"]["path"]
        original_policy = policy_path.read_bytes()

        policy_saved = policy_path.with_name(policy_path.name + ".saved")
        policy_path.rename(policy_saved)
        policy_path.symlink_to(policy_saved.name)
        try:
            symlink_policy_errors = verify_files(
                release,
                manifest_path,
                expected_signing_policy_sha256=signing_policy_pin,
            )
        finally:
            policy_path.unlink()
            policy_saved.rename(policy_path)
        if (
            "invalidSigningPolicy" not in symlink_policy_errors
            or "signedCodePlatformVerificationRequired" in symlink_policy_errors
        ):
            print("verified release integration: symlinked signing policy reached the platform gate")
            return 1

        policy_hardlink = policy_path.with_name(policy_path.name + ".hardlink")
        policy_hardlink.hardlink_to(policy_path)
        try:
            hardlink_policy_errors = verify_files(
                release,
                manifest_path,
                expected_signing_policy_sha256=signing_policy_pin,
            )
        finally:
            policy_hardlink.unlink()
        if (
            "invalidSigningPolicy" not in hardlink_policy_errors
            or "signedCodePlatformVerificationRequired" in hardlink_policy_errors
        ):
            print("verified release integration: hardlinked signing policy reached the platform gate")
            return 1

        for label, mutated_policy_raw in (
            ("noncanonical", (json.dumps(load_json(policy_path), indent=2) + "\n").encode("utf-8")),
            ("oversized", b" " * (MAX_POLICY_BYTES + 1)),
        ):
            mutated_release = copy.deepcopy(release)
            mutated_record = next(
                record for record in mutated_release["validation"]
                if record["id"] == "signing-policy-contract"
            )
            mutated_pin = hashlib.sha256(mutated_policy_raw).hexdigest()
            mutated_record["evidence"]["sha256"] = mutated_pin
            mutated_record["evidence"]["bytes"] = len(mutated_policy_raw)
            policy_path.write_bytes(mutated_policy_raw)
            mutation_errors = verify_files(
                mutated_release,
                manifest_path,
                expected_signing_policy_sha256=mutated_pin,
            )
            policy_path.write_bytes(original_policy)
            if (
                "invalidSigningPolicy" not in mutation_errors
                or "signedCodePlatformVerificationRequired" in mutation_errors
            ):
                print(f"verified release integration: {label} signing policy reached the platform gate")
                return 1

        for label, mutation in (
            ("release-substitution", lambda policy: policy["release"].update({"version": "9.9.9"})),
            (
                "architecture-slice-substitution",
                lambda policy: next(
                    obj for artifact in policy["artifacts"]
                    for obj in artifact["objects"]
                    if obj["architectures"]
                )["architectures"][0].update({"sliceSHA256": "f" * 64}),
            ),
        ):
            policy = load_json(policy_path)
            mutation(policy)
            mutated_policy_raw = canonical_bytes(policy)
            mutated_pin = hashlib.sha256(mutated_policy_raw).hexdigest()
            mutated_release = copy.deepcopy(release)
            mutated_record = next(
                record for record in mutated_release["validation"]
                if record["id"] == "signing-policy-contract"
            )
            mutated_record["evidence"]["sha256"] = mutated_pin
            mutated_record["evidence"]["bytes"] = len(mutated_policy_raw)
            policy_path.write_bytes(mutated_policy_raw)
            mutation_errors = verify_files(
                mutated_release,
                manifest_path,
                expected_signing_policy_sha256=mutated_pin,
            )
            policy_path.write_bytes(original_policy)
            if (
                "invalidSigningPolicy" not in mutation_errors
                or "signedCodePlatformVerificationRequired" in mutation_errors
            ):
                print(f"verified release integration: {label} signing policy reached the platform gate")
                return 1

        swapped_bundles = copy.deepcopy(release)
        swapped_bundles["executables"][0]["verificationBundle"], swapped_bundles["executables"][1]["verificationBundle"] = (
            swapped_bundles["executables"][1]["verificationBundle"],
            swapped_bundles["executables"][0]["verificationBundle"],
        )
        if "invalidSignedCodeVerification" not in verify_files(swapped_bundles, manifest_path, expected_signing_policy_sha256=signing_policy_pin):
            print("verified release integration: exchanged executable verification bundles were accepted")
            return 1

        member_substitution = copy.deepcopy(release)
        executable = member_substitution["executables"][0]
        bundle_path = root / executable["verificationBundle"]["path"]
        original_bundle = bundle_path.read_bytes()
        bundle = load_json(bundle_path)
        bundle["artifactMember"]["sha256"] = "9" * 64
        substituted_bundle = canonical_bytes(bundle)
        bundle_path.write_bytes(substituted_bundle)
        executable["verificationBundle"]["sha256"] = hashlib.sha256(substituted_bundle).hexdigest()
        executable["verificationBundle"]["bytes"] = len(substituted_bundle)
        substitution_errors = verify_files(member_substitution, manifest_path, expected_signing_policy_sha256=signing_policy_pin)
        bundle_path.write_bytes(original_bundle)
        if "invalidSignedCodeVerification" not in substitution_errors:
            print("verified release integration: exact-member substitution was accepted")
            return 1

        oversized_bundle = copy.deepcopy(release)
        executable = oversized_bundle["executables"][0]
        bundle_path = root / executable["verificationBundle"]["path"]
        original_bundle = bundle_path.read_bytes()
        oversized_content = b" " * (1024 * 1024 + 1)
        bundle_path.write_bytes(oversized_content)
        executable["verificationBundle"]["sha256"] = hashlib.sha256(oversized_content).hexdigest()
        executable["verificationBundle"]["bytes"] = len(oversized_content)
        oversized_errors = verify_files(oversized_bundle, manifest_path, expected_signing_policy_sha256=signing_policy_pin)
        bundle_path.write_bytes(original_bundle)
        if "invalidSignedCodeVerification" not in oversized_errors:
            print("verified release integration: oversized verification bundle was accepted")
            return 1

        saved_bundle = bundle_path.with_name(bundle_path.name + ".saved")
        bundle_path.rename(saved_bundle)
        bundle_path.symlink_to(saved_bundle.name)
        try:
            symlink_errors = verify_files(release, manifest_path, expected_signing_policy_sha256=signing_policy_pin)
        finally:
            bundle_path.unlink()
            saved_bundle.rename(bundle_path)
        if "invalidSignedCodeVerification" not in symlink_errors:
            print("verified release integration: symlinked verification bundle was accepted")
            return 1

        graph_record = next(
            record
            for record in release["validation"]
            if record["id"] == "signed-code-graph-construction"
        )
        graph_path = root / graph_record["evidence"]["path"]
        original_graph = graph_path.read_bytes()
        omitted_graph_release = copy.deepcopy(release)
        omitted_graph_record = next(
            record
            for record in omitted_graph_release["validation"]
            if record["id"] == "signed-code-graph-construction"
        )
        omitted_graph = load_json(graph_path)
        mac_graph = next(
            artifact
            for artifact in omitted_graph["artifacts"]
            if artifact["artifact"]["kind"] == "macApplication"
        )
        mac_graph["machOObjects"] = [
            item
            for item in mac_graph["machOObjects"]
            if ".framework/" not in item["path"]
        ]
        omitted_raw = canonical_bytes(omitted_graph)
        graph_path.write_bytes(omitted_raw)
        omitted_graph_record["evidence"]["sha256"] = hashlib.sha256(omitted_raw).hexdigest()
        omitted_graph_record["evidence"]["bytes"] = len(omitted_raw)
        omitted_errors = verify_files(omitted_graph_release, manifest_path, expected_signing_policy_sha256=signing_policy_pin)
        graph_path.write_bytes(original_graph)
        if (
            "invalidSignedCodeGraph" not in omitted_errors
            or "signedCodePlatformVerificationRequired" in omitted_errors
        ):
            print("verified release integration: omitted nested code reached the platform gate")
            return 1

        missing_graph_release = copy.deepcopy(release)
        missing_graph_release["validation"] = [
            record
            for record in missing_graph_release["validation"]
            if record["id"] != "signed-code-graph-construction"
        ]
        missing_graph_errors = verify_files(missing_graph_release, manifest_path, expected_signing_policy_sha256=signing_policy_pin)
        if (
            "missingSignedCodeGraph" not in missing_graph_errors
            or "signedCodePlatformVerificationRequired" in missing_graph_errors
        ):
            print("verified release integration: missing graph did not fail closed")
            return 1

        graph_saved = graph_path.with_name(graph_path.name + ".saved")
        graph_path.rename(graph_saved)
        graph_path.symlink_to(graph_saved.name)
        try:
            symlink_graph_errors = verify_files(release, manifest_path, expected_signing_policy_sha256=signing_policy_pin)
        finally:
            graph_path.unlink()
            graph_saved.rename(graph_path)
        if (
            "invalidSignedCodeGraph" not in symlink_graph_errors
            or "signedCodePlatformVerificationRequired" in symlink_graph_errors
        ):
            print("verified release integration: symlinked signed-code graph was accepted")
            return 1

        noncanonical_release = copy.deepcopy(release)
        noncanonical_record = next(
            record for record in noncanonical_release["validation"]
            if record["id"] == "signed-code-graph-construction"
        )
        noncanonical_raw = (json.dumps(load_json(graph_path), indent=2) + "\n").encode("utf-8")
        graph_path.write_bytes(noncanonical_raw)
        noncanonical_record["evidence"]["sha256"] = hashlib.sha256(noncanonical_raw).hexdigest()
        noncanonical_record["evidence"]["bytes"] = len(noncanonical_raw)
        noncanonical_errors = verify_files(noncanonical_release, manifest_path, expected_signing_policy_sha256=signing_policy_pin)
        graph_path.write_bytes(original_graph)
        if (
            "invalidSignedCodeGraph" not in noncanonical_errors
            or "signedCodePlatformVerificationRequired" in noncanonical_errors
        ):
            print("verified release integration: noncanonical graph reached the platform gate")
            return 1

        oversized_graph_release = copy.deepcopy(release)
        oversized_graph_record = next(
            record for record in oversized_graph_release["validation"]
            if record["id"] == "signed-code-graph-construction"
        )
        oversized_graph_raw = b" " * (MAX_GRAPH_BYTES + 1)
        graph_path.write_bytes(oversized_graph_raw)
        oversized_graph_record["evidence"]["sha256"] = hashlib.sha256(oversized_graph_raw).hexdigest()
        oversized_graph_record["evidence"]["bytes"] = len(oversized_graph_raw)
        oversized_graph_errors = verify_files(oversized_graph_release, manifest_path, expected_signing_policy_sha256=signing_policy_pin)
        graph_path.write_bytes(original_graph)
        if (
            "invalidSignedCodeGraph" not in oversized_graph_errors
            or "signedCodePlatformVerificationRequired" in oversized_graph_errors
        ):
            print("verified release integration: oversized graph reached the platform gate")
            return 1

        duplicate_subject = copy.deepcopy(release)
        duplicate = copy.deepcopy(duplicate_subject["executables"][0])
        duplicate["id"] = "duplicate-subject"
        duplicate_subject["executables"].append(duplicate)
        if "duplicateExecutableSubject" not in validate_manifest(duplicate_subject):
            print("verified release integration: duplicate executable subject was accepted")
            return 1

        source_substitution = copy.deepcopy(release)
        source_path = root / "supply-chain" / "source-sbom.json"
        source_path.write_bytes(b"{}\n")
        source_substitution["sbom"]["document"] = {
            "path": "supply-chain/source-sbom.json",
            "sha256": hashlib.sha256(b"{}\n").hexdigest(),
            "bytes": 3,
        }
        if "invalidArtifactSBOM" not in verify_files(source_substitution, manifest_path, expected_signing_policy_sha256=signing_policy_pin):
            print("verified release integration: source-SBOM substitution was accepted")
            return 1

        metadata_mismatch = copy.deepcopy(release)
        metadata_mismatch["release"]["version"] = "2.0.0"
        if "invalidArtifactSBOM" not in verify_files(metadata_mismatch, manifest_path, expected_signing_policy_sha256=signing_policy_pin):
            print("verified release integration: release metadata mismatch was accepted")
            return 1

        archive_path = root / release["artifacts"][0]["path"]
        original = archive_path.read_bytes()
        archive_path.write_bytes(original + b"mutation")
        mutation_errors = verify_files(release, manifest_path, expected_signing_policy_sha256=signing_policy_pin)
        archive_path.write_bytes(original)
        if "invalidArtifactSBOM" not in mutation_errors or not {"evidenceSizeMismatch", "evidenceDigestMismatch"} & mutation_errors:
            print("verified release integration: post-SBOM archive mutation was accepted")
            return 1
    print("validated 14 exact-candidate release-integration case(s)")
    return 0


def validate_target_graph_release_integration() -> int:
    from validate_release_evidence import referenced_files, validate_manifest, verify_files

    for target_mode in ("ios", "combined"):
        with tempfile.TemporaryDirectory(prefix=f"maccompanion-{target_mode}-graph-release-") as temporary:
            root = Path(temporary)
            release = load_json(
                REPOSITORY / "Tests" / "System" / "ReleaseEvidence" / "valid-promotion-both-targets.json"
            )
            release["evidenceLevel"] = "signedCandidate"
            release["release"]["channel"] = "internal"
            release["physicalScenarios"] = []
            release["promotion"] = None
            for executable in release["executables"]:
                if executable["role"] == "macApp":
                    executable["bundleIdentifier"] = "example.maccompanion.fixture"
                elif executable["role"] == "iosApp":
                    executable["bundleIdentifier"] = "example.maccompanion.fixture.ios"
            layouts: list[tuple[str, str, dict[str, Any]]] = []
            if target_mode == "ios":
                release["release"]["targets"] = ["iOS"]
                release["compatibility"]["minimumMacOS"] = None
                release["notarization"] = None
                release["executables"] = [
                    item for item in release["executables"] if item["platform"] == "iOS"
                ]
                layouts.append((
                    "ios-archive",
                    "iosArchive",
                    load_json(FIXTURE_ROOT / "valid-ios-archive.json"),
                ))
            else:
                layouts.extend([
                    ("ios-archive", "iosArchive", load_json(FIXTURE_ROOT / "valid-ios-archive.json")),
                    ("mac-app", "macApplication", load_json(FIXTURE_ROOT / "valid-mac-app.json")),
                    ("sparkle-archive", "sparkleArchive", load_json(FIXTURE_ROOT / "valid-mac-app.json")),
                ])
            for identifier, _, layout in layouts:
                write_layout_archive(root / "artifacts" / f"{identifier}.zip", layout)
            candidate = {
                "schemaVersion": "maccompanion.artifact-sbom.v0.1",
                "product": "Mac Companion",
                "release": {
                    "version": release["release"]["version"],
                    "buildNumber": release["release"]["buildNumber"],
                    "targets": sorted(release["release"]["targets"]),
                },
                "source": copy.deepcopy(release["source"]),
                "created": "2026-08-21T12:00:00Z",
                "artifacts": [
                    {"id": identifier, "kind": kind, "path": f"artifacts/{identifier}.zip"}
                    for identifier, kind, _ in layouts
                ],
            }
            index, composition, spdx = generate(candidate, root)
            release["artifacts"] = [
                {
                    "id": artifact["id"], "kind": artifact["kind"], "path": artifact["path"],
                    "sha256": artifact["sha256"], "bytes": artifact["bytes"],
                }
                for artifact in index["artifacts"]
            ]
            if target_mode == "combined":
                dmg_path = root / "artifacts" / "mac-companion.dmg"
                dmg_path.write_bytes(b"combined fixture disk image")
                release["artifacts"].append({
                    "id": "mac-dmg", "kind": "macDiskImage", "path": "artifacts/mac-companion.dmg",
                    "sha256": hashlib.sha256(dmg_path.read_bytes()).hexdigest(), "bytes": dmg_path.stat().st_size,
                })
                release["notarization"]["stapledArtifactIDs"] = ["mac-app", "mac-dmg"]
            supply_chain = root / "supply-chain"
            supply_chain.mkdir()
            composition_raw = canonical_bytes(composition)
            spdx_raw = canonical_bytes(spdx)
            index_raw = canonical_bytes(index)
            (supply_chain / "artifact-composition.json").write_bytes(composition_raw)
            (supply_chain / "artifact-sbom.spdx.json").write_bytes(spdx_raw)
            (supply_chain / "artifact-sbom-index.json").write_bytes(index_raw)
            release["sbom"]["document"] = {
                "path": "supply-chain/artifact-sbom-index.json",
                "sha256": hashlib.sha256(index_raw).hexdigest(),
                "bytes": len(index_raw),
            }
            signing_policy_pin = write_signed_code_fixture(root, release, composition)
            for reference in referenced_files(release):
                path = root / reference["path"]
                if path.exists():
                    continue
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"x")
                reference["sha256"] = hashlib.sha256(b"x").hexdigest()
                reference["bytes"] = 1
            manifest_path = root / "release-evidence.json"
            manifest_path.write_bytes(canonical_bytes(release))
            if validate_manifest(release):
                print(f"{target_mode} graph integration: constructed manifest is invalid")
                return 1
            expected = (
                {"signedCodePlatformVerificationRequired"}
                if target_mode == "ios"
                else {"signedCodePlatformVerificationRequired", "missingMacPackagingEquivalence"}
            )
            errors = verify_files(release, manifest_path, expected_signing_policy_sha256=signing_policy_pin)
            if errors != expected:
                print(f"{target_mode} graph integration: valid graph returned {sorted(errors)}")
                return 1
            if target_mode == "combined":
                graph_record = next(
                    item for item in release["validation"]
                    if item["id"] == "signed-code-graph-construction"
                )
                graph_path = root / graph_record["evidence"]["path"]
                original = graph_path.read_bytes()
                for mutation in ("omitIOS", "exchangeArtifacts"):
                    mutated_release = copy.deepcopy(release)
                    mutated_record = next(
                        item for item in mutated_release["validation"]
                        if item["id"] == "signed-code-graph-construction"
                    )
                    graph = load_json(graph_path)
                    if mutation == "omitIOS":
                        graph["artifacts"] = [
                            item for item in graph["artifacts"]
                            if item["artifact"]["platform"] != "iOS"
                        ]
                    else:
                        graph["artifacts"].reverse()
                    raw = canonical_bytes(graph)
                    graph_path.write_bytes(raw)
                    mutated_record["evidence"]["sha256"] = hashlib.sha256(raw).hexdigest()
                    mutated_record["evidence"]["bytes"] = len(raw)
                    mutation_errors = verify_files(mutated_release, manifest_path, expected_signing_policy_sha256=signing_policy_pin)
                    graph_path.write_bytes(original)
                    if (
                        "invalidSignedCodeGraph" not in mutation_errors
                        or "signedCodePlatformVerificationRequired" in mutation_errors
                    ):
                        print(f"combined graph integration: {mutation} reached the platform gate")
                        return 1
    print("validated 4 iOS/combined signed-code graph release-integration case(s)")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate exact-candidate Mac Companion artifact SBOM evidence")
    parser.add_argument("index", nargs="*", type=Path)
    parser.add_argument("--evidence-root", type=Path)
    parser.add_argument("--verify-archives", action="store_true")
    arguments = parser.parse_args()
    if not arguments.index:
        if arguments.evidence_root or arguments.verify_archives:
            parser.error("archive options require an index path")
        fixture_status = validate_fixtures()
        if fixture_status:
            return fixture_status
        release_status = validate_release_integration()
        return release_status if release_status else validate_target_graph_release_integration()
    if arguments.verify_archives and arguments.evidence_root is None:
        parser.error("--verify-archives requires --evidence-root")
    failed = False
    for path in arguments.index:
        try:
            validate_bundle(path, evidence_root=arguments.evidence_root, verify_archives=arguments.verify_archives)
            print(f"{path}: valid artifact SBOM")
        except (ArtifactSBOMError, OSError, ValueError, TypeError, json.JSONDecodeError) as error:
            print(f"{path}: invalid artifact SBOM: {error}")
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())

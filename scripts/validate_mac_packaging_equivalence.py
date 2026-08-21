#!/usr/bin/env python3

from __future__ import annotations

import copy
import hashlib
import json
import os
import stat
import subprocess
import sys
import tempfile
import plistlib
import shutil
from pathlib import Path
from typing import Any

from artifact_sbom import (
    ArtifactSBOMError,
    canonical_bytes,
    generate,
    load_json,
)
from mac_packaging_equivalence import (
    EXPECTED_LAYOUT,
    MacPackagingEquivalenceError,
    build_receipt,
    inspect_dmg,
    load_canonical_receipt,
    scan_mounted_dmg,
    validate_receipt,
)
from validate_artifact_sbom import write_layout_archive, write_signed_code_fixture
from create_mac_packaging_equivalence import atomic_publish
import mac_packaging_equivalence as packaging_module


REPOSITORY = Path(__file__).resolve().parents[1]
FIXTURE_ROOT = REPOSITORY / "Tests" / "System" / "MacPackagingEquivalence"
ARTIFACT_FIXTURES = REPOSITORY / "Tests" / "System" / "ArtifactSBOM"


def _candidate(combined: bool) -> tuple[dict[str, Any], list[tuple[str, str, dict[str, Any]]]]:
    mac_layout = load_json(ARTIFACT_FIXTURES / "valid-mac-app.json")
    layouts = [
        ("mac-application", "macApplication", mac_layout),
        ("sparkle-archive", "sparkleArchive", mac_layout),
    ]
    if combined:
        layouts.append(
            ("ios-archive", "iosArchive", load_json(ARTIFACT_FIXTURES / "valid-ios-archive.json"))
        )
    targets = ["iOS", "macOS"] if combined else ["macOS"]
    return ({
        "schemaVersion": "maccompanion.artifact-sbom.v0.1",
        "product": "Mac Companion",
        "release": {
            "version": "1.0.0-beta.1",
            "buildNumber": "100",
            "targets": targets,
        },
        "source": {
            "revision": "0123456789abcdef0123456789abcdef01234567",
            "dirty": False,
        },
        "created": "2026-08-21T12:00:00Z",
        "artifacts": sorted([
            {"id": identifier, "kind": kind, "path": f"artifacts/{identifier}.zip"}
            for identifier, kind, _ in layouts
        ], key=lambda item: item["id"]),
    }, layouts)


def _context(root: Path, *, combined: bool = False) -> dict[str, Any]:
    candidate, layouts = _candidate(combined)
    for identifier, _, layout in layouts:
        write_layout_archive(root / "artifacts" / f"{identifier}.zip", layout)
    index, composition, spdx = generate(candidate, root)
    supply_chain = root / "supply-chain"
    supply_chain.mkdir()
    composition_raw = canonical_bytes(composition)
    spdx_raw = canonical_bytes(spdx)
    index_raw = canonical_bytes(index)
    (supply_chain / "artifact-composition.json").write_bytes(composition_raw)
    (supply_chain / "artifact-sbom.spdx.json").write_bytes(spdx_raw)
    index_path = supply_chain / "artifact-sbom-index.json"
    index_path.write_bytes(index_raw)
    artifact_reference = {
        "path": "supply-chain/artifact-sbom-index.json",
        "sha256": hashlib.sha256(index_raw).hexdigest(),
        "bytes": len(index_raw),
    }
    dmg_path = root / "artifacts" / "mac-companion.dmg"
    dmg_path.write_bytes(b"synthetic fixture disk image binding")
    dmg_artifact = {
        "id": "mac-disk-image",
        "kind": "macDiskImage",
        "path": "artifacts/mac-companion.dmg",
        "sha256": hashlib.sha256(dmg_path.read_bytes()).hexdigest(),
        "bytes": dmg_path.stat().st_size,
    }
    release_artifacts = [
        {
            "id": artifact["id"],
            "kind": artifact["kind"],
            "path": artifact["path"],
            "sha256": artifact["sha256"],
            "bytes": artifact["bytes"],
        }
        for artifact in index["artifacts"]
    ]
    release = {
        "release": copy.deepcopy(index["release"]),
        "source": copy.deepcopy(index["source"]),
        "artifacts": [*release_artifacts, dmg_artifact],
        "executables": [],
    }
    mac_binding = next(item for item in index["artifacts"] if item["kind"] == "macApplication")
    observed_entries = copy.deepcopy(
        next(item for item in composition["artifacts"] if item["id"] == mac_binding["id"])["entries"]
    )
    receipt = build_receipt(
        index=index,
        composition=composition,
        artifact_sbom_reference=artifact_reference,
        dmg_artifact=dmg_artifact,
        dmg_entries=observed_entries,
        dmg_layout=copy.deepcopy(EXPECTED_LAYOUT),
        created="2026-08-21T12:30:00Z",
    )
    return {
        "index": index,
        "composition": composition,
        "reference": artifact_reference,
        "release": release,
        "receipt": receipt,
        "observedEntries": observed_entries,
        "observedLayout": copy.deepcopy(EXPECTED_LAYOUT),
        "dmgPath": dmg_path,
    }


def _validate_context(context: dict[str, Any]) -> None:
    validate_receipt(
        context["receipt"],
        index=context["index"],
        composition=context["composition"],
        artifact_sbom_reference=context["reference"],
        release_manifest=context["release"],
        observed_dmg_entries=context["observedEntries"],
        observed_dmg_layout=context["observedLayout"],
    )


def _mutate(context: dict[str, Any], mutation: str) -> None:
    receipt = context["receipt"]
    if mutation in {"none", "combinedTargets", "deterministic", "nonCanonical", "duplicateJSONKey", "unpairedSurrogate", "oversizedReceipt"}:
        return
    if mutation == "releaseVersion":
        receipt["release"]["version"] = "2.0.0"
    elif mutation == "sourceRevision":
        receipt["source"]["revision"] = "89abcdef0123456789abcdef0123456789abcdef"
    elif mutation == "artifactSBOMReference":
        receipt["artifactSBOM"]["sha256"] = "1" * 64
    elif mutation == "summaryDigest":
        receipt["canonicalApp"]["treeSHA256"] = "2" * 64
    elif mutation == "containerHash":
        receipt["containers"][0]["sha256"] = "3" * 64
    elif mutation == "containerOrder":
        receipt["containers"].reverse()
    elif mutation == "receiptLayout":
        receipt["dmgLayout"]["rootEntryCount"] = 3
    elif mutation == "observedPayload":
        entry = next(item for item in context["observedEntries"] if item["type"] == "regularFile")
        entry["sha256"] = "4" * 64
    elif mutation == "observedLayout":
        context["observedLayout"]["applicationsLinkTarget"] = "/tmp"
    elif mutation == "duplicateMacApplication":
        duplicate = copy.deepcopy(next(item for item in context["release"]["artifacts"] if item["kind"] == "macApplication"))
        duplicate["id"] = "duplicate-mac-application"
        context["release"]["artifacts"].append(duplicate)
    elif mutation == "missingDMG":
        context["release"]["artifacts"] = [
            item for item in context["release"]["artifacts"] if item["kind"] != "macDiskImage"
        ]
    elif mutation == "extraRootField":
        receipt["unexpected"] = True
    elif mutation == "containerBoolSize":
        receipt["containers"][0]["bytes"] = True
    elif mutation == "created":
        receipt["created"] = "2026-02-30T00:00:00Z"
    elif mutation == "dirtySource":
        receipt["source"]["dirty"] = True
    elif mutation == "duplicateTarget":
        receipt["release"]["targets"] = ["macOS", "macOS"]
    elif mutation == "orphanParent":
        context["observedEntries"] = [
            entry for entry in context["observedEntries"]
            if entry["path"] != "Mac Companion.app/Contents/Resources"
        ]
    else:
        raise ValueError(f"unknown packaging-equivalence mutation: {mutation}")


def _parse_case(context: dict[str, Any], mutation: str, root: Path) -> None:
    path = root / "receipt.json"
    raw = canonical_bytes(context["receipt"])
    if mutation == "nonCanonical":
        raw = (json.dumps(context["receipt"], indent=2, sort_keys=True) + "\n").encode("utf-8")
    elif mutation == "duplicateJSONKey":
        raw = b'{"schemaVersion":"duplicate",' + raw[1:]
    elif mutation == "unpairedSurrogate":
        raw = b'{"bad":"\\ud800"}\n'
    elif mutation == "oversizedReceipt":
        raw = b" " * (packaging_module.MAX_RECEIPT_BYTES + 1)
    path.write_bytes(raw)
    context["receipt"] = load_canonical_receipt(path)


def validate_fixtures() -> int:
    manifest = load_json(FIXTURE_ROOT / "manifest.json")
    if (
        not isinstance(manifest, dict)
        or set(manifest) != {"profile", "cases"}
        or manifest["profile"] != "maccompanion.mac-packaging-equivalence-fixtures.v0.1"
        or not isinstance(manifest["cases"], list)
    ):
        raise MacPackagingEquivalenceError("invalid packaging-equivalence fixture manifest")
    failures: list[str] = []
    seen: set[str] = set()
    for case in manifest["cases"]:
        identifier = case.get("id")
        if not isinstance(identifier, str) or identifier in seen:
            failures.append("duplicate or invalid fixture ID")
            continue
        seen.add(identifier)
        mutation = case.get("mutation")
        error_text: str | None = None
        try:
            with tempfile.TemporaryDirectory(prefix="maccompanion-packaging-fixture-") as temporary:
                root = Path(temporary)
                context = _context(root, combined=mutation == "combinedTargets")
                original = canonical_bytes(context["receipt"])
                _mutate(context, mutation)
                if mutation in {"nonCanonical", "duplicateJSONKey", "unpairedSurrogate", "oversizedReceipt"}:
                    _parse_case(context, mutation, root)
                _validate_context(context)
                if mutation == "deterministic" and canonical_bytes(_context(root / "repeat")["receipt"]) != original:
                    raise MacPackagingEquivalenceError("receipt generation is not deterministic")
            valid = True
        except (ArtifactSBOMError, MacPackagingEquivalenceError, OSError, ValueError, KeyError, TypeError) as error:
            valid = False
            error_text = str(error)
        expected = case.get("expect")
        if (expected == "valid") != valid:
            failures.append(f"{identifier}: expected {expected}, got {'valid' if valid else 'invalid'}: {error_text}")
        if expected not in {"valid", "invalid"}:
            failures.append(f"{identifier}: invalid expectation")
        expected_error = case.get("errorContains")
        if expected_error is not None and (valid or expected_error not in (error_text or "")):
            failures.append(f"{identifier}: expected error containing {expected_error!r}, got {error_text!r}")
    if failures:
        for failure in failures:
            print(failure)
        return 1
    print(f"validated {len(seen)} mac-packaging-equivalence fixture(s)")
    return 0


def _materialize_layout(root: Path, layout: dict[str, Any]) -> None:
    for entry in layout["entries"]:
        destination = root / entry["path"].rstrip("/")
        if entry["type"] == "directory":
            destination.mkdir(parents=True, exist_ok=True)
            os.chmod(destination, int(entry["mode"], 8))
        elif entry["type"] == "regularFile":
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(
                bytes.fromhex(entry["contentHex"])
                if "contentHex" in entry
                else entry["content"].encode("utf-8")
            )
            os.chmod(destination, int(entry["mode"], 8))
        elif entry["type"] == "symlink":
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.symlink_to(entry["target"])
            if hasattr(os, "lchmod"):
                os.lchmod(destination, int(entry["mode"], 8))
        else:
            raise ValueError("unsupported scanner fixture entry")


def _clear_fixture_xattrs(root: Path) -> None:
    subprocess.run(
        ["/usr/bin/xattr", "-c", "-r", "-s", str(root)],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def validate_scanner() -> int:
    layout = load_json(ARTIFACT_FIXTURES / "valid-mac-app.json")
    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="maccompanion-packaging-scanner-") as temporary:
        root = Path(temporary)
        _materialize_layout(root, layout)
        _clear_fixture_xattrs(root)
        (root / "Applications").symlink_to("/Applications")
        try:
            entries, observed_layout = scan_mounted_dmg(root)
            with tempfile.TemporaryDirectory(prefix="maccompanion-packaging-expected-") as candidate_root:
                expected = _context(Path(candidate_root))["observedEntries"]
            if entries != expected or observed_layout != EXPECTED_LAYOUT:
                failures.append("valid mounted tree did not match canonical composition")
        except (MacPackagingEquivalenceError, OSError) as error:
            failures.append(f"valid mounted tree failed: {error}")

        probes: list[tuple[str, Any, str]] = []
        extra = root / "unexpected"
        extra.write_bytes(b"x")
        probes.append(("extra root", extra, "DMG root layout"))
        for label, created, expected_error in probes:
            try:
                scan_mounted_dmg(root)
                failures.append(f"{label} was accepted")
            except MacPackagingEquivalenceError as error:
                if expected_error not in str(error):
                    failures.append(f"{label} returned unexpected error: {error}")
            created.unlink()

        applications = root / "Applications"
        applications.unlink()
        applications.symlink_to("/tmp")
        try:
            scan_mounted_dmg(root)
            failures.append("wrong Applications target was accepted")
        except MacPackagingEquivalenceError:
            pass
        applications.unlink()
        applications.symlink_to("/Applications")

        info = root / "Mac Companion.app" / "Contents" / "Resources" / "Info.txt"
        hardlink = info.with_name("Hardlink.txt")
        os.link(info, hardlink)
        try:
            scan_mounted_dmg(root)
            failures.append("regular-file hard link was accepted")
        except MacPackagingEquivalenceError as error:
            if "hard-linked" not in str(error):
                failures.append(f"hard-link probe returned unexpected error: {error}")
        hardlink.unlink()

        fifo = info.with_name("Special.fifo")
        os.mkfifo(fifo, 0o600)
        try:
            scan_mounted_dmg(root)
            failures.append("special file was accepted")
        except MacPackagingEquivalenceError as error:
            if "special file" not in str(error):
                failures.append(f"special-file probe returned unexpected error: {error}")
        fifo.unlink()

        subprocess.run(
            ["/usr/bin/xattr", "-w", "com.jennymedia.maccompanion.fixture", "x", str(info)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        try:
            scan_mounted_dmg(root)
            failures.append("extended attribute was accepted")
        except MacPackagingEquivalenceError as error:
            if "extended attributes" not in str(error):
                failures.append(f"xattr probe returned unexpected error: {error}")
        subprocess.run(
            ["/usr/bin/xattr", "-d", "com.jennymedia.maccompanion.fixture", str(info)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if packaging_module._platform_xattrs_allowed(
            {packaging_module.PROVENANCE_XATTR: b"\x01\x03\x00" + b"x" * 8}
        ):
            failures.append("wrong provenance prefix was accepted")
        if packaging_module._platform_xattrs_allowed(
            {packaging_module.PROVENANCE_XATTR: b"\x01\x02\x00" + b"x" * 7}
        ):
            failures.append("wrong provenance length was accepted")
    if failures:
        for failure in failures:
            print(failure)
        return 1
    print("validated 8 mounted-tree/xattr-policy case(s) without mounting a disk image")
    return 0


def validate_release_integration() -> int:
    from validate_release_evidence import (
        referenced_files,
        validate_manifest,
        verify_files,
    )

    with tempfile.TemporaryDirectory(prefix="maccompanion-packaging-release-") as temporary:
        root = Path(temporary)
        context = _context(root)
        release = load_json(
            REPOSITORY / "Tests" / "System" / "ReleaseEvidence" / "valid-signed-mac-candidate.json"
        )
        next(
            item for item in release["executables"] if item["role"] == "macApp"
        )["bundleIdentifier"] = "example.maccompanion.fixture"
        release["release"]["version"] = context["release"]["release"]["version"]
        release["release"]["buildNumber"] = context["release"]["release"]["buildNumber"]
        release["release"]["targets"] = context["release"]["release"]["targets"]
        release["source"] = copy.deepcopy(context["release"]["source"])
        release["artifacts"] = copy.deepcopy(context["release"]["artifacts"])
        for executable in release["executables"]:
            executable["artifactID"] = "mac-application"
        release["notarization"]["stapledArtifactIDs"] = [
            "mac-application",
            "mac-disk-image",
        ]
        release["sbom"]["document"] = copy.deepcopy(context["reference"])
        signing_policy_pin = write_signed_code_fixture(
            root, release, context["composition"]
        )

        receipt_path = root / "validation" / "mac-packaging-equivalence.json"
        receipt_raw = canonical_bytes(context["receipt"])
        atomic_publish(receipt_path, receipt_raw)
        if stat.S_IMODE(receipt_path.stat().st_mode) != 0o600:
            print("packaging release integration: receipt mode is not 0600")
            return 1
        try:
            atomic_publish(receipt_path, receipt_raw)
        except FileExistsError:
            pass
        else:
            print("packaging release integration: receipt publisher overwrote evidence")
            return 1
        receipt_reference = {
            "path": "validation/mac-packaging-equivalence.json",
            "sha256": hashlib.sha256(receipt_raw).hexdigest(),
            "bytes": len(receipt_raw),
        }
        release["validation"].append({
            "id": "mac-packaging-equivalence",
            "status": "passed",
            "evidence": receipt_reference,
        })
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
            print("packaging release integration: constructed signed manifest is invalid")
            return 1
        errors = verify_files(
            release,
            manifest_path,
            expected_signing_policy_sha256=signing_policy_pin,
        )
        if errors != {
            "macPackagingEquivalencePlatformVerificationRequired",
            "signedCodePlatformVerificationRequired",
        }:
            print(f"packaging release integration: valid receipt returned {sorted(errors)}")
            return 1

        stale_reference = copy.deepcopy(release)
        stale_record = next(
            record for record in stale_reference["validation"]
            if record["id"] == "mac-packaging-equivalence"
        )
        stale_record["evidence"]["sha256"] = "6" * 64
        stale_errors = verify_files(
            stale_reference,
            manifest_path,
            expected_signing_policy_sha256=signing_policy_pin,
        )
        if (
            "invalidMacPackagingEquivalence" not in stale_errors
            or "macPackagingEquivalencePlatformVerificationRequired" in stale_errors
        ):
            print("packaging release integration: stale receipt reference was misclassified")
            return 1

        missing = copy.deepcopy(release)
        missing["validation"] = [
            record for record in missing["validation"]
            if record["id"] != "mac-packaging-equivalence"
        ]
        if verify_files(
            missing,
            manifest_path,
            expected_signing_policy_sha256=signing_policy_pin,
        ) != {
            "missingMacPackagingEquivalence",
            "signedCodePlatformVerificationRequired",
        }:
            print("packaging release integration: missing receipt did not fail closed exactly")
            return 1

        invalid = copy.deepcopy(release)
        invalid_receipt = copy.deepcopy(context["receipt"])
        invalid_receipt["containers"][0]["sha256"] = "5" * 64
        invalid_raw = canonical_bytes(invalid_receipt)
        receipt_path.write_bytes(invalid_raw)
        invalid_record = next(
            record for record in invalid["validation"]
            if record["id"] == "mac-packaging-equivalence"
        )
        invalid_record["evidence"]["sha256"] = hashlib.sha256(invalid_raw).hexdigest()
        invalid_record["evidence"]["bytes"] = len(invalid_raw)
        invalid_errors = verify_files(
            invalid,
            manifest_path,
            expected_signing_policy_sha256=signing_policy_pin,
        )
        if "invalidMacPackagingEquivalence" not in invalid_errors:
            print("packaging release integration: mismatched receipt was accepted")
            return 1

        noncanonical = copy.deepcopy(release)
        noncanonical_raw = (json.dumps(context["receipt"], indent=2, sort_keys=True) + "\n").encode("utf-8")
        receipt_path.write_bytes(noncanonical_raw)
        noncanonical_record = next(
            record for record in noncanonical["validation"]
            if record["id"] == "mac-packaging-equivalence"
        )
        noncanonical_record["evidence"]["sha256"] = hashlib.sha256(noncanonical_raw).hexdigest()
        noncanonical_record["evidence"]["bytes"] = len(noncanonical_raw)
        if "invalidMacPackagingEquivalence" not in verify_files(
            noncanonical,
            manifest_path,
            expected_signing_policy_sha256=signing_policy_pin,
        ):
            print("packaging release integration: noncanonical receipt was accepted")
            return 1
    print("validated 5 mac-packaging release-integration case(s)")
    return 0


def validate_attach_cleanup_model() -> int:
    failures: list[str] = []
    for scenario in (
        "malformed-output",
        "timeout-after-attach",
        "inventory-failure-recovery",
    ):
        with tempfile.TemporaryDirectory(prefix="maccompanion-attach-model-") as temporary:
            root = Path(temporary)
            dmg = root / "fixture.dmg"
            dmg.write_bytes(b"owned synthetic image")
            digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
            mount_parent = Path(tempfile.mkdtemp(
                prefix="maccompanion-dmg-equivalence-",
                dir="/private/tmp",
            ))
            expected_mount = mount_parent / "mount"
            owned_image = {
                "image-path": str(mount_parent / "pinned.dmg"),
                "writeable": False,
                "system-entities": [
                    {"content-hint": "GUID_partition_scheme", "dev-entry": "/dev/disk901"},
                    {
                        "content-hint": "41504653-0000-11AA-AA11-00306543ECAC",
                        "dev-entry": "/dev/disk902s1",
                        "mount-point": str(expected_mount),
                        "volume-kind": "apfs",
                    },
                ],
            }
            inventories = iter([[], [owned_image], []])
            inventory_calls = 0
            commands: list[list[str]] = []
            original_run = packaging_module._run
            original_run_result = packaging_module._run_result
            original_images = packaging_module._image_records
            original_mkdtemp = packaging_module.tempfile.mkdtemp
            original_ismount = packaging_module.os.path.ismount

            def fake_run(arguments: list[str], *, timeout: int = 120) -> bytes:
                commands.append(arguments)
                if "isencrypted" in arguments:
                    return plistlib.dumps({"encrypted": False})
                if "imageinfo" in arguments:
                    return plistlib.dumps({"Format": "UDZO"})
                if arguments[:3] == ["/usr/sbin/diskutil", "info", "-plist"]:
                    return plistlib.dumps({
                        "FilesystemName": "APFS",
                        "MountPoint": str(expected_mount),
                        "DeviceNode": "/dev/disk902s1",
                        "Writable": False,
                        "WritableMedia": False,
                        "WritableVolume": False,
                    })
                return b""

            def fake_attach(arguments: list[str], *, timeout: int = 120) -> subprocess.CompletedProcess[bytes]:
                if scenario == "timeout-after-attach":
                    raise MacPackagingEquivalenceError("disk-image tool failed")
                return subprocess.CompletedProcess(arguments, 0, b"not a plist", b"")

            def fake_images() -> list[dict[str, Any]]:
                nonlocal inventory_calls
                inventory_calls += 1
                if scenario == "inventory-failure-recovery" and inventory_calls > 1:
                    raise MacPackagingEquivalenceError("synthetic inventory failure")
                return next(inventories)

            try:
                packaging_module._run = fake_run
                packaging_module._run_result = fake_attach
                packaging_module._image_records = fake_images
                packaging_module.tempfile.mkdtemp = lambda **_: str(mount_parent)
                packaging_module.os.path.ismount = lambda _: False
                try:
                    packaging_module.inspect_dmg(
                        dmg,
                        expected_sha256=digest,
                        expected_bytes=dmg.stat().st_size,
                        allow_readonly_mount=True,
                    )
                    failures.append(f"{scenario}: inspection unexpectedly succeeded")
                except MacPackagingEquivalenceError:
                    pass
                if scenario == "inventory-failure-recovery":
                    if not mount_parent.exists():
                        failures.append("inventory-failure-recovery: recovery root was not retained")
                    else:
                        reconciliation_inventories = iter([[owned_image], []])
                        packaging_module._image_records = lambda: next(reconciliation_inventories)
                        try:
                            packaging_module.reconcile_recovery_root(
                                mount_parent,
                                allow_nonforce_detach=True,
                            )
                        except MacPackagingEquivalenceError as error:
                            failures.append(f"inventory-failure-recovery: reconciliation failed: {error}")
            finally:
                packaging_module._run = original_run
                packaging_module._run_result = original_run_result
                packaging_module._image_records = original_images
                packaging_module.tempfile.mkdtemp = original_mkdtemp
                packaging_module.os.path.ismount = original_ismount
            if not any(command[:2] == ["/usr/bin/hdiutil", "detach"] for command in commands):
                failures.append(f"{scenario}: exact device detach was not attempted")
            if mount_parent.exists():
                failures.append(f"{scenario}: private recovery root was not cleaned")
                shutil.rmtree(mount_parent)
    if failures:
        for failure in failures:
            print(failure)
        return 1
    print("validated 3 partial-attach/recovery case(s)")
    return 0


def validate_recovery_refusal_model() -> int:
    failures: list[str] = []
    for scenario in (
        "mutated-pinned-image",
        "ambiguous-ownership",
        "writable-attachment",
        "unexpected-root-file",
        "dangling-temp-symlink",
        "wrong-type-temp",
    ):
        recovery_root = Path(tempfile.mkdtemp(
            prefix="maccompanion-dmg-equivalence-",
            dir="/private/tmp",
        ))
        recovery_root.chmod(0o700)
        pinned = recovery_root / "pinned.dmg"
        pinned.write_bytes(b"recovery-bound image")
        pinned.chmod(0o400)
        mount_point = recovery_root / "mount"
        mount_point.mkdir(mode=0o700)
        digest = hashlib.sha256(b"recovery-bound image").hexdigest()
        packaging_module._write_recovery_state(
            recovery_root / "recovery.json",
            original_image_path=Path("/private/tmp/maccompanion-release-candidate.dmg"),
            pinned_image_path=pinned,
            image_digest=digest,
            image_bytes=len(b"recovery-bound image"),
            mount_point=mount_point,
            device="/dev/disk951",
            prior_devices=set(),
        )
        image = {
            "image-path": str(pinned),
            "writeable": scenario == "writable-attachment",
            "system-entities": [
                {"content-hint": "GUID_partition_scheme", "dev-entry": "/dev/disk951"},
                {
                    "content-hint": "41504653-0000-11AA-AA11-00306543ECAC",
                    "dev-entry": "/dev/disk952s1",
                    "mount-point": str(mount_point),
                    "volume-kind": "apfs",
                },
            ],
        }
        images = [image, copy.deepcopy(image)] if scenario == "ambiguous-ownership" else [image]
        commands: list[list[str]] = []
        original_run = packaging_module._run
        original_images = packaging_module._image_records
        if scenario == "mutated-pinned-image":
            pinned.chmod(0o600)
            pinned.write_bytes(b"mutated recovery image")
            pinned.chmod(0o400)
        elif scenario == "unexpected-root-file":
            (recovery_root / "unexpected").write_bytes(b"unexpected")
        elif scenario == "dangling-temp-symlink":
            (recovery_root / "recovery.json.tmp").symlink_to("missing-record")
        elif scenario == "wrong-type-temp":
            (recovery_root / "recovery.json.tmp").mkdir()

        def fake_run(arguments: list[str], *, timeout: int = 120) -> bytes:
            commands.append(arguments)
            if arguments[:3] == ["/usr/sbin/diskutil", "info", "-plist"]:
                return plistlib.dumps({
                    "FilesystemName": "APFS",
                    "MountPoint": str(mount_point),
                    "DeviceNode": "/dev/disk952s1",
                    "Writable": False,
                    "WritableMedia": False,
                    "WritableVolume": False,
                })
            return b""

        try:
            packaging_module._run = fake_run
            packaging_module._image_records = lambda: copy.deepcopy(images)
            try:
                packaging_module.reconcile_recovery_root(
                    recovery_root,
                    allow_nonforce_detach=True,
                )
                failures.append(f"{scenario}: unsafe recovery unexpectedly succeeded")
            except MacPackagingEquivalenceError:
                pass
        finally:
            packaging_module._run = original_run
            packaging_module._image_records = original_images
        if any(command[:2] == ["/usr/bin/hdiutil", "detach"] for command in commands):
            failures.append(f"{scenario}: recovery attempted an unsafe detach")
        if not recovery_root.exists():
            failures.append(f"{scenario}: refused recovery discarded evidence")
        else:
            shutil.rmtree(recovery_root)
    if failures:
        for failure in failures:
            print(failure)
        return 1
    print("validated 6 fail-closed recovery-refusal case(s)")
    return 0


def validate_interrupted_recovery_update_model() -> int:
    failures: list[str] = []
    for label, interrupted_bytes in (
        ("zero-byte-temp", b""),
        ("truncated-temp", b'{"schemaVersion":'),
    ):
        recovery_root = Path(tempfile.mkdtemp(
            prefix="maccompanion-dmg-equivalence-",
            dir="/private/tmp",
        ))
        recovery_root.chmod(0o700)
        pinned = recovery_root / "pinned.dmg"
        image_bytes = b"recovery-bound image"
        pinned.write_bytes(image_bytes)
        pinned.chmod(0o400)
        mount_point = recovery_root / "mount"
        mount_point.mkdir(mode=0o700)
        packaging_module._write_recovery_state(
            recovery_root / "recovery.json",
            original_image_path=Path("/private/tmp/maccompanion-release-candidate.dmg"),
            pinned_image_path=pinned,
            image_digest=hashlib.sha256(image_bytes).hexdigest(),
            image_bytes=len(image_bytes),
            mount_point=mount_point,
            device="/dev/disk961",
            prior_devices=set(),
        )
        interrupted = recovery_root / "recovery.json.tmp"
        interrupted.write_bytes(interrupted_bytes)
        interrupted.chmod(0o600)
        image = {
            "image-path": str(pinned),
            "writeable": False,
            "system-entities": [
                {"content-hint": "GUID_partition_scheme", "dev-entry": "/dev/disk961"},
                {
                    "content-hint": "41504653-0000-11AA-AA11-00306543ECAC",
                    "dev-entry": "/dev/disk962s1",
                    "mount-point": str(mount_point),
                    "volume-kind": "apfs",
                },
            ],
        }
        inventories = iter([[image], []])
        commands: list[list[str]] = []
        original_run = packaging_module._run
        original_images = packaging_module._image_records

        def fake_run(arguments: list[str], *, timeout: int = 120) -> bytes:
            commands.append(arguments)
            if arguments[:3] == ["/usr/sbin/diskutil", "info", "-plist"]:
                return plistlib.dumps({
                    "FilesystemName": "APFS",
                    "MountPoint": str(mount_point),
                    "DeviceNode": "/dev/disk962s1",
                    "Writable": False,
                    "WritableMedia": False,
                    "WritableVolume": False,
                })
            return b""

        try:
            packaging_module._run = fake_run
            packaging_module._image_records = lambda: next(inventories)
            packaging_module.reconcile_recovery_root(
                recovery_root,
                allow_nonforce_detach=True,
            )
        except (MacPackagingEquivalenceError, StopIteration) as error:
            failures.append(f"{label}: valid primary recovery could not reconcile: {error}")
        finally:
            packaging_module._run = original_run
            packaging_module._image_records = original_images
        if ["/usr/bin/hdiutil", "detach", "/dev/disk961"] not in commands:
            failures.append(f"{label}: exact non-force detach was not attempted")
        if recovery_root.exists():
            failures.append(f"{label}: reconciled recovery root was not removed")
            shutil.rmtree(recovery_root)
    if failures:
        for failure in failures:
            print(failure)
        return 1
    print("validated 2 interrupted recovery-record update case(s)")
    return 0


def validate_pinned_path_model() -> int:
    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="maccompanion-path-swap-") as temporary:
        root = Path(temporary)
        dmg = root / "candidate.dmg"
        original_bytes = b"manifest-bound image bytes"
        dmg.write_bytes(original_bytes)
        digest = hashlib.sha256(original_bytes).hexdigest()
        saved = root / "candidate.saved"
        mount_parent = Path(tempfile.mkdtemp(
            prefix="maccompanion-dmg-equivalence-",
            dir="/private/tmp",
        ))
        pinned = mount_parent / "pinned.dmg"
        mount_point = mount_parent / "mount"
        entities = [
            {"content-hint": "GUID_partition_scheme", "dev-entry": "/dev/disk911"},
            {
                "content-hint": "41504653-0000-11AA-AA11-00306543ECAC",
                "dev-entry": "/dev/disk912s1",
                "mount-point": str(mount_point),
                "volume-kind": "apfs",
            },
        ]
        owned = {
            "image-path": str(pinned),
            "writeable": False,
            "system-entities": entities,
        }
        inventories = iter([[], [owned], []])
        commands: list[list[str]] = []
        swapped = False
        context_root = Path(tempfile.mkdtemp(prefix="maccompanion-path-swap-context-"))
        expected = _context(context_root)["observedEntries"]
        originals = (
            packaging_module._run,
            packaging_module._run_result,
            packaging_module._image_records,
            packaging_module.tempfile.mkdtemp,
            packaging_module.os.path.ismount,
            packaging_module.scan_mounted_dmg,
        )

        def fake_run(arguments: list[str], *, timeout: int = 120) -> bytes:
            nonlocal swapped
            commands.append(arguments)
            if "verify" in arguments and not swapped:
                dmg.rename(saved)
                dmg.write_bytes(b"substituted public-path image")
                swapped = True
            if "isencrypted" in arguments:
                return plistlib.dumps({"encrypted": False})
            if "imageinfo" in arguments:
                return plistlib.dumps({"Format": "UDZO"})
            if arguments[:3] == ["/usr/sbin/diskutil", "info", "-plist"]:
                return plistlib.dumps({
                    "FilesystemName": "APFS",
                    "MountPoint": str(mount_point),
                    "DeviceNode": "/dev/disk912s1",
                    "Writable": False,
                    "WritableMedia": False,
                    "WritableVolume": False,
                })
            if arguments[:2] == ["/usr/bin/hdiutil", "detach"] and swapped:
                dmg.unlink()
                saved.rename(dmg)
                swapped = False
            return b""

        def fake_attach(arguments: list[str], *, timeout: int = 120) -> subprocess.CompletedProcess[bytes]:
            commands.append(arguments)
            return subprocess.CompletedProcess(
                arguments,
                0,
                plistlib.dumps({"system-entities": entities}),
                b"",
            )

        try:
            packaging_module._run = fake_run
            packaging_module._run_result = fake_attach
            packaging_module._image_records = lambda: next(inventories)
            packaging_module.tempfile.mkdtemp = lambda **_: str(mount_parent)
            packaging_module.os.path.ismount = lambda _: False
            packaging_module.scan_mounted_dmg = lambda _: (copy.deepcopy(expected), copy.deepcopy(EXPECTED_LAYOUT))
            observed, layout = packaging_module.inspect_dmg(
                dmg,
                expected_sha256=digest,
                expected_bytes=len(original_bytes),
                allow_readonly_mount=True,
            )
            if observed != expected or layout != EXPECTED_LAYOUT:
                failures.append("pinned-path substitution returned the wrong payload")
        except MacPackagingEquivalenceError as error:
            if "DMG changed during inspection" not in str(error):
                failures.append(f"pinned-path substitution returned unexpected failure: {error}")
        except OSError as error:
            failures.append(f"pinned-path substitution failed: {error}")
        finally:
            (
                packaging_module._run,
                packaging_module._run_result,
                packaging_module._image_records,
                packaging_module.tempfile.mkdtemp,
                packaging_module.os.path.ismount,
                packaging_module.scan_mounted_dmg,
            ) = originals
            if swapped:
                if dmg.exists():
                    dmg.unlink()
                saved.rename(dmg)
            if mount_parent.exists():
                shutil.rmtree(mount_parent)
            shutil.rmtree(context_root)
        tool_paths = [
            command[-1]
            for command in commands
            if tuple(command[:2]) in {
                ("/usr/bin/hdiutil", "verify"),
                ("/usr/bin/hdiutil", "isencrypted"),
                ("/usr/bin/hdiutil", "imageinfo"),
                ("/usr/bin/hdiutil", "attach"),
            }
        ]
        if not tool_paths or any(path != str(pinned) for path in tool_paths):
            failures.append("a disk-image tool reopened the mutable public candidate path")
    if failures:
        for failure in failures:
            print(failure)
        return 1
    print("validated one concurrent public-path substitution case against the pinned DMG copy")
    return 0


def run_platform_integration() -> int:
    from validate_release_evidence import (
        referenced_files,
        validate_manifest,
        verify_files,
    )

    recovery_before = {
        path.name for path in Path("/private/tmp").glob("maccompanion-dmg-equivalence-*")
    }
    with tempfile.TemporaryDirectory(prefix="maccompanion-packaging-platform-") as temporary:
        root = Path(temporary)
        context = _context(root)
        source = root / "source"
        source.mkdir()
        layout = load_json(ARTIFACT_FIXTURES / "valid-mac-app.json")
        _materialize_layout(source, layout)
        _clear_fixture_xattrs(source)
        (source / "Applications").symlink_to("/Applications")
        dmg = context["dmgPath"]
        dmg.unlink()
        subprocess.run(
            [
                "/usr/bin/hdiutil", "create", "-fs", "APFS", "-format", "UDZO",
                "-srcfolder", str(source), "-volname", "Mac Companion", str(dmg),
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
            check=True,
        )
        dmg_artifact = next(
            artifact for artifact in context["release"]["artifacts"]
            if artifact["kind"] == "macDiskImage"
        )
        dmg_artifact["sha256"] = hashlib.sha256(dmg.read_bytes()).hexdigest()
        dmg_artifact["bytes"] = dmg.stat().st_size
        receipt_path = root / "validation" / "mac-packaging-equivalence.json"
        subprocess.run(
            [
                sys.executable,
                str(REPOSITORY / "scripts" / "create_mac_packaging_equivalence.py"),
                "supply-chain/artifact-sbom-index.json",
                "--evidence-root", str(root),
                "--dmg-artifact-id", "mac-disk-image",
                "--dmg-path", "artifacts/mac-companion.dmg",
                "--created", "2026-08-21T13:00:00Z",
                "--output", "validation/mac-packaging-equivalence.json",
                "--allow-readonly-mount",
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=240,
            check=True,
        )
        context["receipt"] = load_canonical_receipt(receipt_path)

        release = load_json(
            REPOSITORY / "Tests" / "System" / "ReleaseEvidence" / "valid-signed-mac-candidate.json"
        )
        next(
            item for item in release["executables"] if item["role"] == "macApp"
        )["bundleIdentifier"] = "example.maccompanion.fixture"
        release["release"]["version"] = context["release"]["release"]["version"]
        release["release"]["buildNumber"] = context["release"]["release"]["buildNumber"]
        release["release"]["targets"] = context["release"]["release"]["targets"]
        release["source"] = copy.deepcopy(context["release"]["source"])
        release["artifacts"] = copy.deepcopy(context["release"]["artifacts"])
        for executable in release["executables"]:
            executable["artifactID"] = "mac-application"
        release["notarization"]["stapledArtifactIDs"] = [
            "mac-application",
            "mac-disk-image",
        ]
        release["sbom"]["document"] = copy.deepcopy(context["reference"])
        signing_policy_pin = write_signed_code_fixture(
            root, release, context["composition"]
        )
        receipt_raw = canonical_bytes(context["receipt"])
        release["validation"].append({
            "id": "mac-packaging-equivalence",
            "status": "passed",
            "evidence": {
                "path": "validation/mac-packaging-equivalence.json",
                "sha256": hashlib.sha256(receipt_raw).hexdigest(),
                "bytes": len(receipt_raw),
            },
        })
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
        manifest_errors = validate_manifest(release)
        if manifest_errors:
            raise MacPackagingEquivalenceError(
                f"platform release manifest is invalid: {sorted(manifest_errors)}"
            )
        platform_errors = verify_files(
            release,
            manifest_path,
            verify_platform_packaging=True,
            expected_signing_policy_sha256=signing_policy_pin,
        )
        if platform_errors != {"signedCodePlatformVerificationRequired"}:
            raise MacPackagingEquivalenceError(
                f"platform release verification failed: {sorted(platform_errors)}"
            )

        original_dmg = dmg.read_bytes()
        dmg.write_bytes(original_dmg + b"mutation")
        mutation_errors = verify_files(
            release,
            manifest_path,
            verify_platform_packaging=True,
            expected_signing_policy_sha256=signing_policy_pin,
        )
        dmg.write_bytes(original_dmg)
        if (
            "invalidMacPackagingEquivalence" not in mutation_errors
            or not {"evidenceDigestMismatch", "evidenceSizeMismatch"} & mutation_errors
        ):
            raise MacPackagingEquivalenceError("mutated DMG passed full platform release verification")
    recovery_after = {
        path.name for path in Path("/private/tmp").glob("maccompanion-dmg-equivalence-*")
    }
    if recovery_after != recovery_before:
        raise MacPackagingEquivalenceError("platform integration left packaging recovery state")
    print("validated 2 explicit APFS/UDZO packaging-reinspection case(s)")
    return 0


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Validate Mac packaging-equivalence evidence")
    parser.add_argument("receipt", nargs="*", type=Path)
    parser.add_argument(
        "--run-platform-integration",
        action="store_true",
        help="create and mount a synthetic APFS/UDZO image; never used by the public gate",
    )
    arguments = parser.parse_args()
    if arguments.receipt:
        parser.error("standalone receipts require release/SBOM context; use release evidence verification")
    fixture_status = validate_fixtures()
    if fixture_status:
        return fixture_status
    scanner_status = validate_scanner()
    if scanner_status:
        return scanner_status
    release_status = validate_release_integration()
    if release_status:
        return release_status
    cleanup_status = validate_attach_cleanup_model()
    if cleanup_status:
        return cleanup_status
    recovery_refusal_status = validate_recovery_refusal_model()
    if recovery_refusal_status:
        return recovery_refusal_status
    interrupted_recovery_status = validate_interrupted_recovery_update_model()
    if interrupted_recovery_status:
        return interrupted_recovery_status
    pinned_status = validate_pinned_path_model()
    if pinned_status:
        return pinned_status
    return run_platform_integration() if arguments.run_platform_integration else 0


if __name__ == "__main__":
    raise SystemExit(main())

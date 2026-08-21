#!/usr/bin/env python3

from __future__ import annotations

import copy
import hashlib
import json
import plistlib
import struct
import tempfile
from pathlib import Path
from typing import Any

from artifact_sbom import ArtifactSBOMError, canonical_bytes, generate, load_json
from signed_code_graph import (
    MAX_GRAPH_BYTES,
    SignedCodeGraphError,
    generate_graph,
    load_graph,
    validate_graph,
)
from validate_artifact_sbom import fixture_candidate, write_layout_archive


REPOSITORY = Path(__file__).resolve().parents[1]
FIXTURE_ROOT = REPOSITORY / "Tests" / "System" / "SignedCodeGraph"
ARTIFACT_FIXTURES = REPOSITORY / "Tests" / "System" / "ArtifactSBOM"
CREATED = "2026-08-21T13:00:00Z"


def thin_macho(cpu_type: int, file_type: int, platform: int, *, version_count: int = 1) -> bytes:
    builds = b"".join(
        struct.pack("<IIIIII", 0x32, 24, platform, 0x000D0000, 0x001A0000, 0)
        for _ in range(version_count)
    )
    signature_offset = 32 + len(builds) + 16
    signature = struct.pack("<IIII", 0x1D, 16, signature_offset, 8)
    header = struct.pack(
        "<IIIIIIII", 0xFEEDFACF, cpu_type, 0, file_type,
        version_count + 1, len(builds) + len(signature), 0, 0,
    )
    return header + builds + signature + b"fixture!"


def fat_macho(*, width: int = 32, duplicate: bool = False, overlap: bool = False) -> bytes:
    arm = thin_macho(0x0100000C, 2, 1)
    x86 = thin_macho(0x01000007 if not duplicate else 0x0100000C, 2, 1)
    entry_size = 32 if width == 64 else 20
    first = ((8 + 2 * entry_size + 15) // 16) * 16
    second = first if overlap else first + len(arm)
    magic = 0xCAFEBABF if width == 64 else 0xCAFEBABE
    header = struct.pack(">II", magic, 2)
    if width == 64:
        table = struct.pack(">IIQQII", 0x0100000C, 0, first, len(arm), 4, 0)
        table += struct.pack(">IIQQII", 0x01000007 if not duplicate else 0x0100000C, 0, second, len(x86), 4, 0)
    else:
        table = struct.pack(">IIIII", 0x0100000C, 0, first, len(arm), 4)
        table += struct.pack(">IIIII", 0x01000007 if not duplicate else 0x0100000C, 0, second, len(x86), 4)
    result = bytearray(header + table)
    result.extend(b"\0" * (first - len(result)))
    result.extend(arm)
    if not overlap:
        result.extend(x86)
    return bytes(result)


def entry(layout: dict[str, Any], path: str) -> dict[str, Any]:
    return next(item for item in layout["entries"] if item["path"] == path)


def binary_plist_with_duplicate_key(raw: bytes) -> bytes:
    trailer = raw[-32:]
    offset_size = trailer[6]
    reference_size = trailer[7]
    top_object = int.from_bytes(trailer[16:24], "big")
    offset_table = int.from_bytes(trailer[24:32], "big")
    start = offset_table + top_object * offset_size
    object_offset = int.from_bytes(raw[start:start + offset_size], "big")
    if raw[object_offset] >> 4 != 0xD or raw[object_offset] & 0xF < 2:
        raise ValueError("fixture top object is not a multi-key binary dictionary")
    keys = object_offset + 1
    mutated = bytearray(raw)
    mutated[keys + reference_size:keys + 2 * reference_size] = mutated[keys:keys + reference_size]
    return bytes(mutated)


def binary_plist_with_repeated_offset(raw: bytes) -> bytes:
    trailer = raw[-32:]
    offset_size = trailer[6]
    object_count = int.from_bytes(trailer[8:16], "big")
    offset_table = int.from_bytes(trailer[24:32], "big")
    if object_count < 2:
        raise ValueError("fixture binary plist lacks two objects")
    mutated = bytearray(raw)
    mutated[offset_table + offset_size:offset_table + 2 * offset_size] = mutated[
        offset_table:offset_table + offset_size
    ]
    return bytes(mutated)


def overlapping_binary_plist() -> bytes:
    objects = bytearray(b"\xd2\x01\x02\x03\x04")
    first_string_offset = 8 + len(objects)
    objects.extend(b"\x5f\x10\x14" + b"X" * 20)
    second_string_offset = first_string_offset + 5
    objects[second_string_offset - 8] = 0x51
    objects[second_string_offset - 8 + 1] = 0x41
    true_offset = 8 + len(objects)
    objects.append(0x09)
    false_offset = 8 + len(objects)
    objects.append(0x08)
    offset_table = 8 + len(objects)
    offsets = bytes([8, first_string_offset, second_string_offset, true_offset, false_offset])
    trailer = b"\0" * 6 + bytes([1, 1])
    trailer += (5).to_bytes(8, "big") + (0).to_bytes(8, "big") + offset_table.to_bytes(8, "big")
    return b"bplist00" + bytes(objects) + offsets + trailer


def prepare_layouts(platform: str, operation: str) -> list[tuple[str, str, dict[str, Any]]]:
    mac = copy.deepcopy(load_json(ARTIFACT_FIXTURES / "valid-mac-app.json"))
    ios = copy.deepcopy(load_json(ARTIFACT_FIXTURES / "valid-ios-archive.json"))
    mac_main = "Mac Companion.app/Contents/MacOS/Mac Companion"
    mac_agent = "Mac Companion.app/Contents/Library/LaunchAgents/MacCompanionAgent"
    mac_framework = "Mac Companion.app/Contents/Frameworks/Fixture.framework/Versions/A/Fixture"
    ios_main = "Products/Applications/Mac Companion.app/Mac Companion"
    ios_extension = "Products/Applications/Mac Companion.app/PlugIns/Fixture.appex/Fixture"
    ios_framework = "Products/Applications/Mac Companion.app/Frameworks/Fixture.framework/Fixture"
    entry(mac, mac_main)["contentHex"] = fat_macho(width=64).hex()
    entry(mac, mac_agent)["contentHex"] = thin_macho(0x0100000C, 2, 1).hex()
    entry(mac, mac_framework)["contentHex"] = fat_macho(width=32).hex()
    entry(mac, mac_framework)["mode"] = "0644"
    entry(ios, ios_main)["contentHex"] = thin_macho(0x0100000C, 2, 2).hex()
    entry(ios, ios_extension)["contentHex"] = thin_macho(0x0100000C, 8, 2).hex()
    entry(ios, ios_framework)["contentHex"] = thin_macho(0x0100000C, 6, 2).hex()
    if operation == "missingInfo":
        mac["entries"] = [item for item in mac["entries"] if item["path"] != "Mac Companion.app/Contents/Info.plist"]
    elif operation == "badCFBundleExecutable":
        target = entry(ios, "Products/Applications/Mac Companion.app/Info.plist")
        target["content"] = target["content"].replace("<string>Mac Companion</string>", "<string>Missing</string>", 1)
    elif operation == "badLaunchAgent":
        target = entry(mac, "Mac Companion.app/Contents/Library/LaunchAgents/MacCompanionAgent.plist")
        target["content"] = target["content"].replace("MacCompanionAgent</string>", "MissingAgent</string>")
    elif operation == "badPackageType":
        target = entry(mac, "Mac Companion.app/Contents/Info.plist")
        target["content"] = target["content"].replace("<string>APPL</string>", "<string>BNDL</string>")
    elif operation == "badFrameworkAlias":
        entry(mac, "Mac Companion.app/Contents/Frameworks/Fixture.framework/Versions/Current")["target"] = "B"
    elif operation == "implicitFrameworkDirectory":
        mac["entries"] = [
            item
            for item in mac["entries"]
            if item["path"] != "Mac Companion.app/Contents/Frameworks/Fixture.framework/"
        ]
    elif operation == "duplicateCFBundleExecutable":
        target = entry(mac, "Mac Companion.app/Contents/Info.plist")
        target["content"] = target["content"].replace(
            "<key>CFBundleExecutable</key>",
            "<key>CFBundleExecutable</key><string>Other</string><key>CFBundleExecutable</key>",
            1,
        )
    elif operation in {
        "binaryInfoPlist", "duplicateBinaryCFBundleKey", "repeatedBinaryOffset",
        "tooManyBinaryKeys", "binaryKeyTooLong", "tooManyBinaryKeyBytes",
        "overlappingBinaryObjects",
    }:
        target = entry(mac, "Mac Companion.app/Contents/Info.plist")
        parsed = plistlib.loads(target.pop("content").encode("utf-8"))
        if operation == "tooManyBinaryKeys":
            parsed.update({f"FixtureKey{index:04d}": index for index in range(4097)})
        elif operation == "binaryKeyTooLong":
            parsed["K" * 1025] = True
        elif operation == "tooManyBinaryKeyBytes":
            parsed.update({("K" * 1018) + f"{index:06d}": index for index in range(257)})
        raw = (
            overlapping_binary_plist()
            if operation == "overlappingBinaryObjects"
            else plistlib.dumps(parsed, fmt=plistlib.FMT_BINARY, sort_keys=True)
        )
        if operation == "duplicateBinaryCFBundleKey":
            raw = binary_plist_with_duplicate_key(raw)
        elif operation == "repeatedBinaryOffset":
            raw = binary_plist_with_repeated_offset(raw)
        target["contentHex"] = raw.hex()
    elif operation == "duplicateBundleProgram":
        target = entry(mac, "Mac Companion.app/Contents/Library/LaunchAgents/MacCompanionAgent.plist")
        target["content"] = target["content"].replace(
            "<key>BundleProgram</key>",
            "<key>BundleProgram</key><string>Other</string><key>BundleProgram</key>",
            1,
        )
    elif operation == "tooManyObjects":
        for index in range(1025):
            mac["entries"].append({
                "path": f"Mac Companion.app/Contents/Resources/object-{index:04d}",
                "type": "regularFile",
                "mode": "0644",
                "contentHex": thin_macho(0x0100000C, 6, 1).hex(),
            })
    elif operation == "tooManyVersionRecords":
        entry(mac, mac_main)["contentHex"] = thin_macho(
            0x0100000C, 2, 1, version_count=9
        ).hex()
    elif operation == "tooManyAggregateVersionRecords":
        for index in range(513):
            mac["entries"].append({
                "path": f"Mac Companion.app/Contents/Resources/version-facts-{index:04d}",
                "type": "regularFile",
                "mode": "0644",
                "contentHex": thin_macho(
                    0x0100000C, 6, 1, version_count=8
                ).hex(),
            })
    elif operation == "truncatedMachO":
        entry(mac, mac_main)["contentHex"] = "cffaedfe"
    elif operation == "overlappingFat":
        entry(mac, mac_main)["contentHex"] = fat_macho(overlap=True).hex()
    elif operation == "duplicateFatArchitecture":
        entry(mac, mac_main)["contentHex"] = fat_macho(duplicate=True).hex()
    elif operation == "outsideBundle":
        mac["entries"].append({"path": "Other.framework/", "type": "directory", "mode": "0755"})
    elif operation == "regularAncestor":
        target = entry(ios, "Products/Applications/Mac Companion.app/")
        target.update({"type": "regularFile", "mode": "0644", "content": "ancestor collision"})
    elif operation == "symlinkAncestor":
        target = entry(mac, "Mac Companion.app/Contents/Frameworks/")
        target.update({"type": "symlink", "mode": "0777", "target": "Resources"})
    elif operation == "tooManyBundles":
        for index in range(256):
            mac["entries"].append({
                "path": f"Mac Companion.app/Contents/Resources/Bundle-{index:03d}.bundle/",
                "type": "directory",
                "mode": "0755",
            })
    layouts: list[tuple[str, str, dict[str, Any]]] = []
    if platform in {"ios", "combined"}:
        layouts.append(("ios-archive", "iosArchive", ios))
    if platform in {"mac", "combined"}:
        layouts.append(("mac-application", "macApplication", mac))
        layouts.append(("sparkle-archive", "sparkleArchive", copy.deepcopy(mac)))
    return layouts


def write_fixture(root: Path, platform: str, operation: str) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], dict[str, Any]]:
    layouts = prepare_layouts(platform, operation)
    for identifier, _, layout in layouts:
        write_layout_archive(root / "artifacts" / f"{identifier}.zip", layout)
    candidate = fixture_candidate(layouts)
    index, composition, _ = generate(candidate, root)
    if operation in {"compositionOmission", "containerOmission", "compressionBomb"}:
        mac_layout = next(layout for identifier, _, layout in layouts if identifier == "mac-application")
        archive_path = root / "artifacts" / "mac-application.zip"
        if operation == "compositionOmission":
            mac_layout["entries"].append({
                "path": "Mac Companion.app/Contents/Resources/hidden-code",
                "type": "regularFile",
                "mode": "0644",
                "contentHex": thin_macho(0x0100000C, 6, 1).hex(),
            })
            write_layout_archive(archive_path, mac_layout)
        elif operation == "containerOmission":
            archive_path.write_bytes(archive_path.read_bytes() + b"unaccounted")
        else:
            mac_layout["entries"].append({
                "path": "Mac Companion.app/Contents/Resources/compression-bomb",
                "type": "regularFile",
                "mode": "0644",
                "content": "A" * (2 * 1024 * 1024 + 1),
            })
            write_layout_archive(archive_path, mac_layout)
        binding = next(item for item in index["artifacts"] if item["id"] == "mac-application")
        raw = archive_path.read_bytes()
        binding["sha256"] = hashlib.sha256(raw).hexdigest()
        binding["bytes"] = len(raw)
    release = {
        "release": copy.deepcopy(candidate["release"]),
        "source": copy.deepcopy(candidate["source"]),
        "artifacts": copy.deepcopy(index["artifacts"]),
        "executables": [],
    }
    executable_paths = {
        "mac-application": [
            ("mac-app", "Mac Companion.app/Contents/MacOS/Mac Companion"),
            ("mac-agent", "Mac Companion.app/Contents/Library/LaunchAgents/MacCompanionAgent"),
        ],
        "ios-archive": [
            ("ios-app", "Products/Applications/Mac Companion.app/Mac Companion"),
            ("ios-extension", "Products/Applications/Mac Companion.app/PlugIns/Fixture.appex/Fixture"),
        ],
    }
    for artifact in index["artifacts"]:
        for identifier, path in executable_paths.get(artifact["id"], []):
            release["executables"].append({"id": identifier, "artifactID": artifact["id"], "relativePath": path})
    if operation == "duplicateReleaseSubject":
        duplicate = copy.deepcopy(release["executables"][0])
        duplicate["id"] += "-duplicate"
        release["executables"].append(duplicate)
    index_raw = canonical_bytes(index)
    supply_chain = root / "supply-chain"
    supply_chain.mkdir()
    index_path = supply_chain / "artifact-sbom-index.json"
    index_path.write_bytes(index_raw)
    reference = {
        "path": "supply-chain/artifact-sbom-index.json",
        "sha256": hashlib.sha256(index_raw).hexdigest(),
        "bytes": len(index_raw),
    }
    graph = generate_graph(
        index=index,
        composition=composition,
        release_manifest=release,
        artifact_sbom_reference=reference,
        evidence_root=root,
        created=CREATED,
    )
    if operation == "none" or operation == "implicitFrameworkDirectory":
        planned_subjects = {
            step["objectPath"]
            for artifact in graph["artifacts"]
            for step in artifact["verificationPlan"]
            if step["action"] == "verifyObjectAllArchitectures"
        }
        if platform in {"mac", "combined"}:
            required_mac_subjects = {
                "Mac Companion.app",
                "Mac Companion.app/Contents/Frameworks/Fixture.framework",
                "Mac Companion.app/Contents/Library/LaunchAgents/MacCompanionAgent",
            }
            if not required_mac_subjects <= planned_subjects:
                raise SignedCodeGraphError("Mac verification plan lacks exact bundle/helper subjects")
        if platform in {"ios", "combined"}:
            required_ios_subjects = {
                "Products/Applications/Mac Companion.app",
                "Products/Applications/Mac Companion.app/PlugIns/Fixture.appex",
                "Products/Applications/Mac Companion.app/Frameworks/Fixture.framework",
            }
            if not required_ios_subjects <= planned_subjects or any("dSYMs/" in path for path in planned_subjects):
                raise SignedCodeGraphError("iOS verification plan lacks exact bundle or dSYM exclusion")
    return index, composition, release, graph


def mutate_graph(graph: dict[str, Any], operation: str) -> None:
    artifact = graph["artifacts"][0]
    if operation == "omitObject":
        artifact["machOObjects"].pop()
    elif operation == "addObject":
        artifact["machOObjects"].append(copy.deepcopy(artifact["machOObjects"][-1]))
    elif operation == "architectureDigest":
        artifact["machOObjects"][0]["machO"]["architectures"][0]["sliceSHA256"] = "0" * 64
    elif operation == "bundleDigest":
        artifact["bundles"][0]["infoPlist"]["sha256"] = "0" * 64
    elif operation == "planStatus":
        artifact["verificationPlan"][0]["status"] = "passed"
    elif operation == "platformEligible":
        artifact["platformAcceptanceEligible"] = True
    elif operation == "source":
        graph["source"]["revision"] = "f" * 40
    elif operation == "artifactSBOM":
        graph["artifactSBOM"]["sha256"] = "f" * 64


def run_case(case: dict[str, Any], root: Path) -> None:
    operation = case["operation"]
    index, composition, release, graph = write_fixture(root, case["platform"], operation)
    reference = copy.deepcopy(graph["artifactSBOM"])
    if operation in {
        "omitObject", "addObject", "architectureDigest", "bundleDigest", "planStatus",
        "platformEligible", "source", "artifactSBOM",
    }:
        mutate_graph(graph, operation)
    elif operation == "archiveSymlink":
        path = root / index["artifacts"][0]["path"]
        saved = path.with_suffix(".saved")
        path.rename(saved)
        path.symlink_to(saved.name)
    elif operation == "archiveMutation":
        path = root / index["artifacts"][0]["path"]
        path.write_bytes(path.read_bytes() + b"mutation")
    elif operation in {"noncanonicalGraph", "oversizedGraph", "symlinkedGraph"}:
        graph_path = root / "signed-code-graph.json"
        graph_path.write_bytes(canonical_bytes(graph))
        if operation == "noncanonicalGraph":
            graph_path.write_text(json.dumps(graph, indent=2) + "\n", encoding="utf-8")
        elif operation == "oversizedGraph":
            graph_path.write_bytes(b" " * (MAX_GRAPH_BYTES + 1))
        else:
            saved = graph_path.with_suffix(".saved")
            graph_path.rename(saved)
            graph_path.symlink_to(saved.name)
        load_graph(graph_path)
        return
    validate_graph(
        graph,
        index=index,
        composition=composition,
        release_manifest=release,
        artifact_sbom_reference=reference,
        evidence_root=root,
    )


def main() -> int:
    manifest = load_json(FIXTURE_ROOT / "manifest.json")
    if (
        not isinstance(manifest, dict)
        or set(manifest) != {"profile", "cases"}
        or manifest["profile"] != "maccompanion.signed-code-graph-fixtures.v0.1"
        or not isinstance(manifest["cases"], list)
    ):
        raise SignedCodeGraphError("invalid signed-code graph fixture manifest")
    failures: list[str] = []
    seen: set[str] = set()
    for case in manifest["cases"]:
        identifier = case.get("id")
        if not isinstance(identifier, str) or identifier in seen:
            failures.append("duplicate or invalid fixture ID")
            continue
        seen.add(identifier)
        try:
            with tempfile.TemporaryDirectory(prefix="maccompanion-signed-code-graph-") as temporary:
                run_case(case, Path(temporary))
            valid = True
            error_text = None
        except (SignedCodeGraphError, ArtifactSBOMError, OSError, ValueError, KeyError, TypeError) as error:
            valid = False
            error_text = str(error)
        if (case.get("expect") == "valid") != valid:
            failures.append(f"{identifier}: expected {case.get('expect')}, got {'valid' if valid else 'invalid'}: {error_text}")
    if failures:
        for failure in failures:
            print(failure)
        return 1
    print(f"validated {len(seen)} signed-code graph fixture(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

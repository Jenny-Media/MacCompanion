#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import os
import stat
import subprocess
import sys
import zipfile
from pathlib import Path, PurePosixPath

from update_policy import (
    SPARKLE_ARCHIVE_SHA256,
    SPARKLE_LICENSE_SHA256,
    SPARKLE_MANIFEST_SHA256,
    SPARKLE_REVISION,
)


MAX_ARCHIVE_BYTES = 64 * 1024 * 1024
MAX_ARCHIVE_ENTRIES = 512
MAX_UNCOMPRESSED_BYTES = 128 * 1024 * 1024
EXPECTED_MACH_O_MEMBERS = {
    "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Versions/B/Autoupdate",
    "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Versions/B/Sparkle",
    "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater",
    "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader",
    "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer",
    "bin/BinaryDelta",
    "bin/generate_appcast",
    "bin/generate_keys",
    "bin/sign_update",
}
EXPECTED_EXECUTABLE_MODE_MEMBERS = EXPECTED_MACH_O_MEMBERS | {
    "SampleAppcast.xml",
    "bin/old_dsa_scripts/sign_update",
}
MACH_O_MAGICS = {
    b"\xca\xfe\xba\xbe",
    b"\xca\xfe\xba\xbf",
    b"\xce\xfa\xed\xfe",
    b"\xcf\xfa\xed\xfe",
    b"\xfe\xed\xfa\xce",
    b"\xfe\xed\xfa\xcf",
}
EXPECTED_SYMLINKS = {
    "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Autoupdate": "Versions/Current/Autoupdate",
    "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Headers": "Versions/Current/Headers",
    "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Modules": "Versions/Current/Modules",
    "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/PrivateHeaders": "Versions/Current/PrivateHeaders",
    "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Resources": "Versions/Current/Resources",
    "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Sparkle": "Versions/Current/Sparkle",
    "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Updater.app": "Versions/Current/Updater.app",
    "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Versions/Current": "B",
    "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/XPCServices": "Versions/Current/XPCServices",
}


class AuditError(ValueError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def require_regular_single_link(path: Path, maximum: int | None = None) -> None:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise AuditError(f"unreadable path: {path}") from error
    if not stat.S_ISREG(metadata.st_mode) or path.is_symlink() or metadata.st_nlink != 1:
        raise AuditError(f"unsafe file authority: {path}")
    if metadata.st_size <= 0 or (maximum is not None and metadata.st_size > maximum):
        raise AuditError(f"invalid file size: {path}")


def git_output(source: Path, *arguments: str) -> str:
    completed = subprocess.run(
        ["git", "-C", str(source), *arguments],
        capture_output=True,
        check=False,
        text=True,
        timeout=30,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise AuditError(f"git inspection failed: {detail}")
    return completed.stdout.strip()


def audit_source(source: Path) -> None:
    if not source.is_dir() or source.is_symlink():
        raise AuditError("source must be a real directory")
    if git_output(source, "rev-parse", "HEAD") != SPARKLE_REVISION:
        raise AuditError("source revision mismatch")
    if git_output(source, "status", "--porcelain=v1", "--untracked-files=all"):
        raise AuditError("source checkout is not clean")

    manifest = source / "Package.swift"
    license_path = source / "LICENSE"
    require_regular_single_link(manifest)
    require_regular_single_link(license_path)
    if sha256(manifest) != SPARKLE_MANIFEST_SHA256:
        raise AuditError("upstream Package.swift digest mismatch")
    if sha256(license_path) != SPARKLE_LICENSE_SHA256:
        raise AuditError("upstream license digest mismatch")
    if any(source.rglob("PrivacyInfo.xcprivacy")):
        raise AuditError("upstream privacy manifest fact changed")


def safe_member_path(name: str) -> PurePosixPath:
    if not name or "\\" in name:
        raise AuditError("unsafe archive member path")
    path = PurePosixPath(name)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        raise AuditError(f"unsafe archive member path: {name}")
    return path


def safe_symlink_target(member: PurePosixPath, target: str) -> None:
    if not target or "\\" in target:
        raise AuditError(f"unsafe symlink target: {member}")
    path = PurePosixPath(target)
    if path.is_absolute():
        raise AuditError(f"absolute symlink target: {member}")
    depth = len(member.parent.parts)
    for part in path.parts:
        if part in {"", "."}:
            raise AuditError(f"ambiguous symlink target: {member}")
        if part == "..":
            depth -= 1
            if depth < 0:
                raise AuditError(f"escaping symlink target: {member}")
        else:
            depth += 1


def audit_archive(archive: Path) -> tuple[int, int]:
    require_regular_single_link(archive, MAX_ARCHIVE_BYTES)
    if sha256(archive) != SPARKLE_ARCHIVE_SHA256:
        raise AuditError("Sparkle archive digest mismatch")

    try:
        bundle = zipfile.ZipFile(archive)
    except (OSError, zipfile.BadZipFile) as error:
        raise AuditError("invalid Sparkle archive") from error
    with bundle:
        entries = bundle.infolist()
        if not entries or len(entries) > MAX_ARCHIVE_ENTRIES:
            raise AuditError("invalid archive entry count")
        if sum(item.file_size for item in entries) > MAX_UNCOMPRESSED_BYTES:
            raise AuditError("archive expansion exceeds policy")
        names: set[str] = set()
        executable_mode_members: set[str] = set()
        mach_o_members: set[str] = set()
        symlinks: dict[str, str] = {}
        privacy_manifests: set[str] = set()
        for item in entries:
            member = safe_member_path(item.filename.rstrip("/"))
            name = member.as_posix()
            if name in names:
                raise AuditError(f"duplicate archive member: {name}")
            names.add(name)
            mode = (item.external_attr >> 16) & 0xFFFF
            kind = stat.S_IFMT(mode)
            if kind == stat.S_IFLNK:
                try:
                    target = bundle.read(item).decode("utf-8")
                except (KeyError, UnicodeDecodeError) as error:
                    raise AuditError(f"unreadable symlink: {name}") from error
                safe_symlink_target(member, target)
                symlinks[name] = target
            elif kind not in {0, stat.S_IFREG, stat.S_IFDIR}:
                raise AuditError(f"unsupported archive member type: {name}")
            elif not item.is_dir() and mode & 0o111:
                executable_mode_members.add(name)
                with bundle.open(item) as handle:
                    if handle.read(4) in MACH_O_MAGICS:
                        mach_o_members.add(name)
            if member.name == "PrivacyInfo.xcprivacy":
                privacy_manifests.add(name)

        if executable_mode_members != EXPECTED_EXECUTABLE_MODE_MEMBERS:
            raise AuditError("archive executable-mode inventory mismatch")
        if mach_o_members != EXPECTED_MACH_O_MEMBERS:
            raise AuditError("archive Mach-O inventory mismatch")
        if symlinks != EXPECTED_SYMLINKS:
            raise AuditError("archive symlink inventory mismatch")
        if privacy_manifests:
            raise AuditError("archive privacy manifest fact changed")
        try:
            archive_license = bundle.read("LICENSE")
        except KeyError as error:
            raise AuditError("archive license is missing") from error
        if hashlib.sha256(archive_license).hexdigest() != SPARKLE_LICENSE_SHA256:
            raise AuditError("archive license digest mismatch")
        if bundle.testzip() is not None:
            raise AuditError("archive CRC validation failed")
        return len(entries), sum(item.file_size for item in entries)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Audit an already-acquired Sparkle source checkout and SwiftPM archive."
    )
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--archive", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        audit_source(arguments.source)
        count, expanded = audit_archive(arguments.archive)
    except (AuditError, OSError, subprocess.SubprocessError) as error:
        print(f"Sparkle provenance audit failed: {error}", file=sys.stderr)
        return 1
    print(
        "Validated Sparkle 2.9.6 provenance: "
        f"revision {SPARKLE_REVISION}, {count} archive entries, "
        f"{expanded} uncompressed bytes, exact license and executable topology."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

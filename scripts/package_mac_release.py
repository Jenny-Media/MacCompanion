#!/usr/bin/env python3

from __future__ import annotations

import argparse
import ctypes
import errno
import hashlib
import json
import os
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Callable, Sequence


APP_NAME = "Mac Companion.app"
APP_IDENTIFIER = "media.jenny.maccompanion"
AGENT_IDENTIFIER = "media.jenny.maccompanion.agent"
SPARKLE_FRAMEWORK_IDENTIFIER = "org.sparkle-project.Sparkle"
SPARKLE_AUTOUPDATE_IDENTIFIER = (
    "Autoupdate-5555494467dcbc6056da3300b22db5f67fff8b2d"
)
SPARKLE_UPDATER_IDENTIFIER = "org.sparkle-project.Sparkle.Updater"
UPDATE_CHECK_PROFILE_KEY = "MacCompanionUpdateUserInitiatedCheckProfile"
USER_INITIATED_FULL_UPDATE_CHECK_PROFILE = (
    "maccompanion.user-initiated-full-update-check.v1"
)
VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$")
BUILD = re.compile(r"^(?:0|[1-9][0-9]{0,17})$")
DITTO = "/usr/bin/ditto"
DISKUTIL = "/usr/sbin/diskutil"
CODESIGN = "/usr/bin/codesign"
Runner = Callable[[Sequence[str]], subprocess.CompletedProcess[str]]
AT_FDCWD = -2
RENAME_EXCL = 0x00000004


class MacReleasePackagingError(ValueError):
    pass


def _run(arguments: Sequence[str]) -> subprocess.CompletedProcess[str]:
    environment = dict(os.environ)
    for key in tuple(environment):
        if key.startswith("DYLD_"):
            environment.pop(key)
    return subprocess.run(
        tuple(arguments),
        check=True,
        capture_output=True,
        text=True,
        timeout=600,
        env=environment,
    )


def _run_checked(runner: Runner, arguments: Sequence[str], label: str) -> subprocess.CompletedProcess[str]:
    try:
        return runner(tuple(arguments))
    except (OSError, subprocess.SubprocessError) as error:
        detail = ""
        if isinstance(error, subprocess.CalledProcessError):
            combined = f"{error.stdout or ''}\n{error.stderr or ''}".strip()
            if combined:
                detail = f": {combined[-4096:]}"
        raise MacReleasePackagingError(f"{label} failed{detail}") from error


def _bounded_identity(value: str) -> str:
    if (
        not value
        or len(value.encode("utf-8")) > 256
        or value != value.strip()
        or any(ord(character) < 32 or ord(character) == 127 for character in value)
    ):
        raise MacReleasePackagingError("invalid DMG signing identity")
    return value


def _regular_executable(path: Path, label: str) -> None:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise MacReleasePackagingError(f"missing {label}") from error
    if not stat.S_ISREG(metadata.st_mode) or path.is_symlink() or metadata.st_mode & 0o111 == 0:
        raise MacReleasePackagingError(f"{label} must be a non-symlink executable file")


def _real_directory(path: Path, label: str) -> None:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise MacReleasePackagingError(f"missing {label}") from error
    if not stat.S_ISDIR(metadata.st_mode) or path.is_symlink():
        raise MacReleasePackagingError(
            f"{label} must be a non-symlink directory"
        )


def _regular_file(path: Path, label: str) -> None:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise MacReleasePackagingError(f"missing {label}") from error
    if not stat.S_ISREG(metadata.st_mode) or path.is_symlink():
        raise MacReleasePackagingError(
            f"{label} must be a non-symlink regular file"
        )


def _signature_facts(runner: Runner, path: Path, expected_identifier: str) -> str:
    result = _run_checked(
        runner,
        (CODESIGN, "--display", "--verbose=4", str(path)),
        f"signature inspection for {expected_identifier}",
    )
    facts: dict[str, list[str]] = {}
    for line in result.stderr.splitlines():
        key, separator, value = line.partition("=")
        if separator:
            facts.setdefault(key, []).append(value)
    if facts.get("Identifier") != [expected_identifier]:
        raise MacReleasePackagingError(f"unexpected signing identifier for {expected_identifier}")
    team = facts.get("TeamIdentifier")
    if not team or len(team) != 1 or not team[0]:
        raise MacReleasePackagingError(f"missing signing team for {expected_identifier}")
    if not any(authority.startswith("Developer ID Application:") for authority in facts.get("Authority", [])):
        raise MacReleasePackagingError(f"{expected_identifier} is not Developer ID signed")
    if not facts.get("Timestamp"):
        raise MacReleasePackagingError(f"{expected_identifier} lacks a secure timestamp")
    if not facts.get("Runtime Version"):
        raise MacReleasePackagingError(f"{expected_identifier} lacks hardened runtime")
    return team[0]


def _verify_app(runner: Runner, app: Path) -> str:
    main = app / "Contents" / "MacOS" / "Mac Companion"
    agent_bundle = app / "Contents" / "Helpers" / "MacCompanionAgent.app"
    agent = agent_bundle / "Contents" / "MacOS" / "MacCompanionAgent"
    agent_profile = agent_bundle / "Contents" / "embedded.provisionprofile"
    launch_agent = app / "Contents" / "Library" / "LaunchAgents" / f"{AGENT_IDENTIFIER}.plist"
    sparkle = app / "Contents" / "Frameworks" / "Sparkle.framework"
    sparkle_version = sparkle / "Versions" / "B"
    sparkle_executable = sparkle_version / "Sparkle"
    autoupdate = sparkle_version / "Autoupdate"
    updater = sparkle_version / "Updater.app"
    updater_executable = updater / "Contents" / "MacOS" / "Updater"
    _regular_executable(main, "Mac application executable")
    _real_directory(agent_bundle, "embedded Agent application wrapper")
    _regular_executable(agent, "embedded Agent executable")
    _regular_file(agent_profile, "embedded Agent provisioning profile")
    _real_directory(sparkle, "embedded Sparkle framework")
    _real_directory(sparkle_version, "embedded Sparkle framework version")
    _real_directory(updater, "embedded Sparkle Updater application")
    _regular_executable(sparkle_executable, "embedded Sparkle executable")
    _regular_executable(autoupdate, "embedded Sparkle Autoupdate executable")
    _regular_executable(updater_executable, "embedded Sparkle Updater executable")
    for xpc_services in (
        sparkle / "XPCServices",
        sparkle_version / "XPCServices",
    ):
        if xpc_services.exists() or xpc_services.is_symlink():
            raise MacReleasePackagingError(
                "stripped Sparkle XPC services re-entered the archive"
            )
    if launch_agent.is_symlink() or not launch_agent.is_file():
        raise MacReleasePackagingError("embedded LaunchAgent property list is missing")
    _run_checked(
        runner,
        (CODESIGN, "--verify", "--strict", "--deep", "--verbose=4", str(app)),
        "strict application signature verification",
    )
    app_team = _signature_facts(runner, app, APP_IDENTIFIER)
    nested_teams = (
        _signature_facts(runner, agent_bundle, AGENT_IDENTIFIER),
        _signature_facts(
            runner,
            sparkle_version,
            SPARKLE_FRAMEWORK_IDENTIFIER,
        ),
        _signature_facts(
            runner,
            autoupdate,
            SPARKLE_AUTOUPDATE_IDENTIFIER,
        ),
        _signature_facts(
            runner,
            updater,
            SPARKLE_UPDATER_IDENTIFIER,
        ),
    )
    if any(team != app_team for team in nested_teams):
        raise MacReleasePackagingError(
            "application and nested-code signing teams differ"
        )
    return app_team


def _digest(path: Path) -> dict[str, object]:
    hasher = hashlib.sha256()
    size = 0
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            size += len(chunk)
            hasher.update(chunk)
    if size <= 0:
        raise MacReleasePackagingError(f"empty packaged artifact: {path.name}")
    return {"path": path.name, "sha256": hasher.hexdigest(), "bytes": size}


def _write_summary(
    path: Path,
    *,
    version: str,
    build_number: str,
    update_check_profile: str | None,
    artifacts: list[dict[str, object]],
) -> None:
    value = {
        "schemaVersion": "maccompanion.local-mac-package.v0.2",
        "product": "Mac Companion",
        "release": {"version": version, "buildNumber": build_number},
        "macUserInitiatedUpdateCheckProfile": update_check_profile,
        "artifacts": artifacts,
        "claims": {
            "developerIDSigned": True,
            "notarized": False,
            "stapled": False,
            "sparkleArchiveSigned": False,
            "promotionReady": False,
        },
        "diskImageBackend": "diskutil-image-create-from",
    }
    path.write_bytes(
        (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
    )
    path.chmod(0o600)


def _rename_exclusive(source: Path, destination: Path) -> None:
    libc = ctypes.CDLL(None, use_errno=True)
    renameatx_np = libc.renameatx_np
    renameatx_np.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    renameatx_np.restype = ctypes.c_int
    result = renameatx_np(
        AT_FDCWD,
        os.fsencode(source),
        AT_FDCWD,
        os.fsencode(destination),
        RENAME_EXCL,
    )
    if result != 0:
        error_number = ctypes.get_errno()
        if error_number == errno.EEXIST:
            raise MacReleasePackagingError("refusing to overwrite release package directory")
        raise MacReleasePackagingError(
            f"cannot publish release package directory: {os.strerror(error_number)}"
        )


def package_release(
    archive: Path,
    output_directory: Path,
    *,
    version: str,
    build_number: str,
    dmg_signing_identity: str,
    runner: Runner = _run,
) -> Path:
    if VERSION.fullmatch(version) is None:
        raise MacReleasePackagingError("invalid release version")
    if BUILD.fullmatch(build_number) is None:
        raise MacReleasePackagingError("invalid build number")
    identity = _bounded_identity(dmg_signing_identity)
    if archive.is_symlink() or not archive.is_dir() or archive.suffix != ".xcarchive":
        raise MacReleasePackagingError("archive must be a non-symlink .xcarchive directory")
    archive = archive.resolve(strict=True)
    app = archive / "Products" / "Applications" / APP_NAME
    try:
        resolved_app = app.resolve(strict=True)
    except OSError as error:
        raise MacReleasePackagingError("archive does not contain the canonical Mac application") from error
    if app.is_symlink() or not app.is_dir() or resolved_app != app or archive not in app.parents:
        raise MacReleasePackagingError("archive does not contain the canonical Mac application")
    info_path = app / "Contents" / "Info.plist"
    if info_path.is_symlink():
        raise MacReleasePackagingError("application Info.plist must not be a symlink")
    try:
        with info_path.open("rb") as handle:
            info = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        raise MacReleasePackagingError("cannot read application Info.plist") from error
    if (
        info.get("CFBundleIdentifier") != APP_IDENTIFIER
        or info.get("CFBundleShortVersionString") != version
        or str(info.get("CFBundleVersion")) != build_number
    ):
        raise MacReleasePackagingError("archive identity or version does not match packaging inputs")
    raw_update_check_profile = info.get(UPDATE_CHECK_PROFILE_KEY)
    if raw_update_check_profile is None or raw_update_check_profile == "":
        update_check_profile = None
    elif raw_update_check_profile == USER_INITIATED_FULL_UPDATE_CHECK_PROFILE:
        update_check_profile = raw_update_check_profile
    else:
        raise MacReleasePackagingError("archive has an invalid user-initiated update-check profile")
    expected_team = _verify_app(runner, app)

    output_parent = output_directory.parent.resolve(strict=True)
    output_directory = output_parent / output_directory.name
    if output_directory.exists() or output_directory.is_symlink():
        raise MacReleasePackagingError("refusing to overwrite release package directory")

    temporary = Path(tempfile.mkdtemp(prefix=f".{output_directory.name}.", dir=output_parent))
    try:
        application_zip = temporary / f"{APP_NAME}.zip"
        sparkle_zip = temporary / f"MacCompanion-{version}.zip"
        dmg = temporary / f"MacCompanion-{version}.dmg"
        image_root = temporary / "image-root"
        image_root.mkdir(mode=0o700)
        image_app = image_root / APP_NAME
        _run_checked(
            runner,
            (DITTO, "-c", "-k", "--keepParent", "--noextattr", "--noacl", "--norsrc", "--noqtn", str(app), str(application_zip)),
            "application ZIP creation",
        )
        if application_zip.is_symlink() or not application_zip.is_file():
            raise MacReleasePackagingError("application ZIP was not created")
        shutil.copyfile(application_zip, sparkle_zip)
        application_zip.chmod(0o644)
        sparkle_zip.chmod(0o644)
        _run_checked(
            runner,
            (DITTO, "--noextattr", "--noacl", "--norsrc", "--noqtn", str(app), str(image_app)),
            "disk-image application staging",
        )
        if image_app.is_symlink() or not image_app.is_dir():
            raise MacReleasePackagingError("disk-image application was not staged")
        if _verify_app(runner, image_app) != expected_team:
            raise MacReleasePackagingError("staged application signing team changed")
        os.symlink("/Applications", image_root / "Applications")
        _run_checked(
            runner,
            (DISKUTIL, "image", "create", "from", "--format", "UDZO", "--volumeName", "Mac Companion", str(image_root), str(dmg)),
            "disk image creation",
        )
        if dmg.is_symlink() or not dmg.is_file():
            raise MacReleasePackagingError("disk image was not created")
        _run_checked(
            runner,
            (CODESIGN, "--force", "--sign", identity, "--timestamp", str(dmg)),
            "disk image signing",
        )
        _run_checked(
            runner,
            (CODESIGN, "--verify", "--strict", "--verbose=4", str(dmg)),
            "disk image signature verification",
        )
        dmg_result = _run_checked(
            runner,
            (CODESIGN, "--display", "--verbose=4", str(dmg)),
            "disk image signature inspection",
        )
        dmg_facts = dict(
            line.partition("=")[::2]
            for line in dmg_result.stderr.splitlines()
            if "=" in line
        )
        if (
            dmg_facts.get("TeamIdentifier") != expected_team
            or not dmg_facts.get("Timestamp")
            or not any(
                line.startswith("Authority=Developer ID Application:")
                for line in dmg_result.stderr.splitlines()
            )
        ):
            raise MacReleasePackagingError("disk image signature does not match the application team")
        _verify_app(runner, app)
        shutil.rmtree(image_root)
        artifacts = [_digest(application_zip), _digest(sparkle_zip), _digest(dmg)]
        _write_summary(
            temporary / "local-package-summary.json",
            version=version,
            build_number=build_number,
            update_check_profile=update_check_profile,
            artifacts=artifacts,
        )
        _rename_exclusive(temporary, output_directory)
        return output_directory
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Package one Developer ID-signed Mac Companion xcarchive without notarizing or publishing it"
    )
    parser.add_argument("archive", type=Path)
    parser.add_argument("--output-directory", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--dmg-signing-identity", required=True)
    arguments = parser.parse_args()
    output = package_release(
        arguments.archive,
        arguments.output_directory,
        version=arguments.version,
        build_number=arguments.build_number,
        dmg_signing_identity=arguments.dmg_signing_identity,
    )
    print(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except MacReleasePackagingError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)

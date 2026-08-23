#!/usr/bin/env python3

from __future__ import annotations

import json
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Sequence

from package_mac_release import (
    AGENT_IDENTIFIER,
    APP_IDENTIFIER,
    CODESIGN,
    DISKUTIL,
    DITTO,
    MacReleasePackagingError,
    package_release,
)


TEAM = "TESTTEAM01"
IDENTITY = "Developer ID Application: Test Company (TESTTEAM01)"


class FakeRunner:
    def __init__(self, *, fail_diskutil: bool = False, race_output: Path | None = None) -> None:
        self.calls: list[tuple[str, ...]] = []
        self.fail_diskutil = fail_diskutil
        self.race_output = race_output
        self.app_verification_count = 0

    def __call__(self, arguments: Sequence[str]) -> subprocess.CompletedProcess[str]:
        argv = tuple(arguments)
        self.calls.append(argv)
        if argv[:5] == (CODESIGN, "--verify", "--strict", "--deep", "--verbose=4"):
            self.app_verification_count += 1
            if self.app_verification_count == 3 and self.race_output is not None:
                self.race_output.mkdir()
                (self.race_output / "owned-by-racer").write_text("preserve", encoding="utf-8")
        if argv[:4] == (DISKUTIL, "image", "create", "from"):
            if self.fail_diskutil:
                raise subprocess.CalledProcessError(1, argv, stderr="injected disk image failure")
            Path(argv[-1]).write_bytes(b"synthetic dmg")
        elif argv[0] == DITTO and "-c" in argv:
            Path(argv[-1]).write_bytes(b"synthetic zip")
        elif argv[0] == DITTO:
            source = Path(argv[-2])
            destination = Path(argv[-1])
            shutil.copytree(source, destination, symlinks=True)
        if argv[:3] == (CODESIGN, "--display", "--verbose=4"):
            path = Path(argv[-1])
            if path.suffix == ".dmg":
                stderr = (
                    "Identifier=MacCompanion-0.1.0-beta.1\n"
                    f"Authority={IDENTITY}\nTimestamp=Aug 23, 2026\nTeamIdentifier={TEAM}\n"
                )
            else:
                identifier = AGENT_IDENTIFIER if path.name == "MacCompanionAgent" else APP_IDENTIFIER
                stderr = (
                    f"Identifier={identifier}\nAuthority={IDENTITY}\nTimestamp=Aug 23, 2026\n"
                    f"TeamIdentifier={TEAM}\nRuntime Version=27.0.0\n"
                )
            return subprocess.CompletedProcess(argv, 0, "", stderr)
        return subprocess.CompletedProcess(argv, 0, "", "")


def make_archive(root: Path) -> Path:
    archive = root / "MacCompanion.xcarchive"
    app = archive / "Products" / "Applications" / "Mac Companion.app"
    (app / "Contents" / "MacOS").mkdir(parents=True)
    (app / "Contents" / "Library" / "LaunchAgents").mkdir(parents=True)
    info = {
        "CFBundleIdentifier": APP_IDENTIFIER,
        "CFBundleShortVersionString": "0.1.0-beta.1",
        "CFBundleVersion": "1",
    }
    with (app / "Contents" / "Info.plist").open("wb") as handle:
        plistlib.dump(info, handle)
    for name in ("Mac Companion", "MacCompanionAgent"):
        executable = app / "Contents" / "MacOS" / name
        executable.write_bytes(b"binary")
        executable.chmod(0o755)
    (app / "Contents" / "Library" / "LaunchAgents" / f"{AGENT_IDENTIFIER}.plist").write_bytes(b"plist")
    return archive


def expect_error(action, phrase: str) -> None:
    try:
        action()
    except MacReleasePackagingError as error:
        if phrase not in str(error):
            raise AssertionError(f"expected {phrase!r}, received {error!r}") from error
    else:
        raise AssertionError(f"expected packaging failure containing {phrase!r}")


def main() -> int:
    with tempfile.TemporaryDirectory() as temporary_name:
        root = Path(temporary_name)
        archive = make_archive(root)
        runner = FakeRunner()
        output = package_release(
            archive,
            root / "candidate",
            version="0.1.0-beta.1",
            build_number="1",
            dmg_signing_identity=IDENTITY,
            runner=runner,
        )
        assert output == (root / "candidate").resolve()
        assert sorted(path.name for path in output.iterdir()) == [
            "Mac Companion.app.zip",
            "MacCompanion-0.1.0-beta.1.dmg",
            "MacCompanion-0.1.0-beta.1.zip",
            "local-package-summary.json",
        ]
        assert (output / "Mac Companion.app.zip").read_bytes() == (output / "MacCompanion-0.1.0-beta.1.zip").read_bytes()
        summary = json.loads((output / "local-package-summary.json").read_text(encoding="utf-8"))
        assert summary["claims"] == {
            "developerIDSigned": True,
            "notarized": False,
            "promotionReady": False,
            "sparkleArchiveSigned": False,
            "stapled": False,
        }
        assert any(call[:4] == (DISKUTIL, "image", "create", "from") for call in runner.calls)
        assert any(call[:3] == (CODESIGN, "--force", "--sign") and call[3] == IDENTITY for call in runner.calls)
        expect_error(
            lambda: package_release(
                archive,
                output,
                version="0.1.0-beta.1",
                build_number="1",
                dmg_signing_identity=IDENTITY,
                runner=FakeRunner(),
            ),
            "overwrite",
        )

    for invalid_version in ("", "1", "1.0.0/escape"):
        with tempfile.TemporaryDirectory() as temporary_name:
            root = Path(temporary_name)
            archive = make_archive(root)
            expect_error(
                lambda value=invalid_version: package_release(
                    archive,
                    root / "candidate",
                    version=value,
                    build_number="1",
                    dmg_signing_identity=IDENTITY,
                    runner=FakeRunner(),
                ),
                "version",
            )

    with tempfile.TemporaryDirectory() as temporary_name:
        root = Path(temporary_name)
        archive = make_archive(root)
        expect_error(
            lambda: package_release(
                archive,
                root / "candidate",
                version="0.1.0-beta.1",
                build_number="1",
                dmg_signing_identity="bad\nidentity",
                runner=FakeRunner(),
            ),
            "identity",
        )

    with tempfile.TemporaryDirectory() as temporary_name:
        root = Path(temporary_name)
        archive = make_archive(root)
        expect_error(
            lambda: package_release(
                archive,
                root / "candidate",
                version="0.1.0-beta.1",
                build_number="1",
                dmg_signing_identity=IDENTITY,
                runner=FakeRunner(fail_diskutil=True),
            ),
            "disk image creation failed",
        )
        assert not (root / "candidate").exists()
        assert not any(path.name.startswith(".candidate.") for path in root.iterdir())

    with tempfile.TemporaryDirectory() as temporary_name:
        root = Path(temporary_name)
        archive = make_archive(root)
        raced_output = root / "candidate"
        expect_error(
            lambda: package_release(
                archive,
                raced_output,
                version="0.1.0-beta.1",
                build_number="1",
                dmg_signing_identity=IDENTITY,
                runner=FakeRunner(race_output=raced_output),
            ),
            "overwrite",
        )
        assert (raced_output / "owned-by-racer").read_text(encoding="utf-8") == "preserve"
        assert not any(path.name.startswith(".candidate.") for path in root.iterdir())

    print("validated 8 local Mac release packaging case(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

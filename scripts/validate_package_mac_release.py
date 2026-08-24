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
    SPARKLE_AUTOUPDATE_IDENTIFIER,
    SPARKLE_FRAMEWORK_IDENTIFIER,
    SPARKLE_UPDATER_IDENTIFIER,
    UPDATE_CHECK_PROFILE_KEY,
    USER_INITIATED_FULL_UPDATE_CHECK_PROFILE,
    package_release,
)


TEAM = "TESTTEAM01"
IDENTITY = "Developer ID Application: Test Company (TESTTEAM01)"


class FakeRunner:
    def __init__(
        self,
        *,
        fail_diskutil: bool = False,
        race_output: Path | None = None,
        ad_hoc_nested: str | None = None,
        mismatched_nested_team: str | None = None,
    ) -> None:
        self.calls: list[tuple[str, ...]] = []
        self.fail_diskutil = fail_diskutil
        self.race_output = race_output
        self.ad_hoc_nested = ad_hoc_nested
        self.mismatched_nested_team = mismatched_nested_team
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
                identifiers = {
                    "MacCompanionAgent.app": AGENT_IDENTIFIER,
                    "B": SPARKLE_FRAMEWORK_IDENTIFIER,
                    "Autoupdate": SPARKLE_AUTOUPDATE_IDENTIFIER,
                    "Updater.app": SPARKLE_UPDATER_IDENTIFIER,
                }
                identifier = identifiers.get(path.name, APP_IDENTIFIER)
                if path.name == self.ad_hoc_nested:
                    return subprocess.CompletedProcess(
                        argv,
                        0,
                        "",
                        f"Identifier={identifier}\nSignature=adhoc\n"
                        "TeamIdentifier=not set\nRuntime Version=26.2.0\n",
                    )
                team = (
                    "OTHERTEAM1"
                    if path.name == self.mismatched_nested_team
                    else TEAM
                )
                stderr = (
                    f"Identifier={identifier}\nAuthority={IDENTITY}\nTimestamp=Aug 23, 2026\n"
                    f"TeamIdentifier={team}\nRuntime Version=27.0.0\n"
                )
            return subprocess.CompletedProcess(argv, 0, "", stderr)
        return subprocess.CompletedProcess(argv, 0, "", "")


def make_archive(root: Path) -> Path:
    archive = root / "MacCompanion.xcarchive"
    app = archive / "Products" / "Applications" / "Mac Companion.app"
    (app / "Contents" / "MacOS").mkdir(parents=True)
    (app / "Contents" / "Library" / "LaunchAgents").mkdir(parents=True)
    agent_bundle = app / "Contents" / "Helpers" / "MacCompanionAgent.app"
    agent_macos = agent_bundle / "Contents" / "MacOS"
    agent_macos.mkdir(parents=True)
    sparkle_version = (
        app
        / "Contents"
        / "Frameworks"
        / "Sparkle.framework"
        / "Versions"
        / "B"
    )
    updater_macos = sparkle_version / "Updater.app" / "Contents" / "MacOS"
    updater_macos.mkdir(parents=True)
    info = {
        "CFBundleIdentifier": APP_IDENTIFIER,
        "CFBundleShortVersionString": "0.1.0-beta.1",
        "CFBundleVersion": "1",
    }
    with (app / "Contents" / "Info.plist").open("wb") as handle:
        plistlib.dump(info, handle)
    with (agent_bundle / "Contents" / "Info.plist").open("wb") as handle:
        plistlib.dump(
            {
                "CFBundleExecutable": "MacCompanionAgent",
                "CFBundleIdentifier": AGENT_IDENTIFIER,
                "CFBundlePackageType": "APPL",
            },
            handle,
        )
    (agent_bundle / "Contents" / "embedded.provisionprofile").write_bytes(
        b"synthetic profile"
    )
    for executable in (
        app / "Contents" / "MacOS" / "Mac Companion",
        agent_macos / "MacCompanionAgent",
    ):
        executable.write_bytes(b"binary")
        executable.chmod(0o755)
    for executable in (
        sparkle_version / "Sparkle",
        sparkle_version / "Autoupdate",
        updater_macos / "Updater",
    ):
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
        assert summary["macUserInitiatedUpdateCheckProfile"] is None
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
        info_path = (
            archive
            / "Products"
            / "Applications"
            / "Mac Companion.app"
            / "Contents"
            / "Info.plist"
        )
        info = plistlib.loads(info_path.read_bytes())
        info[UPDATE_CHECK_PROFILE_KEY] = USER_INITIATED_FULL_UPDATE_CHECK_PROFILE
        info_path.write_bytes(plistlib.dumps(info))
        output = package_release(
            archive,
            root / "candidate",
            version="0.1.0-beta.1",
            build_number="1",
            dmg_signing_identity=IDENTITY,
            runner=FakeRunner(),
        )
        summary = json.loads(
            (output / "local-package-summary.json").read_text(encoding="utf-8")
        )
        assert (
            summary["macUserInitiatedUpdateCheckProfile"]
            == USER_INITIATED_FULL_UPDATE_CHECK_PROFILE
        )

    for invalid_profile in ("unknown-profile", ["non-string-profile"]):
        with tempfile.TemporaryDirectory() as temporary_name:
            root = Path(temporary_name)
            archive = make_archive(root)
            info_path = (
                archive
                / "Products"
                / "Applications"
                / "Mac Companion.app"
                / "Contents"
                / "Info.plist"
            )
            info = plistlib.loads(info_path.read_bytes())
            info[UPDATE_CHECK_PROFILE_KEY] = invalid_profile
            info_path.write_bytes(plistlib.dumps(info))
            expect_error(
                lambda: package_release(
                    archive,
                    root / "candidate",
                    version="0.1.0-beta.1",
                    build_number="1",
                    dmg_signing_identity=IDENTITY,
                    runner=FakeRunner(),
                ),
                "update-check profile",
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

    for runner, phrase in (
        (FakeRunner(ad_hoc_nested="Autoupdate"), "not Developer ID signed"),
        (
            FakeRunner(mismatched_nested_team="Updater.app"),
            "nested-code signing teams differ",
        ),
    ):
        with tempfile.TemporaryDirectory() as temporary_name:
            root = Path(temporary_name)
            archive = make_archive(root)
            expect_error(
                lambda selected=runner: package_release(
                    archive,
                    root / "candidate",
                    version="0.1.0-beta.1",
                    build_number="1",
                    dmg_signing_identity=IDENTITY,
                    runner=selected,
                ),
                phrase,
            )

    with tempfile.TemporaryDirectory() as temporary_name:
        root = Path(temporary_name)
        archive = make_archive(root)
        (archive / "Products" / "Applications" / "Mac Companion.app" /
         "Contents" / "Frameworks" / "Sparkle.framework" / "Versions" /
         "B" / "Autoupdate").unlink()
        expect_error(
            lambda: package_release(
                archive,
                root / "candidate",
                version="0.1.0-beta.1",
                build_number="1",
                dmg_signing_identity=IDENTITY,
                runner=FakeRunner(),
            ),
            "missing embedded Sparkle Autoupdate executable",
        )

    print("validated 14 local Mac release packaging case(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

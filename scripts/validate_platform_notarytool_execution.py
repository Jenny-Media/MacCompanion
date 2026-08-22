#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import os
import tempfile
from pathlib import Path
from typing import Any, Callable

from artifact_sbom import canonical_bytes
from platform_notarytool_execution import (
    PlatformNotarytoolExecutionError,
    execute_accepted_correlation,
    execute_submission,
    prepare_notary_submission,
)
from platform_signing_fixed_tools import (
    FixedToolInvocation,
    inspect_fixed_tool,
    prepare_private_work_root,
)


TOOL_PATH = "/Applications/Xcode-beta.app/Contents/Developer/usr/bin/notarytool"
PROFILE = "MacCompanion Release Notary"
SUBMISSION_ID = "12345678-1234-1234-1234-123456789abc"


def encoded(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")


def reference(path: Path, content: bytes) -> dict[str, Any]:
    descriptor = os.open(
        path,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
        0o600,
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


def result(
    invocation: FixedToolInvocation,
    work_root: Path,
    stdout: bytes,
    stderr: bytes = b"",
) -> dict[str, Any]:
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
        "startedAt": "2026-08-22T18:10:00.000Z",
        "completedAt": "2026-08-22T18:10:01.000Z",
        "durationMilliseconds": 1000,
        "termination": "exited",
        "returnCode": 0,
        "toolUnchanged": True,
        "stdout": reference(work_root / f"{invocation.invocation_id}.stdout", stdout),
        "stderr": reference(work_root / f"{invocation.invocation_id}.stderr", stderr),
        "passed": True,
    }


def fake_runner(
    upload_digest: str,
    upload_name: str,
    *,
    warning: bool = False,
    mutate_on: str | None = None,
    prepared_path: Path | None = None,
) -> Callable[[FixedToolInvocation, Path], dict[str, Any]]:
    def run(invocation: FixedToolInvocation, work_root: Path) -> dict[str, Any]:
        if mutate_on == invocation.invocation_id and prepared_path is not None:
            os.chmod(prepared_path, 0o600)
            with prepared_path.open("ab") as handle:
                handle.write(b"mutation")
            os.chmod(prepared_path, 0o400)
        if invocation.invocation_id.startswith("notary-submit-"):
            return result(
                invocation,
                work_root,
                encoded({
                    "id": SUBMISSION_ID,
                    "message": "Successfully uploaded file",
                    "status": "In Progress",
                }),
            )
        if invocation.invocation_id.startswith("notary-info-"):
            return result(
                invocation,
                work_root,
                encoded({
                    "createdDate": "2026-08-22T18:10:00.125Z",
                    "id": SUBMISSION_ID,
                    "name": upload_name,
                    "status": "Accepted",
                }),
            )
        if invocation.invocation_id.startswith("notary-log-"):
            issues: Any = (
                [{"severity": "warning", "message": "review me"}]
                if warning else None
            )
            return result(
                invocation,
                work_root,
                encoded({
                    "archiveFilename": upload_name,
                    "issues": issues,
                    "jobId": SUBMISSION_ID.upper(),
                    "logFormatVersion": 1,
                    "sha256": upload_digest,
                    "status": "Accepted",
                    "statusCode": 0,
                    "statusSummary": "Ready for distribution",
                    "ticketContents": [{
                        "path": "Mac Companion.app/Contents/MacOS/Mac Companion",
                        "arch": "arm64",
                    }],
                    "uploadDate": "2026-08-22T18:10:02Z",
                }),
            )
        raise RuntimeError("unexpected notarytool invocation")

    return run


def require_failure(operation: Callable[[], Any], expected: str) -> None:
    try:
        operation()
    except PlatformNotarytoolExecutionError as error:
        if expected not in str(error):
            raise RuntimeError(
                f"expected notary execution failure containing {expected!r}, got {error!r}"
            ) from error
    else:
        raise RuntimeError(f"expected notary execution failure containing {expected!r}")


def prepared_context(prefix: str) -> tuple[tempfile.TemporaryDirectory[str], dict[str, Any]]:
    temporary = tempfile.TemporaryDirectory(prefix=prefix)
    root = Path(temporary.name)
    source = root / "MacCompanion-notary.zip"
    source.write_bytes(b"Mac Companion exact notary upload")
    work_root = root / "private"
    prepare_private_work_root(work_root)
    prepared = prepare_notary_submission(
        phase="applicationArchive",
        source=source,
        work_root=work_root,
        tool=inspect_fixed_tool("apple.notarytool", TOOL_PATH),
    )
    return temporary, {
        "root": root,
        "source": source,
        "workRoot": work_root,
        "prepared": prepared,
    }


def main() -> int:
    temporary, context = prepared_context("maccompanion-notary-execution-")
    try:
        prepared = context["prepared"]
        runner = fake_runner(prepared.upload["sha256"], prepared.upload["fileName"])
        submission = execute_submission(
            prepared=prepared,
            credential_profile=PROFILE,
            work_root=context["workRoot"],
            runner=runner,
        )
        accepted = execute_accepted_correlation(
            prepared=prepared,
            submission=submission,
            credential_profile=PROFILE,
            work_root=context["workRoot"],
            runner=runner,
        )
        retained = canonical_bytes(accepted)
        if (
            PROFILE.encode("utf-8") in retained
            or str(prepared.upload_path).encode("utf-8") in retained
            or b"<redacted-keychain-profile>" not in retained
            or b"<private-upload>/applicationArchive-upload.zip" not in retained
            or accepted["acceptedPhase"]["submissionID"] != SUBMISSION_ID
            or accepted["acceptedPhase"]["log"]["sha256"] != prepared.upload["sha256"]
            or accepted["platformAcceptanceEligible"] is not False
        ):
            raise RuntimeError("protected notary execution evidence leaked or is incomplete")
    finally:
        temporary.cleanup()

    temporary, context = prepared_context("maccompanion-notary-warning-")
    try:
        prepared = context["prepared"]
        normal = fake_runner(prepared.upload["sha256"], prepared.upload["fileName"])
        submission = execute_submission(
            prepared=prepared,
            credential_profile=PROFILE,
            work_root=context["workRoot"],
            runner=normal,
        )
        warning_runner = fake_runner(
            prepared.upload["sha256"], prepared.upload["fileName"], warning=True
        )
        require_failure(
            lambda: execute_accepted_correlation(
                prepared=prepared,
                submission=submission,
                credential_profile=PROFILE,
                work_root=context["workRoot"],
                runner=warning_runner,
            ),
            "accepted correlation failed",
        )
    finally:
        temporary.cleanup()

    temporary, context = prepared_context("maccompanion-notary-mutation-")
    try:
        prepared = context["prepared"]
        mutation_runner = fake_runner(
            prepared.upload["sha256"],
            prepared.upload["fileName"],
            mutate_on="notary-submit-applicationArchive",
            prepared_path=prepared.upload_path,
        )
        require_failure(
            lambda: execute_submission(
                prepared=prepared,
                credential_profile=PROFILE,
                work_root=context["workRoot"],
                runner=mutation_runner,
            ),
            "identity changed",
        )
    finally:
        temporary.cleanup()

    temporary, context = prepared_context("maccompanion-notary-substitution-")
    try:
        prepared = context["prepared"]
        runner = fake_runner(prepared.upload["sha256"], prepared.upload["fileName"])
        submission = execute_submission(
            prepared=prepared,
            credential_profile=PROFILE,
            work_root=context["workRoot"],
            runner=runner,
        )
        changed = dict(submission)
        changed["upload"] = dict(submission["upload"])
        changed["upload"]["sha256"] = "5e" * 32
        require_failure(
            lambda: execute_accepted_correlation(
                prepared=prepared,
                submission=changed,
                credential_profile=PROFILE,
                work_root=context["workRoot"],
                runner=runner,
            ),
            "does not bind",
        )
        require_failure(
            lambda: execute_submission(
                prepared=prepared,
                credential_profile="bad/profile",
                work_root=context["workRoot"],
                runner=runner,
            ),
            "credential profile",
        )
    finally:
        temporary.cleanup()

    with tempfile.TemporaryDirectory(prefix="maccompanion-notary-symlink-") as value:
        root = Path(value)
        source = root / "source.zip"
        source.write_bytes(b"source")
        link = root / "linked.zip"
        link.symlink_to(source)
        work_root = root / "private"
        prepare_private_work_root(work_root)
        require_failure(
            lambda: prepare_notary_submission(
                phase="applicationArchive",
                source=link,
                work_root=work_root,
                tool=inspect_fixed_tool("apple.notarytool", TOOL_PATH),
            ),
            "privately pinned",
        )

    print(
        "Validated private exact-upload pinning, fixed notarytool submit/info/log "
        "plans, credential and path redaction, immutable rehashing, warning rejection, "
        "and accepted-phase correlation without contacting Apple."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


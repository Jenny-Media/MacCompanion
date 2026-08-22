#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import os
import re
import stat
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from platform_codesign_verification import INVOCATION_RESULT_KEYS, _read_raw_reference
from platform_notarization import (
    MAX_UPLOAD_BYTES,
    PHASE_PROFILE,
    PlatformNotarizationError,
    _parse_raw_json,
    _submission_id,
    compose_phase,
)
from platform_signing_fixed_tools import (
    FixedToolError,
    FixedToolIdentity,
    FixedToolInvocation,
    run_fixed_tool_invocation,
)


NOTARYTOOL_PATHS = {
    "/Applications/Xcode.app/Contents/Developer/usr/bin/notarytool",
    "/Applications/Xcode-beta.app/Contents/Developer/usr/bin/notarytool",
}
PROFILE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 ._-]{0,127}$")
SUBMIT_OUTPUT_KEYS = {"id", "message", "status"}
PUBLIC_INVOCATION_KEYS = {
    "invocationID",
    "tool",
    "argv",
    "timeoutSeconds",
    "outputLimitBytesPerStream",
    "startedAt",
    "completedAt",
    "durationMilliseconds",
    "termination",
    "returnCode",
    "toolUnchanged",
    "stdout",
    "stderr",
    "passed",
}
SUBMISSION_KEYS = {
    "phase",
    "upload",
    "submissionID",
    "initialStatus",
    "invocation",
    "platformAcceptanceEligible",
}


class PlatformNotarytoolExecutionError(ValueError):
    pass


@dataclass(frozen=True)
class PreparedNotarySubmission:
    phase: str
    upload_path: Path
    upload: dict[str, Any]
    device: int
    inode: int
    mode: int
    modified_nanoseconds: int
    tool: FixedToolIdentity


def _descriptor_identity(metadata: os.stat_result) -> tuple[int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_size,
        metadata.st_mtime_ns,
    )


def _validate_tool(tool: FixedToolIdentity) -> None:
    if tool.tool_id != "apple.notarytool" or tool.path not in NOTARYTOOL_PATHS:
        raise PlatformNotarytoolExecutionError("notary execution tool is not pinned Xcode notarytool")


def _private_root(path: Path) -> None:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise PlatformNotarytoolExecutionError("notary work root is unavailable") from error
    if (
        not stat.S_ISDIR(metadata.st_mode)
        or stat.S_ISLNK(metadata.st_mode)
        or stat.S_IMODE(metadata.st_mode) != 0o700
        or metadata.st_uid != os.geteuid()
    ):
        raise PlatformNotarytoolExecutionError("notary work root is not private")


def _hash_open_file(descriptor: int) -> tuple[str, int, os.stat_result]:
    before = os.fstat(descriptor)
    if not stat.S_ISREG(before.st_mode) or not 0 < before.st_size <= MAX_UPLOAD_BYTES:
        raise PlatformNotarytoolExecutionError("notary upload is not a bounded regular file")
    os.lseek(descriptor, 0, os.SEEK_SET)
    digest = hashlib.sha256()
    byte_count = 0
    while True:
        chunk = os.read(descriptor, 1024 * 1024)
        if not chunk:
            break
        digest.update(chunk)
        byte_count += len(chunk)
    after = os.fstat(descriptor)
    if byte_count != after.st_size or _descriptor_identity(before) != _descriptor_identity(after):
        raise PlatformNotarytoolExecutionError("notary upload changed during hashing")
    return digest.hexdigest(), byte_count, after


def _rehash_prepared(prepared: PreparedNotarySubmission) -> dict[str, Any]:
    try:
        descriptor = os.open(prepared.upload_path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError as error:
        raise PlatformNotarytoolExecutionError("prepared notary upload is unavailable") from error
    try:
        digest, byte_count, metadata = _hash_open_file(descriptor)
    finally:
        os.close(descriptor)
    if (
        metadata.st_uid != os.geteuid()
        or metadata.st_nlink != 1
        or stat.S_IMODE(metadata.st_mode) != 0o400
        or metadata.st_dev != prepared.device
        or metadata.st_ino != prepared.inode
        or metadata.st_mode != prepared.mode
        or metadata.st_mtime_ns != prepared.modified_nanoseconds
        or prepared.upload
        != {
            "fileName": prepared.upload_path.name,
            "bytes": byte_count,
            "sha256": digest,
        }
    ):
        raise PlatformNotarytoolExecutionError("prepared notary upload identity changed")
    return dict(prepared.upload)


def prepare_notary_submission(
    *,
    phase: str,
    source: Path,
    work_root: Path,
    tool: FixedToolIdentity,
) -> PreparedNotarySubmission:
    if phase not in PHASE_PROFILE:
        raise PlatformNotarytoolExecutionError("notary submission phase is unsupported")
    _validate_tool(tool)
    _private_root(work_root)
    suffix = PHASE_PROFILE[phase]["suffix"]
    if not source.name.lower().endswith(suffix):
        raise PlatformNotarytoolExecutionError("notary submission source has the wrong container type")
    output_name = f"{phase}-upload{suffix}"
    output_path = work_root / output_name
    source_descriptor: int | None = None
    output_descriptor: int | None = None
    try:
        source_descriptor = os.open(source, os.O_RDONLY | os.O_NOFOLLOW)
        output_descriptor = os.open(
            output_path,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o600,
        )
    except OSError as error:
        raise PlatformNotarytoolExecutionError("notary upload could not be privately pinned") from error
    source_before: os.stat_result | None = None
    digest = hashlib.sha256()
    byte_count = 0
    try:
        source_before = os.fstat(source_descriptor)
        if (
            not stat.S_ISREG(source_before.st_mode)
            or source_before.st_nlink < 1
            or not 0 < source_before.st_size <= MAX_UPLOAD_BYTES
        ):
            raise PlatformNotarytoolExecutionError("notary submission source is invalid")
        while True:
            chunk = os.read(source_descriptor, 1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
            byte_count += len(chunk)
            cursor = 0
            while cursor < len(chunk):
                cursor += os.write(output_descriptor, chunk[cursor:])
        os.fsync(output_descriptor)
        os.fchmod(output_descriptor, 0o400)
        source_after = os.fstat(source_descriptor)
        output_metadata = os.fstat(output_descriptor)
        if (
            byte_count != source_before.st_size
            or _descriptor_identity(source_before) != _descriptor_identity(source_after)
            or output_metadata.st_size != byte_count
            or output_metadata.st_uid != os.geteuid()
            or output_metadata.st_nlink != 1
            or stat.S_IMODE(output_metadata.st_mode) != 0o400
        ):
            raise PlatformNotarytoolExecutionError("notary upload pinning was not atomic and exact")
    finally:
        if source_descriptor is not None:
            os.close(source_descriptor)
        if output_descriptor is not None:
            os.close(output_descriptor)
    prepared = PreparedNotarySubmission(
        phase=phase,
        upload_path=output_path,
        upload={
            "fileName": output_name,
            "bytes": byte_count,
            "sha256": digest.hexdigest(),
        },
        device=output_metadata.st_dev,
        inode=output_metadata.st_ino,
        mode=output_metadata.st_mode,
        modified_nanoseconds=output_metadata.st_mtime_ns,
        tool=tool,
    )
    _rehash_prepared(prepared)
    return prepared


def _credential_profile(value: str) -> None:
    if PROFILE.fullmatch(value) is None:
        raise PlatformNotarytoolExecutionError("notary credential profile is outside the runtime profile")


def _public_invocation(
    result: dict[str, Any],
    expected: FixedToolInvocation,
    credential_profile: str,
    prepared: PreparedNotarySubmission,
) -> dict[str, Any]:
    if not isinstance(result, dict) or set(result) != INVOCATION_RESULT_KEYS:
        raise PlatformNotarytoolExecutionError("notary invocation result is not closed")
    expected_argv = [expected.tool.path, *expected.arguments]
    if (
        result.get("invocationID") != expected.invocation_id
        or result.get("tool") != expected.tool.public_record()
        or result.get("argv") != expected_argv
        or result.get("passed") is not True
        or result.get("termination") != "exited"
        or result.get("returnCode") != 0
        or result.get("toolUnchanged") is not True
    ):
        raise PlatformNotarytoolExecutionError("notary invocation did not pass its exact private plan")
    argv = list(expected_argv)
    try:
        profile_index = argv.index("--keychain-profile") + 1
    except ValueError as error:
        raise PlatformNotarytoolExecutionError("notary private argv lacks its credential slot") from error
    if profile_index >= len(argv) or argv[profile_index] != credential_profile:
        raise PlatformNotarytoolExecutionError("notary private argv changed its credential slot")
    argv[profile_index] = "<redacted-keychain-profile>"
    upload_text = str(prepared.upload_path)
    argv = [
        f"<private-upload>/{prepared.upload_path.name}" if item == upload_text else item
        for item in argv
    ]
    public = {
        key: result[key]
        for key in PUBLIC_INVOCATION_KEYS
        if key not in {"argv"}
    }
    public["argv"] = argv
    return public


def _read_stream(
    work_root: Path,
    invocation: dict[str, Any],
    stream: str,
    expected_path: str,
) -> bytes:
    try:
        return _read_raw_reference(work_root, invocation.get(stream), expected_path)
    except Exception as error:
        raise PlatformNotarytoolExecutionError("notary raw invocation evidence failed reinspection") from error


def _run(
    invocation: FixedToolInvocation,
    prepared: PreparedNotarySubmission,
    credential_profile: str,
    work_root: Path,
    runner: Callable[[FixedToolInvocation, Path], dict[str, Any]],
) -> tuple[dict[str, Any], bytes, bytes]:
    before = _rehash_prepared(prepared)
    try:
        result = runner(invocation, work_root)
    except (FixedToolError, OSError) as error:
        raise PlatformNotarytoolExecutionError("fixed notarytool invocation failed") from error
    after = _rehash_prepared(prepared)
    if before != after:
        raise PlatformNotarytoolExecutionError("prepared notary upload changed during invocation")
    stdout = _read_stream(
        work_root,
        result,
        "stdout",
        f"{invocation.invocation_id}.stdout",
    )
    stderr = _read_stream(
        work_root,
        result,
        "stderr",
        f"{invocation.invocation_id}.stderr",
    )
    if stderr:
        raise PlatformNotarytoolExecutionError("successful notarytool invocation contains stderr")
    if credential_profile.encode("utf-8") in stdout:
        raise PlatformNotarytoolExecutionError("notarytool output exposed the credential profile")
    final = _rehash_prepared(prepared)
    if after != final:
        raise PlatformNotarytoolExecutionError("prepared notary upload changed during evidence retention")
    return (
        _public_invocation(result, invocation, credential_profile, prepared),
        stdout,
        stderr,
    )


def execute_submission(
    *,
    prepared: PreparedNotarySubmission,
    credential_profile: str,
    work_root: Path,
    runner: Callable[[FixedToolInvocation, Path], dict[str, Any]] = run_fixed_tool_invocation,
) -> dict[str, Any]:
    _credential_profile(credential_profile)
    invocation = FixedToolInvocation(
        invocation_id=f"notary-submit-{prepared.phase}",
        tool=prepared.tool,
        arguments=(
            "submit",
            str(prepared.upload_path),
            "--keychain-profile",
            credential_profile,
            "--output-format",
            "json",
            "--no-progress",
            "--no-wait",
            "--no-s3-acceleration",
        ),
        timeout_seconds=300,
        stdout_required=True,
    )
    public, stdout, _ = _run(
        invocation,
        prepared,
        credential_profile,
        work_root,
        runner,
    )
    output = _parse_raw_json(stdout, "notary submission output")
    if set(output) != SUBMIT_OUTPUT_KEYS:
        raise PlatformNotarytoolExecutionError("notary submission output is not closed")
    submission_id = _submission_id(output.get("id"), "notary submission ID")
    if (
        output.get("message") != "Successfully uploaded file"
        or output.get("status") not in {"In Progress", "Accepted"}
    ):
        raise PlatformNotarytoolExecutionError("notary submission output is not a successful upload")
    return {
        "phase": prepared.phase,
        "upload": dict(prepared.upload),
        "submissionID": submission_id,
        "initialStatus": output["status"],
        "invocation": public,
        "platformAcceptanceEligible": False,
    }


def _validate_submission_record(
    submission: Any,
    prepared: PreparedNotarySubmission,
) -> str:
    if not isinstance(submission, dict) or set(submission) != SUBMISSION_KEYS:
        raise PlatformNotarytoolExecutionError("notary submission record is not closed")
    invocation = submission.get("invocation")
    if not isinstance(invocation, dict) or set(invocation) != PUBLIC_INVOCATION_KEYS:
        raise PlatformNotarytoolExecutionError("public notary submission invocation is not closed")
    expected_argv = [
        prepared.tool.path,
        "submit",
        f"<private-upload>/{prepared.upload_path.name}",
        "--keychain-profile",
        "<redacted-keychain-profile>",
        "--output-format",
        "json",
        "--no-progress",
        "--no-wait",
        "--no-s3-acceleration",
    ]
    if (
        submission.get("phase") != prepared.phase
        or submission.get("upload") != prepared.upload
        or submission.get("initialStatus") not in {"In Progress", "Accepted"}
        or submission.get("platformAcceptanceEligible") is not False
        or invocation.get("invocationID") != f"notary-submit-{prepared.phase}"
        or invocation.get("tool") != prepared.tool.public_record()
        or invocation.get("argv") != expected_argv
        or invocation.get("passed") is not True
        or invocation.get("termination") != "exited"
        or invocation.get("returnCode") != 0
        or invocation.get("toolUnchanged") is not True
    ):
        raise PlatformNotarytoolExecutionError("notary submission record does not bind the prepared upload")
    return _submission_id(submission.get("submissionID"), "notary submission ID")


def execute_accepted_correlation(
    *,
    prepared: PreparedNotarySubmission,
    submission: dict[str, Any],
    credential_profile: str,
    work_root: Path,
    runner: Callable[[FixedToolInvocation, Path], dict[str, Any]] = run_fixed_tool_invocation,
) -> dict[str, Any]:
    _credential_profile(credential_profile)
    submission_id = _validate_submission_record(submission, prepared)
    info_invocation = FixedToolInvocation(
        invocation_id=f"notary-info-{prepared.phase}",
        tool=prepared.tool,
        arguments=(
            "info",
            submission_id,
            "--keychain-profile",
            credential_profile,
            "--output-format",
            "json",
            "--no-progress",
        ),
        timeout_seconds=120,
        stdout_required=True,
    )
    public_info, info_raw, _ = _run(
        info_invocation,
        prepared,
        credential_profile,
        work_root,
        runner,
    )
    info_output = _parse_raw_json(info_raw, "notary info")
    if info_output.get("id") != submission_id:
        raise PlatformNotarytoolExecutionError("notary info does not match the submitted UUID")
    log_invocation = FixedToolInvocation(
        invocation_id=f"notary-log-{prepared.phase}",
        tool=prepared.tool,
        arguments=(
            "log",
            submission_id,
            "--keychain-profile",
            credential_profile,
        ),
        timeout_seconds=120,
        stdout_required=True,
    )
    public_log, log_raw, _ = _run(
        log_invocation,
        prepared,
        credential_profile,
        work_root,
        runner,
    )
    try:
        phase = compose_phase(
            phase=prepared.phase,
            upload=prepared.upload,
            info_raw=info_raw,
            info_path=f"{info_invocation.invocation_id}.stdout",
            log_raw=log_raw,
            log_path=f"{log_invocation.invocation_id}.stdout",
        )
    except PlatformNotarizationError as error:
        raise PlatformNotarytoolExecutionError("notary accepted correlation failed") from error
    if phase["submissionID"] != submission_id:
        raise PlatformNotarytoolExecutionError("notary accepted phase substituted the submission")
    return {
        "submission": submission,
        "infoInvocation": public_info,
        "logInvocation": public_log,
        "acceptedPhase": phase,
        "platformAcceptanceEligible": False,
    }

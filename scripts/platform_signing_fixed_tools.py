#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import os
import re
import selectors
import signal
import stat
import subprocess
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


MAX_OUTPUT_BYTES = 1024 * 1024
MAX_TIMEOUT_SECONDS = 300
MAX_TOOL_BYTES = 128 * 1024 * 1024
MAX_ARGUMENTS = 64
MAX_ARGUMENT_BYTES = 64 * 1024
MAX_SINGLE_ARGUMENT_BYTES = 4096
IDENTIFIER_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")


class FixedToolError(ValueError):
    pass


@dataclass(frozen=True)
class FixedToolIdentity:
    tool_id: str
    path: str
    bytes: int
    sha256: str
    device: int
    inode: int
    mode: int
    modified_nanoseconds: int

    def public_record(self) -> dict[str, Any]:
        return {
            "toolID": self.tool_id,
            "path": self.path,
            "bytes": self.bytes,
            "sha256": self.sha256,
        }


@dataclass(frozen=True)
class FixedToolInvocation:
    invocation_id: str
    tool: FixedToolIdentity
    arguments: tuple[str, ...]
    timeout_seconds: int
    stdout_required: bool = False
    stderr_required: bool = False


def _validate_identifier(value: str, label: str) -> None:
    if not IDENTIFIER_PATTERN.fullmatch(value):
        raise FixedToolError(f"{label} is outside the fixed-tool profile")


def _descriptor_identity(metadata: os.stat_result) -> tuple[int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_size,
        metadata.st_mtime_ns,
    )


def _hash_descriptor(descriptor: int) -> tuple[str, int, os.stat_result]:
    before = os.fstat(descriptor)
    if not stat.S_ISREG(before.st_mode):
        raise FixedToolError("fixed tool is not a regular file")
    if not 0 < before.st_size <= MAX_TOOL_BYTES:
        raise FixedToolError("fixed tool size is outside the profile")
    os.lseek(descriptor, 0, os.SEEK_SET)
    digest = hashlib.sha256()
    size = 0
    while True:
        chunk = os.read(descriptor, 1024 * 1024)
        if not chunk:
            break
        size += len(chunk)
        digest.update(chunk)
    after = os.fstat(descriptor)
    if size != after.st_size or _descriptor_identity(before) != _descriptor_identity(after):
        raise FixedToolError("fixed tool changed during inspection")
    return digest.hexdigest(), size, after


def inspect_fixed_tool(tool_id: str, path: str) -> FixedToolIdentity:
    _validate_identifier(tool_id, "tool ID")
    candidate = Path(path)
    if (
        not candidate.is_absolute()
        or str(candidate) != path
        or os.path.normpath(path) != path
        or len(path.encode("utf-8")) > 1024
    ):
        raise FixedToolError("fixed tool path must be absolute and canonical")
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError as error:
        raise FixedToolError("fixed tool could not be opened without following links") from error
    try:
        digest, byte_count, metadata = _hash_descriptor(descriptor)
    finally:
        os.close(descriptor)
    if metadata.st_uid not in {0, os.geteuid()}:
        raise FixedToolError("fixed tool has an untrusted owner")
    if metadata.st_nlink != 1:
        raise FixedToolError("fixed tool has multiple filesystem links")
    if stat.S_IMODE(metadata.st_mode) & 0o022:
        raise FixedToolError("fixed tool is group- or world-writable")
    if not stat.S_IMODE(metadata.st_mode) & 0o111:
        raise FixedToolError("fixed tool is not executable")
    return FixedToolIdentity(
        tool_id=tool_id,
        path=path,
        bytes=byte_count,
        sha256=digest,
        device=metadata.st_dev,
        inode=metadata.st_ino,
        mode=metadata.st_mode,
        modified_nanoseconds=metadata.st_mtime_ns,
    )


def _same_tool(expected: FixedToolIdentity) -> bool:
    try:
        current = inspect_fixed_tool(expected.tool_id, expected.path)
    except FixedToolError:
        return False
    return current == expected


def prepare_private_work_root(path: Path) -> None:
    try:
        path.mkdir(mode=0o700)
    except FileExistsError as error:
        raise FixedToolError("fixed-tool working root already exists") from error
    metadata = path.lstat()
    if (
        not stat.S_ISDIR(metadata.st_mode)
        or stat.S_IMODE(metadata.st_mode) != 0o700
        or metadata.st_uid != os.geteuid()
    ):
        raise FixedToolError("fixed-tool working root is not private")


def _validate_private_work_root(path: Path) -> None:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise FixedToolError("fixed-tool working root is unavailable") from error
    if (
        not stat.S_ISDIR(metadata.st_mode)
        or stat.S_ISLNK(metadata.st_mode)
        or stat.S_IMODE(metadata.st_mode) != 0o700
        or metadata.st_uid != os.geteuid()
    ):
        raise FixedToolError("fixed-tool working root is not private")


def _write_exclusive(path: Path, content: bytes) -> dict[str, Any]:
    try:
        descriptor = os.open(
            path,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o600,
        )
    except OSError as error:
        raise FixedToolError("fixed-tool raw output path is unavailable") from error
    try:
        cursor = 0
        while cursor < len(content):
            cursor += os.write(descriptor, content[cursor:])
        os.fsync(descriptor)
        metadata = os.fstat(descriptor)
        if (
            not stat.S_ISREG(metadata.st_mode)
            or stat.S_IMODE(metadata.st_mode) != 0o600
            or metadata.st_size != len(content)
        ):
            raise FixedToolError("fixed-tool raw output was not retained privately")
    finally:
        os.close(descriptor)
    return {
        "path": path.name,
        "bytes": len(content),
        "sha256": hashlib.sha256(content).hexdigest(),
    }


def _terminate_process_group(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def _collect_bounded_output(
    process: subprocess.Popen[bytes],
    timeout_seconds: int,
    maximum_output_bytes: int,
) -> tuple[bytes, bytes, str]:
    if process.stdout is None or process.stderr is None:
        raise FixedToolError("fixed-tool output pipes were not created")
    selector = selectors.DefaultSelector()
    stdout_descriptor = process.stdout.fileno()
    stderr_descriptor = process.stderr.fileno()
    streams = {stdout_descriptor: bytearray(), stderr_descriptor: bytearray()}
    selector.register(process.stdout, selectors.EVENT_READ)
    selector.register(process.stderr, selectors.EVENT_READ)
    deadline = time.monotonic() + timeout_seconds
    termination = "exited"
    try:
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                termination = "timedOut"
                _terminate_process_group(process)
                break
            events = selector.select(timeout=min(0.05, remaining))
            if not events and process.poll() is not None:
                events = [
                    (key, selectors.EVENT_READ)
                    for key in list(selector.get_map().values())
                ]
            for key, _ in events:
                try:
                    chunk = os.read(key.fd, 64 * 1024)
                except BlockingIOError:
                    continue
                if not chunk:
                    selector.unregister(key.fileobj)
                    key.fileobj.close()
                    continue
                buffer = streams[key.fd]
                if len(buffer) + len(chunk) > maximum_output_bytes:
                    allowed = max(0, maximum_output_bytes - len(buffer))
                    buffer.extend(chunk[:allowed])
                    termination = "outputLimitExceeded"
                    _terminate_process_group(process)
                    break
                buffer.extend(chunk)
            if termination != "exited":
                break
    finally:
        for key in list(selector.get_map().values()):
            selector.unregister(key.fileobj)
            key.fileobj.close()
        selector.close()
    try:
        process.wait(timeout=1)
    except subprocess.TimeoutExpired:
        _terminate_process_group(process)
        process.wait(timeout=1)
        if termination == "exited":
            termination = "timedOut"
    stdout = bytes(streams[stdout_descriptor])
    stderr = bytes(streams[stderr_descriptor])
    if termination == "exited" and process.returncode is not None and process.returncode < 0:
        termination = "signaled"
    return stdout, stderr, termination


def run_fixed_tool_invocation(
    invocation: FixedToolInvocation,
    work_root: Path,
    *,
    maximum_output_bytes: int = MAX_OUTPUT_BYTES,
) -> dict[str, Any]:
    _validate_identifier(invocation.invocation_id, "invocation ID")
    _validate_private_work_root(work_root)
    if not 1 <= invocation.timeout_seconds <= MAX_TIMEOUT_SECONDS:
        raise FixedToolError("fixed-tool timeout is outside the profile")
    if not 1 <= maximum_output_bytes <= MAX_OUTPUT_BYTES:
        raise FixedToolError("fixed-tool output bound is outside the profile")
    if any("\x00" in value for value in invocation.arguments):
        raise FixedToolError("fixed-tool argument contains NUL")
    encoded_arguments = [value.encode("utf-8") for value in invocation.arguments]
    if (
        len(encoded_arguments) > MAX_ARGUMENTS
        or sum(len(value) for value in encoded_arguments) > MAX_ARGUMENT_BYTES
        or any(len(value) > MAX_SINGLE_ARGUMENT_BYTES for value in encoded_arguments)
    ):
        raise FixedToolError("fixed-tool arguments exceed the bounded profile")
    if not _same_tool(invocation.tool):
        raise FixedToolError("fixed tool does not match its pinned inventory")

    stdout_path = work_root / f"{invocation.invocation_id}.stdout"
    stderr_path = work_root / f"{invocation.invocation_id}.stderr"
    if stdout_path.exists() or stderr_path.exists():
        raise FixedToolError("fixed-tool invocation output already exists")
    environment = {
        "HOME": str(work_root),
        "TMPDIR": str(work_root),
        "LANG": "C",
        "LC_ALL": "C",
    }
    arguments = [invocation.tool.path, *invocation.arguments]
    started = datetime.now(timezone.utc)
    started_monotonic = time.monotonic_ns()
    try:
        process = subprocess.Popen(
            arguments,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=work_root,
            env=environment,
            close_fds=True,
            shell=False,
            start_new_session=True,
        )
    except OSError as error:
        raise FixedToolError("fixed tool could not be executed") from error
    stdout, stderr, termination = _collect_bounded_output(
        process,
        invocation.timeout_seconds,
        maximum_output_bytes,
    )
    completed_monotonic = time.monotonic_ns()
    completed = datetime.now(timezone.utc)
    tool_unchanged = _same_tool(invocation.tool)
    stdout_reference = _write_exclusive(stdout_path, stdout)
    stderr_reference = _write_exclusive(stderr_path, stderr)
    return_code = process.returncode
    passed = (
        termination == "exited"
        and return_code == 0
        and tool_unchanged
        and (not invocation.stdout_required or bool(stdout))
        and (not invocation.stderr_required or bool(stderr))
    )
    return {
        "invocationID": invocation.invocation_id,
        "tool": invocation.tool.public_record(),
        "argv": arguments,
        "environment": environment,
        "timeoutSeconds": invocation.timeout_seconds,
        "outputLimitBytesPerStream": maximum_output_bytes,
        "startedAt": started.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "completedAt": completed.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "durationMilliseconds": max(0, (completed_monotonic - started_monotonic) // 1_000_000),
        "termination": termination,
        "returnCode": return_code,
        "toolUnchanged": tool_unchanged,
        "stdout": stdout_reference,
        "stderr": stderr_reference,
        "passed": passed,
    }

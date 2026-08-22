#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import os
import stat
import tempfile
from pathlib import Path

from platform_signing_fixed_tools import (
    FixedToolError,
    FixedToolInvocation,
    inspect_fixed_tool,
    prepare_private_work_root,
    run_fixed_tool_invocation,
)


def require_failure(operation, expected: str) -> None:
    try:
        operation()
    except FixedToolError as error:
        if expected not in str(error):
            raise RuntimeError(
                f"expected fixed-tool failure containing {expected!r}, got {error!r}"
            ) from error
    else:
        raise RuntimeError(f"expected fixed-tool failure containing {expected!r}")


def write_tool(path: Path, body: str) -> None:
    path.write_text("#!/bin/sh\nset -eu\n" + body, encoding="utf-8")
    path.chmod(0o700)


def invoke(
    tool: Path,
    work_root: Path,
    invocation_id: str,
    *,
    arguments: tuple[str, ...] = (),
    timeout: int = 2,
    output_limit: int = 1024,
    stdout_required: bool = False,
    stderr_required: bool = False,
):
    identity = inspect_fixed_tool("test.tool", str(tool))
    return run_fixed_tool_invocation(
        FixedToolInvocation(
            invocation_id=invocation_id,
            tool=identity,
            arguments=arguments,
            timeout_seconds=timeout,
            stdout_required=stdout_required,
            stderr_required=stderr_required,
        ),
        work_root,
        maximum_output_bytes=output_limit,
    )


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="maccompanion-fixed-tools-") as value:
        parent = Path(value)
        tool = parent / "valid-tool"
        write_tool(tool, "printf 'expected stdout'; printf 'expected stderr' >&2\n")
        root = parent / "valid-run"
        prepare_private_work_root(root)
        result = invoke(
            tool,
            root,
            "valid",
            stdout_required=True,
            stderr_required=True,
        )
        if not result["passed"] or result["termination"] != "exited":
            raise RuntimeError(f"valid fixed-tool invocation failed: {result!r}")
        if result["environment"] != {
            "HOME": str(root),
            "TMPDIR": str(root),
            "LANG": "C",
            "LC_ALL": "C",
        }:
            raise RuntimeError("fixed-tool environment was not closed")
        for stream, expected in (
            ("stdout", b"expected stdout"),
            ("stderr", b"expected stderr"),
        ):
            reference = result[stream]
            output = root.joinpath(reference["path"])
            metadata = output.lstat()
            if stat.S_IMODE(metadata.st_mode) != 0o600:
                raise RuntimeError("fixed-tool output mode was not private")
            if output.read_bytes() != expected:
                raise RuntimeError("fixed-tool raw output changed")
            if reference["sha256"] != hashlib.sha256(expected).hexdigest():
                raise RuntimeError("fixed-tool raw output digest was wrong")

        require_failure(
            lambda: inspect_fixed_tool("test.tool", "relative-tool"),
            "absolute and canonical",
        )
        require_failure(
            lambda: inspect_fixed_tool(
                "test.tool", str(parent / "nested" / ".." / "valid-tool")
            ),
            "absolute and canonical",
        )
        linked_tool = parent / "linked-tool"
        linked_tool.symlink_to(tool)
        require_failure(
            lambda: inspect_fixed_tool("test.tool", str(linked_tool)),
            "without following links",
        )
        hard_linked_tool = parent / "hard-linked-tool"
        os.link(tool, hard_linked_tool)
        require_failure(
            lambda: inspect_fixed_tool("test.tool", str(tool)),
            "multiple filesystem links",
        )
        hard_linked_tool.unlink()
        writable_tool = parent / "writable-tool"
        write_tool(writable_tool, "exit 0\n")
        writable_tool.chmod(0o722)
        require_failure(
            lambda: inspect_fixed_tool("test.tool", str(writable_tool)),
            "group- or world-writable",
        )

        contaminated_root = parent / "contaminated"
        contaminated_root.mkdir(mode=0o755)
        require_failure(
            lambda: invoke(tool, contaminated_root, "bad-root"),
            "working root is not private",
        )

        oversized_root = parent / "oversized-run"
        prepare_private_work_root(oversized_root)
        require_failure(
            lambda: invoke(
                tool,
                oversized_root,
                "oversized",
                arguments=("x" * 4097,),
            ),
            "arguments exceed the bounded profile",
        )

        pinned = inspect_fixed_tool("test.tool", str(tool))
        write_tool(tool, "printf 'changed'\n")
        changed_root = parent / "changed-run"
        prepare_private_work_root(changed_root)
        require_failure(
            lambda: run_fixed_tool_invocation(
                FixedToolInvocation("changed", pinned, (), 2),
                changed_root,
            ),
            "does not match its pinned inventory",
        )

        timeout_tool = parent / "timeout-tool"
        write_tool(timeout_tool, "/bin/sleep 3\n")
        timeout_root = parent / "timeout-run"
        prepare_private_work_root(timeout_root)
        timeout = invoke(timeout_tool, timeout_root, "timeout", timeout=1)
        if timeout["passed"] or timeout["termination"] != "timedOut":
            raise RuntimeError(f"fixed-tool timeout was accepted: {timeout!r}")

        overflow_tool = parent / "overflow-tool"
        write_tool(overflow_tool, "/usr/bin/yes x\n")
        overflow_root = parent / "overflow-run"
        prepare_private_work_root(overflow_root)
        overflow = invoke(
            overflow_tool,
            overflow_root,
            "overflow",
            output_limit=128,
        )
        if overflow["passed"] or overflow["termination"] != "outputLimitExceeded":
            raise RuntimeError(f"fixed-tool output overflow was accepted: {overflow!r}")
        if overflow["stdout"]["bytes"] != 128:
            raise RuntimeError("fixed-tool overflow did not retain the bounded prefix")

        signal_tool = parent / "signal-tool"
        write_tool(signal_tool, "kill -TERM $$\n")
        signal_root = parent / "signal-run"
        prepare_private_work_root(signal_root)
        signaled = invoke(signal_tool, signal_root, "signal")
        if signaled["passed"] or signaled["termination"] != "signaled":
            raise RuntimeError(f"fixed-tool signal termination was accepted: {signaled!r}")

        nonzero_tool = parent / "nonzero-tool"
        write_tool(nonzero_tool, "printf 'failure' >&2; exit 7\n")
        nonzero_root = parent / "nonzero-run"
        prepare_private_work_root(nonzero_root)
        nonzero = invoke(nonzero_tool, nonzero_root, "nonzero")
        if nonzero["passed"] or nonzero["returnCode"] != 7:
            raise RuntimeError(f"fixed-tool nonzero exit was accepted: {nonzero!r}")

        missing_root = parent / "missing-run"
        prepare_private_work_root(missing_root)
        missing = invoke(
            nonzero_tool,
            missing_root,
            "missing",
            stderr_required=False,
            stdout_required=True,
        )
        if missing["passed"]:
            raise RuntimeError("fixed-tool missing required output was accepted")

        duplicate_root = parent / "duplicate-run"
        prepare_private_work_root(duplicate_root)
        invoke(nonzero_tool, duplicate_root, "duplicate")
        require_failure(
            lambda: invoke(nonzero_tool, duplicate_root, "duplicate"),
            "output already exists",
        )

    print(
        "Validated fixed tool identity, private execution, closed environment, "
        "bounded raw outputs, timeouts, signals, and fail-closed result records."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

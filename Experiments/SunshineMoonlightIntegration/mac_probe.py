#!/usr/bin/env python3
"""Run a finite, loopback-only Sunshine startup probe in isolated private data."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import termios
import threading
import time

from reference_build import HERE, verify_source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--port", type=int, default=57989)
    parser.add_argument("--seconds", type=int, default=12)
    parser.add_argument("--pin-stdin", action="store_true")
    parser.add_argument("--data-directory", type=Path)
    args = parser.parse_args()
    if not 1024 < args.port < 65500:
        raise ValueError("Invalid probe port")
    if not 1 <= args.seconds <= 600:
        raise ValueError("Probe duration must be between 1 and 600 seconds")
    root = args.root.resolve()
    source = verify_source(root, "Sunshine")
    binary = source / "cmake-build-maccompanion-reference/Sunshine.app/Contents/MacOS/Sunshine"
    directory = args.data_directory.resolve() if args.data_directory else Path(tempfile.mkdtemp(prefix="mac-probe-", dir=root))
    if root not in directory.parents or not directory.is_dir():
        raise ValueError("Probe data must be an existing directory beneath the experiment root")
    os.chmod(directory, 0o700)
    supervisor = directory / "supervisor"
    subprocess.run(["xcrun", "clang", "-std=c11", "-mmacosx-version-min=26.0", "-Wall", "-Wextra", "-Werror",
                    str(HERE.parents[1] / "Native/Host/companion-supervisor.c"), "-o", str(supervisor)], check=True)
    (directory / "apps.json").write_text(json.dumps({"env": {}, "apps": [{"name": "Desktop", "image-path": "desktop.png"}]}))
    config = directory / "sunshine.conf"
    values = {"port": args.port, "bind_address": "127.0.0.1", "address_family": "ipv4",
              "keyboard": "disabled", "mouse": "disabled", "controller": "disabled",
              "native_pen_touch": "disabled", "upnp": "disabled", "stream_audio": "disabled",
              "origin_web_ui_allowed": "pc", "encoder": "videotoolbox",
              "file_apps": directory / "apps.json", "file_state": directory / "state.json",
              "credentials_file": directory / "credentials.json", "pkey": directory / "key.pem",
              "cert": directory / "cert.pem", "log_path": directory / "sunshine.log"}
    config.write_text("".join(f"{key} = {value}\n" for key, value in values.items()))
    environment = dict(os.environ, SUNSHINE_APPDATA=str(directory))
    output = directory / "startup.log"
    stdin_attributes = None
    if args.pin_stdin and os.isatty(0):
        stdin_attributes = termios.tcgetattr(0)
        hidden_input = termios.tcgetattr(0)
        hidden_input[3] &= ~termios.ECHO
        termios.tcsetattr(0, termios.TCSANOW, hidden_input)
    try:
        with output.open("w") as log:
            command = [str(supervisor), str(time.monotonic_ns() + args.seconds * 1_000_000_000), str(binary), str(config)]
            if args.pin_stdin:
                command.append("-0")
            if args.pin_stdin:
                # The supervisor gives its child a separate process group.
                # Relay via a pipe so terminal job control cannot suspend the
                # child with SIGTTIN while it reads a pairing PIN.
                with subprocess.Popen(command, env=environment, stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT) as child:
                    def relay_pin():
                        while child.poll() is None:
                            line = sys.stdin.readline()
                            if not line:
                                return
                            try:
                                child.stdin.write(line.encode())
                                child.stdin.flush()
                            except (BrokenPipeError, ValueError):
                                return
                    threading.Thread(target=relay_pin, daemon=True).start()
                    try:
                        status = child.wait(timeout=args.seconds + 4)
                    except subprocess.TimeoutExpired:
                        child.terminate()
                        status = child.wait(timeout=3)
                    result = subprocess.CompletedProcess(command, status)
            else:
                result = subprocess.run(command, env=environment, stdout=log, stderr=subprocess.STDOUT, timeout=args.seconds + 4)
    finally:
        if stdin_attributes:
            termios.tcsetattr(0, termios.TCSANOW, stdin_attributes)
    # Report only fixed diagnostics; private local logs may contain machine
    # and monitor names. Never export their raw content into evidence.
    content = output.read_text(errors="replace")
    report = {"exit_code": result.returncode, "local_log": str(output),
              "screen_permission_missing": "No screen capture permission!" in content,
              "encoder_available": "Found H.264 encoder" in content,
              "server_listening": "Configuration UI available" in content}
    (root / "mac-probe-result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()

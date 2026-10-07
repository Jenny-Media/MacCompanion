"""Run an existing virtual-display helper briefly; retain only capture metadata.

Usage: python3 run_helper_probe.py HELPER_EXECUTABLE METADATA_PROBE_EXECUTABLE [watch|legacy]
The helper is always terminated. No permissions, preferences or services change.
"""
import json
import selectors
import subprocess
import sys
import time


def main():
    if len(sys.argv) not in (3, 4) or (len(sys.argv) == 4 and sys.argv[3] not in ("watch", "legacy")):
        raise SystemExit(__doc__)
    helper = subprocess.Popen([sys.argv[1]], stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, text=True)
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(helper.stdout, selectors.EVENT_READ)
            if not selector.select(5):
                raise RuntimeError("helperReadyTimeout")
            line = helper.stdout.readline().strip()
        if not line.startswith("READY ") or not line[6:].isdigit():
            raise RuntimeError("invalidHelperReady")
        display_id = int(line[6:])
        print(json.dumps({"helperReadyDisplayID": display_id}), flush=True)
        time.sleep(2)
        if len(sys.argv) == 4:
            arguments = [sys.argv[2], str(display_id)]
            if sys.argv[3] == "watch":
                arguments.append("watch")
            subprocess.run(arguments, check=True, timeout=70)
            return
        for method in ("stream", "screenshot"):
            try:
                result = subprocess.run([sys.argv[2], str(display_id), method],
                                        capture_output=True, text=True, timeout=12)
                print(json.dumps({"method": method, "exit": result.returncode,
                                  "metadata": result.stdout.strip()}), flush=True)
            except subprocess.TimeoutExpired:
                print(json.dumps({"method": method, "timeout": True}), flush=True)
    finally:
        if helper.poll() is None:
            helper.terminate()
            try:
                helper.wait(timeout=3)
            except subprocess.TimeoutExpired:
                helper.kill()
                helper.wait(timeout=3)


if __name__ == "__main__":
    main()

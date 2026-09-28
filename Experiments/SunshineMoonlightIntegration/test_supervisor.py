#!/usr/bin/env python3
"""Exercise the real macOS supervisor with disposable child processes."""
from pathlib import Path
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest

HERE = Path(__file__).resolve().parent


class SupervisorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory(prefix="maccompanion-supervisor-", dir="/private/tmp")
        cls.root = Path(cls.scratch.name)
        cls.binary = cls.root / "supervisor"
        subprocess.run(["xcrun", "clang", "-std=c11", "-mmacosx-version-min=26.0", "-Wall", "-Wextra", "-Werror",
                        str(HERE.parents[1] / "Native/Host/companion-supervisor.c"), "-o", str(cls.binary)], check=True)
        cls.fake = cls.root / "child.py"
        cls.fake.write_text("import os,sys,time\nfrom pathlib import Path\nPath(sys.argv[1]).write_text(str(os.getpid()))\ntime.sleep(30)\n")

    @classmethod
    def tearDownClass(cls):
        cls.scratch.cleanup()

    def child_pid(self, path):
        deadline = time.monotonic() + 3
        while not path.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(path.exists(), "Disposable helper did not start")
        return int(path.read_text())

    def assert_child_gone(self, pid):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return
            time.sleep(0.01)
        self.fail("Supervisor left its helper running")

    def test_deadline_kills_and_reaps_child(self):
        marker = self.root / "deadline.pid"
        began = time.monotonic()
        result = subprocess.run([str(self.binary), str(time.monotonic_ns() + 200_000_000), sys.executable, str(self.fake), str(marker)], timeout=4)
        self.assertEqual(result.returncode, 124)
        self.assertLess(time.monotonic() - began, 3)
        self.assert_child_gone(self.child_pid(marker))

    def test_stop_signal_kills_and_reaps_child(self):
        marker = self.root / "stop.pid"
        process = subprocess.Popen([str(self.binary), str(time.monotonic_ns() + 30_000_000_000), sys.executable, str(self.fake), str(marker)])
        pid = self.child_pid(marker)
        process.send_signal(signal.SIGTERM)
        self.assertEqual(process.wait(timeout=4), 143)
        self.assert_child_gone(pid)

    def test_owner_exit_kills_child(self):
        marker = self.root / "owner.pid"
        launcher = self.root / "launcher.py"
        launcher.write_text("import subprocess,sys,time\nfrom pathlib import Path\np=subprocess.Popen(sys.argv[1:])\nwhile not Path(sys.argv[-1]).exists(): time.sleep(0.01)\n")
        subprocess.run([sys.executable, str(launcher), str(self.binary), str(time.monotonic_ns() + 30_000_000_000), sys.executable, str(self.fake), str(marker)], timeout=4)
        self.assert_child_gone(self.child_pid(marker))

    def test_rejects_unbounded_lifetime(self):
        for lifetime in ["0", "-1", "nan", "inf", str(time.monotonic_ns() + 14_401_000_000_000), "1garbage"]:
            self.assertEqual(subprocess.run([str(self.binary), lifetime, "/bin/sleep", "1"]).returncode, 64)


if __name__ == "__main__":
    unittest.main()

"""Deterministic host regressions; no SSH listener or multiplexer is started."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import host as tool_host


class ToolHostTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='mcqa-host-test-', dir='/private/tmp')
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.tools = {}
        (self.base / 'bin').mkdir()
        for name in ['tmux', 'zellij', 'herdr']:
            path = self.base / 'bin' / name
            # These temporary executables only print a synthetic version.
            path.write_text('#!/bin/sh\nprintf "%s\\n" "synthetic-' + name + '"\n')
            path.chmod(0o700)
            self.tools[name] = path

    def make_host(self, tools=None):
        root = self.base / 'private-root'
        root.mkdir()
        listener = Mock()
        listener.getsockname.return_value = ('127.0.0.1', 12345)
        listener.accept.side_effect = OSError('synthetic listener is closed')
        with patch.object(tool_host.socket, 'socket', return_value=listener), \
                patch.object(tool_host.tempfile, 'mkdtemp', return_value=str(root)):
            return tool_host.ToolHost(self.base / 'output', tools or self.tools)

    def read_report(self, host):
        encoded = (host.output / 'tool-host-report.json').read_text()
        self.assertNotIn(host.token, encoded)
        return json.loads(encoded)

    def assert_all_tools_attempted(self, cleanup):
        self.assertEqual({Path(call.args[0][0]).name for call in cleanup.call_args_list}, set(self.tools))
        self.assertEqual(cleanup.call_count, 3)

    def exercise_stop_failure(self, error, expected_type):
        host = self.make_host()

        def stop(command, **kwargs):
            if Path(command[0]).name == 'herdr':
                raise error
            return subprocess.CompletedProcess(command, 0)

        with patch.object(tool_host.subprocess, 'run', side_effect=stop) as cleanup:
            with host:
                host.started.update(self.tools)
            self.assert_all_tools_attempted(cleanup)
        self.assertFalse(host.descriptor_path.exists())
        report = self.read_report(host)
        self.assertTrue(report['descriptorRetired'])
        self.assertEqual(report['cleanupExitCodes'], {'herdr': None, 'tmux': 0, 'zellij': 0})
        self.assertEqual(report['cleanupErrorTypes'], {'herdr': expected_type})

    def test_stop_timeout_attempts_other_tools_and_retires_descriptor(self):
        self.exercise_stop_failure(subprocess.TimeoutExpired(['synthetic-stop'], 10), 'TimeoutExpired')

    def test_stop_launch_error_attempts_other_tools_and_retires_descriptor(self):
        self.exercise_stop_failure(OSError('synthetic stop launch failure'), 'OSError')

    def test_client_retirement_error_still_cleans_sessions_and_writes_report(self):
        host = self.make_host()
        process = Mock()
        process.poll.return_value = None
        host.children.add(process)
        with patch.object(host, 'retire', side_effect=OSError('synthetic retirement failure')), \
                patch.object(tool_host.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as cleanup:
            with host:
                host.started.update(self.tools)
            self.assert_all_tools_attempted(cleanup)
        self.assertFalse(host.descriptor_path.exists())
        report = self.read_report(host)
        self.assertEqual(report['teardownErrorTypes'], ['OSError'])
        self.assertEqual(report['remainingClientProcesses'], 1)

    def test_descriptor_unlink_error_is_reported_without_hiding_report(self):
        host = self.make_host()
        unlink = Path.unlink

        def fail_descriptor(path, *args, **kwargs):
            if path == host.descriptor_path:
                raise OSError('synthetic descriptor unlink failure')
            return unlink(path, *args, **kwargs)

        with patch.object(Path, 'unlink', fail_descriptor):
            with host:
                pass
        report = self.read_report(host)
        self.assertFalse(report['descriptorRetired'])
        self.assertEqual(report['teardownErrorTypes'], ['OSError'])
        self.assertTrue(host.descriptor_path.exists())

    def test_relative_executables_resolve_before_private_working_directory(self):
        previous = Path.cwd()
        try:
            os.chdir(self.base)
            host = self.make_host({name: Path('bin') / name for name in self.tools})
        finally:
            os.chdir(previous)
        with host:
            for name, path in host.tools.items():
                self.assertTrue(path.is_absolute())
                self.assertEqual(path, self.tools[name])
                self.assertEqual(host.versions[name], 'synthetic-' + name)
                self.assertEqual(Path(host.argv(name)[0]), path)
                output = subprocess.check_output([host.argv(name)[0], '--version'], cwd=host.root, text=True).strip()
                self.assertEqual(output, 'synthetic-' + name)
            host.started.update(self.tools)
        report = self.read_report(host)
        self.assertEqual(report['cleanupExitCodes'], {'herdr': 0, 'tmux': 0, 'zellij': 0})
        self.assertEqual(report['cleanupErrorTypes'], {})


if __name__ == '__main__':
    unittest.main()

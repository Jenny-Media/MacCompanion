#!/usr/bin/env python3
"""Exercise cache reuse, exclusive leases, and preserved build evidence."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import shutil
import signal
import time
import uuid
import unittest
from unittest.mock import patch

import build_cache as cache
import legacy_build_cache as legacy


class CacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='maccompanion-cache-tests-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.checkout = self.base / 'checkout'
        self.checkout.mkdir()
        self.root = self.base / 'compiler'
        self.evidence = self.base / 'evidence'
        self.identity = {'kind': 'native-ios', 'sdk': 'iphonesimulator', 'arch': 'arm64', 'toolchain': {'xcode': 'synthetic'}}

    def session(self, evidence=None, identity=None, **kwargs):
        return cache.BuildSession(self.checkout, evidence or self.evidence, identity or self.identity,
                                  cache_root=self.root, timeout=0, **kwargs)

    def publish(self, session, content='first'):
        app = session.workspace / 'DerivedData/Build/Products/Debug/Fake.app'
        app.mkdir(parents=True, exist_ok=True)
        (app / 'Fake').write_text(content)
        cache.write_if_changed(session.workspace / 'project.json', '{"nativeSourcesOnly": true}')
        return session.publish({'binarySHA256': content, 'releaseAdmitted': False, 'installed': False}, app)

    def test_reuse_across_dated_evidence_and_immutable_app(self):
        with self.session() as first:
            report = self.publish(first)
            workspace = first.workspace
            saved = Path(report['app']) / 'Fake'
        with self.session(self.base / 'tomorrow-evidence') as second:
            self.assertEqual(second.workspace, workspace)
            newer = self.publish(second, 'second')
        self.assertEqual(saved.read_text(), 'first')
        self.assertEqual((Path(newer['app']) / 'Fake').read_text(), 'second')
        self.assertFalse(report['releaseAdmitted'])
        self.assertFalse(report['installed'])
        self.assertEqual(json.loads((self.evidence / 'build-report.json').read_text()), report)
        self.assertEqual((self.evidence / 'DerivedData/Build/Products/Debug/Fake.app/Fake').read_text(), 'first')

    def test_platform_toolchain_checkout_and_cold_isolation(self):
        with self.session() as first:
            original = first.workspace
        for field, value in [('sdk', 'iphoneos'), ('arch', 'x86_64'), ('kind', 'visionos-probe'), ('toolchain', {'xcode': 'other'})]:
            identity = dict(self.identity, **{field: value})
            with self.session(self.base / field, identity) as other:
                self.assertNotEqual(other.workspace, original)
        with self.session(self.base / 'cold', cold=True) as cold:
            self.assertNotEqual(cold.workspace, original)
        alternate_checkout = self.base / 'alternate'; alternate_checkout.mkdir()
        with cache.BuildSession(alternate_checkout, self.base / 'alternate-evidence', self.identity, cache_root=self.root) as other:
            self.assertNotEqual(other.workspace, original)

    def test_busy_workspace_blocks_independent_process_and_status(self):
        with self.session() as session:
            program = 'import sys; from pathlib import Path; sys.path.insert(0,sys.argv[1]); from build_cache import acquire_lock; acquire_lock(Path(sys.argv[2]),0)'
            result = subprocess.run([sys.executable, '-c', program, str(Path(cache.__file__).parent), str(session.workspace / '.build.lock')], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('workspace is busy', result.stderr)
            self.assertTrue(cache.cache_status(self.root)['workspaces'][0]['active'])
        with self.session() as later:
            self.assertEqual(later.workspace, session.workspace)

    def test_failure_logs_retained_and_latest_success_unchanged(self):
        with self.session() as session:
            report = self.publish(session)
        with self.assertRaisesRegex(RuntimeError, 'synthetic failure'):
            with self.session() as failed:
                (failed.workspace / 'build.log').write_text('diagnostic from failed build\n')
                raise RuntimeError('synthetic failure')
        self.assertEqual((failed.run / 'build.log').read_text(), 'diagnostic from failed build\n')
        self.assertEqual(json.loads((failed.run / 'run.json').read_text())['status'], 'failed')
        self.assertEqual(json.loads((self.evidence / 'build-report.json').read_text()), report)
        with self.assertRaisesRegex(ValueError, 'reused or failed'):
            with cache.compiler_workspace(self.evidence, self.checkout, timeout=0):
                self.fail('Failed compiler workspace must not authorize QA.')

    def test_qa_leases_current_workspace_and_rejects_old_report(self):
        with self.session() as first:
            report = self.publish(first)
        with cache.compiler_workspace(self.evidence, self.checkout, timeout=0) as workspace:
            self.assertEqual(workspace, first.workspace)
            with self.assertRaises(RuntimeError):
                with self.session(self.base / 'other'):
                    self.fail('QA must exclude another compiler invocation.')
        with self.session(self.base / 'other') as second:
            self.publish(second, 'second')
        with self.assertRaisesRegex(ValueError, 'reused or failed'):
            with cache.compiler_workspace(self.evidence, self.checkout, timeout=0):
                self.fail('Old reports cannot authorize a reused compiler workspace.')
        self.assertEqual((Path(report['app']) / 'Fake').read_text(), 'first')

    def test_legacy_consumer_remains_supported(self):
        legacy = self.base / 'legacy'; legacy.mkdir()
        with cache.compiler_workspace(legacy, self.checkout) as workspace:
            self.assertEqual(workspace, legacy)

    def test_consumer_also_locks_evidence_during_cold_publication(self):
        with self.session() as session:
            self.publish(session)
        with cache.acquire_lock(self.evidence / '.evidence.lock', 0):
            with self.assertRaises(RuntimeError):
                with cache.compiler_workspace(self.evidence, self.checkout, timeout=0):
                    self.fail('QA must not race latest aliases from a cold build.')
        with cache.compiler_workspace(self.evidence, self.checkout, timeout=0):
            pass

    def test_foreign_output_and_cache_are_preserved(self):
        self.evidence.mkdir(); original = self.evidence / 'project.json'; original.write_text('keep')
        with self.assertRaisesRegex(ValueError, 'Existing output is preserved'):
            with self.session():
                self.fail('Unmarked evidence cannot be adopted.')
        self.assertEqual(original.read_text(), 'keep')
        foreign = self.base / 'foreign-cache'; foreign.mkdir(); data = foreign / 'keep.txt'; data.write_text('keep')
        with self.assertRaisesRegex(ValueError, 'unmarked cache'):
            with cache.BuildSession(self.checkout, self.base / 'new-evidence', self.identity, cache_root=foreign):
                self.fail('Unmarked caches cannot be adopted.')
        self.assertEqual(data.read_text(), 'keep')

    def test_source_and_overlapping_roots_rejected_before_creation(self):
        inside = self.checkout / 'compiler'
        with self.assertRaisesRegex(ValueError, 'outside the checkout'):
            with cache.BuildSession(self.checkout, self.evidence, self.identity, cache_root=inside):
                self.fail('Cache inside source is forbidden.')
        self.assertFalse(inside.exists())
        with self.assertRaisesRegex(ValueError, 'separate'):
            with self.session(self.root / 'evidence'):
                self.fail('Cache and evidence must not overlap.')
        self.assertFalse(self.root.exists())

    def test_foreign_alias_rejected_before_any_latest_alias_changes(self):
        with self.session() as first:
            report = self.publish(first)
        previous = (self.evidence / 'build-report.json').resolve()
        (self.evidence / 'build.log').write_text('unowned data')
        with self.assertRaisesRegex(ValueError, 'Existing output is preserved'):
            with self.session() as second:
                (second.workspace / 'build.log').write_text('new log')
                self.publish(second, 'second')
        self.assertEqual((self.evidence / 'build.log').read_text(), 'unowned data')
        self.assertEqual((self.evidence / 'build-report.json').resolve(), previous)
        self.assertEqual((Path(report['app']) / 'Fake').read_text(), 'first')

    def test_external_bundle_link_rejected(self):
        outside = self.base / 'outside'; outside.write_text('keep')
        with self.assertRaisesRegex(ValueError, 'outside the bundle'):
            with self.session() as session:
                app = session.workspace / 'Fake.app'; app.mkdir()
                (app / 'link').symlink_to(outside)
                session.publish({}, app)
        self.assertEqual(outside.read_text(), 'keep')

    def test_content_aware_generated_inputs_and_cmake_source_migration(self):
        generated = self.base / 'project.json'
        cache.write_if_changed(generated, 'same')
        before = generated.stat().st_mtime_ns
        cache.write_if_changed(generated, 'same')
        self.assertEqual(generated.stat().st_mtime_ns, before)
        self.assertEqual(cache.cmake_refresh_args(self.base, self.checkout), [])
        (self.base / 'CMakeCache.txt').write_text('CMAKE_HOME_DIRECTORY:INTERNAL=' + str(self.checkout) + '\n')
        self.assertEqual(cache.cmake_refresh_args(self.base, self.checkout), [])
        self.assertEqual(cache.cmake_refresh_args(self.base, self.base / 'other-source'), ['--fresh'])

    def test_validation_cli_preserves_exit_status_log_and_reuses_scratch(self):
        scripts = self.checkout / 'scripts'; scripts.mkdir()
        runner = scripts / 'validate.sh'
        runner.write_text('set -eu\ntest "$MACCOMPANION_VALIDATION_MANAGED" = 1\necho "scratch=$MACCOMPANION_VALIDATION_SCRATCH_ROOT"\nexit "${SYNTHETIC_EXIT:-0}"\n')
        evidence = self.base / 'validation-evidence'
        argv = ['build_cache.py', 'validate', '--cache-root', str(self.root), '--evidence-root', str(evidence)]
        with patch.object(cache, 'ROOT', self.checkout), patch.object(cache, 'toolchain_identity', return_value={}), patch.object(sys, 'argv', argv):
            cache.main()
            cache.main()
            with patch.dict(os.environ, {'SYNTHETIC_EXIT': '7'}):
                with self.assertRaises(subprocess.CalledProcessError) as failure:
                    cache.main()
                self.assertEqual(failure.exception.returncode, 7)
        runs = list((evidence / 'runs').iterdir())
        self.assertEqual(len(runs), 3)
        self.assertEqual(len(list((self.root / 'workspaces').iterdir())), 1)
        self.assertEqual(len({(run / 'validation.log').read_text() for run in runs}), 1)
        self.assertEqual(sorted(json.loads((run / 'run.json').read_text())['status'] for run in runs), ['failed', 'passed', 'passed'])
        status = cache.cache_status(self.root, budget_gib=0, inactive_days=0)
        self.assertTrue(status['overBudget'])
        self.assertFalse(status['deletionEnabled'])
        self.assertTrue(status['workspaces'][0]['reviewCandidate'])


class LegacyCallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='maccompanion-legacy-tests-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.checkout = self.base / 'checkout'
        self.scripts = self.checkout / 'scripts'
        self.scripts.mkdir(parents=True)
        self.root = self.base / 'compiler'
        self.evidence = self.base / 'evidence'
        self.tools = self.base / 'tools'; self.tools.mkdir()
        shutil.copy2(Path(cache.__file__).parent / 'verify_pairing_reliability.sh', self.scripts)
        (self.scripts / 'validate_fixtures.py').write_text('print("synthetic fixture check")\n')
        fake = '''#!SHEBANG
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['FAKE_COMMANDS'], 'a') as log:
    log.write(json.dumps([name, args]) + '\\n')
if name == 'swift':
    scratch = pathlib.Path(args[args.index('--scratch-path') + 1])
    scratch.mkdir(parents=True, exist_ok=True)
    output = scratch / 'compiler-object'
    if not output.exists(): output.write_text('reused')
    if '--show-bin-path' in args:
        print(scratch / 'bin')
    else:
        print(os.environ.get('FAKE_SWIFT_OUTPUT', 'synthetic test passed'))
if name == 'xcodebuild':
    root = pathlib.Path(args[args.index('-derivedDataPath') + 1])
    scheme = args[args.index('-scheme') + 1]
    configuration = 'Debug-iphoneos' if scheme == 'MacCompanionIOS' else ('Debug-iphonesimulator' if scheme == 'ClientUIHarness' else 'Debug')
    app = root / 'Build/Products' / configuration / ('ClientUIHarness.app' if scheme == 'ClientUIHarness' else 'Mac Companion.app')
    app.mkdir(parents=True, exist_ok=True)
    (app / 'binary').write_text('saved-' + configuration)
    if '-resultBundlePath' in args: pathlib.Path(args[args.index('-resultBundlePath') + 1]).mkdir()
    print('synthetic xcodebuild passed')
'''.replace('SHEBANG', sys.executable)
        for name in ('swift', 'xcodebuild', 'codesign'):
            path = self.tools / name; path.write_text(fake); path.chmod(0o755)
        environment = {name: value for name, value in os.environ.items()
                       if not name.startswith('MACCOMPANION_') and name != 'DEVELOPER_DIR'}
        environment.update(PATH=str(self.tools) + os.pathsep + environment.get('PATH', ''),
                           MACCOMPANION_BUILD_CACHE_ROOT=str(self.root),
                           MACCOMPANION_LEGACY_EVIDENCE_ROOT=str(self.evidence),
                           MACCOMPANION_DEVELOPER_DIR='/Applications/Synthetic.app',
                           FAKE_COMMANDS=str(self.base / 'commands.jsonl'))
        for patcher in (patch.dict(os.environ, environment, clear=True),
                        patch.object(legacy, 'ROOT', self.checkout),
                        patch.object(legacy, 'DEFAULT_EVIDENCE', self.base / 'default-evidence'),
                        patch.object(legacy, 'toolchain_identity', return_value={'synthetic': True})):
            patcher.start(); self.addCleanup(patcher.stop)

    def runs(self, evidence=None):
        return sorted((evidence or self.evidence).glob('runs/*'))

    def metadata(self, run):
        return json.loads((run / 'run.json').read_text())

    def test_real_pairing_shell_reuses_scratch_and_retains_failure(self):
        legacy.run('pairing-reliability', [])
        first = self.runs()[0]
        workspace = Path(self.metadata(first)['workspace'])
        compiler = workspace / 'package-build/compiler-object'
        stamp = compiler.stat().st_mtime_ns
        legacy.run('pairing-reliability', [])
        self.assertEqual(len(self.runs()), 2)
        self.assertEqual(compiler.stat().st_mtime_ns, stamp)
        self.assertEqual(len(list((self.root / 'workspaces').iterdir())), 1)
        commands = [json.loads(line) for line in (self.base / 'commands.jsonl').read_text().splitlines()]
        self.assertEqual([name for name, _ in commands], ['swift'] * 10)
        with patch.dict(os.environ, FAKE_SWIFT_OUTPUT='✘ Test synthetic failure'):
            with self.assertRaises(subprocess.CalledProcessError):
                legacy.run('pairing-reliability', [])
        failed = next(run for run in self.runs() if self.metadata(run)['status'] == 'failed')
        self.assertIn('synthetic failure', (failed / 'workflow.log').read_text())
        self.assertEqual(self.metadata(first)['status'], 'passed')
        self.assertEqual(os.environ['DEVELOPER_DIR'], '/Applications/Synthetic.app/Contents/Developer')

    def test_signed_pairing_keys_and_snapshots_survive_compiler_removal(self):
        with patch.dict(os.environ, MACCOMPANION_DEVELOPMENT_TEAM='synthetic-team'):
            legacy.run('pairing-reliability', ['--signed-builds'])
        run = self.runs()[0]
        signed = Path(self.metadata(run)['workspace'])
        snapshots = json.loads((run / 'products.json').read_text())['apps']
        self.assertEqual(len(snapshots), 2)
        commands = [json.loads(line) for line in (self.base / 'commands.jsonl').read_text().splitlines()]
        self.assertEqual([name for name, _ in commands], ['swift'] * 5 + ['xcodebuild'] * 2 + ['codesign'] * 2)
        self.assertTrue(all('--scratch-path' in args for name, args in commands if name == 'swift'))
        self.assertTrue(all(args[args.index('-derivedDataPath') + 1].startswith(str(signed)) for name, args in commands if name == 'xcodebuild'))
        with patch.dict(os.environ, MACCOMPANION_LEGACY_EVIDENCE_ROOT=str(self.base / 'unsigned')):
            legacy.run('pairing-reliability', [])
        unsigned = self.metadata(self.runs(self.base / 'unsigned')[0])['workspace']
        self.assertNotEqual(str(signed), unsigned)
        # Only this test-owned fake compiler tree is disposable.
        shutil.rmtree(signed)
        self.assertTrue(all((Path(path) / 'binary').read_text().startswith('saved-') for path in snapshots))

    def test_profile_toolchain_flags_variant_team_and_cold_isolation(self):
        identities = [legacy.build_identity('pairing-reliability', [])]
        for name, value in [('SWIFTFLAGS', '-DTEST'), ('MACCOMPANION_LEGACY_CACHE_VARIANT', 'probe')]:
            with patch.dict(os.environ, {name: value}):
                identities.append(legacy.build_identity('pairing-reliability', []))
        with patch.dict(os.environ, MACCOMPANION_DEVELOPMENT_TEAM='team-one'):
            identities.append(legacy.build_identity('pairing-reliability', ['--signed-builds']))
        with patch.dict(os.environ, MACCOMPANION_DEVELOPMENT_TEAM='team-two'):
            identities.append(legacy.build_identity('pairing-reliability', ['--signed-builds']))
        with patch.object(legacy, 'toolchain_identity', return_value={'synthetic': 'other'}):
            identities.append(legacy.build_identity('pairing-reliability', []))
        identities.append(legacy.build_identity('simulator-features', []))
        self.assertEqual(len({json.dumps(i, sort_keys=True) for i in identities}), len(identities))
        legacy.run('pairing-reliability', [])
        with patch.dict(os.environ, MACCOMPANION_LEGACY_COLD='1'):
            legacy.run('pairing-reliability', [])
        self.assertEqual(len({self.metadata(run)['workspace'] for run in self.runs()}), 2)

    def test_old_overrides_and_arguments_fail_before_workflow(self):
        for name in ('MACCOMPANION_LAB_DERIVED_DATA', 'MACCOMPANION_PAIRING_DERIVED_DATA'):
            with patch.dict(os.environ, {name: str(self.base / 'old')}):
                with self.assertRaisesRegex(ValueError, 'no longer a compiler override'):
                    legacy.run('pairing-reliability', [])
        for caller, args in [('simulator-features', ['--signed-builds']), ('pairing-reliability', ['arbitrary'])]:
            with self.assertRaises(ValueError):
                legacy.run(caller, args)
        with self.assertRaisesRegex(ValueError, 'DEVELOPMENT_TEAM'):
            legacy.run('pairing-reliability', ['--signed-builds'])
        self.assertFalse(self.root.exists())

    def test_feature_output_remains_parseable_and_nested_pairing_gets_own_root(self):
        (self.scripts / 'verify_simulator_features.sh').write_text('exit 0\n')
        original = legacy.run_command
        def nested(command, env, log):
            if env['MACCOMPANION_LEGACY_MANAGED'] == 'simulator-features':
                self.assertNotIn('MACCOMPANION_LEGACY_EVIDENCE_ROOT', env)
                parent_workspace = Path(env['MACCOMPANION_LEGACY_WORKSPACE'])
                with self.assertRaises(RuntimeError):
                    cache.acquire_lock(parent_workspace / '.build.lock', 0)
                with patch.dict(os.environ, env, clear=True):
                    legacy.run('pairing-reliability', [])
                return 0
            return original(command, env, log)
        import io
        from contextlib import redirect_stdout
        output = io.StringIO()
        with patch.object(legacy, 'run_command', side_effect=nested), redirect_stdout(output):
            legacy.run('simulator-features', [])
        evidence_lines = [line.removeprefix('Evidence: ') for line in output.getvalue().splitlines() if line.startswith('Evidence: ')]
        self.assertEqual(evidence_lines, [str(self.runs()[0])])
        self.assertEqual(len(list((self.base / 'default-evidence').glob('legacy-*/runs/*'))), 1)
        self.assertEqual(len(list((self.root / 'workspaces').iterdir())), 2)

    def test_real_feature_shell_routes_host_and_simulator_builds_to_lease(self):
        shutil.copy2(Path(cache.__file__).parent / 'verify_simulator_features.sh', self.scripts)
        (self.scripts / 'validate_live_control_lab.py').write_text('print("synthetic isolation check")\n')
        (self.scripts / 'verify_pairing_reliability.sh').write_text('echo "synthetic pairing checkpoint"\n')
        (self.scripts / 'report_simulator_run.py').write_text(
            'import json, pathlib, sys\n'
            'run = pathlib.Path(sys.argv[1])\n'
            'assert (run / "features.xcresult").is_dir()\n'
            '(run / "report.json").write_text(json.dumps({"exitCode": int(sys.argv[4])}))\n')
        simulator = str(uuid.uuid4()).upper()
        xcrun = self.tools / 'xcrun'
        xcrun.write_text('#!' + sys.executable + '\nimport os, pathlib, sys\n'
                         'args = sys.argv[1:]\n'
                         'if args[:4] == ["simctl", "list", "devices", "booted"]: print(os.environ["MACCOMPANION_SIMULATOR_ID"])\n'
                         'if args[:2] == ["simctl", "get_app_container"]: print(os.environ["FAKE_CONTAINER"])\n')
        xcrun.chmod(0o755)
        # Precreate the synthetic Swift output under the same profile the wrapper selects.
        identity = legacy.build_identity('simulator-features', [])
        with cache.BuildSession(self.checkout, self.base / 'preparation', identity, cache_root=self.root, aliases=False) as prepared:
            binary = prepared.workspace / 'host-build/bin/maccompanion-test-host'
            binary.parent.mkdir(parents=True)
            binary.write_text('#!' + sys.executable + '\nimport json, pathlib, sys, time\n'
                              'pathlib.Path(sys.argv[1]).write_text(json.dumps({"source": "generated"}))\n'
                              'while True: time.sleep(.1)\n')
            binary.chmod(0o755)
        container = self.base / 'container'; container.mkdir()
        with patch.dict(os.environ, MACCOMPANION_SIMULATOR_ID=simulator, MACCOMPANION_LAB_SUITE='live', FAKE_CONTAINER=str(container)):
            legacy.run('simulator-features', [])
        run = self.runs()[0]
        workspace = Path(self.metadata(run)['workspace'])
        commands = [json.loads(line) for line in (self.base / 'commands.jsonl').read_text().splitlines()]
        self.assertEqual([name for name, _ in commands], ['swift', 'swift', 'xcodebuild', 'xcodebuild'])
        for name, args in commands:
            option = '--scratch-path' if name == 'swift' else '-derivedDataPath'
            self.assertTrue(args[args.index(option) + 1].startswith(str(workspace)))
        self.assertTrue((run / 'maccompanion-test-host').is_file())
        self.assertEqual(json.loads((run / 'report.json').read_text())['exitCode'], 0)
        self.assertFalse((container / 'Documents/lab-fixture.json').exists())
        self.assertFalse(Path('/private/tmp/maccompanion-simulator-' + simulator + '.lock').exists())
        snapshots = json.loads((run / 'products.json').read_text())['apps']
        self.assertEqual(len(snapshots), 1)

    def test_cancellation_keeps_lease_until_owned_worker_stops(self):
        worker = self.base / 'worker.py'
        worker.write_text('import pathlib, signal, sys, time\n'
                          'base = pathlib.Path(sys.argv[1])\n'
                          'def stop(sig, frame):\n'
                          ' time.sleep(.6)\n'
                          ' (base / "worker-stopped").write_text("stopped")\n'
                          ' raise SystemExit(0)\n'
                          'signal.signal(signal.SIGTERM, stop)\n'
                          '(base / "worker-ready").write_text("ready")\n'
                          'while True: time.sleep(.1)\n')
        (self.scripts / 'verify_simulator_features.sh').write_text('"' + sys.executable + '" "' + str(worker) + '" "' + str(self.base) + '"\n')
        program = ('import sys; from pathlib import Path; sys.path.insert(0, ' + repr(str(Path(cache.__file__).parent)) + ')\n'
                   'import legacy_build_cache as legacy\n'
                   'legacy.ROOT = Path(' + repr(str(self.checkout)) + ')\n'
                   'legacy.toolchain_identity = lambda sdks: {"synthetic": True}\n'
                   'legacy.run("simulator-features", [])\n')
        with (self.base / 'driver.log').open('w') as log:
            process = subprocess.Popen([sys.executable, '-c', program], stdout=log, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 10
                while not (self.base / 'worker-ready').exists():
                    if process.poll() is not None or time.monotonic() > deadline:
                        self.fail('Owned synthetic worker did not start; see ' + str(self.base / 'driver.log'))
                    time.sleep(.02)
                workspace = Path(self.metadata(self.runs()[0])['workspace'])
                process.send_signal(signal.SIGTERM)
                time.sleep(.15)
                self.assertFalse((self.base / 'worker-stopped').exists())
                with self.assertRaises(RuntimeError):
                    cache.acquire_lock(workspace / '.build.lock', 0)
                self.assertNotEqual(process.wait(timeout=15), 0)
                self.assertTrue((self.base / 'worker-stopped').exists())
                with cache.acquire_lock(workspace / '.build.lock', 0):
                    self.assertEqual(self.metadata(self.runs()[0])['status'], 'failed')
            finally:
                if process.poll() is None:
                    process.terminate(); process.wait(timeout=20)


if __name__ == '__main__':
    unittest.main(verbosity=2)

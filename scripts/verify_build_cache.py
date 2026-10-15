#!/usr/bin/env python3
"""Exercise cache reuse, exclusive leases, and preserved build evidence."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import build_cache as cache


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


if __name__ == '__main__':
    unittest.main(verbosity=2)

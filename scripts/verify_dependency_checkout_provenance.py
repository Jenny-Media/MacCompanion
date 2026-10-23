#!/usr/bin/env python3
"""Exercise package provenance using disposable Git trees, without real caches."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from dependency_checkout_provenance import CheckoutProvenanceError, verify_checkouts, verify_source_checkout


def git(repository, *arguments):
    return subprocess.check_output(
        ['git', '-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false',
         '-c', 'user.name=Provenance QA', '-c', 'user.email=qa@invalid.example',
         '-C', str(repository), *arguments], stderr=subprocess.PIPE).decode().strip()


class CheckoutProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='maccompanion-package-provenance-', dir='/private/tmp')
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        seed = root / 'seed'
        seed.mkdir()
        git(seed, 'init', '--quiet')
        (seed / 'Sources').mkdir()
        (seed / 'Sources/Probe.swift').write_text('public func probe() -> Int { 1 }\n')
        (seed / 'Package.swift').write_text('// Synthetic package source for Git provenance tests.\n')
        (seed / '.gitignore').write_text('Sources/Ignored.swift\n')
        git(seed, 'add', '.')
        git(seed, 'commit', '--quiet', '-m', 'Synthetic source')
        self.revision = git(seed, 'rev-parse', 'HEAD')
        self.packages = root / 'SourcePackages'
        (self.packages / 'repositories').mkdir(parents=True)
        (self.packages / 'checkouts').mkdir()
        self.cache = self.packages / 'repositories/probe-cache'
        self.checkout = self.packages / 'checkouts/Probe'
        git(root, 'clone', '--quiet', '--bare', str(seed), str(self.cache))
        self.url = 'https://github.com/example/provenance-probe.git'
        git(self.cache, 'remote', 'set-url', 'origin', self.url)
        git(root, 'clone', '--quiet', str(self.cache), str(self.checkout))
        self.source = self.checkout / 'Sources/Probe.swift'
        self.pins = [{'identity': 'probe', 'kind': 'remoteSourceControl', 'location': self.url,
                      'state': {'revision': self.revision}}]
        self.workspace = {'version': 7, 'object': {'dependencies': [{
            'packageRef': {'identity': 'probe', 'kind': 'remoteSourceControl', 'location': self.url},
            'state': {'name': 'sourceControlCheckout', 'checkoutState': {'revision': self.revision}},
            'subpath': 'Probe'}]}}
        self.write_workspace()

    def write_workspace(self):
        (self.packages / 'workspace-state.json').write_text(json.dumps(self.workspace))

    def verify(self, previous=None):
        return verify_checkouts(self.packages, self.pins, previous=previous)

    def test_clean_cache_reuse_records_actual_content(self):
        before = self.verify()
        self.assertEqual(self.verify(previous=before), before)
        self.assertEqual(before['probe']['revision'], self.revision)
        self.assertEqual(before['probe']['originURL'], self.url)
        self.assertEqual(before['probe']['trackedFileCount'], 3)
        files = {}
        for name in ['.gitignore', 'Package.swift', 'Sources/Probe.swift']:
            files[name] = {'mode': '100644', 'sha256': hashlib.sha256((self.checkout / name).read_bytes()).hexdigest()}
        encoded = json.dumps(files, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()
        self.assertEqual(before['probe']['sourceTreeSHA256'], hashlib.sha256(encoded).hexdigest())

    def test_dirty_tracked_source_is_rejected(self):
        self.source.write_text('public func probe() -> Int { 2 }\n')
        with self.assertRaisesRegex(CheckoutProvenanceError, 'tracked or untracked changes'):
            self.verify()

    def test_explicit_transform_records_actual_bytes_and_keeps_default_strict(self):
        before = self.source.read_bytes()
        after = before.replace(b'{ 1 }', b'{ 2 }')
        transforms = {'probe': {'Sources/Probe.swift': (before, after)}}
        original = self.verify()
        self.source.write_bytes(after)
        adapted = verify_checkouts(self.packages, self.pins, transforms=transforms)
        self.assertNotEqual(adapted['probe']['sourceTreeSHA256'], original['probe']['sourceTreeSHA256'])
        self.assertEqual(verify_checkouts(self.packages, self.pins, transforms=transforms, previous=adapted), adapted)
        with self.assertRaises(CheckoutProvenanceError):
            self.verify()
        git(self.checkout, 'update-index', '--assume-unchanged', 'Sources/Probe.swift')
        self.source.write_bytes(after + b'// unadmitted modification\n')
        with self.assertRaisesRegex(CheckoutProvenanceError, 'admitted transform'):
            verify_checkouts(self.packages, self.pins, transforms=transforms)

    def test_explicit_transform_does_not_admit_other_paths_or_an_invented_baseline(self):
        before = self.source.read_bytes()
        after = before.replace(b'{ 1 }', b'{ 2 }')
        transforms = {'probe': {'Sources/Probe.swift': (before, after)}}
        self.source.write_bytes(after)
        (self.checkout / 'Package.swift').write_text('// unadmitted package change\n')
        with self.assertRaisesRegex(CheckoutProvenanceError, 'tracked or untracked changes'):
            verify_checkouts(self.packages, self.pins, transforms=transforms)
        git(self.checkout, 'restore', 'Package.swift')
        transforms['probe']['Sources/Probe.swift'] = (b'invented source', after)
        with self.assertRaisesRegex(CheckoutProvenanceError, 'pinned Git tree'):
            verify_checkouts(self.packages, self.pins, transforms=transforms)

    def test_untracked_compiled_source_is_rejected(self):
        (self.checkout / 'Sources/Added.swift').write_text('public func added() {}\n')
        with self.assertRaisesRegex(CheckoutProvenanceError, 'tracked or untracked changes'):
            self.verify()

    def test_ignored_compiled_source_is_rejected(self):
        (self.checkout / 'Sources/Ignored.swift').write_text('public func ignored() {}\n')
        self.assertEqual(git(self.checkout, 'status', '--porcelain'), '')
        with self.assertRaisesRegex(CheckoutProvenanceError, 'unadmitted ignored files'):
            self.verify()

    def test_assume_unchanged_source_is_compared_with_git_blob(self):
        git(self.checkout, 'update-index', '--assume-unchanged', 'Sources/Probe.swift')
        self.source.write_text('public func probe() -> Int { 99 }\n')
        self.assertEqual(git(self.checkout, 'status', '--porcelain'), '')
        with self.assertRaisesRegex(CheckoutProvenanceError, 'differs from its pinned Git tree'):
            self.verify()

    def test_wrong_checkout_revision_is_rejected(self):
        git(self.checkout, 'commit', '--quiet', '--allow-empty', '-m', 'Different revision')
        with self.assertRaisesRegex(CheckoutProvenanceError, 'HEAD does not match'):
            self.verify()

    def test_wrong_workspace_revision_is_rejected(self):
        self.workspace['object']['dependencies'][0]['state']['checkoutState']['revision'] = '0' * 40
        self.write_workspace()
        with self.assertRaisesRegex(CheckoutProvenanceError, 'workspace revision does not match'):
            self.verify()

    def test_edited_workspace_cannot_claim_an_unused_pinned_checkout(self):
        self.workspace['object']['dependencies'][0]['state']['name'] = 'edited'
        self.write_workspace()
        with self.assertRaisesRegex(CheckoutProvenanceError, 'unedited source-control checkout'):
            self.verify()

    def test_wrong_source_origin_is_rejected(self):
        git(self.cache, 'remote', 'set-url', 'origin', 'https://github.com/example/other-source.git')
        with self.assertRaisesRegex(CheckoutProvenanceError, 'origin does not match'):
            self.verify()

    def test_cloud_transport_matches_pinned_source_without_recording_credentials(self):
        for origin in ['ssh://git@github.com/example/provenance-probe.git',
                       'git@github.com:example/provenance-probe.git',
                       'https://synthetic-user:synthetic-password@github.com/example/provenance-probe.git']:
            with self.subTest(origin=origin):
                git(self.cache, 'remote', 'set-url', 'origin', origin)
                with self.assertRaises(CheckoutProvenanceError):
                    self.verify()
                result = verify_checkouts(self.packages, self.pins, allow_cloud_transport=True)
                self.assertEqual(result['probe']['originURL'], self.url)
                self.assertNotIn('synthetic-password', json.dumps(result))

    def test_cloud_file_transport_is_limited_to_own_repository_cache(self):
        git(self.checkout, 'remote', 'set-url', 'origin', self.cache.as_uri())
        result = verify_checkouts(self.packages, self.pins, allow_cloud_transport=True)
        self.assertEqual(result['probe']['originURL'], self.url)
        git(self.checkout, 'remote', 'set-url', 'origin', self.checkout.as_uri())
        with self.assertRaisesRegex(CheckoutProvenanceError, 'outside its resolved repository cache'):
            verify_checkouts(self.packages, self.pins, allow_cloud_transport=True)

    def test_cloud_compares_origin_before_local_scm_proxy_url_rewriting(self):
        git(self.cache, 'config', 'url.http://127.0.0.1:8123/source/.insteadOf', 'https://github.com/')
        self.assertTrue(git(self.cache, 'remote', 'get-url', 'origin').startswith('http://127.0.0.1:8123/'))
        with self.assertRaises(CheckoutProvenanceError):
            self.verify()
        result = verify_checkouts(self.packages, self.pins, allow_cloud_transport=True)
        self.assertEqual(result['probe']['originURL'], self.url)

    def test_cloud_transport_still_rejects_other_sources_and_modified_bytes(self):
        for origin in ['ssh://git@github.com/example/other-source.git',
                       'ssh://git@github.example/example/provenance-probe.git',
                       'http://github.com/example/provenance-probe.git',
                       'https://github.com:8443/example/provenance-probe.git']:
            with self.subTest(origin=origin):
                git(self.cache, 'remote', 'set-url', 'origin', origin)
                with self.assertRaises(CheckoutProvenanceError):
                    verify_checkouts(self.packages, self.pins, allow_cloud_transport=True)
        git(self.cache, 'remote', 'set-url', 'origin', 'git@github.com:example/provenance-probe.git')
        self.source.write_text('public func probe() -> Int { 99 }\n')
        with self.assertRaises(CheckoutProvenanceError):
            verify_checkouts(self.packages, self.pins, allow_cloud_transport=True)

    def test_wrong_workspace_url_is_rejected(self):
        self.workspace['object']['dependencies'][0]['packageRef']['location'] = 'https://github.com/example/other-source.git'
        self.write_workspace()
        with self.assertRaisesRegex(CheckoutProvenanceError, 'Resolved source URL does not match'):
            self.verify()

    def test_missing_or_extra_resolved_identity_is_rejected(self):
        extra = copy.deepcopy(self.workspace['object']['dependencies'][0])
        extra['packageRef']['identity'] = 'unexpected'
        self.workspace['object']['dependencies'].append(extra)
        self.write_workspace()
        with self.assertRaisesRegex(CheckoutProvenanceError, 'complete lockfile'):
            self.verify()
        self.workspace['object']['dependencies'] = []
        self.write_workspace()
        with self.assertRaisesRegex(CheckoutProvenanceError, 'complete lockfile'):
            self.verify()

    def test_source_changed_during_build_is_rejected(self):
        before = self.verify()
        self.source.write_text('public func probe() -> Int { 3 }\n')
        with self.assertRaises(CheckoutProvenanceError):
            self.verify(previous=before)

    def test_changed_provenance_cannot_replace_prebuild_snapshot(self):
        before = self.verify()
        # Both URLs identify the same GitHub repository. The after-build record
        # must still retain the exact origin observed before compiling.
        git(self.cache, 'remote', 'set-url', 'origin', self.url.removesuffix('.git'))
        with self.assertRaisesRegex(CheckoutProvenanceError, 'changed during the build'):
            self.verify(previous=before)

    def test_external_source_checkout_records_the_same_actual_tree(self):
        before = verify_source_checkout(self.checkout, self.revision)
        remote = self.verify()['probe']
        self.assertEqual(before['sourceTreeSHA256'], remote['sourceTreeSHA256'])
        self.assertEqual(before['trackedFileCount'], remote['trackedFileCount'])
        self.assertEqual(verify_source_checkout(self.checkout, self.revision, previous=before), before)

    def test_external_source_rejects_hidden_index_changes(self):
        for flag in ['--assume-unchanged', '--skip-worktree']:
            with self.subTest(flag=flag):
                git(self.checkout, 'update-index', flag, 'Sources/Probe.swift')
                self.source.write_text('public func probe() -> Int { 99 }\n')
                self.assertEqual(git(self.checkout, 'status', '--porcelain'), '')
                with self.assertRaisesRegex(CheckoutProvenanceError, 'differs from its pinned Git tree'):
                    verify_source_checkout(self.checkout, self.revision)
                self.source.write_text('public func probe() -> Int { 1 }\n')
                git(self.checkout, 'update-index', '--no-assume-unchanged', '--no-skip-worktree', 'Sources/Probe.swift')

    def test_external_source_rejects_changed_modes_and_ignored_additions(self):
        git(self.checkout, 'config', 'core.filemode', 'false')
        self.source.chmod(0o755)
        self.assertEqual(git(self.checkout, 'status', '--porcelain'), '')
        with self.assertRaisesRegex(CheckoutProvenanceError, 'executable mode changed'):
            verify_source_checkout(self.checkout, self.revision)
        self.source.chmod(0o644)
        (self.checkout / 'Sources/Ignored.swift').write_text('public func ignored() {}\n')
        with self.assertRaisesRegex(CheckoutProvenanceError, 'unadmitted ignored files'):
            verify_source_checkout(self.checkout, self.revision)

    def test_external_source_rechecks_revision_and_postbuild_content(self):
        before = verify_source_checkout(self.checkout, self.revision)
        with self.assertRaisesRegex(CheckoutProvenanceError, 'HEAD does not match'):
            verify_source_checkout(self.checkout, '0' * 40)
        git(self.checkout, 'update-index', '--assume-unchanged', 'Sources/Probe.swift')
        self.source.write_text('public func probe() -> Int { 99 }\n')
        with self.assertRaisesRegex(CheckoutProvenanceError, 'differs from its pinned Git tree'):
            verify_source_checkout(self.checkout, self.revision, previous=before)

    def test_uninitialized_gitlink_cannot_hide_unverified_source(self):
        git(self.checkout, 'update-index', '--add', '--cacheinfo', '160000,' + self.revision + ',Documentation')
        git(self.checkout, 'commit', '--quiet', '-m', 'Synthetic documentation submodule')
        revision = git(self.checkout, 'rev-parse', 'HEAD')
        docs = self.checkout / 'Documentation'
        docs.mkdir()
        before = verify_source_checkout(self.checkout, revision)
        self.assertEqual(before['trackedFileCount'], 4)
        (docs / 'Unadmitted.swift').write_text('public func unadmitted() {}\n')
        with self.assertRaises(CheckoutProvenanceError):
            verify_source_checkout(self.checkout, revision, previous=before)

    def test_initialized_gitlink_verifies_its_actual_pinned_source(self):
        git(self.checkout, 'update-index', '--add', '--cacheinfo', '160000,' + self.revision + ',Documentation')
        git(self.checkout, 'commit', '--quiet', '-m', 'Synthetic documentation submodule')
        revision = git(self.checkout, 'rev-parse', 'HEAD')
        docs = self.checkout / 'Documentation'
        git(self.checkout, 'clone', '--quiet', str(self.cache), str(docs))
        before = verify_source_checkout(self.checkout, revision)
        git(docs, 'update-index', '--assume-unchanged', 'Sources/Probe.swift')
        (docs / 'Sources/Probe.swift').write_text('public func probe() -> Int { 99 }\n')
        with self.assertRaisesRegex(CheckoutProvenanceError, 'differs from its pinned Git tree'):
            verify_source_checkout(self.checkout, revision, previous=before)


if __name__ == '__main__':
    unittest.main()

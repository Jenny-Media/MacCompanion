#!/usr/bin/env python3
"""Check the persistent cloud project's release boundaries and dependency pins."""
import json
import hashlib
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

from build_cloud_ios_dependencies import download_source, openssl
from verify_direct_client_dependencies import validate_cloud

ROOT = Path(__file__).resolve().parents[1]
CLOUD = ROOT / 'Native/iOSCloud'


class CloudProjectTests(unittest.TestCase):
    def test_normal_direct_sources_and_synced_membership(self):
        spec = json.loads((CLOUD / 'project.json').read_text())
        app = spec['targets']['MacCompanionIOS']
        folders = {v['path'] for v in app['sources'] if v.get('type') == 'syncedFolder'}
        self.assertEqual(folders, {'../../Apps/MacCompanionIOS', '../../Native/SessionActivity',
                                  '../../Native/Terminal', '../../Native/VNC'})
        pbx = (CLOUD / 'MacCompanionCloud.xcodeproj/project.pbxproj').read_text()
        self.assertIn('PBXFileSystemSynchronizedRootGroup', pbx)
        for excluded in ['CompanionVNCTransport.h', 'CompanionVNCTransport.m', '"source-lock.json"']:
            self.assertIn(excluded, pbx)
        for value in [pbx, json.dumps(spec)]:
            for forbidden in ['Experiments/', '/Users/', '/private/tmp/', 'PROVISIONING_PROFILE_SPECIFIER']:
                self.assertNotIn(forbidden, value)

    def test_release_signing_and_entry_point(self):
        spec = json.loads((CLOUD / 'project.json').read_text())
        for name, target in spec['targets'].items():
            settings = target['settings']['base']
            self.assertEqual(settings['CODE_SIGN_STYLE'], 'Automatic')
            self.assertEqual(settings['DEVELOPMENT_TEAM'], '$(MACCOMPANION_DEVELOPMENT_TEAM)')
            self.assertEqual(settings['MARKETING_VERSION'], '1.0')
            self.assertEqual(settings['CODE_SIGN_IDENTITY'], '$(inherited)')
            entitlements = plistlib.loads((CLOUD / (name + '.entitlements')).read_bytes())
            self.assertEqual(entitlements, {'keychain-access-groups':
                                           ['$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)']})
        app = spec['targets']['MacCompanionIOS']
        self.assertEqual(app['settings']['base']['SWIFT_ACTIVE_COMPILATION_CONDITIONS'],
                         '$(inherited) MACCOMPANION_VNC_DEVELOPMENT')
        self.assertNotIn('DEBUG', json.dumps(app['settings']['configs']['Release']))
        self.assertEqual(spec['schemes']['MacCompanionIOS']['archive']['config'], 'Release')
        info = plistlib.loads((CLOUD / 'DirectScreenSharing-Info.plist').read_bytes())
        self.assertIs(info['ITSAppUsesNonExemptEncryption'], False)
        self.assertTrue(info['NSSupportsLiveActivities'])

    def test_packages_match_normal_pins(self):
        lock = CLOUD / 'MacCompanionCloud.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
        actual = {p['identity']: p for p in json.loads(lock.read_text())['pins']}
        expected = {p['identity']: p for p in json.loads((ROOT / 'Native/Terminal/Package.resolved').read_text())['pins']}
        # Xcode can omit the unused historical ColorizeSwift pin on iOS.
        self.assertLessEqual(set(expected) - set(actual), {'colorizeswift'})
        self.assertEqual(actual, {k: expected[k] for k in actual})
        spec = json.loads((CLOUD / 'project.json').read_text())
        terminal = json.loads((ROOT / 'Native/Terminal/source-lock.json').read_text())
        self.assertEqual(spec['packages']['SwiftTerm']['revision'], terminal['SwiftTerm']['revision'])
        self.assertEqual(spec['packages']['Citadel']['path'], '../../Native/Dependencies/Citadel')

    def test_modified_openssl_archive_rejected_before_compilation(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            lock = json.loads((ROOT / 'Native/VNC/source-lock.json').read_text())
            (path / ('openssl-' + lock['opensslVersion'] + '.tar.gz')).write_bytes(b'not the pinned source')
            with self.assertRaisesRegex(ValueError, 'differs from the production source lock'):
                openssl(path)

    def test_cloud_authority_rejects_project_and_package_drift(self):
        policy = json.loads((ROOT / 'spec/dependency-policy/v0/direct-client-development.json').read_text())['xcodeCloud']
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            paths = [*policy['projectFiles'], policy['resolvedLockfilePath'], 'Native/Terminal/Package.resolved']
            for relative in paths:
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)
            validate_cloud(policy, root)
            project = root / 'Native/iOSCloud/MacCompanionCloud.xcodeproj/project.pbxproj'
            original = project.read_bytes()
            project.write_bytes(original + b'\n// unapproved project change\n')
            with self.assertRaises(AssertionError):
                validate_cloud(policy, root)

            project.write_bytes(original)
            lock = root / policy['resolvedLockfilePath']
            original = lock.read_bytes()
            value = json.loads(original)
            value['pins'][0]['state']['revision'] = '0' * 40
            lock.write_text(json.dumps(value))
            with self.assertRaises(AssertionError):
                validate_cloud(policy, root)
            value = json.loads(original)
            value['pins'] = [p for p in value['pins'] if p['identity'] != 'swiftterm']
            lock.write_text(json.dumps(value))
            with self.assertRaises(AssertionError):
                validate_cloud(policy, root)

    def test_incomplete_download_retries_without_promoting_partial_content(self):
        payload = b'complete source archive'
        artifact = {'url': 'https://example.invalid/pinned-source', 'sha256': hashlib.sha256(payload).hexdigest()}
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / 'source.tar.gz'
            attempts = []
            def download(url, destination):
                self.assertFalse(archive.exists())
                attempts.append(destination)
                destination.write_bytes(payload[:3] if len(attempts) < 3 else payload)
                if len(attempts) < 3:
                    raise urllib.error.ContentTooShortError('incomplete response', None)
            with patch('build_cloud_ios_dependencies.time.sleep'):
                download_source(artifact, archive, download)
            self.assertEqual(archive.read_bytes(), payload)
            self.assertEqual(len(set(attempts)), 3)
            self.assertTrue(all(p.read_bytes() == payload[:3] for p in attempts[:2]))

    def test_complete_download_with_wrong_hash_is_not_promoted(self):
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / 'source.tar.gz'
            def download(url, destination):
                destination.write_bytes(b'unapproved source')
            with self.assertRaisesRegex(ValueError, 'does not match'):
                download_source({'url': 'https://example.invalid/source', 'sha256': '0' * 64}, archive, download)
            self.assertFalse(archive.exists())


if __name__ == '__main__':
    unittest.main()

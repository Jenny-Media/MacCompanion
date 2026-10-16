#!/usr/bin/env python3
"""Check visible app names without migrating signing, storage or module identities."""
from copy import deepcopy
from pathlib import Path
import plistlib
import tempfile
from types import SimpleNamespace
import unittest

import direct_app_naming as naming
from build_direct_visionos import configure_client


class DirectAppNamingTests(unittest.TestCase):
    def test_naming_preserves_security_and_storage_settings(self):
        for platform, bundle in [
            ('ios', 'media.jenny.maccompanion.ios'),
            ('macos', 'media.jenny.maccompanion'),
            ('macos', 'media.jenny.maccompanion.ios'),  # Distribution override.
            ('visionos', 'dev.maccompanion.visionos.client'),
            ('visionos', 'media.jenny.maccompanion.ios'),
        ]:
            with self.subTest(platform=platform, bundle=bundle):
                settings = {'PRODUCT_BUNDLE_IDENTIFIER': bundle,
                            'CODE_SIGN_ENTITLEMENTS': '/existing/App.entitlements',
                            'DEVELOPMENT_TEAM': 'existing-team',
                            'PROVISIONING_PROFILE_SPECIFIER': 'existing-profile',
                            'PRODUCT_NAME': 'old name'}
                metadata = {'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)',
                            'CFBundleExecutable': '$(EXECUTABLE_NAME)',
                            'MacCompanionSharedKeychainGroup': 'existing-team.media.jenny.maccompanion.ios',
                            'CFBundleURLTypes': [{'CFBundleURLSchemes': ['maccompanion-session']}],
                            'ITSAppUsesNonExemptEncryption': False}
                original_settings, original_metadata = deepcopy(settings), deepcopy(metadata)
                naming.configure(settings, metadata, platform)
                self.assertEqual(settings['PRODUCT_NAME'], 'Mac Companion')
                self.assertEqual(metadata['CFBundleName'], 'Mac Companion')
                self.assertEqual(metadata['CFBundleDisplayName'], 'Mac Companion')
                for key in ['PRODUCT_NAME', 'EXECUTABLE_NAME', 'PRODUCT_MODULE_NAME']:
                    settings.pop(key)
                    original_settings.pop(key, None)
                for key in ['CFBundleName', 'CFBundleDisplayName']:
                    metadata.pop(key)
                self.assertEqual(settings, original_settings)
                self.assertEqual(metadata, original_metadata)

    def test_executable_and_module_names_keep_existing_test_imports_valid(self):
        for platform, executable, module, host in [
            ('ios', 'Mac Companion', 'Mac_Companion',
             '$(BUILT_PRODUCTS_DIR)/Mac Companion.app/Mac Companion'),
            ('macos', 'MacCompanion', 'MacCompanion',
             '$(BUILT_PRODUCTS_DIR)/Mac Companion.app/Contents/MacOS/MacCompanion'),
            ('visionos', 'MacCompanionVision', 'MacCompanionVision',
             '$(BUILT_PRODUCTS_DIR)/Mac Companion.app/MacCompanionVision'),
        ]:
            with self.subTest(platform=platform):
                settings = {}
                naming.configure(settings, {}, platform)
                self.assertEqual(settings['EXECUTABLE_NAME'], executable)
                self.assertEqual(settings['PRODUCT_MODULE_NAME'], module)
                self.assertEqual(naming.test_host(platform), host)

    def test_visionos_generated_hosted_tests_use_renamed_wrapper(self):
        target = {'settings': {'base': {
            'PRODUCT_BUNDLE_IDENTIFIER': 'dev.maccompanion.visionos.client',
            'HEADER_SEARCH_PATHS': ['/existing/headers']}},
            'info': {'properties': {}}, 'sources': []}
        spec = {'targets': {'MacCompanionVision': target},
                'schemes': {'MacCompanionVision': {}}}
        configure_client(spec, 'MacCompanionVision', SimpleNamespace(sdk='xrsimulator'))
        self.assertEqual(target['settings']['base']['PRODUCT_BUNDLE_IDENTIFIER'],
                         'dev.maccompanion.visionos.client')
        self.assertEqual(target['settings']['base']['PRODUCT_MODULE_NAME'], 'MacCompanionVision')
        tests = spec['targets']['VisionClientTests']['settings']['base']
        self.assertEqual(tests['TEST_HOST'],
                         '$(BUILT_PRODUCTS_DIR)/Mac Companion.app/MacCompanionVision')
        self.assertEqual(tests['BUNDLE_LOADER'], '$(TEST_HOST)')

    def artifact(self, directory, platform, wrapper='Mac Companion.app'):
        app = Path(directory) / wrapper
        contents = app / 'Contents' if platform == 'macos' else app
        contents.mkdir(parents=True)
        executable = {'ios': 'Mac Companion', 'macos': 'MacCompanion',
                      'visionos': 'MacCompanionVision'}[platform]
        metadata = {'CFBundleName': 'Mac Companion', 'CFBundleDisplayName': 'Mac Companion',
                    'CFBundleExecutable': executable}
        (contents / 'Info.plist').write_bytes(plistlib.dumps(metadata))
        binary = contents / 'MacOS' / executable if platform == 'macos' else contents / executable
        binary.parent.mkdir(parents=True, exist_ok=True)
        binary.write_bytes(b'synthetic executable')
        return app, contents / 'Info.plist', binary

    def test_finished_bundles_keep_distinct_executable_paths(self):
        for platform in ['ios', 'macos', 'visionos']:
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as directory:
                app, _, _ = self.artifact(directory, platform)
                self.assertEqual(naming.verify(app, platform)['CFBundleDisplayName'], 'Mac Companion')

    def test_rejects_partial_renames_and_changed_executable(self):
        for platform in ['ios', 'macos', 'visionos']:
            for key in ['CFBundleName', 'CFBundleDisplayName', 'CFBundleExecutable']:
                with self.subTest(platform=platform, key=key), tempfile.TemporaryDirectory() as directory:
                    app, info, _ = self.artifact(directory, platform)
                    metadata = plistlib.loads(info.read_bytes())
                    metadata[key] = 'Incorrect name'
                    info.write_bytes(plistlib.dumps(metadata))
                    with self.assertRaises(ValueError):
                        naming.verify(app, platform)

    def test_rejects_old_wrapper_names(self):
        for platform, wrapper in [('macos', 'MacCompanion.app'),
                                  ('visionos', 'MacCompanionVision.app')]:
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as directory:
                app, _, _ = self.artifact(directory, platform, wrapper)
                with self.assertRaisesRegex(ValueError, 'bundle must be named'):
                    naming.verify(app, platform)

    def test_rejects_missing_executable(self):
        with tempfile.TemporaryDirectory() as directory:
            app, _, binary = self.artifact(directory, 'macos')
            binary.unlink()
            with self.assertRaisesRegex(ValueError, 'executable is missing'):
                naming.verify(app, 'macos')


if __name__ == '__main__':
    unittest.main()

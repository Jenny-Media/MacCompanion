"""Synthetic source-admission regressions; no compiler caches or user data."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location(
    'workspace_prototype_build', ROOT / 'Experiments/MacWorkspacePrototype/build.py')
prototype = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prototype)
from build_direct_macos import source_inputs


class BuildAdmissionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='maccompanion-prototype-admission-', dir='/private/tmp')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        # Preserve only the path layout. Every file has synthetic contents.
        for relative in source_inputs():
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(('synthetic:' + relative).encode())
        self.expected = source_inputs(self.root)
        self.patched = patch.object(prototype, 'native_source_inputs', lambda: source_inputs(self.root))
        self.patched.start()
        self.addCleanup(self.patched.stop)

    def test_unchanged_complete_native_manifest_is_admitted(self):
        prototype.verify_inputs(self.expected)

    def test_new_mac_swift_source_invalidates_the_baseline(self):
        (self.root / 'Native/Mac/NewCompiledSource.swift').write_text('synthetic')
        with self.assertRaisesRegex(RuntimeError, 'complete current source set'):
            prototype.verify_inputs(self.expected)

    def test_new_files_swift_source_invalidates_the_baseline(self):
        (self.root / 'Native/Terminal/Files/NewCompiledSource.swift').write_text('synthetic')
        with self.assertRaises(RuntimeError):
            prototype.verify_inputs(self.expected)

    def test_changed_native_source_invalidates_the_baseline(self):
        (self.root / 'Native/Mac/MacFilesWindow.swift').write_text('changed synthetic bytes')
        with self.assertRaises(RuntimeError):
            prototype.verify_inputs(self.expected)

    def test_removed_directory_source_invalidates_the_baseline(self):
        (self.root / 'Native/Mac/MacFilesWindow.swift').unlink()
        with self.assertRaises(RuntimeError):
            prototype.verify_inputs(self.expected)

    def test_source_added_after_initial_admission_is_rejected(self):
        prototype.verify_inputs(self.expected)
        (self.root / 'Native/Terminal/Files/AddedDuringBuild.swift').write_text('synthetic')
        with self.assertRaises(RuntimeError):
            prototype.verify_inputs(self.expected)

    def test_missing_required_builder_is_rejected(self):
        (self.root / 'scripts/build_direct_macos.py').unlink()
        with self.assertRaises(FileNotFoundError):
            prototype.verify_inputs(self.expected)

    def test_unrelated_file_does_not_change_native_admission(self):
        (self.root / 'unrelated-not-compiled.txt').write_text('synthetic')
        prototype.verify_inputs(self.expected)


if __name__ == '__main__':
    unittest.main()

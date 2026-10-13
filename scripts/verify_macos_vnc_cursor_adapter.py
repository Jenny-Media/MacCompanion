#!/usr/bin/env python3
"""Check macOS adapter admission and cache reuse against a supplied pinned checkout."""
import argparse
import copy
import json
from pathlib import Path
import tempfile
import unittest

from prepare_macos_vnc_cursor import ROOT, adapted_cursor, prepare, verify


class CursorAdapterTests(unittest.TestCase):
    def setUp(self):
        self.lock = json.loads((ROOT / 'Native/VNC/source-lock.json').read_text())
        temporary = tempfile.TemporaryDirectory(prefix='maccompanion-cursor-admission-', dir='/private/tmp')
        self.addCleanup(temporary.cleanup)
        self.output = Path(temporary.name)

    def test_exact_patch_and_reuse_preserve_original(self):
        original = (self.source / self.lock['macOSCursorCallback']['path']).read_bytes()
        directory, expected, before = prepare(self.source, self.output, self.lock)
        self.assertEqual(prepare(self.source, self.output, self.lock), (directory, expected, before))
        self.assertEqual(verify(directory, expected), before)
        self.assertEqual((self.source / self.lock['macOSCursorCallback']['path']).read_bytes(), original)
        self.assertEqual((directory / self.lock['macOSCursorCallback']['path']).read_bytes(),
                         adapted_cursor(original, self.lock['macOSCursorCallback']))

    def test_unadmitted_transform_is_rejected(self):
        policy = self.lock['macOSCursorCallback']
        original = (self.source / policy['path']).read_bytes()
        with self.assertRaises(ValueError):
            adapted_cursor(original + b'\n', policy)
        for field in ['originalSHA256', 'adaptedSHA256', 'patchSHA256', 'path', 'patchPath']:
            changed = copy.deepcopy(policy); changed[field] = 'unadmitted'
            with self.assertRaises(ValueError):
                adapted_cursor(original, changed)

    def test_modified_reused_source_is_rejected(self):
        directory, _, _ = prepare(self.source, self.output, self.lock)
        path = directory / self.lock['macOSCursorCallback']['path']
        path.write_bytes(path.read_bytes() + b'\n')
        with self.assertRaises(ValueError):
            prepare(self.source, self.output, self.lock)

    def test_extra_file_mode_and_link_are_rejected(self):
        directory, expected, _ = prepare(self.source, self.output, self.lock)
        extra = directory / 'unadmitted.c'; extra.write_text('unadmitted')
        with self.assertRaises(ValueError):
            verify(directory, expected)
        extra.unlink()
        path = directory / self.lock['macOSCursorCallback']['path']; path.chmod(0o755)
        with self.assertRaises(ValueError):
            verify(directory, expected)
        path.chmod(0o644)
        extra.symlink_to(path)
        with self.assertRaises(ValueError):
            verify(directory, expected)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    CursorAdapterTests.source = parser.parse_args().source.resolve(strict=True)
    unittest.main(argv=['verify_macos_vnc_cursor_adapter'])

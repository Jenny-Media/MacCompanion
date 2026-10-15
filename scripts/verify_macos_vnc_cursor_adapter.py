#!/usr/bin/env python3
"""Check shared cursor admission and iOS CMake cache migration/reuse against a pinned checkout."""
import argparse
import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from prepare_macos_vnc_cursor import ROOT, adapted_cursor, prepare, verify
from build_vnc_ios_development import cmake_source_options


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


class IOSCursorBuildCacheTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='maccompanion-cursor-cmake-', dir='/private/tmp')
        self.addCleanup(temporary.cleanup)
        self.output = Path(temporary.name)
        self.build = self.output / 'build'

    def source(self, name):
        directory = self.output / name
        directory.mkdir()
        (directory / 'CMakeLists.txt').write_text(
            'cmake_minimum_required(VERSION 3.24)\nproject(CursorCacheProbe NONE)\n')
        return directory

    def configure(self, source, *definitions):
        subprocess.run(['/opt/homebrew/bin/cmake', *cmake_source_options(self.build, source),
                        '-S', str(source), '-B', str(self.build), *definitions],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    def test_ios_migrates_pristine_source_cache(self):
        pristine = self.source('pristine')
        adapted = self.source('adapted source')
        self.assertEqual(cmake_source_options(self.build, pristine), [])
        self.configure(pristine, '-DMC_OLD_SOURCE_MARKER:STRING=old')
        sentinel = self.build / 'preserved-output.txt'
        sentinel.write_text('preserved')
        self.assertEqual(cmake_source_options(self.build, adapted), ['--fresh'])
        self.configure(adapted)
        cache = (self.build / 'CMakeCache.txt').read_text().splitlines()
        self.assertIn('CMAKE_HOME_DIRECTORY:INTERNAL=' + str(adapted.resolve()), cache)
        self.assertNotIn('MC_OLD_SOURCE_MARKER:STRING=old', cache)
        self.assertEqual(sentinel.read_text(), 'preserved')

    def test_ios_reuses_unchanged_source_cache(self):
        source = self.source('adapted')
        self.configure(source, '-DMC_REUSE_MARKER:STRING=keep')
        sentinel = self.build / 'CMakeFiles' / 'retained-probe.txt'
        sentinel.write_text('retained')
        self.assertEqual(cmake_source_options(self.build, source), [])
        self.configure(source)
        self.assertIn('MC_REUSE_MARKER:STRING=keep',
                      (self.build / 'CMakeCache.txt').read_text().splitlines())
        self.assertEqual(sentinel.read_text(), 'retained')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    CursorAdapterTests.source = parser.parse_args().source.resolve(strict=True)
    unittest.main(argv=['verify_macos_vnc_cursor_adapter'])

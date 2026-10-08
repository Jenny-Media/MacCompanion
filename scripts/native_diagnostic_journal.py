#!/usr/bin/env python3
"""Retain a bounded content-free runtime log through atomic size rotation.

This is test evidence collection only. It does not modify the application log,
grant authority, or infer successful transitions from missing records.
"""
import os
from pathlib import Path
import stat
import sys
import tempfile
import threading
import unittest


class NativeDiagnosticJournal:
    def __init__(self, source, output, maximum_bytes=8 * 1024 * 1024, resolve_source=None):
        self.source, self.output = Path(source), Path(output)
        self.maximum_bytes = maximum_bytes
        self.reader = None
        self.identity = None
        self.bytes = 0
        self.rotations = 0
        self.relocations = 0
        self.resolve_source = resolve_source
        self.failure = None
        self.stop_event = threading.Event()
        self.thread = None
        fd = os.open(self.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        self.writer = os.fdopen(fd, 'wb', buffering=0)

    def _named(self):
        try:
            return self.source.lstat()
        except FileNotFoundError:
            # XCTest may move the whole app data container during install. A
            # held descriptor follows that move until the app rotates its log;
            # the cached path then cannot locate the replacement inode.
            if self.resolve_source is None or self.source.parent.is_dir():
                return None
            replacement = Path(self.resolve_source())
            if not replacement.is_absolute() or replacement == self.output:
                raise ValueError('Invalid relocated diagnostic source')
            if replacement == self.source:
                return None
            self.source = replacement
            self.relocations += 1
            try:
                return self.source.lstat()
            except FileNotFoundError:
                return None

    def _open(self):
        if self._named() is None:
            return False
        try:
            fd = os.open(self.source, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        except FileNotFoundError:
            return False
        facts = os.fstat(fd)
        if not stat.S_ISREG(facts.st_mode) or facts.st_size > self.maximum_bytes:
            os.close(fd)
            raise ValueError('Expected a bounded regular runtime diagnostic log')
        self.reader = os.fdopen(fd, 'rb', buffering=0)
        self.identity = facts.st_dev, facts.st_ino
        return True

    def _drain(self):
        if os.fstat(self.reader.fileno()).st_size < self.reader.tell():
            raise ValueError('Diagnostic log shrank without atomic replacement')
        while True:
            data = self.reader.read(65536)
            if not data:
                return
            if self.bytes + len(data) > self.maximum_bytes:
                raise ValueError('Diagnostic journal exceeded its evidence budget')
            self.writer.write(data)
            self.bytes += len(data)

    def poll(self):
        # Hold the old descriptor across rename. Its unread tail still exists
        # after unlink, unlike a path snapshot that loses pre-rotation records.
        while self.reader is not None or self._open():
            self._drain()
            named = self._named()
            if named is None:
                return
            if not stat.S_ISREG(named.st_mode):
                raise ValueError('Runtime diagnostic path became unsafe')
            if (named.st_dev, named.st_ino) == self.identity:
                return
            self._drain()
            self.reader.close()
            self.reader = None
            self.rotations += 1

    def start(self):
        if self.thread is not None:
            raise RuntimeError('Diagnostic journal already started')
        # Capture any existing inode before starting the UI journey.
        self.poll()
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def _run(self):
        try:
            while not self.stop_event.wait(.05):
                self.poll()
        except Exception as error:
            self.failure = error
            print('Diagnostic journal collection failed: ' + type(error).__name__,
                  file=sys.stderr, flush=True)

    def finish(self):
        self.stop_event.set()
        if self.thread is not None:
            self.thread.join(timeout=5)
            if self.thread.is_alive():
                raise RuntimeError('Diagnostic journal did not stop')
        try:
            if self.failure is not None:
                raise self.failure
            self.poll()
            named = self._named()
            if self.reader is None or named is None:
                raise ValueError('Runtime diagnostic source missing at completion')
            if (named.st_dev, named.st_ino) != self.identity:
                raise ValueError('Runtime diagnostic source changed at completion')
            return {'profile': 'maccompanion.content-free-diagnostic-journal.v1',
                    'atomicRotationsDrained': self.rotations,
                    'applicationContainerRelocations': self.relocations,
                    'bytes': self.bytes, 'readOnlyApplicationLog': True,
                    'complete': True}
        finally:
            if self.reader is not None:
                self.reader.close()
                self.reader = None
            self.writer.close()


class JournalTests(unittest.TestCase):
    def test_container_relocation_then_rotation_preserves_every_record(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original, current = root / 'original-container', root / 'current-container'
            original.mkdir()
            source, output = original / 'runtime.log', root / 'journal.log'
            source.write_bytes(b'before relocation\n')
            journal = NativeDiagnosticJournal(source, output,
                resolve_source=lambda: current / 'runtime.log')
            journal.poll()
            original.rename(current)
            moved_source = current / 'runtime.log'
            with moved_source.open('ab') as file:
                file.write(b'after relocation\n')
            journal.poll()
            with moved_source.open('ab') as file:
                file.write(b'unread old tail\n')
            replacement = current / 'replacement'
            replacement.write_bytes(b'after rotation\n')
            replacement.replace(moved_source)
            facts = journal.finish()
            self.assertEqual(output.read_bytes(),
                b'before relocation\nafter relocation\nunread old tail\nafter rotation\n')
            self.assertEqual(facts['applicationContainerRelocations'], 1)
            self.assertEqual(facts['atomicRotationsDrained'], 1)

    def test_missing_or_unresolved_moved_source_cannot_report_complete(self):
        for relocate in (False, True):
            with self.subTest(relocate=relocate), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                container = root / 'container'
                container.mkdir()
                source, output = container / 'runtime.log', root / 'journal.log'
                if relocate:
                    source.write_bytes(b'before move\n')
                journal = NativeDiagnosticJournal(source, output)
                journal.poll()
                if relocate:
                    container.rename(root / 'relocated')
                with self.assertRaisesRegex(ValueError, 'missing at completion'):
                    journal.finish()

    def test_atomic_rotation_drains_unread_tail_without_repeating_lines(self):
        with tempfile.TemporaryDirectory() as directory:
            source, output = Path(directory) / 'runtime.log', Path(directory) / 'journal.log'
            source.write_bytes(b'first\n')
            journal = NativeDiagnosticJournal(source, output)
            journal.poll()
            with source.open('ab') as file:
                file.write(b'last old inode\n')
            replacement = Path(directory) / 'replacement'
            replacement.write_bytes(b'new inode\n')
            replacement.replace(source)
            journal.poll()
            with source.open('ab') as file:
                file.write(b'new tail\n')
            facts = journal.finish()
            self.assertEqual(output.read_bytes(), b'first\nlast old inode\nnew inode\nnew tail\n')
            self.assertEqual(facts['atomicRotationsDrained'], 1)

    def test_initially_missing_file_and_partial_line_are_retained(self):
        with tempfile.TemporaryDirectory() as directory:
            source, output = Path(directory) / 'runtime.log', Path(directory) / 'journal.log'
            journal = NativeDiagnosticJournal(source, output)
            journal.poll()
            source.write_bytes(b'partial')
            journal.poll()
            with source.open('ab') as file:
                file.write(b' line\n')
            journal.finish()
            self.assertEqual(output.read_bytes(), b'partial line\n')

    def test_same_inode_truncation_and_unsafe_replacement_are_failures(self):
        for change in ('truncate', 'symlink'):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory:
                source, output = Path(directory) / 'runtime.log', Path(directory) / 'journal.log'
                source.write_bytes(b'first record\n')
                journal = NativeDiagnosticJournal(source, output)
                journal.poll()
                if change == 'truncate':
                    source.write_bytes(b'')
                else:
                    source.unlink()
                    source.symlink_to(output)
                with self.assertRaises(ValueError):
                    journal.finish()

    def test_size_budget_and_output_collision_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            source, output = Path(directory) / 'runtime.log', Path(directory) / 'journal.log'
            source.write_bytes(b'12345')
            journal = NativeDiagnosticJournal(source, output, maximum_bytes=4)
            with self.assertRaises(ValueError):
                journal.finish()
            with self.assertRaises(FileExistsError):
                NativeDiagnosticJournal(source, output)


if __name__ == '__main__':
    unittest.main()

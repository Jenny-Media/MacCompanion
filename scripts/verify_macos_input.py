#!/usr/bin/env python3
"""Verify actual native Mac input models against authoritative golden cases."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='maccompanion-mac-input-', dir='/private/tmp') as temporary:
    output = Path(temporary)
    subprocess.run(['xcrun', '--sdk', 'macosx', 'swiftc', '-parse-as-library', '-swift-version', '6',
        '-D', 'MACCOMPANION_VNC_DEVELOPMENT', '-module-cache-path', str(output / 'cache'),
        str(ROOT / 'Native/Mac/MacVNCInput.swift'), str(ROOT / 'Native/Mac/MacTerminalMouseReport.swift'),
        str(ROOT / 'Native/MacTests/InputContractTests.swift'),
        '-o', str(output / 'input-tests')], check=True)
    subprocess.run([str(output / 'input-tests'), str(ROOT / 'spec/fixtures/native-macos-client-v1.json')], check=True)

#!/usr/bin/env python3
"""Run the actual native visionOS input model against manifest-indexed cases."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='maccompanion-vision-input-', dir='/private/tmp') as temporary:
    output = Path(temporary)
    subprocess.run(['xcrun', '--sdk', 'macosx', 'swiftc', '-parse-as-library', '-swift-version', '6',
        '-module-cache-path', str(output / 'cache'), str(ROOT / 'Native/Vision/VisionDesktopGeometry.swift'),
        str(ROOT / 'Native/VisionTests/InputContractTests.swift'), '-o', str(output / 'input-tests')], check=True)
    subprocess.run([str(output / 'input-tests'), str(ROOT / 'spec/fixtures/native-visionos-client-v1.json')], check=True)

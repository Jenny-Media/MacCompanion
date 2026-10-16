#!/usr/bin/env python3
"""Verify native Apple Screen Sharing handoff and Terminal window ownership."""
import hashlib
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
# Validation supplies its leased compiler workspace. Standalone checks have a
# stable checkout-specific scratch path; neither route deletes earlier evidence.
slot = hashlib.sha256(str(ROOT).encode()).hexdigest()[:12]
output = Path(os.environ.get('MACCOMPANION_VALIDATION_SCRATCH_ROOT',
                            '/private/tmp/maccompanion-handoff-' + slot)) / 'macos-handoff'
output.mkdir(parents=True, exist_ok=True)
subprocess.run(['xcrun', '--sdk', 'macosx', 'swiftc', '-swift-version', '6', '-parse-as-library',
    '-D', 'MACCOMPANION_VNC_DEVELOPMENT', '-module-cache-path', str(output / 'ModuleCache'),
    '-import-objc-header', str(ROOT / 'Native/VNC/CompanionVNCDirectEndpoint.h'),
    str(ROOT / 'Native/Mac/MacToolCoordinator.swift'), str(ROOT / 'Native/MacTests/ScreenSharingHandoffTests.swift'),
    '-o', str(output / 'handoff-tests')], check=True)
subprocess.run([str(output / 'handoff-tests'), str(ROOT / 'spec/fixtures/native-macos-client-v1.json')], check=True)

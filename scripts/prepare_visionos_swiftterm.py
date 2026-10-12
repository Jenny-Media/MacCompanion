"""Admit one access-level adaptation for the pinned visionOS UIKit frontend.

No dependency implementation or pin is changed. The complete package tree is
verified before writing, then the native builder records the actual adapted
tree before and after compilation. Other platforms never enable this exception.
"""
import hashlib
import json
from pathlib import Path
import stat
import subprocess

from dependency_checkout_provenance import verify_checkouts


def prepare(derived_data: Path):
    root = Path(__file__).resolve().parents[1]
    packages = derived_data / 'SourcePackages'
    package = packages / 'checkouts/SwiftTerm'
    policy = json.loads((root / 'spec/dependency-policy/v0/direct-client-development.json').read_text())['visionOSSwiftTermPressEndpoint']
    name = policy['path']
    if name != 'Sources/SwiftTerm/iOS/iOSTerminalView.swift':
        raise RuntimeError('Unexpected native key-release adaptation path.')
    before = subprocess.check_output(['git', '-C', str(package), 'show', 'HEAD:' + name])
    old = b'public override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?)'
    new = b'open override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?)'
    if policy['originalDeclaration'].encode() != old or policy['adaptedDeclaration'].encode() != new or before.count(old) != 1:
        raise RuntimeError('Unexpected native key-release declaration.')
    after = before.replace(old, new)
    if hashlib.sha256(before).hexdigest() != policy['originalSHA256'] or hashlib.sha256(after).hexdigest() != policy['adaptedSHA256']:
        raise RuntimeError('Native key-release adaptation does not match its admitted hashes.')
    transforms = {'swiftterm': {name: (before, after)}}
    pins = json.loads((root / 'Native/Terminal/Package.resolved').read_text())['pins']
    verify_checkouts(packages, pins, transforms=transforms)
    path = package / name
    if path.read_bytes() == before:
        mode = stat.S_IMODE(path.stat().st_mode)
        try:
            path.chmod(mode | stat.S_IWUSR)
            path.write_bytes(after)
        finally:
            path.chmod(mode)
    verify_checkouts(packages, pins, transforms=transforms)
    return transforms

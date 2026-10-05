#!/usr/bin/env python3
"""Admit only the hash-pinned direct-client development dependency graph."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / 'spec/dependency-policy/v0/direct-client-development.json'
VENDOR = 'Native/Dependencies/Citadel'
RESOLVED = 'Native/Terminal/Package.resolved'

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def validate():
    policy = json.loads(POLICY.read_text())
    assert set(policy) == {'profile', 'releaseAdmitted', 'vendorPackage', 'sourceLockPath', 'sourceLockSHA256', 'resolvedLockfilePath', 'resolvedLockfileSHA256'}
    assert policy['profile'] == 'maccompanion.direct-client-development-dependencies.v1'
    assert policy['releaseAdmitted'] is False and policy['vendorPackage'] == VENDOR
    assert policy['resolvedLockfilePath'] == RESOLVED and policy['sourceLockPath'] == 'Native/Terminal/source-lock.json'
    source_lock = ROOT / policy['sourceLockPath']
    assert sha(source_lock) == policy['sourceLockSHA256'] and sha(ROOT / RESOLVED) == policy['resolvedLockfileSHA256']
    source = json.loads(source_lock.read_text()); vendor = ROOT / VENDOR
    assert {str(p.relative_to(vendor)): sha(p) for p in sorted(vendor.rglob('*')) if p.is_file()} == source['Citadel']['files']
    assert all(not p.is_symlink() for p in vendor.rglob('*'))
    pins = json.loads((ROOT / RESOLVED).read_text())['pins']
    assert pins and len({p['identity'] for p in pins}) == len(pins)
    assert all(p['kind'] == 'remoteSourceControl' and p['location'].startswith('https://github.com/') and len(p['state']['revision']) == 40 for p in pins)
    assert next(p for p in pins if p['identity'] == 'swiftterm')['state']['revision'] == source['SwiftTerm']['revision']
    return {VENDOR}, {RESOLVED}

if __name__ == '__main__':
    validate(); print('Direct client development dependencies: vendor sources and complete package revisions hash-pinned; Release remains gated')

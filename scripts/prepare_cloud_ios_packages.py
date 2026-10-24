#!/usr/bin/env python3
"""Verify resolved cloud packages and approve only the already-pinned plugin."""
import argparse
import json
from pathlib import Path

from dependency_checkout_provenance import verify_checkouts
from prepare_swiftterm_build_tool import prepare
from prepare_uikit_swiftterm import prepare as prepare_frontend
from verify_direct_client_dependencies import validate as validate_policy

ROOT = Path(__file__).resolve().parents[1]


def approve_swiftterm(security_directory, revision):
    """Use Xcode's per-plugin approval, preserving unrelated approval records."""
    path = security_directory / 'plugins.json'
    approvals = json.loads(path.read_text()) if path.exists() else []
    if not isinstance(approvals, list) or any(not isinstance(v, dict) for v in approvals):
        raise ValueError('Unexpected existing Swift package plugin approval format')
    approval = {'fingerprint': revision, 'packageIdentity': 'swiftterm',
                'targetName': 'SwiftTermBuildInfoPlugin'}
    if approval not in approvals:
        approvals.append(approval)
        security_directory.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(approvals, indent=2) + '\n')


def configure(derived_data, security_directory, *, verify_only=False):
    validate_policy()
    policy = json.loads((ROOT / 'spec/dependency-policy/v0/direct-client-development.json').read_text())
    cloud = policy['xcodeCloud']
    pins = json.loads((ROOT / cloud['resolvedLockfilePath']).read_text())['pins']
    provenance = derived_data / 'maccompanion-cloud-packages.json'
    previous = json.loads(provenance.read_text()) if verify_only else None
    transforms = prepare_frontend(derived_data, pins=pins, allow_cloud_transport=True, verify_only=verify_only)
    snapshot = verify_checkouts(derived_data / 'SourcePackages', pins, previous=previous,
                               transforms=transforms, allow_cloud_transport=True)
    if verify_only:
        print('Cloud package sources remain unchanged after xcodebuild')
        return
    # The existing helper verifies the pinned checkout again before compiling
    # its unmodified host generator for Xcode 27's Debug plugin-tool path.
    prepare(derived_data, transforms=transforms['swiftterm'])
    pin = next(p for p in pins if p['identity'] == 'swiftterm')
    approve_swiftterm(security_directory, pin['state']['revision'])
    provenance.write_text(json.dumps(snapshot, indent=2) + '\n')
    print('Verified cloud packages; approved only the pinned SwiftTerm build plugin')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--derived-data', type=Path, required=True)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    configure(args.derived_data, Path.home() / 'Library/org.swift.swiftpm/security',
              verify_only=args.verify_only)


if __name__ == '__main__':
    main()

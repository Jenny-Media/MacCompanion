#!/usr/bin/env python3
"""Build an isolated live SSH probe; use only a disposable, authorized VM."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', type=Path, required=True, help='Completed direct Mac build and its pinned package cache')
    parser.add_argument('--output', type=Path, required=True, help='Temporary output outside the checkout')
    args = parser.parse_args()
    base, output = args.build.resolve(), args.output.resolve()
    if output == ROOT or ROOT in output.parents:
        parser.error('Output must stay outside the checkout.')
    if any(not os.environ.get(name) for name in ('MC_VM_HOST', 'MC_VM_ACCOUNT', 'MC_VM_PASSWORD', 'MC_VM_HOST_KEY')):
        parser.error('Set the four MC_VM_* environment values for the disposable VM; credentials are never logged.')
    from verify_direct_client_dependencies import validate
    validate()
    output.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix='verified-source-', dir=output)) / 'Citadel'
    shutil.copytree(ROOT / 'Native/Dependencies/Citadel', staging)
    specification = json.loads((base / 'project.json').read_text())
    specification['name'] = 'NativeMacLiveTransportQA'
    specification['packages']['Citadel'] = {'path': str(staging)}
    specification['targets'] = {'SSHProbe': {
        'type': 'tool', 'platform': 'macOS',
        'sources': [{'path': str(Path(__file__).with_name('SSHProbe.swift'))}],
        'dependencies': [{'package': 'Citadel'}],
        'settings': {'base': {'SWIFT_VERSION': '6.0', 'MACOSX_DEPLOYMENT_TARGET': '26.0',
                              'ARCHS': 'arm64', 'CODE_SIGNING_ALLOWED': 'NO'}}}}
    specification['schemes'] = {'SSHProbe': {'build': {'targets': {'SSHProbe': 'all'}}}}
    project = output / 'project.json'
    project.write_text(json.dumps(specification, indent=2) + '\n')
    subprocess.run(['/opt/homebrew/bin/xcodegen', 'generate', '--spec', str(project)], check=True)
    xcode = output / 'NativeMacLiveTransportQA.xcodeproj'
    lock = xcode / 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    lock.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / 'Native/Terminal/Package.resolved', lock)
    derived = base / 'QA/DerivedData'
    with (output / 'build.log').open('w') as log:
        subprocess.run(['xcodebuild', '-project', str(xcode), '-scheme', 'SSHProbe', '-configuration', 'Debug',
                        '-destination', 'generic/platform=macOS', '-derivedDataPath', str(derived),
                        '-clonedSourcePackagesDirPath', str(base / 'DerivedData/SourcePackages'),
                        '-onlyUsePackageVersionsFromResolvedFile', '-skipPackagePluginValidation', 'build'],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    subprocess.run([str(derived / 'Build/Products/Debug/SSHProbe')], check=True, timeout=60)


if __name__ == '__main__':
    main()

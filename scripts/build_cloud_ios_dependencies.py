#!/usr/bin/env python3
"""Prepare the normal source-verified iOS dependencies for a stable cloud project.

No signing credentials, binary downloads, experimental app sources or project
regeneration are involved. The normal managed builder remains authoritative for
LibVNCClient, its admitted patches and native dependency verification.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
CLOUD = ROOT / 'Native/iOSCloud'


def run(*args, **kwargs):
    subprocess.run([str(v) for v in args], check=True, **kwargs)


def capture(*args):
    return subprocess.check_output(args, text=True).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def download_source(artifact, archive, download=None):
    download = download or urllib.request.urlretrieve
    for attempt in range(3):
        temporary = archive.with_name(archive.name + '.download-' + uuid.uuid4().hex)
        try:
            download(artifact['url'], temporary)
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            if attempt == 2:
                raise
            print('Incomplete source download; retrying with a fresh file', flush=True)
            time.sleep(2 ** attempt)
            continue
        if digest(temporary) != artifact['sha256']:
            raise ValueError('OpenSSL download does not match the production source lock')
        temporary.replace(archive)
        return


def openssl(root):
    lock = json.loads((ROOT / 'Native/VNC/source-lock.json').read_text())
    version = lock['opensslVersion']
    artifact = {'version': version, 'sha256': lock['opensslSourceSHA256'],
                'url': 'https://www.openssl.org/source/openssl-' + version + '.tar.gz'}
    root.mkdir(parents=True, exist_ok=True)
    archive = root / ('openssl-' + version + '.tar.gz')
    if not archive.exists():
        download_source(artifact, archive)
    if digest(archive) != artifact['sha256']:
        raise ValueError('OpenSSL archive differs from the production source lock')
    sdk = capture('xcrun', '--sdk', 'iphoneos', '--show-sdk-path')
    inputs = {'source': artifact, 'sdk': 'iphoneos', 'sourceBuilderSHA256': digest(Path(__file__)),
              'toolchain': capture('xcodebuild', '-version'),
              'sdkVersion': capture('xcrun', '--sdk', 'iphoneos', '--show-sdk-version')}
    provenance = root / 'iphoneos-provenance.json'
    if provenance.exists():
        prior = json.loads(provenance.read_text())
        framework = root / prior['framework']
        if prior['inputs'] == inputs and all((framework / p).is_file() and digest(framework / p) == sha
                                             for p, sha in prior['files'].items()):
            return root
    # Preserve previous products and evidence on changes; never delete caches.
    generation = Path(tempfile.mkdtemp(prefix='openssl-device-', dir=root))
    with tarfile.open(archive) as stream:
        stream.extractall(generation, filter='data')
    source = generation / ('openssl-' + version)
    work = generation / 'objects'
    work.mkdir()
    with (generation / 'build.log').open('w') as log:
        run('perl', source / 'Configure', 'ios64-xcrun', 'no-shared', 'no-module', 'no-tests',
            'no-engine', '-isysroot', sdk, '-miphoneos-version-min=26.0', cwd=work, stdout=log, stderr=subprocess.STDOUT)
        run('make', '-j4', 'build_libs', cwd=work, stdout=log, stderr=subprocess.STDOUT)
        framework = generation / 'OpenSSL.framework'
        (framework / 'Headers/openssl').mkdir(parents=True)
        for headers in (source / 'include/openssl', work / 'include/openssl'):
            for header in headers.glob('*.h'):
                shutil.copyfile(header, framework / 'Headers/openssl' / header.name)
        (framework / 'Modules').mkdir()
        (framework / 'Modules/module.modulemap').write_text(
            'framework module OpenSSL { umbrella "../Headers" export * module * { export * } }\n')
        (framework / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'dev.maccompanion.experiment.openssl',
            'CFBundleExecutable': 'OpenSSL', 'CFBundleName': 'OpenSSL',
            'CFBundlePackageType': 'FMWK', 'CFBundleVersion': '1',
            'CFBundleShortVersionString': version, 'CFBundleSupportedPlatforms': ['iPhoneOS'],
            'MinimumOSVersion': '26.0'}))
        run('xcrun', '--sdk', 'iphoneos', 'clang', '-arch', 'arm64', '-isysroot', sdk,
            '-miphoneos-version-min=26.0', '-g', '-dynamiclib', '-Wl,-all_load',
            work / 'libssl.a', work / 'libcrypto.a', '-install_name',
            '@rpath/OpenSSL.framework/OpenSSL', '-o', framework / 'OpenSSL', stdout=log, stderr=subprocess.STDOUT)
        shutil.copyfile(source / 'LICENSE.txt', framework / 'LICENSE.txt')
    platform = root / 'iphoneos'
    if platform.is_symlink():
        platform.unlink()
    elif platform.exists():
        raise ValueError('Preserving unexpected OpenSSL output; choose a fresh workspace')
    platform.symlink_to(generation, target_is_directory=True)
    provenance.write_text(json.dumps({'inputs': inputs, 'sourceBuilt': True, 'releaseAdmitted': False,
        'framework': str(framework.relative_to(root)),
        'files': {str(p.relative_to(framework)): digest(p) for p in framework.rglob('*') if p.is_file()}}, indent=2))
    return root


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, required=True)
    args = parser.parse_args()
    workspace = args.workspace.resolve()
    if workspace.is_relative_to(ROOT):
        raise SystemExit('Use a dependency workspace outside the checkout')
    workspace.mkdir(parents=True, exist_ok=True)
    lock = json.loads((ROOT / 'Native/VNC/source-lock.json').read_text())
    source = workspace / 'libvncserver'
    if not source.exists():
        run('git', 'clone', '--no-checkout', lock['repository'], source)
        run('git', '-C', source, 'checkout', '--detach', lock['revision'])
    if capture('git', '-C', str(source), 'rev-parse', 'HEAD') != lock['revision']:
        raise ValueError('Unexpected LibVNCClient revision')
    output = workspace / 'prepared'
    run(sys.executable, ROOT / 'scripts/build_vnc_ios_development.py', '--source', source,
        '--openssl', openssl(workspace / 'openssl'), '--output', output, '--sdk', 'iphoneos', '--prepare-only')
    records = sorted((output / 'runs').glob('*/run.json'), key=lambda p: p.stat().st_mtime_ns)
    record = json.loads(records[-1].read_text())
    if record['status'] != 'prepared':
        raise ValueError('Native dependency preparation did not complete')
    compiler = Path(record['preparedProject']).parent
    spec = json.loads((compiler / 'project.json').read_text())
    include = Path(spec['targets']['MacCompanionIOS']['settings']['base']['HEADER_SEARCH_PATHS'][0])
    header_link = compiler / 'source-include'
    if header_link.is_symlink():
        header_link.unlink()
    elif header_link.exists():
        raise ValueError('Refusing to replace unexpected header directory')
    header_link.symlink_to(include, target_is_directory=True)
    link = CLOUD / '.cloud'
    if link.is_symlink():
        link.unlink()
    elif link.exists():
        raise ValueError('Refusing to replace unexpected native dependency directory')
    link.symlink_to(compiler, target_is_directory=True)
    print('Cloud native dependencies ready:', compiler)


if __name__ == '__main__':
    main()

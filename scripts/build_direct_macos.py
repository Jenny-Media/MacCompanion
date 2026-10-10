#!/usr/bin/env python3
"""Build the native direct Mac client with the admitted, pinned dependencies.

Generated development output stays outside the checkout. No host/Agent sources
or experiments are linked into the client. Distribution admission is separate.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def capture(*args):
    return subprocess.check_output([str(x) for x in args], text=True).strip()


def run(*args, **kwargs):
    subprocess.run([str(x) for x in args], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True, help='Clean pinned LibVNCClient checkout')
    parser.add_argument('--openssl-archive', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--arch', choices=['arm64', 'x86_64'], default='arm64')
    parser.add_argument('--signing-identity', help='Existing local Apple Development certificate SHA-1')
    parser.add_argument('--team', help='Existing Apple team; required for development signing')
    parser.add_argument('--profile', type=Path, help='Existing installed Mac development provisioning profile')
    args = parser.parse_args()
    def source_inputs():
        roots = [ROOT / 'Native/Mac', ROOT / 'Native/VNC', ROOT / 'Native/Terminal', ROOT / 'Native/Dependencies',
                 ROOT / 'Apps/MacCompanionMac/Assets.xcassets']
        files = [p for folder in roots for p in sorted(folder.rglob('*')) if p.is_file()]
        files += [Path(__file__), *[ROOT / 'scripts' / name for name in [
            'direct_mac_development_signing.py', 'verify_direct_client_dependencies.py',
            'prepare_swiftterm_build_tool.py', 'dependency_checkout_provenance.py']],
            ROOT / 'spec/dependency-policy/v0/direct-client-development.json',
            ROOT / 'spec/privacy-manifest/v0/targets/mac-containing-app/PrivacyInfo.xcprivacy']
        return {str(p.relative_to(ROOT)): sha(p) for p in files}
    application_inputs = source_inputs()
    args.output = args.output.resolve()
    if args.output.is_relative_to(ROOT):
        raise SystemExit('Generated output must be outside the checkout.')
    from verify_direct_client_dependencies import validate
    validate()
    lock = json.loads((ROOT / 'Native/VNC/source-lock.json').read_text())
    from dependency_checkout_provenance import verify_source_checkout
    vnc_sources = verify_source_checkout(args.source, lock['revision'])
    if sha(args.openssl_archive) != lock['opensslSourceSHA256']:
        raise SystemExit('OpenSSL source archive checksum mismatch.')
    args.output.mkdir(parents=True, exist_ok=True)
    sdk = capture('xcrun', '--sdk', 'macosx', '--show-sdk-path')
    version = capture('xcodebuild', '-version')
    crypto = args.output / 'openssl'
    crypto.mkdir(exist_ok=True)
    source = crypto / ('openssl-' + lock['opensslVersion'])
    if not source.exists():
        with tarfile.open(args.openssl_archive) as archive:
            archive.extractall(crypto, filter='data')
    with tarfile.open(args.openssl_archive) as archive:
        for member in archive:
            if member.isfile() and sha(crypto / member.name) != hashlib.sha256(archive.extractfile(member).read()).hexdigest():
                raise SystemExit('Extracted OpenSSL source changed: ' + member.name)
    work = crypto / args.arch
    inputs = {'sourceSHA256': lock['opensslSourceSHA256'], 'arch': args.arch, 'sdk': sdk,
              'toolchain': version, 'deploymentTarget': '26.0', 'builderSHA256': sha(Path(__file__))}
    provenance = work / 'provenance.json'
    prior = json.loads(provenance.read_text()) if provenance.exists() else {}
    if prior.get('inputs') != inputs or any(not (work / p).exists() or sha(work / p) != h for p, h in prior.get('files', {}).items()):
        work.mkdir(exist_ok=True)
        environment = dict(os.environ, CC=capture('xcrun', '--find', 'clang'),
                           CFLAGS='-arch ' + args.arch + ' -isysroot ' + sdk + ' -mmacosx-version-min=26.0')
        with (crypto / (args.arch + '-build.log')).open('w') as log:
            run('perl', source / 'Configure', 'darwin64-' + args.arch + '-cc', 'no-shared', 'no-module', 'no-tests', 'no-engine',
                cwd=work, env=environment, stdout=log, stderr=subprocess.STDOUT)
            run('make', '-j6', 'build_libs', cwd=work, env=environment, stdout=log, stderr=subprocess.STDOUT)
        provenance.write_text(json.dumps({'inputs': inputs, 'sourceBuilt': True,
            'files': {p: sha(work / p) for p in ['libssl.a', 'libcrypto.a']}}, indent=2) + '\n')
    headers = crypto / 'headers' / 'openssl'
    headers.mkdir(parents=True, exist_ok=True)
    for directory in [source / 'include/openssl', work / 'include/openssl']:
        for p in directory.glob('*.h'):
            shutil.copy2(p, headers / p.name)
    vnc = args.output / ('libvncclient-' + args.arch)
    definitions = {'CMAKE_OSX_SYSROOT': sdk, 'CMAKE_OSX_ARCHITECTURES': args.arch,
        'CMAKE_OSX_DEPLOYMENT_TARGET': '26.0', 'CMAKE_POLICY_VERSION_MINIMUM': '3.5',
        'CMAKE_C_COMPILER': capture('xcrun', '--find', 'clang'), 'BUILD_SHARED_LIBS': 'OFF',
        'WITH_OPENSSL': 'ON', 'WITH_ZLIB': 'ON', 'OPENSSL_INCLUDE_DIR': headers.parent,
        'OPENSSL_SSL_LIBRARY': work / 'libssl.a', 'OPENSSL_CRYPTO_LIBRARY': work / 'libcrypto.a',
        'ZLIB_INCLUDE_DIR': Path(sdk) / 'usr/include', 'ZLIB_LIBRARY': Path(sdk) / 'usr/lib/libz.tbd',
        'CMAKE_IGNORE_PREFIX_PATH': '/opt/homebrew'}
    for name in ['LZO', 'JPEG', 'PNG', 'SDL', 'GTK', 'LIBSSHTUNNEL', 'GNUTLS', 'SYSTEMD', 'GCRYPT', 'FFMPEG', 'SASL', 'XCB', 'EXAMPLES', 'TESTS', 'WEBSOCKETS', 'TIGHTVNC_FILETRANSFER']:
        definitions['WITH_' + name] = 'OFF'
    with (args.output / 'vnc-build.log').open('w') as log:
        run('/opt/homebrew/bin/cmake', '-S', args.source, '-B', vnc, *['-D' + k + '=' + str(v) for k, v in definitions.items()], stdout=log, stderr=subprocess.STDOUT)
        run('/opt/homebrew/bin/cmake', '--build', vnc, '--target', 'vncclient', '-j6', stdout=log, stderr=subprocess.STDOUT)
    shared_vnc = ['DirectMacLibraryV1.swift', 'DirectMacIdentityV1.swift', 'DirectMacDiscoveryV1.swift', 'DirectCloudSyncV1.swift',
        'DirectClientPlatformV1.swift', 'DirectAppearanceV1.swift', 'DirectProAccess.swift', 'DirectRecoveryV1.swift', 'VNCSessionPreferences.swift',
        'CompanionVNCSession.m', 'CompanionVNCDirectConnection.m', 'CompanionVNCKeyboard.m']
    shared_terminal = ['DirectTerminalSession.swift', 'TerminalSecretStore.swift', 'TerminalSSHKey.swift', 'TerminalKeyLibrary.swift', 'TerminalKeyInstallation.swift',
                       'TerminalKeyboard.swift', 'TerminalLoginSelection.swift', 'TerminalIdentityGuide.swift',
                       'TerminalKeySettings.swift', 'TerminalKeyInstallView.swift', 'TerminalKeyboardSettings.swift']
    sources = [{'path': str(ROOT / 'Native/Mac')}, *[{'path': str(ROOT / 'Native/VNC' / p)} for p in shared_vnc],
        *[{'path': str(ROOT / 'Native/Terminal' / p)} for p in shared_terminal],
        {'path': str(ROOT / 'Apps/MacCompanionMac/Assets.xcassets'), 'buildPhase': 'resources'},
        {'path': str(ROOT / 'spec/privacy-manifest/v0/targets/mac-containing-app/PrivacyInfo.xcprivacy'), 'buildPhase': 'resources'}]
    info = args.output / 'Info.plist'
    info.write_bytes(plistlib.dumps({'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)', 'CFBundleExecutable': '$(EXECUTABLE_NAME)',
        'CFBundleName': 'Mac Companion', 'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '1.0', 'CFBundleVersion': '1',
        'LSMinimumSystemVersion': '26.0', 'NSHighResolutionCapable': True, 'LSApplicationCategoryType': 'public.app-category.utilities',
        'NSLocalNetworkUsageDescription': 'Connect to your Macs using Screen Sharing and Remote Login.',
        'NSBonjourServices': ['_rfb._tcp', '_ssh._tcp', '_device-info._tcp'],
        'MacCompanionSharedKeychainGroup': '$(TeamIdentifierPrefix)media.jenny.maccompanion.ios'}))
    terminal_lock = json.loads((ROOT / 'Native/Terminal/source-lock.json').read_text())
    spec = {'name': 'NativeMacClient', 'options': {'deploymentTarget': {'macOS': '26.0'}},
        'packages': {'Citadel': {'path': str(ROOT / 'Native/Dependencies/Citadel')},
                     'SwiftTerm': {k: v for k, v in terminal_lock['SwiftTerm'].items() if k in ['url', 'revision']}},
        'targets': {'MacCompanion': {'type': 'application', 'platform': 'macOS', 'sources': sources,
            'dependencies': [{'package': 'Citadel'}, {'package': 'SwiftTerm'}, {'framework': str(vnc / 'libvncclient.a'), 'embed': False},
                {'framework': str(work / 'libssl.a'), 'embed': False}, {'framework': str(work / 'libcrypto.a'), 'embed': False}],
            'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': 'media.jenny.maccompanion', 'INFOPLIST_FILE': str(info),
                'SWIFT_VERSION': '6.0', 'SWIFT_STRICT_CONCURRENCY': 'complete', 'CODE_SIGNING_ALLOWED': 'NO',
                'SWIFT_ACTIVE_COMPILATION_CONDITIONS': '$(inherited) MACCOMPANION_VNC_DEVELOPMENT',
                'SWIFT_OBJC_BRIDGING_HEADER': str(ROOT / 'Native/Mac/MacCompanionDirect-Bridging-Header.h'),
                'HEADER_SEARCH_PATHS': [str(ROOT / 'Native/VNC'), str(args.source / 'include'), str(vnc / 'include')],
                'LIBRARY_SEARCH_PATHS': [str(vnc), str(work)],
                'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon',
                'OTHER_LDFLAGS': ['$(inherited)', '-lz'], 'ARCHS': args.arch, 'ONLY_ACTIVE_ARCH': 'YES'}}}},
        'schemes': {'MacCompanion': {'build': {'targets': {'MacCompanion': 'all'}}}}}
    signing = None
    if any([args.signing_identity, args.team, args.profile]):
        if not all([args.signing_identity, args.team, args.profile]):
            parser.error('Development signing requires --signing-identity, --team and --profile together.')
        from direct_mac_development_signing import configure
        signing = configure(spec['targets']['MacCompanion']['settings']['base'], identity=args.signing_identity, team=args.team,
                            profile_path=args.profile, output=args.output, bundle='media.jenny.maccompanion',
                            sync_group=args.team + '.media.jenny.maccompanion.ios')
        metadata = plistlib.loads(info.read_bytes())
        metadata['MacCompanionSharedKeychainGroup'] = args.team + '.media.jenny.maccompanion.ios'
        info.write_bytes(plistlib.dumps(metadata))
    project = args.output / 'project.json'
    project.write_text(json.dumps(spec, indent=2) + '\n')
    run('/opt/homebrew/bin/xcodegen', 'generate', '--spec', project)
    project_path = args.output / 'NativeMacClient.xcodeproj'
    lock_path = project_path / 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / 'Native/Terminal/Package.resolved', lock_path)
    with (args.output / 'resolve.log').open('w') as log:
        run('xcodebuild', '-resolvePackageDependencies', '-project', project_path, '-scheme', 'MacCompanion', '-derivedDataPath', args.output / 'DerivedData',
            '-onlyUsePackageVersionsFromResolvedFile', '-skipPackageUpdates', stdout=log, stderr=subprocess.STDOUT)
    expected = json.loads((ROOT / 'Native/Terminal/Package.resolved').read_text())['pins']
    if json.loads(lock_path.read_text())['pins'] != expected:
        raise SystemExit('Resolved package revisions changed. Use the admitted complete lockfile.')
    from dependency_checkout_provenance import verify_checkouts
    package_sources = verify_checkouts(args.output / 'DerivedData/SourcePackages', expected)
    from prepare_swiftterm_build_tool import prepare
    prepare(args.output / 'DerivedData')
    with (args.output / 'build.log').open('w') as log:
        run('xcodebuild', '-project', project_path, '-scheme', 'MacCompanion', '-configuration', 'Debug',
            '-destination', 'generic/platform=macOS', '-derivedDataPath', args.output / 'DerivedData',
            '-onlyUsePackageVersionsFromResolvedFile', '-skipPackagePluginValidation', 'build', stdout=log, stderr=subprocess.STDOUT)
    if json.loads(lock_path.read_text())['pins'] != expected:
        raise SystemExit('Resolved package revisions changed during the build.')
    package_sources_after = verify_checkouts(args.output / 'DerivedData/SourcePackages', expected, previous=package_sources)
    vnc_sources_after = verify_source_checkout(args.source, lock['revision'], previous=vnc_sources)
    if source_inputs() != application_inputs:
        raise SystemExit('Application sources changed during the build. Rerun against a stable source snapshot.')
    app = args.output / 'DerivedData/Build/Products/Debug/MacCompanion.app'
    executable = app / 'Contents/MacOS/MacCompanion'
    if signing:
        from direct_mac_development_signing import verify
        verify(app, signing, args.output)
    report = {'schema': 1, 'kind': 'native-macos-direct-client-build', 'arch': args.arch, 'toolchain': version,
              'sourceInputs': application_inputs, 'sourceRevision': capture('git', '-C', ROOT, 'rev-parse', 'HEAD'),
              'sourceWorktreeDirty': bool(capture('git', '-C', ROOT, 'status', '--porcelain')),
              'dependencies': {'LibVNCClient': lock['revision'], 'OpenSSL': inputs, 'SwiftPackages': expected,
                               'LibVNCClientSources': {'beforeBuild': vnc_sources, 'afterBuild': vnc_sources_after},
                               'SwiftPackageSources': {'beforeBuild': package_sources, 'afterBuild': package_sources_after}},
              'app': str(app), 'executableSHA256': sha(executable),
              'artifactFiles': {str(p.relative_to(app)): sha(p) for p in sorted(app.rglob('*')) if p.is_file() and not p.is_symlink()},
              'signedDeviceAcceptance': False,
              'developmentSigning': signing, 'iCloudDeliveryVerified': False, 'releaseReadiness': False}
    (args.output / 'build-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(app)


if __name__ == '__main__':
    main()

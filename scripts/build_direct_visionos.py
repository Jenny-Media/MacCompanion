#!/usr/bin/env python3
"""Reproducible native visionOS development build; no distribution admission.

--probe links only the disposable feasibility application. Device-SDK compilation
never installs or contacts a device. Outputs and package caches stay outside Git.
"""
import argparse
from build_cache import BuildSession, cmake_refresh_args, toolchain_identity, write_if_changed
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]

def application_inputs(probe):
    roots = [ROOT / 'Native/VNC', ROOT / 'Native/Terminal', ROOT / 'Native/Dependencies',
             ROOT / ('Experiments/VisionOSFeasibility' if probe else 'Native/Vision')]
    files = [p for folder in roots for p in sorted(folder.rglob('*')) if p.is_file()]
    files += [ROOT / 'Native/Mac' / (name + '.swift') for name in ['MacSessionStatus', 'MacTerminalHeldInput', 'MacTerminalMouseReport']]
    files += [Path(__file__), *[ROOT / 'scripts' / name for name in ['build_cache.py', 'verify_direct_client_dependencies.py',
        'prepare_swiftterm_build_tool.py', 'prepare_visionos_swiftterm.py', 'dependency_checkout_provenance.py']],
        ROOT / 'spec/dependency-policy/v0/direct-client-development.json',
        ROOT / 'spec/privacy-manifest/v0/targets/ios-app/PrivacyInfo.xcprivacy']
    return {str(p.relative_to(ROOT)): digest(p) for p in files}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def capture(*args):
    return subprocess.check_output([str(a) for a in args], text=True).strip()

def run(*args, **kwargs):
    subprocess.run([str(a) for a in args], check=True, **kwargs)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--openssl-archive', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True, help='Evidence directory outside the checkout; compiler files are reused separately')
    parser.add_argument('--cache-root', type=Path, help='Override MACCOMPANION_BUILD_CACHE_ROOT')
    parser.add_argument('--cold', action='store_true', help='Use a fresh compiler workspace without deleting existing caches')
    parser.add_argument('--sdk', choices=['xros', 'xrsimulator'], required=True)
    parser.add_argument('--probe', action='store_true')
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    identity = {'kind': 'visionos-probe' if args.probe else 'native-visionos', 'sdk': args.sdk, 'arch': 'arm64', 'toolchain': toolchain_identity((args.sdk,))}
    with BuildSession(ROOT, args.output, identity, cache_root=args.cache_root, cold=args.cold) as session:
        args.output = session.workspace
        build(args, parser, session)


def build(args, parser, session):
    application_before = application_inputs(args.probe)
    args.output = args.output.resolve()
    if args.output.is_relative_to(ROOT):
        parser.error('Generated output must be outside the checkout.')
    from verify_direct_client_dependencies import validate
    from dependency_checkout_provenance import verify_source_checkout
    validate()
    lock = json.loads((ROOT / 'Native/VNC/source-lock.json').read_text())
    vnc_before = verify_source_checkout(args.source, lock['revision'])
    if digest(args.openssl_archive) != lock['opensslSourceSHA256']:
        raise SystemExit('OpenSSL archive checksum mismatch.')
    args.output.mkdir(parents=True, exist_ok=True)
    sdk = capture('xcrun', '--sdk', args.sdk, '--show-sdk-path')
    version = capture('xcodebuild', '-version')
    triple = 'arm64-apple-xros26.0' + ('-simulator' if args.sdk == 'xrsimulator' else '')
    crypto = args.output / 'openssl'
    crypto.mkdir(exist_ok=True)
    source = crypto / ('openssl-' + lock['opensslVersion'])
    if not source.exists():
        with tarfile.open(args.openssl_archive) as archive:
            archive.extractall(crypto, filter='data')
    with tarfile.open(args.openssl_archive) as archive:
        for member in archive:
            if member.isfile() and digest(crypto / member.name) != hashlib.sha256(archive.extractfile(member).read()).hexdigest():
                raise SystemExit('OpenSSL source changed: ' + member.name)
    work = crypto / args.sdk
    inputs = {'archiveSHA256': lock['opensslSourceSHA256'], 'sdk': sdk,
              'triple': triple, 'toolchain': version,
              'recipe': 'darwin64-arm64-cc no-asm no-shared no-module no-tests no-engine; explicit clang target; build_libs'}
    stamp = work / 'provenance.json'
    prior = json.loads(stamp.read_text()) if stamp.exists() else {}
    if {k: prior.get('inputs', {}).get(k) for k in inputs} != inputs or any(not (work / p).exists() or digest(work / p) != h for p, h in prior.get('files', {}).items()):
        work.mkdir(exist_ok=True)
        # Compile portable OpenSSL sources with the explicit visionOS target.
        # No iOS or macOS object may be reused as a visionOS binary.
        env = dict(os.environ, CC=capture('xcrun', '--find', 'clang'),
                   CFLAGS='-target ' + triple + ' -isysroot ' + sdk)
        with (crypto / 'build.log').open('w') as log:
            run('perl', source / 'Configure', 'darwin64-arm64-cc', 'no-asm', 'no-shared', 'no-module', 'no-tests', 'no-engine',
                cwd=work, env=env, stdout=log, stderr=subprocess.STDOUT)
            run('make', '-j6', 'build_libs', cwd=work, env=env, stdout=log, stderr=subprocess.STDOUT)
        stamp.write_text(json.dumps({'inputs': inputs, 'sourceBuilt': True,
            'files': {p: digest(work / p) for p in ['libssl.a', 'libcrypto.a']}}, indent=2) + '\n')
    headers = crypto / 'headers/openssl'
    headers.mkdir(parents=True, exist_ok=True)
    for directory in [source / 'include/openssl', work / 'include/openssl']:
        for p in directory.glob('*.h'):
            shutil.copy2(p, headers / p.name)
    vnc = args.output / 'libvncclient'
    definitions = {'CMAKE_SYSTEM_NAME': 'visionOS', 'CMAKE_OSX_SYSROOT': sdk,
        'CMAKE_OSX_ARCHITECTURES': 'arm64', 'CMAKE_OSX_DEPLOYMENT_TARGET': '26.0',
        'CMAKE_POLICY_VERSION_MINIMUM': '3.5', 'CMAKE_C_COMPILER': capture('xcrun', '--find', 'clang'),
        'BUILD_SHARED_LIBS': 'OFF', 'WITH_OPENSSL': 'ON', 'WITH_ZLIB': 'ON',
        'OPENSSL_INCLUDE_DIR': headers.parent, 'OPENSSL_SSL_LIBRARY': work / 'libssl.a',
        'OPENSSL_CRYPTO_LIBRARY': work / 'libcrypto.a', 'ZLIB_INCLUDE_DIR': Path(sdk) / 'usr/include',
        'ZLIB_LIBRARY': Path(sdk) / 'usr/lib/libz.tbd', 'CMAKE_IGNORE_PREFIX_PATH': '/opt/homebrew',
        'CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED': 'NO'}
    for name in ['LZO', 'JPEG', 'PNG', 'SDL', 'GTK', 'LIBSSHTUNNEL', 'GNUTLS', 'SYSTEMD', 'GCRYPT', 'FFMPEG', 'SASL', 'XCB', 'EXAMPLES', 'TESTS', 'WEBSOCKETS', 'TIGHTVNC_FILETRANSFER']:
        definitions['WITH_' + name] = 'OFF'
    with (args.output / 'vnc-build.log').open('w') as log:
        run('/opt/homebrew/bin/cmake', *cmake_refresh_args(vnc, args.source), '-S', args.source, '-B', vnc, *['-D' + k + '=' + str(v) for k, v in definitions.items()], stdout=log, stderr=subprocess.STDOUT)
        run('/opt/homebrew/bin/cmake', '--build', vnc, '--target', 'vncclient', '-j6', stdout=log, stderr=subprocess.STDOUT)
    app_sources = ROOT / ('Experiments/VisionOSFeasibility' if args.probe else 'Native/Vision')
    sources = [{'path': str(app_sources), 'excludes': ['README.md', '*Tests.swift']}]
    sources += [{'path': str(ROOT / 'Native/VNC' / name)} for name in ['CompanionVNCSession.m', 'CompanionVNCDirectConnection.m', 'CompanionVNCKeyboard.m']]
    name = 'VisionOSDependencyProbe' if args.probe else 'MacCompanionVision'
    bundle = 'dev.maccompanion.visionos.probe' if args.probe else 'dev.maccompanion.visionos.client'
    terminal_lock = json.loads((ROOT / 'Native/Terminal/source-lock.json').read_text())
    base = {'PRODUCT_BUNDLE_IDENTIFIER': bundle, 'PRODUCT_NAME': name, 'SWIFT_VERSION': '6.0',
        'SWIFT_STRICT_CONCURRENCY': 'complete', 'CODE_SIGNING_ALLOWED': 'NO', 'ENABLE_DEBUG_DYLIB': 'NO',
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS': '$(inherited) MACCOMPANION_VNC_DEVELOPMENT',
        'SWIFT_OBJC_BRIDGING_HEADER': str(app_sources / 'Bridging-Header.h'),
        'HEADER_SEARCH_PATHS': [str(ROOT / 'Native/VNC'), str(args.source / 'include'), str(vnc / 'include')],
        'LIBRARY_SEARCH_PATHS': [str(vnc), str(work)],
        'OTHER_LDFLAGS': ['$(inherited)', '-lz'], 'ARCHS': 'arm64', 'ONLY_ACTIVE_ARCH': 'YES'}
    if args.sdk == 'xrsimulator':
        entitlements = args.output / 'Simulator.entitlements'
        write_if_changed(entitlements, plistlib.dumps({'application-identifier': bundle, 'keychain-access-groups': [bundle]}))
        base.update(CODE_SIGNING_ALLOWED='YES', CODE_SIGN_IDENTITY='-', CODE_SIGN_ENTITLEMENTS=str(entitlements))
    spec = {'name': name, 'options': {'deploymentTarget': {'visionOS': '26.0'}},
        'packages': {'Citadel': {'path': str(ROOT / 'Native/Dependencies/Citadel')},
            'SwiftTerm': {k: v for k, v in terminal_lock['SwiftTerm'].items() if k in ['url', 'revision']}},
        'targets': {name: {'type': 'application', 'platform': 'visionOS', 'sources': sources,
            'settings': {'base': base}, 'dependencies': [{'package': 'Citadel'}, {'package': 'SwiftTerm'},
                *[{'framework': str(p), 'embed': False} for p in [vnc / 'libvncclient.a', work / 'libssl.a', work / 'libcrypto.a']]],
            'info': {'path': str(args.output / 'Info.plist'), 'properties': {'CFBundleDisplayName': 'Mac Companion',
                'CFBundleShortVersionString': '1.0', 'CFBundleVersion': '1',
                'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': True},
                'NSFaceIDUsageDescription': 'Use device authentication to protect your saved Macs and local SSH keys.',
                'NSLocalNetworkUsageDescription': 'Connect to your Macs using Screen Sharing and Remote Login.',
                'NSBonjourServices': ['_rfb._tcp', '_ssh._tcp', '_device-info._tcp']}}}},
        'schemes': {name: {'build': {'targets': {name: 'all'}}}}}
    if args.probe:
        spec['targets']['VisionInputUITests'] = {'type': 'bundle.ui-testing', 'platform': 'visionOS',
            'sources': [{'path': str(app_sources / 'ProbeUITests.swift')}], 'dependencies': [{'target': name}],
            'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': bundle + '.uitests', 'SWIFT_VERSION': '6.0',
                'CODE_SIGNING_ALLOWED': 'YES' if args.sdk == 'xrsimulator' else 'NO', 'CODE_SIGN_IDENTITY': '-', 'GENERATE_INFOPLIST_FILE': 'YES'}}}
        spec['schemes'][name]['test'] = {'targets': ['VisionInputUITests']}
    else:
        configure_client(spec, name, args)
    write_if_changed(args.output / 'project.json', json.dumps(spec, indent=2))
    run('/opt/homebrew/bin/xcodegen', 'generate', '--use-cache', '--cache-path', args.output / '.xcodegen-cache', '--spec', args.output / 'project.json', '--project', args.output)
    project = args.output / (name + '.xcodeproj')
    package_lock = project / 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    package_lock.parent.mkdir(parents=True, exist_ok=True)
    write_if_changed(package_lock, (ROOT / 'Native/Terminal/Package.resolved').read_bytes())
    build_args = ['xcodebuild', '-project', project, '-scheme', name, '-derivedDataPath', args.output / 'DerivedData', '-onlyUsePackageVersionsFromResolvedFile']
    with (args.output / 'resolve.log').open('w') as log:
        run(*build_args, '-resolvePackageDependencies', stdout=log, stderr=subprocess.STDOUT)
    from prepare_visionos_swiftterm import prepare as prepare_frontend
    transforms = prepare_frontend(args.output / 'DerivedData')
    from prepare_swiftterm_build_tool import prepare
    prepare(args.output / 'DerivedData', transforms=transforms['swiftterm'])
    from dependency_checkout_provenance import verify_checkouts
    expected = json.loads((ROOT / 'Native/Terminal/Package.resolved').read_text())['pins']
    package_sources = verify_checkouts(args.output / 'DerivedData/SourcePackages', expected, transforms=transforms)
    if args.prepare_only:
        session.prepared(project)
        print(project); return
    with (args.output / 'build.log').open('w') as log:
        run(*build_args, '-sdk', args.sdk, '-destination', 'generic/platform=visionOS Simulator' if args.sdk == 'xrsimulator' else 'generic/platform=visionOS',
            '-skipPackagePluginValidation', 'build', stdout=log, stderr=subprocess.STDOUT)
    if json.loads(package_lock.read_text())['pins'] != expected:
        raise SystemExit('Package pins changed during build.')
    vnc_after = verify_source_checkout(args.source, lock['revision'])
    if vnc_after != vnc_before:
        raise SystemExit('LibVNCClient source changed during build.')
    if application_inputs(args.probe) != application_before:
        raise SystemExit('Application inputs changed during build. Rebuild the final source.')
    verify_checkouts(args.output / 'DerivedData/SourcePackages', expected, previous=package_sources, transforms=transforms)
    app = args.output / ('DerivedData/Build/Products/Debug-' + args.sdk) / (name + '.app')
    if not args.probe and plistlib.loads((app / 'Info.plist').read_bytes()).get('ITSAppUsesNonExemptEncryption') is not False:
        raise SystemExit('Built app is missing the approved export compliance metadata.')
    report = {'profile': 'maccompanion.native-visionos-development.v1',
        'sdk': args.sdk, 'toolchain': version, 'app': str(app), 'binarySHA256': digest(app / name),
        'applicationCode': {str(p.relative_to(app)): digest(p) for p in sorted(app.rglob('*'))
                            if p.is_file() and (p == app / name or p.suffix == '.dylib')},
        'libVNCClientSources': vnc_before, 'pins': expected, 'packageSources': package_sources,
        'swiftTermPressEndpoint': json.loads((ROOT / 'spec/dependency-policy/v0/direct-client-development.json').read_text())['visionOSSwiftTermPressEndpoint'],
        'applicationInputs': application_before, 'applicationInputsUnchanged': True, 'probe': args.probe,
        'installed': False, 'physicalAcceptance': False, 'releaseAdmitted': False}
    report = session.publish(report, app)
    print('Native visionOS application:', report['app'])

def configure_client(spec, name, args):
    shared_vnc = ['DirectMacLibraryV1', 'DirectMacIdentityV1', 'DirectMacDiscoveryV1', 'DirectCloudSyncV1',
        'DirectClientPlatformV1', 'DirectAppearanceV1', 'DirectProAccess', 'DirectRecoveryV1',
        'DirectSettingsComponents', 'VNCSessionPreferences', 'DirectQuickActionsEditor', 'DirectDesktopSSHTunnel']
    shared_terminal = ['DirectTerminalSession', 'TerminalSecretStore', 'TerminalSSHKey', 'TerminalKeyLibrary',
        'TerminalKeyInstallation', 'TerminalKeyboard', 'TerminalLoginSelection', 'TerminalIdentityGuide',
        'TerminalKeySettings', 'TerminalKeyInstallView', 'TerminalKeyboardSettings']
    target = spec['targets'][name]
    # Only the shipping client carries the approved outside-France declaration.
    target['info']['properties']['ITSAppUsesNonExemptEncryption'] = False
    target['sources'] += [{'path': str(ROOT / 'Native/VNC' / (p + '.swift'))} for p in shared_vnc]
    target['sources'] += [{'path': str(ROOT / 'Native/Terminal' / (p + '.swift'))} for p in shared_terminal]
    target['sources'].append({'path': str(ROOT / 'Native/Terminal/Files/DirectFilesLoginDraft.swift')})
    target['sources'] += [{'path': str(ROOT / 'Native/Mac' / (p + '.swift'))} for p in ['MacSessionStatus', 'MacTerminalHeldInput', 'MacTerminalMouseReport']]
    target['sources'].append({'path': str(ROOT / 'spec/privacy-manifest/v0/targets/ios-app/PrivacyInfo.xcprivacy'), 'buildPhase': 'resources'})
    test_settings = {'PRODUCT_BUNDLE_IDENTIFIER': 'dev.maccompanion.visionos.client.tests',
        'SWIFT_VERSION': '6.0', 'SWIFT_STRICT_CONCURRENCY': 'complete',
        'CODE_SIGNING_ALLOWED': 'YES' if args.sdk == 'xrsimulator' else 'NO', 'CODE_SIGN_IDENTITY': '-',
        'GENERATE_INFOPLIST_FILE': 'YES', 'TEST_HOST': '$(BUILT_PRODUCTS_DIR)/' + name + '.app/' + name,
        'BUNDLE_LOADER': '$(TEST_HOST)', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS': '$(inherited) MACCOMPANION_VNC_DEVELOPMENT'}
    test_settings['HEADER_SEARCH_PATHS'] = target['settings']['base']['HEADER_SEARCH_PATHS']
    spec['targets']['VisionClientTests'] = {'type': 'bundle.unit-test', 'platform': 'visionOS',
        'sources': [{'path': str(ROOT / 'Native/VisionTests/Hosted')},
            {'path': str(ROOT / 'Native/ClientTests/CredentialFormLifecycleTests.swift')},
            {'path': str(ROOT / 'spec/fixtures/direct-files-v1.json'), 'buildPhase': 'resources'},
            {'path': str(ROOT / 'Native/MacTests/Hosted/SSHTestServer.swift')},
            {'path': str(ROOT / 'spec/fixtures/native-visionos-client-v1.json'), 'buildPhase': 'resources'}],
        'dependencies': [{'target': name}],
        'settings': {'base': test_settings}}
    spec['schemes'][name]['test'] = {'targets': ['VisionClientTests']}
    spec['targets']['VisionWindowUITests'] = {'type': 'bundle.ui-testing', 'platform': 'visionOS',
        'sources': [{'path': str(ROOT / 'Native/VisionTests/UI')},
            {'path': str(ROOT / 'Native/VisionTests/Hosted/VisionSSHTestServer.swift')},
            {'path': str(ROOT / 'Native/MacTests/Hosted/SSHTestServer.swift')}],
        'dependencies': [{'target': name}, {'package': 'Citadel'}],
        'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': 'dev.maccompanion.visionos.client.uitests', 'SWIFT_VERSION': '6.0',
            'CODE_SIGNING_ALLOWED': 'YES' if args.sdk == 'xrsimulator' else 'NO', 'CODE_SIGN_IDENTITY': '-', 'GENERATE_INFOPLIST_FILE': 'YES'}}}
    spec['schemes'][name]['test']['targets'].append('VisionWindowUITests')

if __name__ == '__main__':
    main()

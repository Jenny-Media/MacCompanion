#!/usr/bin/env python3
"""Build the normal iOS app with independently admitted VNC production sources.

Generated development project; no Experimental app source is linked.
Permanent release dependency/signing gates remain authoritative.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
HERE = ROOT / "Native/VNC"
LOCK = json.loads((HERE / 'source-lock.json').read_text())

def run(*args, **kwargs):
    subprocess.run([str(x) for x in args], check=True, **kwargs)

def output(*args):
    return subprocess.check_output([str(x) for x in args], text=True).strip()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--openssl', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--sdk', choices=['iphoneos', 'iphonesimulator'], required=True)
    args = parser.parse_args()
    sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    def source_inputs():
        return {str(p.relative_to(ROOT)): sha(p) for root in [HERE, ROOT / 'Native/SessionActivity', ROOT / 'Native/Terminal', ROOT / 'Native/Dependencies', ROOT / 'Apps/MacCompanionIOS', ROOT / 'Apps/MacCompanionSessionActivity', ROOT / 'Packages/MacCompanionKit/Sources']
            for p in sorted(root.rglob('*')) if p.is_file()}
    terminal_lock = json.loads((ROOT / 'Native/Terminal/source-lock.json').read_text())
    vendor = ROOT / terminal_lock['Citadel']['localPath']
    if {str(p.relative_to(vendor)): sha(p) for p in sorted(vendor.rglob('*')) if p.is_file()} != terminal_lock['Citadel']['files']:
        raise SystemExit('Vendored SSH source does not match its recorded upstream patch hashes.')
    from verify_direct_client_dependencies import validate
    validate()
    inputs = source_inputs()
    args.output = args.output.resolve()
    if args.output.is_relative_to(ROOT):
        raise SystemExit('Generated build output must be outside the checkout.')
    if output('git', '-C', args.source, 'rev-parse', 'HEAD') != LOCK['revision']:
        raise SystemExit('Unexpected LibVNCClient revision.')
    if output('git', '-C', args.source, 'status', '--porcelain'):
        raise SystemExit('LibVNCClient source is modified.')
    provenance = json.loads((args.openssl / (args.sdk + '-provenance.json')).read_text())
    framework = args.openssl / args.sdk / 'OpenSSL.framework'
    if provenance['inputs']['source']['sha256'] != LOCK['opensslSourceSHA256']:
        raise SystemExit('Unexpected OpenSSL source provenance.')
    if provenance['inputs']['sdk'] != args.sdk or not provenance['sourceBuilt']:
        raise SystemExit('OpenSSL platform provenance mismatch.')
    for path, digest in provenance['files'].items():
        if hashlib.sha256((framework / path).read_bytes()).hexdigest() != digest:
            raise SystemExit('OpenSSL framework hash mismatch.')
    args.output.mkdir(parents=True, exist_ok=True)
    deps = args.output / 'dependencies'
    deps.mkdir(exist_ok=True)
    shutil.copytree(framework, deps / 'OpenSSL.framework', dirs_exist_ok=True)
    sdk = output('xcrun', '--sdk', args.sdk, '--show-sdk-path')
    build = args.output / 'libvncclient'
    definitions = {
        'CMAKE_SYSTEM_NAME': 'iOS', 'CMAKE_OSX_SYSROOT': sdk,
        'CMAKE_POLICY_VERSION_MINIMUM': '3.5',
        'CMAKE_OSX_ARCHITECTURES': 'arm64', 'CMAKE_OSX_DEPLOYMENT_TARGET': '26.0',
        'CMAKE_C_COMPILER': output('xcrun', '--find', 'clang'),
        'BUILD_SHARED_LIBS': 'OFF', 'WITH_OPENSSL': 'ON', 'WITH_ZLIB': 'ON',
        'OPENSSL_INCLUDE_DIR': framework / 'Headers',
        'OPENSSL_SSL_LIBRARY': framework / 'OpenSSL',
        'OPENSSL_CRYPTO_LIBRARY': framework / 'OpenSSL',
        'ZLIB_INCLUDE_DIR': Path(sdk) / 'usr/include',
        'ZLIB_LIBRARY': Path(sdk) / 'usr/lib/libz.tbd',
        'CMAKE_IGNORE_PREFIX_PATH': '/opt/homebrew',
        'WITH_LZO': 'OFF', 'WITH_JPEG': 'OFF', 'WITH_PNG': 'OFF',
        'WITH_SDL': 'OFF', 'WITH_GTK': 'OFF', 'WITH_LIBSSHTUNNEL': 'OFF',
        'WITH_GNUTLS': 'OFF', 'WITH_SYSTEMD': 'OFF', 'WITH_GCRYPT': 'OFF',
        'WITH_FFMPEG': 'OFF', 'WITH_SASL': 'OFF', 'WITH_XCB': 'OFF',
        'WITH_EXAMPLES': 'OFF', 'WITH_TESTS': 'OFF',
        'WITH_WEBSOCKETS': 'OFF', 'WITH_TIGHTVNC_FILETRANSFER': 'OFF'
    }
    run('/opt/homebrew/bin/cmake', '-S', args.source, '-B', build,
        *['-D' + k + '=' + str(v) for k, v in definitions.items()])
    run('/opt/homebrew/bin/cmake', '--build', build, '--target', 'vncclient', '-j', '6')
    resolved = args.output / 'normal-project.json'
    run('/opt/homebrew/bin/xcodegen', 'dump', '--spec', ROOT / 'project.yml', '--type', 'json', '--file', resolved, '--quiet')
    original = json.loads(resolved.read_text())
    target = original['targets']['MacCompanionIOS']
    for source in target['sources']:
        source['path'] = str(ROOT / source['path'])
        if source['path'] == str(ROOT / 'Apps/MacCompanionIOS'):
            source.setdefault('excludes', []).append('Info.plist')
    target['sources'].append({'path': str(ROOT / 'Native/SessionActivity')})
    target['sources'].append({'path': str(ROOT / 'Native/Terminal'), 'excludes': ['source-lock.json', 'Package.resolved']})
    target['sources'].append({'path': str(HERE), 'excludes': ['source-lock.json', 'CompanionVNCTransport.m', 'CompanionVNCTransport.h']})
    shutil.copyfile(args.source / 'COPYING', args.output / 'LibVNCClient-COPYING.txt')
    target['sources'].append({'path': 'LibVNCClient-COPYING.txt', 'buildPhase': 'resources'})
    target['dependencies'] = [
        {'package': 'Citadel'}, {'package': 'SwiftTerm'},
        {'framework': str(build / 'libvncclient.a'), 'embed': False},
        {'framework': str(deps / 'OpenSSL.framework'), 'embed': True, 'codeSign': False}]
    base = target['settings']['base']
    base.update({'CURRENT_PROJECT_VERSION': str(base['CURRENT_PROJECT_VERSION']),
        'INFOPLIST_FILE': str(ROOT / base['INFOPLIST_FILE']),
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS': '$(inherited) DEBUG MACCOMPANION_VNC_DEVELOPMENT',
        'SWIFT_OBJC_BRIDGING_HEADER': str(HERE / 'MacCompanionVNC-Bridging-Header.h'),
        'CLANG_ENABLE_OBJC_ARC': 'YES', 'ENABLE_DEBUG_DYLIB': 'NO', 'CODE_SIGNING_ALLOWED': 'NO',
        'HEADER_SEARCH_PATHS': [str(args.source / 'include'), str(build / 'include')],
        'LIBRARY_SEARCH_PATHS': [str(build)], 'ARCHS': 'arm64', 'ONLY_ACTIVE_ARCH': 'YES', 'OTHER_LDFLAGS': ['$(inherited)', '-lz']})
    import plistlib
    direct_info = plistlib.loads((ROOT / base['INFOPLIST_FILE']).read_bytes())
    direct_info['NSBonjourServices'] = ['_rfb._tcp']
    direct_info['NSSupportsLiveActivities'] = True
    direct_info['CFBundleURLTypes'] = [{'CFBundleURLName': 'Mac Companion Session', 'CFBundleURLSchemes': ['maccompanion-session']}]
    direct_info.pop('NSCameraUsageDescription', None)
    direct_info['NSFaceIDUsageDescription'] = 'Unlock Mac Companion to access your saved Macs and remote sessions.'
    info_path = args.output / 'DirectScreenSharing-Info.plist'
    info_path.write_bytes(plistlib.dumps(direct_info))
    base['INFOPLIST_FILE'] = str(info_path)
    if args.sdk == 'iphonesimulator':
        import plistlib
        keychain = 'dev.maccompanion.simulator.media.jenny.maccompanion.ios'
        entitlements = args.output / 'SimulatorDevelopment.entitlements'
        entitlements.write_bytes(plistlib.dumps({'application-identifier': keychain, 'keychain-access-groups': [keychain]}))
        base.update({'CODE_SIGNING_ALLOWED': 'YES', 'CODE_SIGN_IDENTITY': '-', 'CODE_SIGN_ENTITLEMENTS': str(entitlements)})
    widget = {
        'type': 'app-extension', 'platform': 'iOS',
        'sources': [{'path': str(ROOT / 'Apps/MacCompanionSessionActivity')}, {'path': str(ROOT / 'Native/SessionActivity')},
                    {'path': str(ROOT / 'spec/privacy-manifest/v0/targets/ios-app/PrivacyInfo.xcprivacy'), 'buildPhase': 'resources'}],
        'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': base['PRODUCT_BUNDLE_IDENTIFIER'] + '.session-status',
            'PRODUCT_NAME': 'MacCompanionSessionActivity', 'SWIFT_VERSION': '6.0',
            'IPHONEOS_DEPLOYMENT_TARGET': '26.0', 'TARGETED_DEVICE_FAMILY': '1,2',
            'MARKETING_VERSION': str(base['MARKETING_VERSION']), 'CURRENT_PROJECT_VERSION': str(base['CURRENT_PROJECT_VERSION']),
            'CODE_SIGNING_ALLOWED': 'YES' if args.sdk == 'iphonesimulator' else 'NO', 'CODE_SIGN_IDENTITY': '-',
            'APPLICATION_EXTENSION_API_ONLY': 'YES', 'SKIP_INSTALL': 'YES', 'ENABLE_DEBUG_DYLIB': 'NO'}},
        'info': {'path': str(args.output / 'SessionActivity-Info.plist'),
                 'properties': {'CFBundleDisplayName': 'Mac Companion Session', 'CFBundleShortVersionString': '$(MARKETING_VERSION)', 'CFBundleVersion': '$(CURRENT_PROJECT_VERSION)', 'NSExtension': {'NSExtensionPointIdentifier': 'com.apple.widgetkit-extension'}}}}
    target['dependencies'].append({'target': 'MacCompanionSessionActivity', 'embed': True, 'codeSign': False})
    spec = {'name': 'NormalVNCDevelopment', 'configs': {'Debug': 'debug'},
        'options': {**original.get('options', {}), 'createIntermediateGroups': False, 'defaultConfig': 'Debug'},
        'settings': original.get('settings', {}),
        'packages': {'Citadel': {'path': str(ROOT / 'Native/Dependencies/Citadel')}, 'SwiftTerm': {k: v for k, v in json.loads((ROOT / 'Native/Terminal/source-lock.json').read_text())['SwiftTerm'].items() if k in ['url', 'revision']}},
        'targets': {'MacCompanionIOS': target, 'MacCompanionSessionActivity': widget},
        'schemes': {'MacCompanionIOS': {'build': {'targets': {'MacCompanionIOS': 'all'}}, **{action: {'config': 'Debug'} for action in ['run', 'test', 'profile', 'analyze', 'archive']}}}}
    (args.output / 'project.json').write_text(json.dumps(spec, indent=2))
    run('/opt/homebrew/bin/xcodegen', 'generate', '--spec', args.output / 'project.json', '--project', args.output)
    package_lock = args.output / 'NormalVNCDevelopment.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    package_lock.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / 'Native/Terminal/Package.resolved', package_lock)
    with (args.output / 'build.log').open('w') as log:
        run('xcodebuild', '-project', args.output / 'NormalVNCDevelopment.xcodeproj', '-scheme', 'MacCompanionIOS',
            '-configuration', 'Debug', '-sdk', args.sdk,
            '-destination', 'generic/platform=iOS Simulator' if args.sdk == 'iphonesimulator' else 'generic/platform=iOS',
            '-derivedDataPath', args.output / 'DerivedData', '-onlyUsePackageVersionsFromResolvedFile', '-skipPackagePluginValidation', 'build', stdout=log, stderr=subprocess.STDOUT)
    expected_pins = json.loads((ROOT / 'Native/Terminal/Package.resolved').read_text())['pins']
    if json.loads(package_lock.read_text())['pins'] != expected_pins:
        raise SystemExit('Resolved terminal package revisions changed during build.')
    app = args.output / ('DerivedData/Build/Products/Debug-' + args.sdk) / 'Mac Companion.app'
    if inputs != source_inputs():
        raise SystemExit('Application sources changed during the build. Rebuild the final sources.')
    (args.output / 'build-report.json').write_text(json.dumps({'profile': 'maccompanion.normal-ios-direct-screen-sharing-development.v1',
        'normalSourceRoot': True, 'releaseAdmitted': False, 'sdk': args.sdk, 'app': str(app),
        'upstream': LOCK, 'terminalDependencies': terminal_lock, 'terminalPackagePins': expected_pins, 'libVNCClientSHA256': sha(build / 'libvncclient.a'), 'inputs': inputs,
        'normalApplicationBinarySHA256': sha(app / 'Mac Companion'), 'installed': False}, indent=2))
    print('Normal VNC app:', app)

if __name__ == '__main__':
    main()

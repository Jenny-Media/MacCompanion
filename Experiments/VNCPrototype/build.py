#!/usr/bin/env python3
"""Build an isolated iOS RFB client. All generated files stay outside the checkout."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
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
    parser.add_argument('--display-layout', type=Path)
    args = parser.parse_args()
    args.output = args.output.resolve()
    if args.output.is_relative_to(HERE.parents[1]):
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
    sources = [{'path': str(HERE / 'Sources')}]
    shutil.copyfile(args.source / 'COPYING', args.output / 'LibVNCClient-COPYING.txt')
    sources.append({'path': 'LibVNCClient-COPYING.txt', 'buildPhase': 'resources'})
    if args.display_layout:
        # Private host geometry is a generated resource, never authoring data.
        layout = json.loads(args.display_layout.read_text())
        (args.output / 'DisplayLayout.json').write_text(json.dumps(layout))
        sources.append({'path': 'DisplayLayout.json', 'buildPhase': 'resources'})
    spec = {
        'name': 'VNCPrototype',
        'options': {'deploymentTarget': {'iOS': '26.0'}},
        'targets': {'VNCPrototype': {
            'type': 'application', 'platform': 'iOS', 'sources': sources,
            'info': {'path': 'Info.plist', 'properties': {
                'CFBundleDisplayName': 'VNC Prototype',
                'NSLocalNetworkUsageDescription': 'Connect this test viewer to your Mac’s Screen Sharing service on your local network.',
                'NSBonjourServices': ['_rfb._tcp'],
                'UILaunchScreen': {},
                'UIApplicationSceneManifest': {
                    'UIApplicationSupportsMultipleScenes': False,
                    'UISceneConfigurations': {'UIWindowSceneSessionRoleApplication': [{
                        'UISceneConfigurationName': 'Default', 'UISceneDelegateClassName': 'SceneDelegate'
                    }]}
                },
                'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight']
            }},
            'settings': {'base': {
                'PRODUCT_BUNDLE_IDENTIFIER': 'dev.maccompanion.vnc-prototype',
                'CLANG_ENABLE_OBJC_ARC': 'YES', 'ENABLE_DEBUG_DYLIB': 'NO',
                'CODE_SIGNING_ALLOWED': 'NO', 'TARGETED_DEVICE_FAMILY': '1,2',
                'HEADER_SEARCH_PATHS': [str(args.source / 'include'), str(build / 'include')],
                'LIBRARY_SEARCH_PATHS': [str(build)],
                'OTHER_LDFLAGS': ['-lz'], 'MARKETING_VERSION': '0.1', 'CURRENT_PROJECT_VERSION': '1'
            }},
            'dependencies': [
                {'framework': str(build / 'libvncclient.a'), 'embed': False},
                {'framework': 'dependencies/OpenSSL.framework', 'embed': True, 'codeSign': False}
            ]
        }, 'VNCLifecycleTests': {
            'type': 'bundle.ui-testing', 'platform': 'iOS',
            'sources': [{'path': str(HERE / 'UITests')}],
            'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': 'dev.maccompanion.vnc-prototype.uitests',
                                  'CODE_SIGNING_ALLOWED': 'NO', 'GENERATE_INFOPLIST_FILE': 'YES'}},
            'dependencies': [{'target': 'VNCPrototype'}]
        }},
        'schemes': {'VNCPrototype': {
            'build': {'targets': {'VNCPrototype': 'all', 'VNCLifecycleTests': ['test']}},
            'test': {'targets': [{'name': 'VNCLifecycleTests'}]}
        }}
    }
    (args.output / 'project.json').write_text(json.dumps(spec, indent=2))
    run('/opt/homebrew/bin/xcodegen', 'generate', '--spec', args.output / 'project.json', '--project', args.output)
    inputs = {str(p.relative_to(HERE)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted(HERE.rglob('*')) if p.is_file() and '__pycache__' not in str(p)}
    (args.output / 'build-inputs.json').write_text(json.dumps({
        'authoring': inputs, 'upstream': LOCK, 'sdk': args.sdk,
        'opensslInputs': provenance['inputs'], 'releaseAdmitted': False
    }, indent=2))
    print('Prototype project:', args.output / 'VNCPrototype.xcodeproj')

if __name__ == '__main__':
    main()

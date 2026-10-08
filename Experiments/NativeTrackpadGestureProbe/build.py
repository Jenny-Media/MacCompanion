#!/usr/bin/env python3
"""Build a disposable macOS loopback probe; outputs must stay outside the repo."""
import argparse
import json
import pathlib
import plistlib
import shutil
import subprocess

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]

def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=pathlib.Path, required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    if out.is_relative_to(REPO):
        raise SystemExit('Build output must be outside the repository.')
    lock = json.loads((REPO / 'Experiments/VNCPrototype/source-lock.json').read_text())
    revision = subprocess.check_output(['git', '-C', str(args.source), 'rev-parse', 'HEAD'], text=True).strip()
    status = subprocess.check_output(['git', '-C', str(args.source), 'status', '--porcelain'], text=True)
    if revision != lock['revision'] or status:
        raise SystemExit('Requires the unmodified, pinned LibVNCClient source.')
    out.mkdir(parents=True, exist_ok=True)
    build = out / 'libvncclient'
    sdk_version = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-version'], text=True).strip()
    definitions = {
        'CMAKE_POLICY_VERSION_MINIMUM': '3.5',
        'CMAKE_OSX_DEPLOYMENT_TARGET': sdk_version,
        'BUILD_SHARED_LIBS': 'OFF', 'WITH_OPENSSL': 'ON', 'WITH_ZLIB': 'ON',
        'OPENSSL_ROOT_DIR': '/opt/homebrew/opt/openssl@3',
        'WITH_LZO': 'OFF', 'WITH_JPEG': 'OFF', 'WITH_PNG': 'OFF', 'WITH_SDL': 'OFF',
        'WITH_GTK': 'OFF', 'WITH_LIBSSHTUNNEL': 'OFF', 'WITH_GNUTLS': 'OFF',
        'WITH_SYSTEMD': 'OFF', 'WITH_GCRYPT': 'OFF', 'WITH_FFMPEG': 'OFF',
        'WITH_SASL': 'OFF', 'WITH_XCB': 'OFF', 'WITH_EXAMPLES': 'OFF',
        'WITH_TESTS': 'OFF', 'WITH_WEBSOCKETS': 'OFF', 'WITH_TIGHTVNC_FILETRANSFER': 'OFF',
    }
    run('/opt/homebrew/bin/cmake', '-S', args.source, '-B', build,
        *[f'-D{k}={v}' for k, v in definitions.items()])
    run('/opt/homebrew/bin/cmake', '--build', build, '--target', 'vncclient', '-j', '6')
    app = out / 'NativeGestureProbe.app'
    executable = app / 'Contents/MacOS/NativeGestureProbe'
    executable.parent.mkdir(parents=True, exist_ok=True)
    resources = app / 'Contents/Resources'
    resources.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(args.source / 'COPYING', resources / 'LibVNCClient-COPYING.txt')
    with (app / 'Contents/Info.plist').open('wb') as stream:
        plistlib.dump({
            'CFBundleIdentifier': 'dev.maccompanion.experiment.native-gesture-probe',
            'CFBundleName': 'Native Gesture Probe', 'CFBundleExecutable': 'NativeGestureProbe',
            'CFBundlePackageType': 'APPL', 'NSHighResolutionCapable': True,
            'NSPrincipalClass': 'ProbeApplication',
            'LSMinimumSystemVersion': sdk_version,
        }, stream)
    run('xcrun', 'clang', '-fobjc-arc', '-fblocks', '-Wall', '-Wextra',
        '-Wno-unused-parameter', '-mmacosx-version-min=' + sdk_version,
        '-I' + str(args.source / 'include'), '-I' + str(build / 'include'),
        HERE / 'Probe.m', build / 'libvncclient.a',
        '-L/opt/homebrew/opt/openssl@3/lib', '-lssl', '-lcrypto', '-lz',
        '-framework', 'AppKit', '-framework', 'CoreGraphics', '-o', executable)
    run('/usr/bin/codesign', '--force', '--sign', '-', app)
    print(app)

if __name__ == '__main__':
    main()

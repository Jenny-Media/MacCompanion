#!/usr/bin/env python3
"""Generate/build an isolated macOS package, with existing dependency pins."""
import argparse
import json
import pathlib
import plistlib
import shutil
import subprocess

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]

def main():
    parser = argparse.ArgumentParser()
    for name in ('output', 'vnc-source', 'vnc-build', 'openssl'):
        parser.add_argument('--' + name, type=pathlib.Path, required=True)
    args = parser.parse_args()
    out, source, vnc, ssl = [p.resolve() for p in (args.output, args.vnc_source, args.vnc_build, args.openssl)]
    if out.is_relative_to(REPO):
        raise SystemExit('Outputs must be outside the checkout.')
    lock = json.loads((REPO / 'Native/VNC/source-lock.json').read_text())
    revision = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != lock['revision'] or subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain'], text=True).strip():
        raise SystemExit('Requires clean pinned LibVNCClient source.')
    package = out / 'Package'; package.mkdir(parents=True, exist_ok=True)
    for name in ('Sources', 'Tests'):
        shutil.copytree(HERE / name, package / name, dirs_exist_ok=True)
    shutil.copyfile(REPO / 'Native/Terminal/Package.resolved', package / 'Package.resolved')
    def literal(value):
        return json.dumps(str(value))
    manifest = '''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "SSHScreenSharingProbe", platforms: [.macOS("26.0")],
    dependencies: [.package(path: CITADEL),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/Wellz26/swift-nio-ssh.git", "0.3.4" ..< "0.4.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.12.3")],
    targets: [
        .target(name: "Tunnel", dependencies: [.product(name: "Citadel", package: "Citadel"),
            .product(name: "NIO", package: "swift-nio"), .product(name: "NIOSSH", package: "swift-nio-ssh")]),
        .target(name: "CRFBProbe", cSettings: [.unsafeFlags(["-I" + VNC_SOURCE, "-I" + VNC_INCLUDE])],
            linkerSettings: [.unsafeFlags([VNC_LIBRARY, SSL_LIBRARY, CRYPTO_LIBRARY, "-lz"])]),
        .executableTarget(name: "Probe", dependencies: ["Tunnel", "CRFBProbe"]),
        .testTarget(name: "TunnelTests", dependencies: ["Tunnel", .product(name: "Crypto", package: "swift-crypto"),
            .product(name: "NIOEmbedded", package: "swift-nio"), .product(name: "NIOSSH", package: "swift-nio-ssh")])])
'''
    substitutions = {'CITADEL': REPO / 'Native/Dependencies/Citadel', 'VNC_SOURCE': source / 'include',
        'VNC_INCLUDE': vnc / 'include', 'VNC_LIBRARY': vnc / 'libvncclient.a',
        'SSL_LIBRARY': ssl / 'libssl.a', 'CRYPTO_LIBRARY': ssl / 'libcrypto.a'}
    for token, path in substitutions.items():
        manifest = manifest.replace(token, literal(path))
    (package / 'Package.swift').write_text(manifest)
    subprocess.run(['swift', 'build', '--package-path', str(package), '--disable-sandbox', '-j', '6'], check=True)
    binary_path = subprocess.check_output(['swift', 'build', '--package-path', str(package), '--show-bin-path'], text=True).strip()
    app = out / 'SSHScreenSharingProbe.app'; contents = app / 'Contents'
    (contents / 'MacOS').mkdir(parents=True, exist_ok=True)
    (contents / 'Resources').mkdir(exist_ok=True)
    shutil.copyfile(pathlib.Path(binary_path) / 'Probe', contents / 'MacOS/Probe')
    (contents / 'MacOS/Probe').chmod(0o755)
    shutil.copyfile(source / 'COPYING', contents / 'Resources/LibVNCClient-COPYING.txt')
    with (contents / 'Info.plist').open('wb') as stream:
        plistlib.dump({'CFBundleIdentifier': 'dev.maccompanion.experiment.ssh-screen-sharing',
            'CFBundleName': 'SSH Screen Sharing Probe', 'CFBundleExecutable': 'Probe',
            'CFBundlePackageType': 'APPL', 'NSHighResolutionCapable': True,
            'ProbeResultPath': str(out / 'result.json'),
            'LSMinimumSystemVersion': '26.0'}, stream)
    subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(app)], check=True)
    print(app)

if __name__ == '__main__':
    main()

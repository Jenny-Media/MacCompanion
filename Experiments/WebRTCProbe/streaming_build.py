#!/usr/bin/env python3
"""Build the isolated round-trip executable from the exactly admitted framework."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from build import inspect_archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', required=True, type=Path)
    args = parser.parse_args()
    inspect_archive(args.archive)
    root = Path(tempfile.mkdtemp(prefix='maccompanion-webrtc-stream-', dir='/private/tmp'))
    print(root, flush=True)
    subprocess.run(['ditto', '-xk', str(args.archive.resolve()), str(root/'sdk')], check=True)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    framework = root/'sdk/WebRTC.xcframework/macos-x86_64_arm64'
    source = Path(__file__).resolve().parent
    frozen = root/'Sources'
    frozen.mkdir()
    names = ['MediaPeer.swift', 'SyntheticFrames.swift', 'RoundTripMain.swift']
    for name in names: shutil.copy2(source/name, frozen/name)
    (root/'source-hashes.json').write_text(json.dumps(
        {name: hashlib.sha256((frozen/name).read_bytes()).hexdigest() for name in names}, indent=2)+'\n')
    command = ['xcrun', '--sdk', 'macosx', 'swiftc', '-O', '-swift-version', '6', '-parse-as-library',
        '-sdk', sdk, '-target', 'arm64-apple-macosx26.0', '-F', str(framework), '-framework', 'WebRTC',
        '-module-cache-path', str(root/'module-cache'), '-o', str(root/'round-trip'),
        '-Xlinker', '-rpath', '-Xlinker', str(framework)]
    command += [str(frozen/name) for name in names]
    result = subprocess.run(command, text=True, capture_output=True)
    (root/'build.log').write_text(result.stdout+result.stderr)
    if result.returncode: print(result.stderr)
    result.check_returncode()
    print('Built '+str(root/'round-trip'), flush=True)


if __name__ == '__main__': main()

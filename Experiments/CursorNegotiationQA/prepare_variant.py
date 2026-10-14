#!/usr/bin/env python3
"""Prepare disposable exact-source cursor negotiation comparisons, never release targets."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--variant', choices=['combined', 'apple', 'standard'], required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
output = args.output.resolve()
if not output.is_relative_to(Path('/private/tmp')) or output.exists():
    raise SystemExit('Use a fresh output directory under /private/tmp.')
paths = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=ROOT)
source = output / 'source'
for encoded in paths.split(b'\0'):
    if not encoded:
        continue
    relative = Path(encoded.decode())
    original = ROOT / relative
    if not original.is_file() or original.is_symlink():
        raise SystemExit('Only regular admitted repository sources may be copied.')
    destination = source / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(original, destination)
path = source / 'Native/VNC/CompanionVNCSession.m'
baseline = path.read_text()
content = baseline
if args.variant == 'apple':
    assert content.count('client->appData.useRemoteCursor = TRUE;') == 1
    content = content.replace('client->appData.useRemoteCursor = TRUE;', 'client->appData.useRemoteCursor = FALSE;')
    identifier = 1
elif args.variant == 'standard':
    needle = 'static int layoutEncodings[] = {1101,\n#if TARGET_OS_OSX || TARGET_OS_IOS\n    1104,\n#endif\n    1105, 0};'
    assert content.count(needle) == 1
    content = content.replace(needle, 'static int layoutEncodings[] = {1101, 1105, 0};')
    identifier = 2
else:
    identifier = 0
marker = 'NSDictionary *stats = @{@"connectionStarts": @(_connections),'
assert content.count(marker) == 1
content = content.replace(marker, 'NSDictionary *stats = @{@"cursorNegotiationVariant": @(' + str(identifier) + '), @"connectionStarts": @(_connections),')
path.write_text(content)
# Bind the exact implementation and record only numeric format choices and hashes.
metadata = {'variant': args.variant, 'numericID': identifier,
            'sourceRoot': str(source), 'baselineSessionSHA256': hashlib.sha256(baseline.encode()).hexdigest(),
            'variantSessionSHA256': hashlib.sha256(content.encode()).hexdigest(),
            'expectedCursorEncodings': [-240, -239, -232, 1104] if identifier == 0 else [1104] if identifier == 1 else [-240, -239, -232],
            'preservedDisplayEncodings': [1101, 1105],
            'authenticationChanged': False, 'frameRequestsChanged': False}
(output / 'variant.json').write_text(json.dumps(metadata, indent=2) + '\n')
print(json.dumps(metadata))

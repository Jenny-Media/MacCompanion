#!/usr/bin/env python3
"""Verify display/cursor geometry and smart zoom from the sole fixture index."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
fixtures = ROOT / "spec/fixtures"
manifest = json.loads((fixtures / "manifest.json").read_text())
entry = next(x for x in manifest["fixtures"] if x["path"] == "vnc-desktop-tunnel-v0.1.json")
assert entry["expect"] == "valid"
profile = json.loads((fixtures / entry["path"]).read_text())
rect = lambda a: 'CGRectMake(' + ','.join(map(str, a)) + ')'
size = lambda a: 'CGSizeMake(' + ','.join(map(str, a)) + ')'
point = lambda a: 'CGPointMake(' + ','.join(map(str, a)) + ')'
checks = []
for case in profile['viewportCases']:
    call = f"CompanionVNCViewportRect({size(case['framebuffer'])}, {rect(case['normalized'])}, {str(case['selected']).lower()}, {case['aspect']})"
    checks.append(f"assert(CGRectIsNull({call}));" if case['rect'] is None else f"assert(CGRectEqualToRect({call}, {rect(case['rect'])}));")
for case in profile['viewportPointerCases']:
    call = f"CompanionVNCPointerPoint({rect(case['rect'])}, {point(case['point'])}, {str(case['clamp']).lower()}, &mapped)"
    checks.append(f"assert({call} == {str(case['mapped'] is not None).lower()});")
    if case['mapped'] is not None: checks.append(f"assert(CGPointEqualToPoint(mapped, {point(case['mapped'])}));")
for case in profile['windowFitCases']:
    call = f"CompanionVNCWindowInCrop({rect(case['crop'])}, {rect(case['window'])})"
    checks.append(f"assert(CGRectIsNull({call}));" if case['local'] is None else f"assert(CGRectEqualToRect({call}, {rect(case['local'])}));")
for case in profile['cursorPositionCases']:
    call = f"CompanionVNCCursorLocalPoint({rect(case['crop'])}, {point(case['point'])}, &mapped)"
    checks.append(f"assert({call} == {str(case['local'] is not None).lower()});")
    if case['local'] is not None: checks.append(f"assert(CGPointEqualToPoint(mapped, {point(case['local'])}));")
for case in profile['cursorScreenCases']:
    call = f"CompanionVNCCursorScreenRect({point(case['anchor'])}, {size(case['size'])}, {point(case['hotspot'])}, {case['zoom']})"
    checks.append(f"assert(CGRectIsNull({call}));" if case['rect'] is None else f"assert(CGRectEqualToRect({call}, {rect(case['rect'])}));")
for index, case in enumerate(profile['cursorPixelCases']):
    array = lambda values: ','.join(map(str, values)) or '0'
    checks.append('{ ' + f"uint8_t source[] = {{{array(case['source'])}}}, mask[] = {{{array(case['mask'])}}}, rgba[16] = {{0}};")
    call = f"CompanionVNCCursorRGBA({case['size'][0]}, {case['size'][1]}, {case['bytesPerPixel']}, {case['hotspot'][0]}, {case['hotspot'][1]}, source, {len(case['source'])}, mask, {len(case['mask'])}, rgba, sizeof(rgba))"
    checks.append(f"assert({call} == {str(case['rgba'] is not None).lower()});")
    if case['rgba'] is not None:
        checks.append(f"const uint8_t expected[] = {{{array(case['rgba'])}}}; assert(memcmp(rgba, expected, sizeof(expected)) == 0);")
    checks.append('}')
for case in profile['smartZoomCases']:
    call = f"CompanionVNCSmartZoomRect({size(case['cropSize'])}, {size(case['canvasSize'])}, {point(case['point'])}, {case['minimumZoom']}, {case['maximumZoom']})"
    checks.append(f"assert(CGRectIsNull({call}));" if case['rect'] is None else f"assert(CGRectEqualToRect({call}, {rect(case['rect'])}));")
direct_entry = next(x for x in manifest['fixtures'] if x['path'] == 'direct-screen-sharing-v1.json')
assert direct_entry['expect'] == 'valid'
direct = json.loads((fixtures / direct_entry['path']).read_text())
for case in direct['followCursorCases']:
    call = f"CompanionVNCFollowOffset({size(case['content'])}, {rect(case['viewport'])}, {point(case['cursor'])})"
    checks.append(f"mapped = {call}; assert(fabs(mapped.x - {case['offset'][0]}) < .0001 && fabs(mapped.y - {case['offset'][1]}) < .0001);")
source = '\n'.join(['#include <assert.h>', '#include <string.h>', '#include "CompanionVNCViewport.h"', '#include "CompanionVNCCursor.h"',
    'int main(void) { CGPoint mapped;', *checks, 'return 0; }'])
with tempfile.TemporaryDirectory(prefix='maccompanion-vnc-viewport-') as directory:
    path = Path(directory); (path/'test.c').write_text(source)
    subprocess.run(['xcrun', 'clang', '-std=c11', '-Wall', '-Wextra', '-Werror',
        '-framework', 'CoreGraphics', '-I', str(ROOT/'Native/VNC'), str(path/'test.c'), '-o', str(path/'test')], check=True)
    subprocess.run([str(path/'test')], check=True)
print('VNC viewport: indexed display crops, pointer/cursor mapping, RGBA masks, readable hotspots, smart-zoom and follow-cursor bounds passed')

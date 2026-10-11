#!/usr/bin/env python3
"""Execute the authoritative local OCR pixel-selection and work bounds."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / 'spec/fixtures/manifest.json').read_text())
entry = next(f for f in manifest['fixtures'] if f['path'] == 'direct-screen-sharing-v1.json')
assert entry['expect'] == 'valid'
fixture = json.loads((ROOT / 'spec/fixtures' / entry['path']).read_text())
checks = []
for case in fixture['copyTextGeometryCases']:
    call = 'CompanionVNCTextPixelRect(CGSizeMake(%s), CGRectMake(%s))' % (
        ','.join(map(str, case['size'])), ','.join(map(str, case['selection'])))
    checks.append('assert(CGRectIsNull(%s));' % call if case['pixels'] is None else
                  'assert(CGRectEqualToRect(%s, CGRectMake(%s)));' % (call, ','.join(map(str, case['pixels']))))
for case in fixture['copyTextBoundsCases']:
    checks.append('assert(CompanionVNCTextAreaFits(CGSizeMake(%s)) == %s);' % (
        ','.join(map(str, case['size'])), str(case['fits']).lower()))
checks += ['assert(CGRectIsNull(CompanionVNCTextPixelRect(CGSizeMake(10,10),CGRectMake(NAN,0,1,1))));',
           'assert(!CompanionVNCTextAreaFits(CGSizeMake(INFINITY,1)));']
with tempfile.TemporaryDirectory(prefix='maccompanion-copy-text-') as folder:
    p = Path(folder)
    (p / 'test.c').write_text('#include <assert.h>\n#include "CompanionVNCTextGeometry.h"\nint main(void) {\n' + '\n'.join(checks) + '\n}\n')
    subprocess.run(['xcrun', 'clang', '-Wall', '-Wextra', '-Werror', '-framework', 'CoreGraphics',
                    '-I', str(ROOT / 'Native/VNC'), str(p / 'test.c'), '-o', str(p / 'test')], check=True)
    subprocess.run([str(p / 'test')], check=True)
print('Copy Text: indexed original-pixel selection and bounded recognition geometry passed')

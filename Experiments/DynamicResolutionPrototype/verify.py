#!/usr/bin/env python3
"""Consume the sole indexed fixture corpus and compile the bounded wire builder."""
import hashlib, json, pathlib, subprocess, tempfile
from prepare_runtime import prepare, ROOT, HERE
from summarize import summarize

manifest = json.loads((ROOT / 'spec/fixtures/manifest.json').read_text())
entry = next(x for x in manifest['fixtures'] if x['path'] == 'ios-dynamic-resolution-prototype-v1.json')
fixture = json.loads((ROOT / 'spec/fixtures' / entry['path']).read_text())
assert hashlib.sha256(json.dumps(fixture,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest() == entry['canonicalSHA256']
for case in fixture['analysisCases']:
    result=summarize(case['rows'])
    for key,value in case.items():
        if key!='rows': assert result[key]==value,(key,result[key],value)
subprocess.run(['python3', str(ROOT/'scripts/verify_vnc_desktop_size.py')], check=True)
checks = []
for row in fixture['packetCases']:
    expected = ','.join(str(x) for x in bytes.fromhex(row['hex']))
    w,h = row['points']
    checks.append(f'{{ uint8_t p[196], e[] = {{{expected}}}; assert(MCDynamicDisplayPacket((MCDynamicSize){{{w},{h}}},p,sizeof(p))); assert(memcmp(p,e,196)==0); }}')
for w,h in fixture['invalidPacketSizes']:
    checks.append(f'assert(!MCDynamicDisplayPacket((MCDynamicSize){{(uint16_t){w},(uint16_t){h}}},p,sizeof(p)));')
for row in fixture['viewportCases']:
    w,h = row['viewport']; size = row['points']
    checks.append(f'assert(MCDynamicSizeForViewport({w},{h},&s)=={str(size is not None).lower()});')
    if size: checks.append(f'assert(s.width=={size[0]} && s.height=={size[1]});')
for row in fixture['selectionPackets']:
    expected = ','.join(str(x) for x in bytes.fromhex(row['hex']))
    checks.append(f'{{ uint8_t e[] = {{{expected}}}; MCDynamicSelectionPacket({row["id"]},p); assert(memcmp(p,e,8)==0); }}')
source = '\n'.join(['#include <assert.h>', '#include "DynamicDisplay.h"','int main(void){ uint8_t p[196]; MCDynamicSize s;',*checks,'assert(!MCDynamicSizeForViewport(NAN,400,&s)); assert(!MCDynamicSizeForViewport(INFINITY,400,&s)); return 0; }'])
with tempfile.TemporaryDirectory(prefix='maccompanion-resolution-wire-') as tmp:
    p = pathlib.Path(tmp); (p/'wire.c').write_text(source)
    subprocess.run(['xcrun','clang','-std=c11','-Wall','-Wextra','-Werror','-I',str(HERE),str(p/'wire.c'),'-o',str(p/'wire')],check=True)
    subprocess.run([str(p/'wire')],check=True)
    prepare(p/'runtime')
    session = (p/'runtime/CompanionVNCSession.m').read_text()
    assert session.index('[self processDesktopSizeChange:client]') < session.index('healthy = [self configureDesktopUpdates:client]')
print('Indexed dynamic-display wire vectors, bounds, selection, nonfinite rejection and isolated runtime preparation passed')

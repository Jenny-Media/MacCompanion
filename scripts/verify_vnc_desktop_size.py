#!/usr/bin/env python3
"""Compile the native bounded builder against the sole indexed wire vectors."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / 'spec/fixtures/manifest.json').read_text())
entry = next(row for row in manifest['fixtures'] if row['path'] == 'ios-dynamic-resolution-prototype-v1.json')
fixture = json.loads((ROOT / 'spec/fixtures' / entry['path']).read_text())
canonical = json.dumps(fixture, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()
assert hashlib.sha256(canonical).hexdigest() == entry['canonicalSHA256']
checks = []
for row in fixture['packetCases'] + fixture['landscapePresets']:
    expected = ','.join(str(x) for x in bytes.fromhex(row['hex']))
    w, h = row['points']
    checks.append(f'{{ uint8_t e[]={{{expected}}}; assert(CompanionVNCDesktopDisplayPacket((CompanionVNCDesktopSize){{{w},{h}}},p,sizeof(p))); assert(!memcmp(p,e,sizeof(e))); }}')
    if 'id' in row:
        checks.append(f'assert(CompanionVNCDesktopSizeForPreset({row["id"]},&s) && s.width=={w} && s.height=={h} && s.width>s.height);')
for w, h in fixture['invalidPacketSizes']:
    checks.append(f'assert(!CompanionVNCDesktopDisplayPacket((CompanionVNCDesktopSize){{(uint16_t){w},(uint16_t){h}}},p,sizeof(p)));')
for row in fixture['viewportCases']:
    w, h = row['viewport']
    size = row['points']
    checks.append(f'assert(CompanionVNCDesktopSizeForViewport({w},{h},&s)=={str(size is not None).lower()});')
    if size:
        checks.append(f'assert(s.width=={size[0]} && s.height=={size[1]});')
for row in fixture['selectionPackets']:
    expected = ','.join(str(x) for x in bytes.fromhex(row['hex']))
    checks.append(f'{{ uint8_t e[]={{{expected}}}; CompanionVNCDesktopSelectionPacket({row["id"]},p); assert(!memcmp(p,e,sizeof(e))); }}')
catalogue = fixture['selectedCatalogueLayouts']
expected = ','.join(str(x) for x in bytes.fromhex(catalogue['catalogueHex']))
checks.append(f'uint8_t catalogueBytes[]={{{expected}}}; CompanionVNCDisplayLayout catalogue; assert(CompanionVNCDecodeDisplayLayout(catalogueBytes,sizeof(catalogueBytes),&catalogue));')
for row in catalogue['cases']:
    raw = ','.join(str(x) for x in bytes.fromhex(row['bodyHex']))
    accepted = str(row['accepted']).lower()
    check = f'{{ uint8_t b[]={{{raw}}}; CompanionVNCDisplayLayout result={{0}}, original=result; assert(CompanionVNCDecodeSelectedDisplayLayout(b,sizeof(b),{row["requestedID"]},&catalogue,&result)=={accepted});'
    if row['accepted']:
        dimensions = catalogue['externalStreamPixels' if row['requestedID'] == 5 else 'internalStreamPixels']
        check += f' assert(result.count==1 && result.displays[0].id=={row["requestedID"]} && result.displays[0].x==0 && result.displays[0].y==0 && result.width=={dimensions[0]} && result.height=={dimensions[1]});'
        check += ' (void)original; assert(!CompanionVNCDecodeSelectedDisplayLayout(b,sizeof(b),0,&catalogue,&result)); assert(!CompanionVNCDecodeSelectedDisplayLayout(b,sizeof(b),999,&catalogue,&result)); assert(!CompanionVNCDecodeSelectedDisplayLayout(b,sizeof(b),5,NULL,&result));'
        check += ' for(size_t length=0;length<sizeof(b);length++) { CompanionVNCDisplayLayout untouched={0}, result=untouched; assert(!CompanionVNCDecodeSelectedDisplayLayout(b,length,5,&catalogue,&result)); assert(!memcmp(&result,&untouched,sizeof(result))); }'
        check += ' assert(!CompanionVNCDecodeSelectedDisplayLayout(b,(size_t)UINT16_MAX+1,5,&catalogue,&result));'
        # A selected catalogue is not an ordinary all-display canvas.
        check += ' assert(!CompanionVNCDecodeDisplayLayout(b,sizeof(b),&result));'
    else:
        check += ' assert(!memcmp(&result,&original,sizeof(result)));'
    checks.append(check + ' }')
for row in fixture['baselineRefreshPolicy']['cases']:
    expected = 2 if row['expired'] else 1 if row['retry'] else 0
    checks.append(f'assert(CompanionVNCBaselineRefreshAction({row["elapsed"]},{row["lastRequestAge"]},{row["lastProgressAge"]},{row["retries"]})=={expected});')
for row in fixture['displayLayoutDeadlineCases']:
    checks.append(f'assert(CompanionVNCDesktopLayoutTimedOut({row["elapsed"]},{str(row["exactLayout"]).lower()})=={str(row["timedOut"]).lower()});')
for row in fixture['virtualLayoutDeadlineCases']:
    checks.append(f'assert(CompanionVNCVirtualLayoutTimedOut({row["elapsed"]},{str(row["exactLayout"]).lower()})=={str(row["timedOut"]).lower()});')
source = '\n'.join(['#include <assert.h>', '#include "CompanionVNCDesktopSize.h"',
    'int main(void){ uint8_t p[196]; CompanionVNCDesktopSize s;', *checks,
    'assert(!CompanionVNCDesktopSizeForPreset(0,&s)); assert(!CompanionVNCDesktopSizeForPreset(4,&s));',
    'assert(CompanionVNCDesktopLayoutTimedOut(NAN,true)); assert(CompanionVNCDesktopLayoutTimedOut(INFINITY,false)); assert(!CompanionVNCDesktopSizeForViewport(NAN,400,&s)); assert(!CompanionVNCDesktopSizeForViewport(INFINITY,400,&s)); return 0; }'])
with tempfile.TemporaryDirectory(prefix='maccompanion-desktop-size-') as tmp:
    folder = Path(tmp)
    (folder / 'wire.c').write_text(source)
    subprocess.run(['xcrun', 'clang', '-std=c11', '-Wall', '-Wextra', '-Werror', '-I', str(ROOT / 'Native/VNC'), str(folder / 'wire.c'), '-o', str(folder / 'wire')], check=True)
    subprocess.run([str(folder / 'wire')], check=True)
print('Native desktop-size presets, golden packets, selected-catalogue responses and resource bounds passed')

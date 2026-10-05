#!/usr/bin/env python3
"""Exercise actual native endpoint/login bounds against the sole fixture index."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / 'spec/fixtures/manifest.json').read_text())
assert any(f['path'] == 'direct-screen-sharing-v1.json' for f in manifest['fixtures'])
profile = json.loads((ROOT / 'spec/fixtures/direct-screen-sharing-v1.json').read_text())
checks = []
for c in profile['addressCases']:
    checks.append('''{ struct sockaddr_storage storage = {0}; const char *address = %s;
    struct sockaddr_in *v4 = (void *)&storage; struct sockaddr_in6 *v6 = (void *)&storage;
    if (strchr(address, ':')) { v6->sin6_family = AF_INET6; v6->sin6_scope_id = %d; assert(inet_pton(AF_INET6, address, &v6->sin6_addr) == 1); }
    else { v4->sin_family = AF_INET; assert(inet_pton(AF_INET, address, &v4->sin_addr) == 1); }
    assert(CompanionVNCLocalEndpoint((void *)&storage, sizeof(storage)) == %s); }''' % (json.dumps(c['address']), c['scope'], str(c['valid']).lower()))
for c in profile['portCases']:
    checks.append('assert(CompanionVNCPortValid(%d) == %s);' % (c['port'], str(c['valid']).lower()))
for c in profile['loginCases']:
    b = c['value'].encode(); values = ','.join(str(v) for v in b) or '0'
    checks.append('{ const char bytes[] = {%s}; assert(CompanionVNCLoginBytes(bytes, %d) == %s); }' % (values, len(b), str(c['valid']).lower()))
for c in profile['displayLayoutCases']:
    b = bytes.fromhex(c['bodyHex']); values = ','.join(str(v) for v in b)
    checks.append('{ const uint8_t bytes[] = {%s}; CompanionVNCDisplayLayout layout; assert(CompanionVNCDecodeDisplayLayout(bytes, sizeof(bytes), &layout) == %s);' % (values, str(c['valid']).lower()))
    if c['valid']:
        checks.append('assert(layout.width == %d && layout.height == %d && layout.count == %d);' % (*c['backing'], len(c['screens'])))
        for i,(did,x,y,right,bottom) in enumerate(c['screens']):
            checks.append('assert(layout.displays[%d].id == %d && layout.displays[%d].x == %d && layout.displays[%d].y == %d && layout.displays[%d].width == %d && layout.displays[%d].height == %d);' % (i,did,i,x,i,y,i,right-x,i,bottom-y))
    checks.append('}')
source = '#include <assert.h>\n#include "CompanionVNCDirectEndpoint.h"\n#include "CompanionVNCDisplayLayout.h"\nint main(void) {\n' + '\n'.join(checks) + '\n}\n'
with tempfile.TemporaryDirectory(prefix='maccompanion-vnc-direct-') as folder:
    p = Path(folder); (p / 'test.c').write_text(source)
    subprocess.run(['xcrun', 'clang', '-Wall', '-Wextra', '-Werror', '-I', str(ROOT/'Native/VNC'), str(p/'test.c'), '-o', str(p/'test')], check=True)
    subprocess.run([str(p/'test')], check=True)
print(f"Direct Screen Sharing: {len(profile['addressCases'])} endpoint, {len(profile['portCases'])} port, {len(profile['loginCases'])} login and {len(profile['displayLayoutCases'])} Apple display-layout cases passed")

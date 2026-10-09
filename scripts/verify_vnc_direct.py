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
for c in profile['connectionReadinessCases']:
    arguments = ', '.join(str(c[key]).lower() for key in [
        'running', 'inputReady', 'inputOnly', 'paused', 'stopping', 'overflow',
        'awaitingResumeFrame', 'baselinePresented'])
    checks.append('assert(CompanionVNCConnectionReady(%s) == %s);' % (arguments, str(c['connected']).lower()))
for c in profile['displayLayoutCases']:
    b = bytes.fromhex(c['bodyHex']); values = ','.join(str(v) for v in b)
    checks.append('{ const uint8_t bytes[] = {%s}; CompanionVNCDisplayLayout layout; assert(CompanionVNCDecodeDisplayLayout(bytes, sizeof(bytes), &layout) == %s);' % (values, str(c['valid']).lower()))
    if c['valid']:
        checks.append('assert(layout.width == %d && layout.height == %d && layout.count == %d);' % (*c['backing'], len(c['screens'])))
        for i,(did,x,y,right,bottom) in enumerate(c['screens']):
            checks.append('assert(layout.displays[%d].id == %d && layout.displays[%d].x == %d && layout.displays[%d].y == %d && layout.displays[%d].width == %d && layout.displays[%d].height == %d);' % (i,did,i,x,i,y,i,right-x,i,bottom-y))
    checks.append('}')
for c in profile['nativeMagnificationCases']:
    expected = bytes.fromhex(c['hex'])
    values = ','.join(str(v) for v in expected) or '0'
    checks.append('''{ CompanionVNCMagnification state = {%s, %d, %d}, before = state;
    uint8_t bytes[52]; memset(bytes, 0xaa, sizeof(bytes));
    const uint8_t expected[] = {%s};
    size_t count = CompanionVNCMagnificationPacket(&state, %d, %.17g, %d, %d, %d, %d, bytes, sizeof(bytes));
    assert(count == %d);
    if (count) { assert(memcmp(bytes, expected, count) == 0); assert(state.active == %s); }
    else { assert(memcmp(&state, &before, sizeof(state)) == 0); for (size_t i=0; i<sizeof(bytes); i++) assert(bytes[i] == 0xaa); }
    }''' % (str(c['active']).lower(), c['x'], c['y'], values, c['phase'], c['delta'], c['x'], c['y'], c['width'], c['height'], len(expected), str(c['phase'] != 4).lower()))
for c in profile['nativeScrollCases']:
    expected = bytes.fromhex(c['hex']); values = ','.join(str(v) for v in expected) or '0'
    checks.append('''{ CompanionVNCScroll state = {%s, %d, %d}, before = state;
    uint8_t bytes[58]; memset(bytes, 0xaa, sizeof(bytes)); const uint8_t expected[] = {%s};
    size_t count = CompanionVNCScrollPacket(&state, %d, %.17g, %.17g, %d, %d, %d, %d, bytes, sizeof(bytes));
    assert(count == %d);
    if (count) { assert(memcmp(bytes, expected, count) == 0); assert(state.active == %s); }
    else { assert(memcmp(&state, &before, sizeof(state)) == 0); for (size_t i=0; i<sizeof(bytes); i++) assert(bytes[i] == 0xaa); }
    }''' % (str(c['active']).lower(), c['x'], c['y'], values, c['phase'], c['dx'], c['dy'], c['x'], c['y'], c['width'], c['height'], len(expected), str(c['phase'] != 4).lower()))
for c in profile['nativeGestureSupportCases']:
    checks.append('assert(CompanionVNCNativeGesturesSupported(%s, %s, %d, %d, %d, %d) == %s);' % (str(c['apple889']).lower(), str(c['layoutValid']).lower(), c['width'], c['height'], c['backingWidth'], c['backingHeight'], str(c['valid']).lower()))
# Repeated gestures, fixed anchors, malformed deltas and insufficient output capacity.
checks.append(r'''{
    CompanionVNCMagnification state = {0}; uint8_t bytes[52];
    for (unsigned repeat=0; repeat<100; repeat++) {
        assert(CompanionVNCMagnificationPacket(&state, 1, 0, 12, 34, 100, 100, bytes, 51) == 0);
        assert(!state.active);
        assert(CompanionVNCMagnificationPacket(&state, 1, 0, 12, 34, 100, 100, bytes, 52) == 52);
        assert(CompanionVNCMagnificationPacket(&state, 2, NAN, 0, 0, 100, 100, bytes, 52) == 0);
        assert(CompanionVNCMagnificationPacket(&state, 2, INFINITY, 0, 0, 100, 100, bytes, 52) == 0);
        assert(state.active && state.x == 12 && state.y == 34);
        assert(CompanionVNCMagnificationPacket(&state, 2, -.5, 99, 99, 100, 100, bytes, 52) == 36);
        assert(state.x == 12 && state.y == 34 && bytes[17] == 12 && bytes[19] == 34);
        assert(CompanionVNCMagnificationPacket(&state, 4, 0, 0, 0, 100, 100, bytes, 52) == 52);
        assert(!state.active);
        assert(CompanionVNCMagnificationPacket(&state, 2, .1, 0, 0, 100, 100, bytes, 52) == 0);
    }
}''')
checks.append(r'''{
    CompanionVNCScroll state = {0}; uint8_t bytes[58];
    for (unsigned repeat=0; repeat<100; repeat++) {
        assert(CompanionVNCScrollPacket(&state,1,0,0,12,34,100,100,bytes,57)==0);
        assert(!state.active);
        assert(CompanionVNCScrollPacket(&state,1,0,0,12,34,100,100,bytes,58)==58);
        assert(CompanionVNCScrollPacket(&state,2,NAN,0,0,0,100,100,bytes,58)==0);
        assert(CompanionVNCScrollPacket(&state,2,0,INFINITY,0,0,100,100,bytes,58)==0);
        assert(CompanionVNCScrollPacket(&state,2,.25,-.25,99,99,100,100,bytes,58)==58);
        assert(state.x==12 && state.y==34 && bytes[55]==12 && bytes[57]==34);
        assert(CompanionVNCScrollPacket(&state,4,0,0,0,0,100,100,bytes,58)==58);
        assert(!state.active);
        assert(CompanionVNCScrollPacket(&state,2,1,1,0,0,100,100,bytes,58)==0);
    }
}''')
source = '#include <assert.h>\n#include "CompanionVNCDirectEndpoint.h"\n#include "CompanionVNCDisplayLayout.h"\n#include "CompanionVNCGestures.h"\n#include "CompanionVNCReadiness.h"\nint main(void) {\n' + '\n'.join(checks) + '\n}\n'
with tempfile.TemporaryDirectory(prefix='maccompanion-vnc-direct-') as folder:
    p = Path(folder); (p / 'test.c').write_text(source)
    subprocess.run(['xcrun', 'clang', '-Wall', '-Wextra', '-Werror', '-I', str(ROOT/'Native/VNC'), str(p/'test.c'), '-o', str(p/'test')], check=True)
    subprocess.run([str(p/'test')], check=True)
print(f"Direct Screen Sharing: {len(profile['addressCases'])} endpoint, {len(profile['portCases'])} port, {len(profile['loginCases'])} login and {len(profile['displayLayoutCases'])} Apple display-layout cases, {len(profile['nativeMagnificationCases'])} native magnification vectors, {len(profile['nativeScrollCases'])} precise scroll vectors and 100 repeated lifecycles each passed")
print(f"Mode-specific connection readiness: {len(profile['connectionReadinessCases'])} cases passed")

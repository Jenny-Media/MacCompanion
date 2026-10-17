"""Exact optional read-service transforms for the pinned direct-client library."""
import difflib
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TRANSFORMS = {'include/rfb/rfbclient.h': [(b'extern rfbBool ReadFromRFBServer(rfbClient* client, char *out, unsigned '
                              b'int n);',
                              b'typedef struct {\n  uint64_t socketBytes, deliveredBytes, waitCalls;\n'
                              b'  double waitMS;\n} CompanionVNCReadMetrics;\ntypedef struct {\n  rfbBo'
                              b'ol (*service)(rfbClient *client);\n  CompanionVNCReadMetrics *metrics'
                              b'; /* Optional, numeric-only, sole-owner storage. */\n} CompanionVNCRe'
                              b'adService;\n/* The caller retains this descriptor until cleared on th'
                              b'e sole socket owner. */\nextern void CompanionVNCSetReadService(rfbCl'
                              b'ient *client, const CompanionVNCReadService *service);\n\nextern rfbBo'
                              b'ol ReadFromRFBServer(rfbClient* client, char *out, unsigned int n);',
                              1)],
 'src/libvncclient/sockets.c': [(b'/*\n * ReadFromRFBServer is called whenever',
                                 b'/* Optional cooperative input service, installed only after authenti'
                                 b'cation. */\nstatic char companionReadServiceTag;\nvoid\nCompanionVN'
                                 b'CSetReadService(rfbClient *client, const CompanionVNCReadService *se'
                                 b'rvice)\n{\n  rfbClientSetClientData(client, &companionReadServiceT'
                                 b'ag, (void *)service);\n}\nstatic const CompanionVNCReadService *\nC'
                                 b'ompanionVNCGetReadService(rfbClient *client)\n{\n  return (const C'
                                 b'ompanionVNCReadService *)rfbClientGetClientData(client, &companionRe'
                                 b'adServiceTag);\n}\nstatic rfbBool\nCompanionVNCServiceRead(rfbClien'
                                 b't *client)\n{\n  const CompanionVNCReadService *service = Companio'
                                 b'nVNCGetReadService(client);\n  return !service || !service->service |'
                                 b'| service->service(client);\n}\n\nstatic CompanionVNCReadMetrics *\n'
                                 b'CompanionVNCGetReadMetrics(rfbClient *client)\n{\n  const Companio'
                                 b'nVNCReadService *service = CompanionVNCGetReadService(client);\n  ret'
                                 b'urn service ? service->metrics : NULL;\n}\nstatic void\nCompanionVN'
                                 b'CRecordSocketRead(rfbClient *client, unsigned int bytes)\n{\n  Com'
                                 b'panionVNCReadMetrics *metrics = CompanionVNCGetReadMetrics(client);\n'
                                 b'  if (metrics) metrics->socketBytes += bytes;\n}\nstatic void\nComp'
                                 b'anionVNCRecordDelivered(rfbClient *client, unsigned int bytes)\n{'
                                 b'\n  CompanionVNCReadMetrics *metrics = CompanionVNCGetReadMetrics(cli'
                                 b'ent);\n  if (metrics) metrics->deliveredBytes += bytes;\n}\nstatic '
                                 b'int\nCompanionVNCWaitForRead(rfbClient *client, unsigned int usec'
                                 b's)\n{\n  CompanionVNCReadMetrics *metrics = CompanionVNCGetReadMet'
                                 b'rics(client);\n  if (!metrics) return WaitForMessage(client, usec'
                                 b's);\n  struct timespec before, after;\n  int valid = clock_gettime'
                                 b'(CLOCK_MONOTONIC, &before) == 0;\n  int result = WaitForMessage(clien'
                                 b't, usecs);\n  metrics->waitCalls++;\n  if (valid && clock_gettime('
                                 b'CLOCK_MONOTONIC, &after) == 0) {\n    double elapsed = (after.tv_sec '
                                 b'- before.tv_sec) * 1000.0 + (after.tv_nsec - before.tv_nsec) / 10000'
                                 b'00.0;\n    if (elapsed > 0) metrics->waitMS += elapsed;\n  }\n  ret'
                                 b'urn result;\n}\n\n/*\n * ReadFromRFBServer is called whenever',
                                 1),
                                (b'  const int USECS_WAIT_PER_RETRY = 100000;',
                                 b'  const int USECS_WAIT_PER_RETRY = CompanionVNCGetReadService(client'
                                 b') ? 10000 : 100000;',
                                 1),
                                (b'  if (n <= client->buffered) {',
                                 b'  if (!CompanionVNCServiceRead(client))\n    return FALSE;\n\n  if '
                                 b'(n <= client->buffered) {',
                                 1),
                                (b'      int i;\n',
                                 b'      int i;\n      if (!CompanionVNCServiceRead(client))\n       '
                                 b' return FALSE;\n',
                                 2),
                                (b'#include <assert.h>', b'#include <assert.h>\n#include <time.h>', 1),
                                (b'  int retries = 0;\n#undef DEBUG_READ_EXACT',
                                 b'  int retries = 0;\n  const unsigned int requestedBytes = n;\n#und'
                                 b'ef DEBUG_READ_EXACT',
                                 1),
                                (b'    WaitForMessage(client, USECS_WAIT_PER_RETRY);',
                                 b'    CompanionVNCWaitForRead(client, USECS_WAIT_PER_RETRY);',
                                 2),
                                (b'      client->buffered += i;',
                                 b'      if (i > 0) CompanionVNCRecordSocketRead(client, (unsigned int)'
                                 b'i);\n      client->buffered += i;',
                                 1),
                                (b'      out += i;\n      n -= i;',
                                 b'      if (i > 0) CompanionVNCRecordSocketRead(client, (unsigned int)'
                                 b'i);\n      out += i;\n      n -= i;',
                                 1),
                                (b'    goto hexdump;\n#endif\n    return TRUE;',
                                 b'    goto hexdump;\n#endif\n    CompanionVNCRecordDelivered(client,'
                                 b' requestedBytes);\n    return TRUE;',
                                 1),
                                (b'  return TRUE;\n}\n\n\n/*\n * Write an exact number of bytes',
                                 b'  CompanionVNCRecordDelivered(client, requestedBytes);\n  return TRUE'
                                 b';\n}\n\n\n/*\n * Write an exact number of bytes',
                                 1)]}

def adapted_read_service(original, policy):
    path = policy['path']
    patch_name = {'include/rfb/rfbclient.h': 'Native/VNC/direct-read-service-header.patch',
                  'src/libvncclient/sockets.c': 'Native/VNC/direct-read-service-sockets.patch'}
    if path not in TRANSFORMS or policy['patchPath'] != patch_name[path]:
        raise ValueError('Unexpected VNC read-service adapter path.')
    digest = lambda value: hashlib.sha256(value).hexdigest()
    if digest(original) != policy['originalSHA256']:
        raise ValueError('Pinned read-service source differs from the admitted original.')
    adapted = original
    for before, after, count in TRANSFORMS[path]:
        if adapted.count(before) != count:
            raise ValueError('Read-service adapter anchor mismatch.')
        adapted = adapted.replace(before, after)
    patch = ''.join(difflib.unified_diff(original.decode().splitlines(True), adapted.decode().splitlines(True),
                    fromfile='a/' + path, tofile='b/' + path, n=0)).encode()
    if (digest(adapted) != policy['adaptedSHA256'] or digest(patch) != policy['patchSHA256']
            or (ROOT / policy['patchPath']).read_bytes() != patch):
        raise ValueError('VNC read-service adapter differs from its admitted patch.')
    return adapted

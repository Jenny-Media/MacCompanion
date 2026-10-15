"""Exact optional read-service transforms for the pinned direct-client library."""
import difflib
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TRANSFORMS = {'include/rfb/rfbclient.h': [(b'extern rfbBool ReadFromRFBServer(rfbClient* client, char *out, unsigned int '
                              b'n);',
                              b'typedef struct {\n  rfbBool (*service)(rfbClient *client);\n} CompanionVNC'
                              b'ReadService;\n/* The caller retains this descriptor until cleared on the sole'
                              b' socket owner. */\nextern void CompanionVNCSetReadService(rfbClient *client, '
                              b'const CompanionVNCReadService *service);\n\nextern rfbBool ReadFromRFBServ'
                              b'er(rfbClient* client, char *out, unsigned int n);',
                              1)],
 'src/libvncclient/sockets.c': [(b'/*\n * ReadFromRFBServer is called whenever',
                                 b'/* Optional cooperative input service, installed only after authenticati'
                                 b'on. */\nstatic char companionReadServiceTag;\nvoid\nCompanionVNCSetRead'
                                 b'Service(rfbClient *client, const CompanionVNCReadService *service)\n{\n  r'
                                 b'fbClientSetClientData(client, &companionReadServiceTag, (void *)service)'
                                 b';\n}\nstatic const CompanionVNCReadService *\nCompanionVNCGetReadServic'
                                 b'e(rfbClient *client)\n{\n  return (const CompanionVNCReadService *)rfbClie'
                                 b'ntGetClientData(client, &companionReadServiceTag);\n}\nstatic rfbBool\n'
                                 b'CompanionVNCServiceRead(rfbClient *client)\n{\n  const CompanionVNCReadSer'
                                 b'vice *service = CompanionVNCGetReadService(client);\n  return !service ||'
                                 b' !service->service || service->service(client);\n}\n\n/*\n * ReadFromRFB'
                                 b'Server is called whenever',
                                 1),
                                (b'  const int USECS_WAIT_PER_RETRY = 100000;',
                                 b'  const int USECS_WAIT_PER_RETRY = CompanionVNCGetReadService(client) ? '
                                 b'10000 : 100000;',
                                 1),
                                (b'  if (n <= client->buffered) {',
                                 b'  if (!CompanionVNCServiceRead(client))\n    return FALSE;\n\n  if (n <'
                                 b'= client->buffered) {',
                                 1),
                                (b'      int i;\n',
                                 b'      int i;\n      if (!CompanionVNCServiceRead(client))\n        return '
                                 b'FALSE;\n',
                                 2)]}

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
                    fromfile='a/' + path, tofile='b/' + path)).encode()
    if (digest(adapted) != policy['adaptedSHA256'] or digest(patch) != policy['patchSHA256']
            or (ROOT / policy['patchPath']).read_bytes() != patch):
        raise ValueError('VNC read-service adapter differs from its admitted patch.')
    return adapted

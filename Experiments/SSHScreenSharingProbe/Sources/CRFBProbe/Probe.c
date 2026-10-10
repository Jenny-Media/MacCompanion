#include "CRFBProbe.h"
#include <rfb/rfbclient.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

struct ProbeCredential { const char *username; const char *password; };
static char credentialTag;
static void QuietLog(const char *format, ...) { (void)format; }
static rfbCredential *Credential(rfbClient *client, int type) {
    if (type != rfbCredentialTypeUser) return NULL;
    struct ProbeCredential *saved = rfbClientGetClientData(client, &credentialTag);
    rfbCredential *result = calloc(1, sizeof(*result));
    if (result) {
        result->userCredential.username = strdup(saved->username);
        result->userCredential.password = strdup(saved->password);
    }
    return result;
}
int ProbeARDHandshake(int socket, const char *username, const char *password) {
    rfbClientLog = QuietLog; rfbClientErr = QuietLog;
    rfbClient *client = rfbGetClient(8, 3, 4);
    if (!client) { close(socket); return 0; }
    struct ProbeCredential credentials = { username, password };
    client->sock = socket; client->readTimeout = 10;
    client->appData.shareDesktop = TRUE;
    client->GetCredential = Credential;
    rfbClientSetClientData(client, &credentialTag, &credentials);
    uint32_t schemes[] = { rfbARD };
    SetClientAuthSchemes(client, schemes, 1);
    int result = InitialiseRFBConnection(client);
    rfbClientCleanup(client);
    return result;
}

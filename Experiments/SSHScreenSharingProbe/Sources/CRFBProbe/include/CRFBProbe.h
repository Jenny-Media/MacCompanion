#ifndef CRFB_PROBE_H
#define CRFB_PROBE_H
// Takes ownership of socket on every outcome. No updates/input are requested.
int ProbeARDHandshake(int socket, const char *username, const char *password);
#endif

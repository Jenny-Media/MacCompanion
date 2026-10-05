#pragma once
#include <arpa/inet.h>
#include <stdbool.h>
#include <string.h>
#include <sys/socket.h>

static inline bool CompanionVNCLocalIPv4(uint32_t ip) {
    return (ip >> 24) == 10 || (ip >> 24) == 127 || (ip >> 22) == 0x191 ||
        (ip >> 20) == 0xac1 || (ip >> 16) == 0xc0a8 || (ip >> 16) == 0xa9fe;
}
static inline bool CompanionVNCPortValid(int port) { return port >= 1 && port <= 65535; }
static inline bool CompanionVNCLocalEndpoint(const struct sockaddr *address, size_t length) {
    if (!address || length < sizeof(struct sockaddr)) return false;
    if (address->sa_family == AF_INET && length >= sizeof(struct sockaddr_in)) {
        return CompanionVNCLocalIPv4(ntohl(((const struct sockaddr_in *)address)->sin_addr.s_addr));
    }
    if (address->sa_family != AF_INET6 || length < sizeof(struct sockaddr_in6)) return false;
    const struct sockaddr_in6 *a = (const struct sockaddr_in6 *)address;
    const uint8_t *bytes = a->sin6_addr.s6_addr;
    if (IN6_IS_ADDR_V4MAPPED(&a->sin6_addr)) {
        uint32_t ip; memcpy(&ip, bytes + 12, 4); return CompanionVNCLocalIPv4(ntohl(ip));
    }
    return IN6_IS_ADDR_LOOPBACK(&a->sin6_addr) || (bytes[0] & 0xfe) == 0xfc ||
        (IN6_IS_ADDR_LINKLOCAL(&a->sin6_addr) && a->sin6_scope_id != 0);
}
static inline bool CompanionVNCLoginBytes(const char *bytes, size_t length) {
    return bytes && length > 0 && length <= 63 && !memchr(bytes, 0, length);
}

#pragma once
#include <string.h>

// Only exact pinned-engine format literals are classified. Never format or
// retain variadic arguments: they can contain endpoints or other private data.
static inline int CompanionMoonlightTerminalDiagnostic(const char *format) {
    if (!format) return 0;
    static const struct { const char *format; int code; } reasons[] = {
        {"Control stream received unexpected disconnect event\n", 1},
        {"Disconnect event timeout expired\n", 2},
        {"Control stream connection failed: %d\n", 3},
        {"Video Receive: recvUdpSocket() failed: %d\n", 4},
        {"Audio Receive: recvUdpSocket() failed: %d\n", 5},
        {"Request IDR Frame: Transaction failed: %d\n", 6},
        {"Request Invaldiate Reference Frames: Transaction failed: %d\n", 7},
        {"Loss Stats: Sending frame FEC status message failed: %d\n", 8},
        {"Loss Stats: Transaction failed: %d\n", 8},
        {"Video Receive: malloc() failed\n", 9},
        {"Audio Receive: malloc() failed\n", 9},
        {"Loss Stats: malloc() failed\n", 9},
        {"Terminating connection due to lack of video traffic\n", 10},
        {"Terminating connection due to lack of a successful video frame\n", 11},
        {"Server notified termination reason: 0x%08x\n", 12},
        {"Server notified termination reason: 0x%04x\n", 12},
    };
    for (unsigned index = 0; index < sizeof(reasons) / sizeof(reasons[0]); index++) {
        if (!strcmp(format, reasons[index].format)) return reasons[index].code;
    }
    return 0;
}

#ifndef COMPANION_VNC_READINESS_H
#define COMPANION_VNC_READINESS_H
#include <stdbool.h>

// inputReady is set only after authenticated RFB initialization. Trackpad
// deliberately never presents a baseline; Desktop must present complete pixels.
static inline bool CompanionVNCConnectionReady(bool running, bool inputReady,
    bool inputOnly, bool paused, bool stopping, bool overflow,
    bool awaitingResumeFrame, bool baselinePresented) {
    return running && inputReady && !paused && !stopping && !overflow
        && (inputOnly || (!awaitingResumeFrame && baselinePresented));
}
#endif

#ifndef COMPANION_LOCAL_XPC_PLATFORM_C_H
#define COMPANION_LOCAL_XPC_PLATFORM_C_H

#include <dispatch/dispatch.h>
#include <stdbool.h>
#include <stdint.h>
#include <xpc/xpc.h>

XPC_ASSUME_NONNULL_BEGIN

typedef enum : int32_t {
    MCLocalXPCResultOK = 0,
    MCLocalXPCResultConstructionFailed = 1,
    MCLocalXPCResultRequirementFailed = 2,
    MCLocalXPCResultActivationFailed = 3,
    MCLocalXPCResultSendFailed = 4,
} MCLocalXPCResult;
typedef struct MCLocalXPCListener *MCLocalXPCListenerRef;
typedef struct MCLocalXPCSession *MCLocalXPCSessionRef;
typedef struct MCLocalXPCMessage *MCLocalXPCMessageRef;

typedef void (^MCLocalXPCIncomingSessionHandler)(MCLocalXPCSessionRef peer);
typedef void (^MCLocalXPCCancelHandler)(void);
typedef void (^MCLocalXPCMessageHandler)(MCLocalXPCMessageRef message);
typedef void (^MCLocalXPCReplyHandler)(
    MCLocalXPCMessageRef _Nullable reply,
    bool had_error
);

API_AVAILABLE(macos(26.0))
MCLocalXPCListenerRef _Nullable MCLocalXPCListenerCreateInactive(
    const char *service_name,
    dispatch_queue_t queue,
    MCLocalXPCIncomingSessionHandler handler,
    MCLocalXPCResult * _Nullable result_out
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCListenerRequireSameTeamIdentifier(
    MCLocalXPCListenerRef listener,
    const char *signing_identifier
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCListenerActivate(MCLocalXPCListenerRef listener);

API_AVAILABLE(macos(26.0))
void MCLocalXPCListenerCancel(MCLocalXPCListenerRef listener);

API_AVAILABLE(macos(26.0))
MCLocalXPCSessionRef _Nullable MCLocalXPCSessionCreateInactive(
    const char *service_name,
    dispatch_queue_t queue,
    MCLocalXPCResult * _Nullable result_out
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionRequireSameTeamIdentifier(
    MCLocalXPCSessionRef session,
    const char *signing_identifier
);

API_AVAILABLE(macos(26.0))
void MCLocalXPCSessionSetCancelHandler(
    MCLocalXPCSessionRef session,
    MCLocalXPCCancelHandler handler
);

API_AVAILABLE(macos(26.0))
void MCLocalXPCSessionSetMessageHandler(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageHandler handler
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionActivate(MCLocalXPCSessionRef session);

API_AVAILABLE(macos(26.0))
void MCLocalXPCSessionCancel(MCLocalXPCSessionRef session);

API_AVAILABLE(macos(26.0))
void MCLocalXPCSessionCancelOwned(MCLocalXPCSessionRef session);

API_AVAILABLE(macos(26.0))
void MCLocalXPCSessionRelease(MCLocalXPCSessionRef session);

API_AVAILABLE(macos(26.0))
bool MCLocalXPCMessageIsExactHello(MCLocalXPCMessageRef message);

API_AVAILABLE(macos(26.0))
bool MCLocalXPCMessageIsExactHelloAcknowledgement(MCLocalXPCMessageRef message);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionReplyToHello(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef hello
);

API_AVAILABLE(macos(26.0))
void MCLocalXPCSessionSendHello(
    MCLocalXPCSessionRef session,
    MCLocalXPCReplyHandler handler
);

XPC_ASSUME_NONNULL_END

#endif

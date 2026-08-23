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
typedef enum : int32_t {
    MCLocalXPCMenuPresentationReplyAcknowledged = 0,
    MCLocalXPCMenuPresentationReplyRejected = 1,
    MCLocalXPCMenuPresentationReplyMalformedOrTransportError = 2,
} MCLocalXPCMenuPresentationReply;
typedef enum : int32_t {
    MCLocalXPCMenuPairingCommandCreate = 0,
    MCLocalXPCMenuPairingCommandDismiss = 1,
    MCLocalXPCMenuPairingCommandResolveDecision = 2,
} MCLocalXPCMenuPairingCommandKind;
typedef enum : int32_t {
    MCLocalXPCInteractiveLeaseCommandInstall = 0,
    MCLocalXPCInteractiveLeaseCommandRenew = 1,
    MCLocalXPCInteractiveLeaseCommandRevoke = 2,
    MCLocalXPCInteractiveLeaseCommandPrepareInitialDesktop = 3,
} MCLocalXPCInteractiveLeaseCommandKind;
typedef struct MCLocalXPCListener *MCLocalXPCListenerRef;
typedef struct MCLocalXPCSession *MCLocalXPCSessionRef;
typedef struct MCLocalXPCMessage *MCLocalXPCMessageRef;
typedef struct MCLocalXPCPeerRequirement *MCLocalXPCPeerRequirementRef;

typedef void (^MCLocalXPCIncomingSessionHandler)(MCLocalXPCSessionRef peer);
typedef void (^MCLocalXPCCancelHandler)(void);
typedef void (^MCLocalXPCMessageHandler)(MCLocalXPCMessageRef message);
typedef void (^MCLocalXPCReplyHandler)(
    MCLocalXPCMessageRef _Nullable reply,
    bool had_error
);
typedef void (^MCLocalXPCStatusReplyHandler)(
    const uint8_t * _Nullable payload,
    size_t payload_length,
    bool source_unavailable,
    bool malformed_or_transport_error
);
typedef void (^MCLocalXPCBootstrapPayloadReplyHandler)(
    const uint8_t * _Nullable payload,
    size_t payload_length,
    bool malformed_or_transport_error
);
typedef void (^MCLocalXPCMenuPresentationReplyHandler)(
    MCLocalXPCMenuPresentationReply reply
);
typedef void (^MCLocalXPCMenuPairingCommandReplyHandler)(
    const uint8_t * _Nullable payload,
    size_t payload_length,
    bool command_failed,
    bool malformed_or_transport_error
);
typedef void (^MCLocalXPCInteractiveLeaseReplyHandler)(
    const uint8_t * _Nullable payload,
    size_t payload_length,
    bool malformed_or_transport_error
);
typedef void (^MCLocalXPCInteractiveAdmissionReplyHandler)(
    const uint8_t * _Nullable payload,
    size_t payload_length,
    bool malformed_or_transport_error
);

enum {
    MCLocalXPCMaximumStatusPayloadBytes = 4096,
    MCLocalXPCMaximumBootstrapPayloadBytes = 4096,
    MCLocalXPCMaximumMenuPresentationPayloadBytes = 4096,
    MCLocalXPCMaximumMenuPairingCommandPayloadBytes = 4096,
    MCLocalXPCMaximumInteractiveLeasePayloadBytes = 4096,
    MCLocalXPCMaximumInteractiveAdmissionPayloadBytes = 4096,
};

API_AVAILABLE(macos(26.0))
MCLocalXPCPeerRequirementRef _Nullable
MCLocalXPCPeerRequirementCreateSameTeamIdentifier(
    const char *signing_identifier,
    MCLocalXPCResult * _Nullable result_out
);

API_AVAILABLE(macos(26.0))
void MCLocalXPCPeerRequirementRelease(
    MCLocalXPCPeerRequirementRef requirement
);

API_AVAILABLE(macos(26.0))
MCLocalXPCListenerRef _Nullable MCLocalXPCListenerCreateInactive(
    const char *service_name,
    dispatch_queue_t queue,
    MCLocalXPCIncomingSessionHandler handler,
    MCLocalXPCResult * _Nullable result_out
);

API_AVAILABLE(macos(26.0))
void MCLocalXPCListenerSetPeerRequirement(
    MCLocalXPCListenerRef listener,
    MCLocalXPCPeerRequirementRef requirement
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCListenerActivate(MCLocalXPCListenerRef listener);

API_AVAILABLE(macos(26.0))
void MCLocalXPCListenerCancel(MCLocalXPCListenerRef listener);

API_AVAILABLE(macos(26.0))
void MCLocalXPCListenerRejectPeer(MCLocalXPCSessionRef peer);

API_AVAILABLE(macos(26.0))
MCLocalXPCSessionRef _Nullable MCLocalXPCSessionCreateInactive(
    const char *service_name,
    dispatch_queue_t queue,
    MCLocalXPCResult * _Nullable result_out
);

API_AVAILABLE(macos(26.0))
void MCLocalXPCSessionSetPeerRequirement(
    MCLocalXPCSessionRef session,
    MCLocalXPCPeerRequirementRef requirement
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
void MCLocalXPCSessionDisposeAfterFailedActivation(
    MCLocalXPCSessionRef session
);

API_AVAILABLE(macos(26.0))
void MCLocalXPCSessionRetain(MCLocalXPCSessionRef session);

API_AVAILABLE(macos(26.0))
void MCLocalXPCSessionCancelOwned(MCLocalXPCSessionRef session);

API_AVAILABLE(macos(26.0))
void MCLocalXPCSessionRelease(MCLocalXPCSessionRef session);

API_AVAILABLE(macos(26.0))
bool MCLocalXPCMessageIsExactHello(MCLocalXPCMessageRef message);

API_AVAILABLE(macos(26.0))
bool MCLocalXPCMessageIsExactHelloAcknowledgement(MCLocalXPCMessageRef message);

API_AVAILABLE(macos(26.0))
bool MCLocalXPCMessageIsExactMenuReady(MCLocalXPCMessageRef message);

API_AVAILABLE(macos(26.0))
bool MCLocalXPCMessageIsExactMenuReadyAcknowledgement(
    MCLocalXPCMessageRef message
);

API_AVAILABLE(macos(26.0))
bool MCLocalXPCMessageIsExactStatusRead(MCLocalXPCMessageRef message);

API_AVAILABLE(macos(26.0))
bool MCLocalXPCMessageIsExactRemoteAccessBootstrapRead(
    MCLocalXPCMessageRef message
);

API_AVAILABLE(macos(26.0))
bool MCLocalXPCMessageGetExactRemoteAccessEnable(
    MCLocalXPCMessageRef message,
    const uint8_t * _Nullable * _Nullable payload_out,
    size_t * _Nullable payload_length_out
);

API_AVAILABLE(macos(26.0))
void MCLocalXPCMessageRetain(MCLocalXPCMessageRef message);

API_AVAILABLE(macos(26.0))
void MCLocalXPCMessageRelease(MCLocalXPCMessageRef message);

API_AVAILABLE(macos(26.0))
bool MCLocalXPCExactMessageParserSelfTest(void);

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

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionReplyToMenuReady(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request
);

API_AVAILABLE(macos(26.0))
void MCLocalXPCSessionSendMenuReady(
    MCLocalXPCSessionRef session,
    MCLocalXPCReplyHandler handler
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionReplyToStatusReadSuccess(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request,
    const uint8_t *payload,
    size_t payload_length
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionReplyToStatusReadUnavailable(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request
);

API_AVAILABLE(macos(26.0))
void MCLocalXPCSessionSendStatusRead(
    MCLocalXPCSessionRef session,
    MCLocalXPCStatusReplyHandler handler
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionReplyToRemoteAccessBootstrapOffer(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request,
    const uint8_t *payload,
    size_t payload_length
);

API_AVAILABLE(macos(26.0))
void MCLocalXPCSessionSendRemoteAccessBootstrapRead(
    MCLocalXPCSessionRef session,
    MCLocalXPCBootstrapPayloadReplyHandler handler
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionReplyToRemoteAccessEnabled(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request,
    const uint8_t *payload,
    size_t payload_length
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionSendRemoteAccessEnable(
    MCLocalXPCSessionRef session,
    const uint8_t *payload,
    size_t payload_length,
    MCLocalXPCBootstrapPayloadReplyHandler handler
);

API_AVAILABLE(macos(26.0))
bool MCLocalXPCMessageGetExactMenuPairingCommand(
    MCLocalXPCMessageRef message,
    MCLocalXPCMenuPairingCommandKind * _Nullable kind_out,
    const uint8_t * _Nullable * _Nullable payload_out,
    size_t * _Nullable payload_length_out
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionReplyToMenuPairingCommandSuccess(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request,
    MCLocalXPCMenuPairingCommandKind kind,
    const uint8_t *payload,
    size_t payload_length
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionReplyToMenuPairingCommandFailure(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request,
    MCLocalXPCMenuPairingCommandKind kind
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionSendMenuPairingCommand(
    MCLocalXPCSessionRef session,
    MCLocalXPCMenuPairingCommandKind kind,
    const uint8_t *payload,
    size_t payload_length,
    MCLocalXPCMenuPairingCommandReplyHandler handler
);

API_AVAILABLE(macos(26.0))
bool MCLocalXPCMessageGetExactInteractiveLeaseCommand(
    MCLocalXPCMessageRef message,
    MCLocalXPCInteractiveLeaseCommandKind * _Nullable kind_out,
    const uint8_t * _Nullable * _Nullable payload_out,
    size_t * _Nullable payload_length_out
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionReplyToInteractiveLeaseCommandSuccess(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request,
    MCLocalXPCInteractiveLeaseCommandKind kind,
    const uint8_t * _Nullable payload,
    size_t payload_length
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionSendInteractiveLeaseCommand(
    MCLocalXPCSessionRef session,
    MCLocalXPCInteractiveLeaseCommandKind kind,
    const uint8_t *payload,
    size_t payload_length,
    MCLocalXPCInteractiveLeaseReplyHandler handler
);

API_AVAILABLE(macos(26.0))
bool MCLocalXPCMessageGetExactInteractiveAdmissionPublication(
    MCLocalXPCMessageRef message,
    const uint8_t * _Nullable * _Nullable payload_out,
    size_t * _Nullable payload_length_out
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionReplyToInteractiveAdmissionPublication(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request,
    const uint8_t *payload,
    size_t payload_length
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionSendInteractiveAdmissionPublication(
    MCLocalXPCSessionRef session,
    const uint8_t *payload,
    size_t payload_length,
    MCLocalXPCInteractiveAdmissionReplyHandler handler
);

/// Returns an owned exact request object. The caller releases it with
/// MCLocalXPCMessageRelease.
API_AVAILABLE(macos(26.0))
MCLocalXPCMessageRef _Nullable MCLocalXPCMessageCreatePairingReviewPublish(
    const uint8_t *payload,
    size_t payload_length
);

API_AVAILABLE(macos(26.0))
MCLocalXPCMessageRef _Nullable MCLocalXPCMessageCreatePairingReviewWithdrawal(
    const uint8_t *review_id,
    size_t review_id_length
);

API_AVAILABLE(macos(26.0))
MCLocalXPCMessageRef _Nullable
MCLocalXPCMessageCreateHostRecoveryReviewPublish(
    const uint8_t *payload,
    size_t payload_length
);

API_AVAILABLE(macos(26.0))
MCLocalXPCMessageRef _Nullable
MCLocalXPCMessageCreateHostRecoveryResumePublish(
    const uint8_t *payload,
    size_t payload_length
);

API_AVAILABLE(macos(26.0))
MCLocalXPCMessageRef _Nullable MCLocalXPCMessageCreateHostRecoveryWithdrawal(
    const uint8_t *review_id,
    size_t review_id_length
);

API_AVAILABLE(macos(26.0))
bool MCLocalXPCMessageGetExactPairingReviewPublish(
    MCLocalXPCMessageRef message,
    const uint8_t * _Nullable * _Nullable payload_out,
    size_t * _Nullable payload_length_out
);

API_AVAILABLE(macos(26.0))
const uint8_t * _Nullable
MCLocalXPCMessageGetExactPairingReviewWithdrawal(
    MCLocalXPCMessageRef message
);

API_AVAILABLE(macos(26.0))
bool MCLocalXPCMessageGetExactHostRecoveryReviewPublish(
    MCLocalXPCMessageRef message,
    const uint8_t * _Nullable * _Nullable payload_out,
    size_t * _Nullable payload_length_out
);

API_AVAILABLE(macos(26.0))
bool MCLocalXPCMessageGetExactHostRecoveryResumePublish(
    MCLocalXPCMessageRef message,
    const uint8_t * _Nullable * _Nullable payload_out,
    size_t * _Nullable payload_length_out
);

API_AVAILABLE(macos(26.0))
const uint8_t * _Nullable
MCLocalXPCMessageGetExactHostRecoveryWithdrawal(
    MCLocalXPCMessageRef message
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionReplyToPairingReviewPublishAcknowledgement(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionReplyToPairingReviewPublishRejection(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionReplyToPairingReviewWithdrawalAcknowledgement(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionReplyToHostRecoveryReviewPublishAcknowledgement(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionReplyToHostRecoveryReviewPublishRejection(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionReplyToHostRecoveryResumePublishAcknowledgement(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionReplyToHostRecoveryResumePublishRejection(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionReplyToHostRecoveryWithdrawalAcknowledgement(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionSendPairingReviewPublish(
    MCLocalXPCSessionRef session,
    const uint8_t *payload,
    size_t payload_length,
    MCLocalXPCMenuPresentationReplyHandler handler
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionSendPairingReviewWithdrawal(
    MCLocalXPCSessionRef session,
    const uint8_t *review_id,
    size_t review_id_length,
    MCLocalXPCMenuPresentationReplyHandler handler
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionSendHostRecoveryReviewPublish(
    MCLocalXPCSessionRef session,
    const uint8_t *payload,
    size_t payload_length,
    MCLocalXPCMenuPresentationReplyHandler handler
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionSendHostRecoveryResumePublish(
    MCLocalXPCSessionRef session,
    const uint8_t *payload,
    size_t payload_length,
    MCLocalXPCMenuPresentationReplyHandler handler
);

API_AVAILABLE(macos(26.0))
MCLocalXPCResult MCLocalXPCSessionSendHostRecoveryWithdrawal(
    MCLocalXPCSessionRef session,
    const uint8_t *review_id,
    size_t review_id_length,
    MCLocalXPCMenuPresentationReplyHandler handler
);

XPC_ASSUME_NONNULL_END

#endif

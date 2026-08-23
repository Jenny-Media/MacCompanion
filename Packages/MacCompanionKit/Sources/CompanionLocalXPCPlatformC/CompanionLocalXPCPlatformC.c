#include "CompanionLocalXPCPlatformC.h"

#include <string.h>

static const char MCLocalXPCPairingReviewPublishKind[] =
    "presentation.pairing-review.publish";
static const char MCLocalXPCPairingReviewPublishAcknowledgementKind[] =
    "presentation.pairing-review.publish.ack";
static const char MCLocalXPCPairingReviewPublishRejectionKind[] =
    "presentation.pairing-review.publish.error";
static const char MCLocalXPCPairingReviewWithdrawalKind[] =
    "presentation.pairing-review.withdraw";
static const char MCLocalXPCPairingReviewWithdrawalAcknowledgementKind[] =
    "presentation.pairing-review.withdraw.ack";
static const char MCLocalXPCHostRecoveryReviewPublishKind[] =
    "presentation.host-recovery-review.publish";
static const char MCLocalXPCHostRecoveryReviewPublishAcknowledgementKind[] =
    "presentation.host-recovery-review.publish.ack";
static const char MCLocalXPCHostRecoveryReviewPublishRejectionKind[] =
    "presentation.host-recovery-review.publish.error";
static const char MCLocalXPCHostRecoveryResumePublishKind[] =
    "presentation.host-recovery-resume.publish";
static const char MCLocalXPCHostRecoveryResumePublishAcknowledgementKind[] =
    "presentation.host-recovery-resume.publish.ack";
static const char MCLocalXPCHostRecoveryResumePublishRejectionKind[] =
    "presentation.host-recovery-resume.publish.error";
static const char MCLocalXPCHostRecoveryWithdrawalKind[] =
    "presentation.host-recovery.withdraw";
static const char MCLocalXPCHostRecoveryWithdrawalAcknowledgementKind[] =
    "presentation.host-recovery.withdraw.ack";
static const char MCLocalXPCRemoteAccessBootstrapReadKind[] =
    "bootstrap.remote-access.read";
static const char MCLocalXPCRemoteAccessBootstrapReadAcknowledgementKind[] =
    "bootstrap.remote-access.read.ack";
static const char MCLocalXPCRemoteAccessEnableKind[] =
    "bootstrap.remote-access.enable";
static const char MCLocalXPCRemoteAccessEnableAcknowledgementKind[] =
    "bootstrap.remote-access.enable.ack";
static const char MCLocalXPCPairingSessionCreateKind[] =
    "command.pairing-session.create";
static const char MCLocalXPCPairingSessionCreateAcknowledgementKind[] =
    "command.pairing-session.create.ack";
static const char MCLocalXPCPairingSessionCreateFailureKind[] =
    "command.pairing-session.create.error";
static const char MCLocalXPCPairingSessionDismissKind[] =
    "command.pairing-session.dismiss";
static const char MCLocalXPCPairingSessionDismissAcknowledgementKind[] =
    "command.pairing-session.dismiss.ack";
static const char MCLocalXPCPairingSessionDismissFailureKind[] =
    "command.pairing-session.dismiss.error";
static const char MCLocalXPCPairingDecisionResolveKind[] =
    "command.pairing-decision.resolve";
static const char MCLocalXPCPairingDecisionResolveAcknowledgementKind[] =
    "command.pairing-decision.resolve.ack";
static const char MCLocalXPCPairingDecisionResolveFailureKind[] =
    "command.pairing-decision.resolve.error";
static const char MCLocalXPCInteractiveLeaseInstallKind[] =
    "runtime.interactive.install";
static const char MCLocalXPCInteractiveLeaseInstallAcknowledgementKind[] =
    "runtime.interactive.install.ack";
static const char MCLocalXPCInteractiveLeaseRenewKind[] =
    "runtime.interactive.renew";
static const char MCLocalXPCInteractiveLeaseRenewAcknowledgementKind[] =
    "runtime.interactive.renew.ack";
static const char MCLocalXPCInteractiveLeaseRevokeKind[] =
    "runtime.interactive.revoke";
static const char MCLocalXPCInteractiveLeaseRevokeAcknowledgementKind[] =
    "runtime.interactive.revoke.ack";
static const char MCLocalXPCInteractiveInitialDesktopPrepareKind[] =
    "runtime.interactive.desktop.prepare";
static const char MCLocalXPCInteractiveInitialDesktopPrepareAcknowledgementKind[] =
    "runtime.interactive.desktop.prepare.ack";
static const char MCLocalXPCInteractiveSurfaceTargetsKind[] =
    "runtime.interactive.surface.targets";
static const char MCLocalXPCInteractiveSurfaceTargetsAcknowledgementKind[] =
    "runtime.interactive.surface.targets.ack";
static const char MCLocalXPCInteractiveSurfaceResolveKind[] =
    "runtime.interactive.surface.resolve";
static const char MCLocalXPCInteractiveSurfaceResolveAcknowledgementKind[] =
    "runtime.interactive.surface.resolve.ack";
static const char MCLocalXPCInteractiveSurfaceTransitionKind[] =
    "runtime.interactive.surface.transition";
static const char MCLocalXPCInteractiveSurfaceTransitionAcknowledgementKind[] =
    "runtime.interactive.surface.transition.ack";
static const char MCLocalXPCInteractiveSurfaceAcknowledgementKind[] =
    "runtime.interactive.surface.acknowledge";
static const char MCLocalXPCInteractiveSurfaceAcknowledgementAcknowledgementKind[] =
    "runtime.interactive.surface.acknowledge.ack";
static const char MCLocalXPCInteractiveSurfaceFailureKind[] =
    "runtime.interactive.surface.failure";
static const char MCLocalXPCInteractiveSurfaceFailureAcknowledgementKind[] =
    "runtime.interactive.surface.failure.ack";
static const char MCLocalXPCInteractiveAdmissionPublicationKind[] =
    "runtime.interactive.admission.publish";
static const char MCLocalXPCInteractiveAdmissionAcknowledgementKind[] =
    "runtime.interactive.admission.publish.ack";
static const char MCLocalXPCInteractiveInputKind[] =
    "runtime.interactive.input.apply";
static const char MCLocalXPCInteractiveInputAcknowledgementKind[] =
    "runtime.interactive.input.apply.ack";
static const char MCLocalXPCInteractiveMediaPublicationKind[] =
    "runtime.interactive.media.publish";
static const char MCLocalXPCInteractiveMediaAcknowledgementKind[] =
    "runtime.interactive.media.publish.ack";

static const char * _Nullable MCLocalXPCMenuPairingCommandRequestKind(
    MCLocalXPCMenuPairingCommandKind kind
) {
    switch (kind) {
    case MCLocalXPCMenuPairingCommandCreate:
        return MCLocalXPCPairingSessionCreateKind;
    case MCLocalXPCMenuPairingCommandDismiss:
        return MCLocalXPCPairingSessionDismissKind;
    case MCLocalXPCMenuPairingCommandResolveDecision:
        return MCLocalXPCPairingDecisionResolveKind;
    }
    return NULL;
}

static const char * _Nullable
MCLocalXPCMenuPairingCommandAcknowledgementKind(
    MCLocalXPCMenuPairingCommandKind kind
) {
    switch (kind) {
    case MCLocalXPCMenuPairingCommandCreate:
        return MCLocalXPCPairingSessionCreateAcknowledgementKind;
    case MCLocalXPCMenuPairingCommandDismiss:
        return MCLocalXPCPairingSessionDismissAcknowledgementKind;
    case MCLocalXPCMenuPairingCommandResolveDecision:
        return MCLocalXPCPairingDecisionResolveAcknowledgementKind;
    }
    return NULL;
}

static const char * _Nullable MCLocalXPCMenuPairingCommandFailureKind(
    MCLocalXPCMenuPairingCommandKind kind
) {
    switch (kind) {
    case MCLocalXPCMenuPairingCommandCreate:
        return MCLocalXPCPairingSessionCreateFailureKind;
    case MCLocalXPCMenuPairingCommandDismiss:
        return MCLocalXPCPairingSessionDismissFailureKind;
    case MCLocalXPCMenuPairingCommandResolveDecision:
        return MCLocalXPCPairingDecisionResolveFailureKind;
    }
    return NULL;
}

static const char * _Nullable MCLocalXPCInteractiveLeaseRequestKind(
    MCLocalXPCInteractiveLeaseCommandKind kind
) {
    switch (kind) {
    case MCLocalXPCInteractiveLeaseCommandInstall:
        return MCLocalXPCInteractiveLeaseInstallKind;
    case MCLocalXPCInteractiveLeaseCommandRenew:
        return MCLocalXPCInteractiveLeaseRenewKind;
    case MCLocalXPCInteractiveLeaseCommandRevoke:
        return MCLocalXPCInteractiveLeaseRevokeKind;
    case MCLocalXPCInteractiveLeaseCommandPrepareInitialDesktop:
        return MCLocalXPCInteractiveInitialDesktopPrepareKind;
    case MCLocalXPCInteractiveLeaseCommandSurfaceTargets:
        return MCLocalXPCInteractiveSurfaceTargetsKind;
    case MCLocalXPCInteractiveLeaseCommandSurfaceResolve:
        return MCLocalXPCInteractiveSurfaceResolveKind;
    case MCLocalXPCInteractiveLeaseCommandSurfaceTransition:
        return MCLocalXPCInteractiveSurfaceTransitionKind;
    case MCLocalXPCInteractiveLeaseCommandSurfaceAcknowledgement:
        return MCLocalXPCInteractiveSurfaceAcknowledgementKind;
    case MCLocalXPCInteractiveLeaseCommandSurfaceFailure:
        return MCLocalXPCInteractiveSurfaceFailureKind;
    }
    return NULL;
}

static const char * _Nullable MCLocalXPCInteractiveLeaseAcknowledgementKind(
    MCLocalXPCInteractiveLeaseCommandKind kind
) {
    switch (kind) {
    case MCLocalXPCInteractiveLeaseCommandInstall:
        return MCLocalXPCInteractiveLeaseInstallAcknowledgementKind;
    case MCLocalXPCInteractiveLeaseCommandRenew:
        return MCLocalXPCInteractiveLeaseRenewAcknowledgementKind;
    case MCLocalXPCInteractiveLeaseCommandRevoke:
        return MCLocalXPCInteractiveLeaseRevokeAcknowledgementKind;
    case MCLocalXPCInteractiveLeaseCommandPrepareInitialDesktop:
        return MCLocalXPCInteractiveInitialDesktopPrepareAcknowledgementKind;
    case MCLocalXPCInteractiveLeaseCommandSurfaceTargets:
        return MCLocalXPCInteractiveSurfaceTargetsAcknowledgementKind;
    case MCLocalXPCInteractiveLeaseCommandSurfaceResolve:
        return MCLocalXPCInteractiveSurfaceResolveAcknowledgementKind;
    case MCLocalXPCInteractiveLeaseCommandSurfaceTransition:
        return MCLocalXPCInteractiveSurfaceTransitionAcknowledgementKind;
    case MCLocalXPCInteractiveLeaseCommandSurfaceAcknowledgement:
        return MCLocalXPCInteractiveSurfaceAcknowledgementAcknowledgementKind;
    case MCLocalXPCInteractiveLeaseCommandSurfaceFailure:
        return MCLocalXPCInteractiveSurfaceFailureAcknowledgementKind;
    }
    return NULL;
}

static bool MCLocalXPCInteractiveLeaseReplyCarriesPayload(
    MCLocalXPCInteractiveLeaseCommandKind kind
) {
    return kind == MCLocalXPCInteractiveLeaseCommandPrepareInitialDesktop
        || kind == MCLocalXPCInteractiveLeaseCommandInstall
        || kind == MCLocalXPCInteractiveLeaseCommandRevoke
        || kind == MCLocalXPCInteractiveLeaseCommandSurfaceTargets
        || kind == MCLocalXPCInteractiveLeaseCommandSurfaceResolve
        || kind == MCLocalXPCInteractiveLeaseCommandSurfaceTransition
        || kind == MCLocalXPCInteractiveLeaseCommandSurfaceAcknowledgement
        || kind == MCLocalXPCInteractiveLeaseCommandSurfaceFailure;
}

static void MCLocalXPCReleaseError(xpc_rich_error_t error) {
    if (error != NULL) {
        xpc_release(error);
    }
}

static bool MCLocalXPCMessageIsExact(
    xpc_object_t message,
    const char *expected_kind
) {
    if (message == NULL
        || xpc_get_type(message) != XPC_TYPE_DICTIONARY) {
        return false;
    }

    __block size_t field_count = 0;
    __block bool fields_are_closed = true;
    xpc_dictionary_apply(
        message,
        ^bool(const char *key, xpc_object_t value) {
            field_count += 1;
            if (strcmp(key, "kind") == 0) {
                fields_are_closed = fields_are_closed
                    && xpc_get_type(value) == XPC_TYPE_STRING;
            } else if (strcmp(key, "version") == 0) {
                fields_are_closed = fields_are_closed
                    && xpc_get_type(value) == XPC_TYPE_INT64;
            } else {
                fields_are_closed = false;
            }
            return true;
        }
    );

    const char *kind = xpc_dictionary_get_string(message, "kind");
    return field_count == 2
        && fields_are_closed
        && kind != NULL
        && strcmp(kind, expected_kind) == 0
        && xpc_dictionary_get_int64(message, "version") == 1;
}

static bool MCLocalXPCMessageGetExactData(
    xpc_object_t message,
    const char *expected_kind,
    size_t maximum_payload_length,
    const uint8_t **payload_out,
    size_t *payload_length_out
) {
    if (message == NULL
        || xpc_get_type(message) != XPC_TYPE_DICTIONARY) {
        return false;
    }

    __block size_t field_count = 0;
    __block bool fields_are_closed = true;
    xpc_dictionary_apply(
        message,
        ^bool(const char *key, xpc_object_t value) {
            field_count += 1;
            if (strcmp(key, "kind") == 0) {
                fields_are_closed = fields_are_closed
                    && xpc_get_type(value) == XPC_TYPE_STRING;
            } else if (strcmp(key, "version") == 0) {
                fields_are_closed = fields_are_closed
                    && xpc_get_type(value) == XPC_TYPE_INT64;
            } else if (strcmp(key, "payload") == 0) {
                fields_are_closed = fields_are_closed
                    && xpc_get_type(value) == XPC_TYPE_DATA;
            } else {
                fields_are_closed = false;
            }
            return true;
        }
    );

    const char *kind = xpc_dictionary_get_string(message, "kind");
    size_t length = 0;
    const void *payload = xpc_dictionary_get_data(
        message,
        "payload",
        &length
    );
    bool valid = field_count == 3
        && fields_are_closed
        && kind != NULL
        && strcmp(kind, expected_kind) == 0
        && xpc_dictionary_get_int64(message, "version") == 1
        && payload != NULL
        && length > 0
        && length <= maximum_payload_length;
    if (!valid) {
        return false;
    }
    if (payload_out != NULL) {
        *payload_out = (const uint8_t *)payload;
    }
    if (payload_length_out != NULL) {
        *payload_length_out = length;
    }
    return true;
}

static bool MCLocalXPCMessageIsExactStatusSuccess(
    xpc_object_t message,
    const void **payload_out,
    size_t *payload_length_out
) {
    if (message == NULL
        || xpc_get_type(message) != XPC_TYPE_DICTIONARY) {
        return false;
    }

    __block size_t field_count = 0;
    __block bool fields_are_closed = true;
    xpc_dictionary_apply(
        message,
        ^bool(const char *key, xpc_object_t value) {
            field_count += 1;
            if (strcmp(key, "kind") == 0) {
                fields_are_closed = fields_are_closed
                    && xpc_get_type(value) == XPC_TYPE_STRING;
            } else if (strcmp(key, "version") == 0) {
                fields_are_closed = fields_are_closed
                    && xpc_get_type(value) == XPC_TYPE_INT64;
            } else if (strcmp(key, "payload") == 0) {
                fields_are_closed = fields_are_closed
                    && xpc_get_type(value) == XPC_TYPE_DATA;
            } else {
                fields_are_closed = false;
            }
            return true;
        }
    );

    const char *kind = xpc_dictionary_get_string(message, "kind");
    size_t length = 0;
    const void *payload = xpc_dictionary_get_data(
        message,
        "payload",
        &length
    );
    if (payload_out != NULL) {
        *payload_out = payload;
    }
    if (payload_length_out != NULL) {
        *payload_length_out = length;
    }
    return field_count == 3
        && fields_are_closed
        && kind != NULL
        && strcmp(kind, "status.read.ack") == 0
        && xpc_dictionary_get_int64(message, "version") == 1
        && length > 0
        && length <= MCLocalXPCMaximumStatusPayloadBytes;
}

static bool MCLocalXPCMessageIsExactStatusUnavailable(
    xpc_object_t message
) {
    if (message == NULL
        || xpc_get_type(message) != XPC_TYPE_DICTIONARY) {
        return false;
    }

    __block size_t field_count = 0;
    __block bool fields_are_closed = true;
    xpc_dictionary_apply(
        message,
        ^bool(const char *key, xpc_object_t value) {
            field_count += 1;
            if (strcmp(key, "kind") == 0
                || strcmp(key, "code") == 0) {
                fields_are_closed = fields_are_closed
                    && xpc_get_type(value) == XPC_TYPE_STRING;
            } else if (strcmp(key, "version") == 0) {
                fields_are_closed = fields_are_closed
                    && xpc_get_type(value) == XPC_TYPE_INT64;
            } else {
                fields_are_closed = false;
            }
            return true;
        }
    );

    const char *kind = xpc_dictionary_get_string(message, "kind");
    const char *code = xpc_dictionary_get_string(message, "code");
    return field_count == 3
        && fields_are_closed
        && kind != NULL
        && strcmp(kind, "status.read.error") == 0
        && code != NULL
        && strcmp(code, "sourceUnavailable") == 0
        && xpc_dictionary_get_int64(message, "version") == 1;
}

static bool MCLocalXPCMessageGetExactPresentationPublish(
    xpc_object_t message,
    const char *expected_kind,
    const uint8_t **payload_out,
    size_t *payload_length_out
) {
    if (message == NULL
        || xpc_get_type(message) != XPC_TYPE_DICTIONARY) {
        return false;
    }

    __block size_t field_count = 0;
    __block bool fields_are_closed = true;
    xpc_dictionary_apply(
        message,
        ^bool(const char *key, xpc_object_t value) {
            field_count += 1;
            if (strcmp(key, "kind") == 0) {
                fields_are_closed = fields_are_closed
                    && xpc_get_type(value) == XPC_TYPE_STRING;
            } else if (strcmp(key, "version") == 0) {
                fields_are_closed = fields_are_closed
                    && xpc_get_type(value) == XPC_TYPE_INT64;
            } else if (strcmp(key, "payload") == 0) {
                fields_are_closed = fields_are_closed
                    && xpc_get_type(value) == XPC_TYPE_DATA;
            } else {
                fields_are_closed = false;
            }
            return true;
        }
    );

    const char *kind = xpc_dictionary_get_string(message, "kind");
    size_t payload_length = 0;
    const uint8_t *payload = xpc_dictionary_get_data(
        message,
        "payload",
        &payload_length
    );
    bool exact = field_count == 3
        && fields_are_closed
        && kind != NULL
        && strcmp(kind, expected_kind) == 0
        && xpc_dictionary_get_int64(message, "version") == 1
        && payload != NULL
        && payload_length > 0
        && payload_length
            <= MCLocalXPCMaximumMenuPresentationPayloadBytes;
    if (!exact) {
        return false;
    }
    if (payload_out != NULL) {
        *payload_out = payload;
    }
    if (payload_length_out != NULL) {
        *payload_length_out = payload_length;
    }
    return true;
}

static const uint8_t *MCLocalXPCMessageGetExactPresentationWithdrawal(
    xpc_object_t message,
    const char *expected_kind
) {
    if (message == NULL
        || xpc_get_type(message) != XPC_TYPE_DICTIONARY) {
        return NULL;
    }

    __block size_t field_count = 0;
    __block bool fields_are_closed = true;
    xpc_dictionary_apply(
        message,
        ^bool(const char *key, xpc_object_t value) {
            field_count += 1;
            if (strcmp(key, "kind") == 0) {
                fields_are_closed = fields_are_closed
                    && xpc_get_type(value) == XPC_TYPE_STRING;
            } else if (strcmp(key, "version") == 0) {
                fields_are_closed = fields_are_closed
                    && xpc_get_type(value) == XPC_TYPE_INT64;
            } else if (strcmp(key, "reviewID") == 0) {
                fields_are_closed = fields_are_closed
                    && xpc_get_type(value) == XPC_TYPE_UUID;
            } else {
                fields_are_closed = false;
            }
            return true;
        }
    );

    const char *kind = xpc_dictionary_get_string(message, "kind");
    const uint8_t *review_id = xpc_dictionary_get_uuid(
        message,
        "reviewID"
    );
    if (field_count != 3
        || !fields_are_closed
        || kind == NULL
        || strcmp(kind, expected_kind) != 0
        || xpc_dictionary_get_int64(message, "version") != 1
        || review_id == NULL) {
        return NULL;
    }
    static const uint8_t zero_uuid[16] = {0};
    return memcmp(review_id, zero_uuid, sizeof(zero_uuid)) == 0
        ? NULL
        : review_id;
}

static bool MCLocalXPCReviewIDBytesAreValid(
    const uint8_t *review_id,
    size_t review_id_length
) {
    static const uint8_t zero_uuid[16] = {0};
    return review_id != NULL
        && review_id_length == sizeof(zero_uuid)
        && memcmp(review_id, zero_uuid, sizeof(zero_uuid)) != 0;
}

static xpc_object_t _Nullable MCLocalXPCCreatePresentationPublish(
    const char *kind,
    const uint8_t *payload,
    size_t payload_length
) {
    if (payload == NULL
        || payload_length == 0
        || payload_length
            > MCLocalXPCMaximumMenuPresentationPayloadBytes) {
        return NULL;
    }
    xpc_object_t request = xpc_dictionary_create_empty();
    if (request == NULL) {
        return NULL;
    }
    xpc_dictionary_set_string(request, "kind", kind);
    xpc_dictionary_set_int64(request, "version", 1);
    xpc_dictionary_set_data(
        request,
        "payload",
        payload,
        payload_length
    );
    return request;
}

static xpc_object_t _Nullable MCLocalXPCCreatePresentationWithdrawal(
    const char *kind,
    const uint8_t *review_id,
    size_t review_id_length
) {
    if (!MCLocalXPCReviewIDBytesAreValid(
            review_id,
            review_id_length
        )) {
        return NULL;
    }
    xpc_object_t request = xpc_dictionary_create_empty();
    if (request == NULL) {
        return NULL;
    }
    xpc_dictionary_set_string(request, "kind", kind);
    xpc_dictionary_set_int64(request, "version", 1);
    xpc_dictionary_set_uuid(request, "reviewID", review_id);
    return request;
}

static bool MCLocalXPCMessageIsExactPresentationRejected(
    xpc_object_t message,
    const char *expected_kind
) {
    if (message == NULL
        || xpc_get_type(message) != XPC_TYPE_DICTIONARY) {
        return false;
    }

    __block size_t field_count = 0;
    __block bool fields_are_closed = true;
    xpc_dictionary_apply(
        message,
        ^bool(const char *key, xpc_object_t value) {
            field_count += 1;
            if (strcmp(key, "kind") == 0
                || strcmp(key, "code") == 0) {
                fields_are_closed = fields_are_closed
                    && xpc_get_type(value) == XPC_TYPE_STRING;
            } else if (strcmp(key, "version") == 0) {
                fields_are_closed = fields_are_closed
                    && xpc_get_type(value) == XPC_TYPE_INT64;
            } else {
                fields_are_closed = false;
            }
            return true;
        }
    );

    const char *kind = xpc_dictionary_get_string(message, "kind");
    const char *code = xpc_dictionary_get_string(message, "code");
    return field_count == 3
        && fields_are_closed
        && kind != NULL
        && strcmp(kind, expected_kind) == 0
        && code != NULL
        && strcmp(code, "presentationRejected") == 0
        && xpc_dictionary_get_int64(message, "version") == 1;
}

static MCLocalXPCMenuPresentationReply
MCLocalXPCClassifyMenuPresentationReply(
    xpc_object_t reply,
    xpc_rich_error_t error,
    const char *acknowledgement_kind,
    const char * _Nullable rejection_kind
);

MCLocalXPCListenerRef MCLocalXPCListenerCreateInactive(
    const char *service_name,
    dispatch_queue_t queue,
    MCLocalXPCIncomingSessionHandler handler,
    MCLocalXPCResult *result_out
) {
    xpc_rich_error_t error = NULL;
    xpc_listener_t listener = xpc_listener_create(
        service_name,
        queue,
        XPC_LISTENER_CREATE_INACTIVE | XPC_LISTENER_CREATE_FORCE_MACH,
        ^(xpc_session_t peer) {
            handler((MCLocalXPCSessionRef)peer);
        },
        &error
    );
    if (listener == NULL) {
        MCLocalXPCReleaseError(error);
        if (result_out != NULL) {
            *result_out = MCLocalXPCResultConstructionFailed;
        }
        return NULL;
    }
    MCLocalXPCReleaseError(error);
    if (result_out != NULL) {
        *result_out = MCLocalXPCResultOK;
    }
    return (MCLocalXPCListenerRef)listener;
}

MCLocalXPCPeerRequirementRef
MCLocalXPCPeerRequirementCreateSameTeamIdentifier(
    const char *signing_identifier,
    MCLocalXPCResult *result_out
) {
    xpc_rich_error_t error = NULL;
    xpc_peer_requirement_t requirement =
        xpc_peer_requirement_create_team_identity(signing_identifier, &error);
    if (requirement == NULL) {
        MCLocalXPCReleaseError(error);
        if (result_out != NULL) {
            *result_out = MCLocalXPCResultRequirementFailed;
        }
        return NULL;
    }
    MCLocalXPCReleaseError(error);
    if (result_out != NULL) {
        *result_out = MCLocalXPCResultOK;
    }
    return (MCLocalXPCPeerRequirementRef)requirement;
}

void MCLocalXPCPeerRequirementRelease(
    MCLocalXPCPeerRequirementRef requirement
) {
    xpc_release((xpc_peer_requirement_t)requirement);
}

void MCLocalXPCListenerSetPeerRequirement(
    MCLocalXPCListenerRef listener,
    MCLocalXPCPeerRequirementRef requirement
) {
    xpc_listener_set_peer_requirement(
        (xpc_listener_t)listener,
        (xpc_peer_requirement_t)requirement
    );
}

MCLocalXPCResult MCLocalXPCListenerActivate(
    MCLocalXPCListenerRef listener
) {
    xpc_rich_error_t error = NULL;
    bool activated = xpc_listener_activate((xpc_listener_t)listener, &error);
    MCLocalXPCReleaseError(error);
    return activated
        ? MCLocalXPCResultOK
        : MCLocalXPCResultActivationFailed;
}

void MCLocalXPCListenerCancel(MCLocalXPCListenerRef listener) {
    xpc_listener_cancel((xpc_listener_t)listener);
    xpc_release((xpc_listener_t)listener);
}

void MCLocalXPCListenerRejectPeer(MCLocalXPCSessionRef peer) {
    xpc_listener_reject_peer(
        (xpc_session_t)peer,
        "Mac Companion listener is not accepting this peer"
    );
}

MCLocalXPCSessionRef MCLocalXPCSessionCreateInactive(
    const char *service_name,
    dispatch_queue_t queue,
    MCLocalXPCResult *result_out
) {
    xpc_rich_error_t error = NULL;
    xpc_session_t session = xpc_session_create_mach_service(
        service_name,
        queue,
        XPC_SESSION_CREATE_INACTIVE,
        &error
    );
    if (session == NULL) {
        MCLocalXPCReleaseError(error);
        if (result_out != NULL) {
            *result_out = MCLocalXPCResultConstructionFailed;
        }
        return NULL;
    }
    MCLocalXPCReleaseError(error);
    if (result_out != NULL) {
        *result_out = MCLocalXPCResultOK;
    }
    return (MCLocalXPCSessionRef)session;
}

void MCLocalXPCSessionSetPeerRequirement(
    MCLocalXPCSessionRef session,
    MCLocalXPCPeerRequirementRef requirement
) {
    xpc_session_set_peer_requirement(
        (xpc_session_t)session,
        (xpc_peer_requirement_t)requirement
    );
}

void MCLocalXPCSessionSetCancelHandler(
    MCLocalXPCSessionRef session,
    MCLocalXPCCancelHandler handler
) {
    xpc_session_set_cancel_handler(
        (xpc_session_t)session,
        ^(xpc_rich_error_t _) {
            handler();
        }
    );
}

void MCLocalXPCSessionSetMessageHandler(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageHandler handler
) {
    xpc_session_set_incoming_message_handler(
        (xpc_session_t)session,
        ^(xpc_object_t message) {
            handler((MCLocalXPCMessageRef)message);
        }
    );
}

MCLocalXPCResult MCLocalXPCSessionActivate(
    MCLocalXPCSessionRef session
) {
    xpc_rich_error_t error = NULL;
    bool activated = xpc_session_activate((xpc_session_t)session, &error);
    MCLocalXPCReleaseError(error);
    return activated
        ? MCLocalXPCResultOK
        : MCLocalXPCResultActivationFailed;
}

void MCLocalXPCSessionCancel(MCLocalXPCSessionRef session) {
    xpc_session_cancel((xpc_session_t)session);
}

void MCLocalXPCSessionDisposeAfterFailedActivation(
    MCLocalXPCSessionRef session
) {
    xpc_release((xpc_session_t)session);
}

void MCLocalXPCSessionRetain(MCLocalXPCSessionRef session) {
    xpc_retain((xpc_session_t)session);
}

void MCLocalXPCSessionCancelOwned(MCLocalXPCSessionRef session) {
    xpc_session_cancel((xpc_session_t)session);
    xpc_release((xpc_session_t)session);
}

void MCLocalXPCSessionRelease(MCLocalXPCSessionRef session) {
    xpc_release((xpc_session_t)session);
}

bool MCLocalXPCMessageIsExactHello(MCLocalXPCMessageRef message) {
    return MCLocalXPCMessageIsExact((xpc_object_t)message, "hello");
}

bool MCLocalXPCMessageIsExactHelloAcknowledgement(
    MCLocalXPCMessageRef message
) {
    return MCLocalXPCMessageIsExact(
        (xpc_object_t)message,
        "hello.ack"
    );
}

bool MCLocalXPCMessageIsExactMenuReady(MCLocalXPCMessageRef message) {
    return MCLocalXPCMessageIsExact(
        (xpc_object_t)message,
        "lifecycle.menu-ready"
    );
}

bool MCLocalXPCMessageIsExactMenuReadyAcknowledgement(
    MCLocalXPCMessageRef message
) {
    return MCLocalXPCMessageIsExact(
        (xpc_object_t)message,
        "lifecycle.menu-ready.ack"
    );
}
bool MCLocalXPCMessageIsExactStatusRead(MCLocalXPCMessageRef message) {
    return MCLocalXPCMessageIsExact(
        (xpc_object_t)message,
        "status.read"
    );
}

bool MCLocalXPCMessageIsExactRemoteAccessBootstrapRead(
    MCLocalXPCMessageRef message
) {
    return MCLocalXPCMessageIsExact(
        (xpc_object_t)message,
        MCLocalXPCRemoteAccessBootstrapReadKind
    );
}

bool MCLocalXPCMessageGetExactRemoteAccessEnable(
    MCLocalXPCMessageRef message,
    const uint8_t **payload_out,
    size_t *payload_length_out
) {
    return MCLocalXPCMessageGetExactData(
        (xpc_object_t)message,
        MCLocalXPCRemoteAccessEnableKind,
        MCLocalXPCMaximumBootstrapPayloadBytes,
        payload_out,
        payload_length_out
    );
}

bool MCLocalXPCMessageGetExactMenuPairingCommand(
    MCLocalXPCMessageRef message,
    MCLocalXPCMenuPairingCommandKind *kind_out,
    const uint8_t **payload_out,
    size_t *payload_length_out
) {
    const MCLocalXPCMenuPairingCommandKind kinds[] = {
        MCLocalXPCMenuPairingCommandCreate,
        MCLocalXPCMenuPairingCommandDismiss,
        MCLocalXPCMenuPairingCommandResolveDecision,
    };
    for (size_t index = 0;
         index < sizeof(kinds) / sizeof(kinds[0]);
         index += 1) {
        const char *request_kind =
            MCLocalXPCMenuPairingCommandRequestKind(kinds[index]);
        const uint8_t *payload = NULL;
        size_t payload_length = 0;
        if (request_kind != NULL
            && MCLocalXPCMessageGetExactData(
                (xpc_object_t)message,
                request_kind,
                MCLocalXPCMaximumMenuPairingCommandPayloadBytes,
                &payload,
                &payload_length
            )) {
            if (kind_out != NULL) {
                *kind_out = kinds[index];
            }
            if (payload_out != NULL) {
                *payload_out = payload;
            }
            if (payload_length_out != NULL) {
                *payload_length_out = payload_length;
            }
            return true;
        }
    }
    return false;
}

bool MCLocalXPCMessageGetExactInteractiveLeaseCommand(
    MCLocalXPCMessageRef message,
    MCLocalXPCInteractiveLeaseCommandKind *kind_out,
    const uint8_t **payload_out,
    size_t *payload_length_out
) {
    const MCLocalXPCInteractiveLeaseCommandKind kinds[] = {
        MCLocalXPCInteractiveLeaseCommandPrepareInitialDesktop,
        MCLocalXPCInteractiveLeaseCommandInstall,
        MCLocalXPCInteractiveLeaseCommandRenew,
        MCLocalXPCInteractiveLeaseCommandRevoke,
        MCLocalXPCInteractiveLeaseCommandSurfaceTargets,
        MCLocalXPCInteractiveLeaseCommandSurfaceResolve,
        MCLocalXPCInteractiveLeaseCommandSurfaceTransition,
        MCLocalXPCInteractiveLeaseCommandSurfaceAcknowledgement,
        MCLocalXPCInteractiveLeaseCommandSurfaceFailure,
    };
    for (size_t index = 0;
         index < sizeof(kinds) / sizeof(kinds[0]);
         index += 1) {
        const char *request_kind =
            MCLocalXPCInteractiveLeaseRequestKind(kinds[index]);
        const uint8_t *payload = NULL;
        size_t payload_length = 0;
        if (request_kind != NULL
            && MCLocalXPCMessageGetExactData(
                (xpc_object_t)message,
                request_kind,
                MCLocalXPCMaximumInteractiveLeasePayloadBytes,
                &payload,
                &payload_length
            )) {
            if (kind_out != NULL) {
                *kind_out = kinds[index];
            }
            if (payload_out != NULL) {
                *payload_out = payload;
            }
            if (payload_length_out != NULL) {
                *payload_length_out = payload_length;
            }
            return true;
        }
    }
    return false;
}

bool MCLocalXPCMessageGetExactInteractiveAdmissionPublication(
    MCLocalXPCMessageRef message,
    const uint8_t **payload_out,
    size_t *payload_length_out
) {
    return MCLocalXPCMessageGetExactData(
        (xpc_object_t)message,
        MCLocalXPCInteractiveAdmissionPublicationKind,
        MCLocalXPCMaximumInteractiveAdmissionPayloadBytes,
        payload_out,
        payload_length_out
    );
}

bool MCLocalXPCMessageGetExactInteractiveInput(
    MCLocalXPCMessageRef message,
    const uint8_t **payload_out,
    size_t *payload_length_out
) {
    return MCLocalXPCMessageGetExactData(
        (xpc_object_t)message,
        MCLocalXPCInteractiveInputKind,
        MCLocalXPCMaximumInteractiveInputPayloadBytes,
        payload_out,
        payload_length_out
    );
}

bool MCLocalXPCMessageGetExactInteractiveMediaPublication(
    MCLocalXPCMessageRef message,
    const uint8_t **header_out,
    size_t *header_length_out,
    const uint8_t **payload_out,
    size_t *payload_length_out
) {
    xpc_object_t value = (xpc_object_t)message;
    if (value == NULL || xpc_get_type(value) != XPC_TYPE_DICTIONARY) {
        return false;
    }
    __block size_t field_count = 0;
    __block bool fields_are_closed = true;
    xpc_dictionary_apply(
        value,
        ^bool(const char *key, xpc_object_t field) {
            field_count += 1;
            if (strcmp(key, "kind") == 0) {
                fields_are_closed = fields_are_closed
                    && xpc_get_type(field) == XPC_TYPE_STRING;
            } else if (strcmp(key, "version") == 0) {
                fields_are_closed = fields_are_closed
                    && xpc_get_type(field) == XPC_TYPE_INT64;
            } else if (strcmp(key, "header") == 0
                       || strcmp(key, "payload") == 0) {
                fields_are_closed = fields_are_closed
                    && xpc_get_type(field) == XPC_TYPE_DATA;
            } else {
                fields_are_closed = false;
            }
            return true;
        }
    );
    const char *kind = xpc_dictionary_get_string(value, "kind");
    size_t header_length = 0;
    const void *header = xpc_dictionary_get_data(
        value,
        "header",
        &header_length
    );
    size_t payload_length = 0;
    const void *payload = xpc_dictionary_get_data(
        value,
        "payload",
        &payload_length
    );
    bool valid = field_count == 4
        && fields_are_closed
        && kind != NULL
        && strcmp(kind, MCLocalXPCInteractiveMediaPublicationKind) == 0
        && xpc_dictionary_get_int64(value, "version") == 1
        && header != NULL
        && header_length == MCLocalXPCInteractiveMediaHeaderBytes
        && (payload != NULL || payload_length == 0)
        && payload_length <= MCLocalXPCMaximumInteractiveMediaPayloadBytes;
    if (!valid) {
        return false;
    }
    if (header_out != NULL) {
        *header_out = (const uint8_t *)header;
    }
    if (header_length_out != NULL) {
        *header_length_out = header_length;
    }
    if (payload_out != NULL) {
        *payload_out = (const uint8_t *)payload;
    }
    if (payload_length_out != NULL) {
        *payload_length_out = payload_length;
    }
    return true;
}

MCLocalXPCMessageRef MCLocalXPCMessageCreatePairingReviewPublish(
    const uint8_t *payload,
    size_t payload_length
) {
    return (MCLocalXPCMessageRef)MCLocalXPCCreatePresentationPublish(
        MCLocalXPCPairingReviewPublishKind,
        payload,
        payload_length
    );
}

MCLocalXPCMessageRef MCLocalXPCMessageCreatePairingReviewWithdrawal(
    const uint8_t *review_id,
    size_t review_id_length
) {
    return (MCLocalXPCMessageRef)MCLocalXPCCreatePresentationWithdrawal(
        MCLocalXPCPairingReviewWithdrawalKind,
        review_id,
        review_id_length
    );
}

MCLocalXPCMessageRef MCLocalXPCMessageCreateHostRecoveryReviewPublish(
    const uint8_t *payload,
    size_t payload_length
) {
    return (MCLocalXPCMessageRef)MCLocalXPCCreatePresentationPublish(
        MCLocalXPCHostRecoveryReviewPublishKind,
        payload,
        payload_length
    );
}

MCLocalXPCMessageRef MCLocalXPCMessageCreateHostRecoveryResumePublish(
    const uint8_t *payload,
    size_t payload_length
) {
    return (MCLocalXPCMessageRef)MCLocalXPCCreatePresentationPublish(
        MCLocalXPCHostRecoveryResumePublishKind,
        payload,
        payload_length
    );
}

MCLocalXPCMessageRef MCLocalXPCMessageCreateHostRecoveryWithdrawal(
    const uint8_t *review_id,
    size_t review_id_length
) {
    return (MCLocalXPCMessageRef)MCLocalXPCCreatePresentationWithdrawal(
        MCLocalXPCHostRecoveryWithdrawalKind,
        review_id,
        review_id_length
    );
}

bool MCLocalXPCMessageGetExactPairingReviewPublish(
    MCLocalXPCMessageRef message,
    const uint8_t **payload_out,
    size_t *payload_length_out
) {
    return MCLocalXPCMessageGetExactPresentationPublish(
        (xpc_object_t)message,
        MCLocalXPCPairingReviewPublishKind,
        payload_out,
        payload_length_out
    );
}

const uint8_t *MCLocalXPCMessageGetExactPairingReviewWithdrawal(
    MCLocalXPCMessageRef message
) {
    return MCLocalXPCMessageGetExactPresentationWithdrawal(
        (xpc_object_t)message,
        MCLocalXPCPairingReviewWithdrawalKind
    );
}

bool MCLocalXPCMessageGetExactHostRecoveryReviewPublish(
    MCLocalXPCMessageRef message,
    const uint8_t **payload_out,
    size_t *payload_length_out
) {
    return MCLocalXPCMessageGetExactPresentationPublish(
        (xpc_object_t)message,
        MCLocalXPCHostRecoveryReviewPublishKind,
        payload_out,
        payload_length_out
    );
}

bool MCLocalXPCMessageGetExactHostRecoveryResumePublish(
    MCLocalXPCMessageRef message,
    const uint8_t **payload_out,
    size_t *payload_length_out
) {
    return MCLocalXPCMessageGetExactPresentationPublish(
        (xpc_object_t)message,
        MCLocalXPCHostRecoveryResumePublishKind,
        payload_out,
        payload_length_out
    );
}

const uint8_t *MCLocalXPCMessageGetExactHostRecoveryWithdrawal(
    MCLocalXPCMessageRef message
) {
    return MCLocalXPCMessageGetExactPresentationWithdrawal(
        (xpc_object_t)message,
        MCLocalXPCHostRecoveryWithdrawalKind
    );
}

void MCLocalXPCMessageRetain(MCLocalXPCMessageRef message) {
    xpc_retain((xpc_object_t)message);
}

void MCLocalXPCMessageRelease(MCLocalXPCMessageRef message) {
    xpc_release((xpc_object_t)message);
}


bool MCLocalXPCExactMessageParserSelfTest(void) {
    bool valid = true;

    xpc_object_t exact = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(exact, "kind", "hello");
    xpc_dictionary_set_int64(exact, "version", 1);
    valid = valid && MCLocalXPCMessageIsExact(exact, "hello");
    xpc_release(exact);

    xpc_object_t unsigned_version = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(unsigned_version, "kind", "hello");
    xpc_dictionary_set_uint64(unsigned_version, "version", 1);
    valid = valid
        && !MCLocalXPCMessageIsExact(unsigned_version, "hello");
    xpc_release(unsigned_version);

    xpc_object_t double_version = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(double_version, "kind", "hello");
    xpc_dictionary_set_double(double_version, "version", 1.0);
    valid = valid
        && !MCLocalXPCMessageIsExact(double_version, "hello");
    xpc_release(double_version);

    xpc_object_t bool_version = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(bool_version, "kind", "hello");
    xpc_dictionary_set_bool(bool_version, "version", true);
    valid = valid
        && !MCLocalXPCMessageIsExact(bool_version, "hello");
    xpc_release(bool_version);

    xpc_object_t missing_version = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(missing_version, "kind", "hello");
    valid = valid
        && !MCLocalXPCMessageIsExact(missing_version, "hello");
    xpc_release(missing_version);

    xpc_object_t extra_field = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(extra_field, "kind", "hello");
    xpc_dictionary_set_int64(extra_field, "version", 1);
    xpc_dictionary_set_string(extra_field, "extra", "rejected");
    valid = valid && !MCLocalXPCMessageIsExact(extra_field, "hello");
    xpc_release(extra_field);

    xpc_object_t wrong_kind_type = xpc_dictionary_create_empty();
    xpc_dictionary_set_int64(wrong_kind_type, "kind", 1);
    xpc_dictionary_set_int64(wrong_kind_type, "version", 1);
    valid = valid
        && !MCLocalXPCMessageIsExact(wrong_kind_type, "hello");
    xpc_release(wrong_kind_type);

    const uint8_t status_bytes[] = {0x7b, 0x7d};
    const void *parsed_status_bytes = NULL;
    size_t parsed_status_length = 0;
    xpc_object_t status_success = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(status_success, "kind", "status.read.ack");
    xpc_dictionary_set_int64(status_success, "version", 1);
    xpc_dictionary_set_data(
        status_success,
        "payload",
        status_bytes,
        sizeof(status_bytes)
    );
    valid = valid && MCLocalXPCMessageIsExactStatusSuccess(
        status_success,
        &parsed_status_bytes,
        &parsed_status_length
    );
    valid = valid
        && parsed_status_length == sizeof(status_bytes)
        && memcmp(
            parsed_status_bytes,
            status_bytes,
            sizeof(status_bytes)
        ) == 0;
    xpc_dictionary_set_bool(status_success, "extra", true);
    valid = valid && !MCLocalXPCMessageIsExactStatusSuccess(
        status_success,
        &parsed_status_bytes,
        &parsed_status_length
    );
    xpc_release(status_success);

    xpc_object_t status_unavailable = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        status_unavailable,
        "kind",
        "status.read.error"
    );
    xpc_dictionary_set_int64(status_unavailable, "version", 1);
    xpc_dictionary_set_string(
        status_unavailable,
        "code",
        "sourceUnavailable"
    );
    valid = valid
        && MCLocalXPCMessageIsExactStatusUnavailable(status_unavailable);
    xpc_dictionary_set_string(status_unavailable, "code", "other");
    valid = valid
        && !MCLocalXPCMessageIsExactStatusUnavailable(status_unavailable);
    xpc_release(status_unavailable);

    xpc_object_t status_request = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(status_request, "kind", "status.read");
    xpc_dictionary_set_int64(status_request, "version", 1);
    valid = valid
        && MCLocalXPCMessageIsExactStatusRead(
            (MCLocalXPCMessageRef)status_request
        );
    xpc_dictionary_set_bool(status_request, "extra", true);
    valid = valid
        && !MCLocalXPCMessageIsExactStatusRead(
            (MCLocalXPCMessageRef)status_request
        );
    xpc_release(status_request);

    xpc_object_t zero_status = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(zero_status, "kind", "status.read.ack");
    xpc_dictionary_set_int64(zero_status, "version", 1);
    xpc_dictionary_set_data(zero_status, "payload", status_bytes, 0);
    valid = valid && !MCLocalXPCMessageIsExactStatusSuccess(
        zero_status,
        &parsed_status_bytes,
        &parsed_status_length
    );
    xpc_release(zero_status);

    xpc_object_t wrong_status_type = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        wrong_status_type,
        "kind",
        "status.read.ack"
    );
    xpc_dictionary_set_int64(wrong_status_type, "version", 1);
    xpc_dictionary_set_string(wrong_status_type, "payload", "{}");
    valid = valid && !MCLocalXPCMessageIsExactStatusSuccess(
        wrong_status_type,
        &parsed_status_bytes,
        &parsed_status_length
    );
    xpc_release(wrong_status_type);

    uint8_t oversized_status[
        MCLocalXPCMaximumStatusPayloadBytes + 1
    ] = {0};
    xpc_object_t oversized_status_reply = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        oversized_status_reply,
        "kind",
        "status.read.ack"
    );
    xpc_dictionary_set_int64(oversized_status_reply, "version", 1);
    xpc_dictionary_set_data(
        oversized_status_reply,
        "payload",
        oversized_status,
        sizeof(oversized_status)
    );
    valid = valid && !MCLocalXPCMessageIsExactStatusSuccess(
        oversized_status_reply,
        &parsed_status_bytes,
        &parsed_status_length
    );
    xpc_release(oversized_status_reply);

    const uint8_t bootstrap_bytes[] = {0x7b, 0x7d};
    const uint8_t *parsed_bootstrap_bytes = NULL;
    size_t parsed_bootstrap_length = 0;
    valid = valid
        && strcmp(
            MCLocalXPCRemoteAccessBootstrapReadKind,
            "bootstrap.remote-access.read"
        ) == 0
        && strcmp(
            MCLocalXPCRemoteAccessBootstrapReadAcknowledgementKind,
            "bootstrap.remote-access.read.ack"
        ) == 0
        && strcmp(
            MCLocalXPCRemoteAccessEnableKind,
            "bootstrap.remote-access.enable"
        ) == 0
        && strcmp(
            MCLocalXPCRemoteAccessEnableAcknowledgementKind,
            "bootstrap.remote-access.enable.ack"
        ) == 0;

    xpc_object_t bootstrap_read = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        bootstrap_read,
        "kind",
        MCLocalXPCRemoteAccessBootstrapReadKind
    );
    xpc_dictionary_set_int64(bootstrap_read, "version", 1);
    valid = valid && MCLocalXPCMessageIsExactRemoteAccessBootstrapRead(
        (MCLocalXPCMessageRef)bootstrap_read
    );
    xpc_dictionary_set_bool(bootstrap_read, "extra", true);
    valid = valid && !MCLocalXPCMessageIsExactRemoteAccessBootstrapRead(
        (MCLocalXPCMessageRef)bootstrap_read
    );
    xpc_release(bootstrap_read);

    xpc_object_t bootstrap_enable = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        bootstrap_enable,
        "kind",
        MCLocalXPCRemoteAccessEnableKind
    );
    xpc_dictionary_set_int64(bootstrap_enable, "version", 1);
    xpc_dictionary_set_data(
        bootstrap_enable,
        "payload",
        bootstrap_bytes,
        sizeof(bootstrap_bytes)
    );
    valid = valid && MCLocalXPCMessageGetExactRemoteAccessEnable(
        (MCLocalXPCMessageRef)bootstrap_enable,
        &parsed_bootstrap_bytes,
        &parsed_bootstrap_length
    );
    valid = valid
        && parsed_bootstrap_length == sizeof(bootstrap_bytes)
        && memcmp(
            parsed_bootstrap_bytes,
            bootstrap_bytes,
            sizeof(bootstrap_bytes)
        ) == 0;
    xpc_dictionary_set_string(bootstrap_enable, "payload", "{}");
    valid = valid && !MCLocalXPCMessageGetExactRemoteAccessEnable(
        (MCLocalXPCMessageRef)bootstrap_enable,
        &parsed_bootstrap_bytes,
        &parsed_bootstrap_length
    );
    xpc_release(bootstrap_enable);

    xpc_object_t bootstrap_offer = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        bootstrap_offer,
        "kind",
        MCLocalXPCRemoteAccessBootstrapReadAcknowledgementKind
    );
    xpc_dictionary_set_int64(bootstrap_offer, "version", 1);
    xpc_dictionary_set_data(
        bootstrap_offer,
        "payload",
        bootstrap_bytes,
        sizeof(bootstrap_bytes)
    );
    valid = valid && MCLocalXPCMessageGetExactData(
        bootstrap_offer,
        MCLocalXPCRemoteAccessBootstrapReadAcknowledgementKind,
        MCLocalXPCMaximumBootstrapPayloadBytes,
        &parsed_bootstrap_bytes,
        &parsed_bootstrap_length
    );
    xpc_release(bootstrap_offer);

    xpc_object_t bootstrap_receipt = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        bootstrap_receipt,
        "kind",
        MCLocalXPCRemoteAccessEnableAcknowledgementKind
    );
    xpc_dictionary_set_int64(bootstrap_receipt, "version", 1);
    xpc_dictionary_set_data(
        bootstrap_receipt,
        "payload",
        bootstrap_bytes,
        sizeof(bootstrap_bytes)
    );
    valid = valid && MCLocalXPCMessageGetExactData(
        bootstrap_receipt,
        MCLocalXPCRemoteAccessEnableAcknowledgementKind,
        MCLocalXPCMaximumBootstrapPayloadBytes,
        &parsed_bootstrap_bytes,
        &parsed_bootstrap_length
    );
    xpc_dictionary_set_int64(bootstrap_receipt, "version", 2);
    valid = valid && !MCLocalXPCMessageGetExactData(
        bootstrap_receipt,
        MCLocalXPCRemoteAccessEnableAcknowledgementKind,
        MCLocalXPCMaximumBootstrapPayloadBytes,
        &parsed_bootstrap_bytes,
        &parsed_bootstrap_length
    );
    xpc_release(bootstrap_receipt);

    uint8_t oversized_bootstrap[
        MCLocalXPCMaximumBootstrapPayloadBytes + 1
    ] = {0};
    xpc_object_t oversized_bootstrap_enable = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        oversized_bootstrap_enable,
        "kind",
        MCLocalXPCRemoteAccessEnableKind
    );
    xpc_dictionary_set_int64(oversized_bootstrap_enable, "version", 1);
    xpc_dictionary_set_data(
        oversized_bootstrap_enable,
        "payload",
        oversized_bootstrap,
        sizeof(oversized_bootstrap)
    );
    valid = valid && !MCLocalXPCMessageGetExactRemoteAccessEnable(
        (MCLocalXPCMessageRef)oversized_bootstrap_enable,
        &parsed_bootstrap_bytes,
        &parsed_bootstrap_length
    );
    xpc_release(oversized_bootstrap_enable);

    const uint8_t menu_command_payload[] = {0x7b, 0x7d};
    const MCLocalXPCMenuPairingCommandKind menu_command_kinds[] = {
        MCLocalXPCMenuPairingCommandCreate,
        MCLocalXPCMenuPairingCommandDismiss,
        MCLocalXPCMenuPairingCommandResolveDecision,
    };
    for (size_t index = 0;
         index < sizeof(menu_command_kinds) / sizeof(menu_command_kinds[0]);
         index += 1) {
        const MCLocalXPCMenuPairingCommandKind expected_kind =
            menu_command_kinds[index];
        const char *request_kind =
            MCLocalXPCMenuPairingCommandRequestKind(expected_kind);
        const char *acknowledgement_kind =
            MCLocalXPCMenuPairingCommandAcknowledgementKind(expected_kind);
        const char *failure_kind =
            MCLocalXPCMenuPairingCommandFailureKind(expected_kind);
        valid = valid
            && request_kind != NULL
            && acknowledgement_kind != NULL
            && failure_kind != NULL;
        xpc_object_t request = xpc_dictionary_create_empty();
        xpc_dictionary_set_string(request, "kind", request_kind);
        xpc_dictionary_set_int64(request, "version", 1);
        xpc_dictionary_set_data(
            request,
            "payload",
            menu_command_payload,
            sizeof(menu_command_payload)
        );
        MCLocalXPCMenuPairingCommandKind parsed_kind =
            MCLocalXPCMenuPairingCommandCreate;
        const uint8_t *parsed_payload = NULL;
        size_t parsed_length = 0;
        valid = valid && MCLocalXPCMessageGetExactMenuPairingCommand(
            (MCLocalXPCMessageRef)request,
            &parsed_kind,
            &parsed_payload,
            &parsed_length
        );
        valid = valid
            && parsed_kind == expected_kind
            && parsed_length == sizeof(menu_command_payload)
            && memcmp(
                parsed_payload,
                menu_command_payload,
                sizeof(menu_command_payload)
            ) == 0;
        xpc_dictionary_set_bool(request, "extra", true);
        valid = valid && !MCLocalXPCMessageGetExactMenuPairingCommand(
            (MCLocalXPCMessageRef)request,
            NULL,
            NULL,
            NULL
        );
        xpc_release(request);

        xpc_object_t acknowledgement = xpc_dictionary_create_empty();
        xpc_dictionary_set_string(
            acknowledgement,
            "kind",
            acknowledgement_kind
        );
        xpc_dictionary_set_int64(acknowledgement, "version", 1);
        xpc_dictionary_set_data(
            acknowledgement,
            "payload",
            menu_command_payload,
            sizeof(menu_command_payload)
        );
        valid = valid && MCLocalXPCMessageGetExactData(
            acknowledgement,
            acknowledgement_kind,
            MCLocalXPCMaximumMenuPairingCommandPayloadBytes,
            NULL,
            NULL
        );
        xpc_release(acknowledgement);

        xpc_object_t failure = xpc_dictionary_create_empty();
        xpc_dictionary_set_string(failure, "kind", failure_kind);
        xpc_dictionary_set_int64(failure, "version", 1);
        valid = valid && MCLocalXPCMessageIsExact(failure, failure_kind);
        xpc_dictionary_set_string(failure, "detail", "secret");
        valid = valid && !MCLocalXPCMessageIsExact(failure, failure_kind);
        xpc_release(failure);
    }

    const MCLocalXPCInteractiveLeaseCommandKind lease_kinds[] = {
        MCLocalXPCInteractiveLeaseCommandPrepareInitialDesktop,
        MCLocalXPCInteractiveLeaseCommandInstall,
        MCLocalXPCInteractiveLeaseCommandRenew,
        MCLocalXPCInteractiveLeaseCommandRevoke,
        MCLocalXPCInteractiveLeaseCommandSurfaceTargets,
        MCLocalXPCInteractiveLeaseCommandSurfaceResolve,
        MCLocalXPCInteractiveLeaseCommandSurfaceTransition,
        MCLocalXPCInteractiveLeaseCommandSurfaceAcknowledgement,
        MCLocalXPCInteractiveLeaseCommandSurfaceFailure,
    };
    for (size_t index = 0;
         index < sizeof(lease_kinds) / sizeof(lease_kinds[0]);
         index += 1) {
        const MCLocalXPCInteractiveLeaseCommandKind expected_kind =
            lease_kinds[index];
        const char *request_kind =
            MCLocalXPCInteractiveLeaseRequestKind(expected_kind);
        const char *acknowledgement_kind =
            MCLocalXPCInteractiveLeaseAcknowledgementKind(expected_kind);
        valid = valid
            && request_kind != NULL
            && acknowledgement_kind != NULL;

        xpc_object_t request = xpc_dictionary_create_empty();
        xpc_dictionary_set_string(request, "kind", request_kind);
        xpc_dictionary_set_int64(request, "version", 1);
        xpc_dictionary_set_data(
            request,
            "payload",
            menu_command_payload,
            sizeof(menu_command_payload)
        );
        MCLocalXPCInteractiveLeaseCommandKind parsed_kind =
            MCLocalXPCInteractiveLeaseCommandInstall;
        const uint8_t *parsed_payload = NULL;
        size_t parsed_length = 0;
        valid = valid && MCLocalXPCMessageGetExactInteractiveLeaseCommand(
            (MCLocalXPCMessageRef)request,
            &parsed_kind,
            &parsed_payload,
            &parsed_length
        );
        valid = valid
            && parsed_kind == expected_kind
            && parsed_length == sizeof(menu_command_payload)
            && memcmp(
                parsed_payload,
                menu_command_payload,
                sizeof(menu_command_payload)
            ) == 0;
        xpc_dictionary_set_int64(request, "version", 2);
        valid = valid
            && !MCLocalXPCMessageGetExactInteractiveLeaseCommand(
                (MCLocalXPCMessageRef)request,
                NULL,
                NULL,
                NULL
            );
        xpc_release(request);

        xpc_object_t acknowledgement = xpc_dictionary_create_empty();
        xpc_dictionary_set_string(
            acknowledgement,
            "kind",
            acknowledgement_kind
        );
        xpc_dictionary_set_int64(acknowledgement, "version", 1);
        if (MCLocalXPCInteractiveLeaseReplyCarriesPayload(expected_kind)) {
            xpc_dictionary_set_data(
                acknowledgement,
                "payload",
                menu_command_payload,
                sizeof(menu_command_payload)
            );
            valid = valid && MCLocalXPCMessageGetExactData(
                acknowledgement,
                acknowledgement_kind,
                MCLocalXPCMaximumInteractiveLeasePayloadBytes,
                NULL,
                NULL
            );
        } else {
            valid = valid && MCLocalXPCMessageIsExact(
                acknowledgement,
                acknowledgement_kind
            );
        }
        xpc_release(acknowledgement);
    }

    const uint8_t admission_payload[] = {0x7b, 0x7d};
    xpc_object_t admission_request = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        admission_request,
        "kind",
        MCLocalXPCInteractiveAdmissionPublicationKind
    );
    xpc_dictionary_set_int64(admission_request, "version", 1);
    xpc_dictionary_set_data(
        admission_request,
        "payload",
        admission_payload,
        sizeof(admission_payload)
    );
    const uint8_t *parsed_admission_payload = NULL;
    size_t parsed_admission_length = 0;
    valid = valid
        && MCLocalXPCMessageGetExactInteractiveAdmissionPublication(
            (MCLocalXPCMessageRef)admission_request,
            &parsed_admission_payload,
            &parsed_admission_length
        )
        && parsed_admission_length == sizeof(admission_payload)
        && memcmp(
            parsed_admission_payload,
            admission_payload,
            sizeof(admission_payload)
        ) == 0;
    xpc_dictionary_set_bool(admission_request, "extra", true);
    valid = valid
        && !MCLocalXPCMessageGetExactInteractiveAdmissionPublication(
            (MCLocalXPCMessageRef)admission_request,
            NULL,
            NULL
        );
    xpc_release(admission_request);

    xpc_object_t admission_acknowledgement = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        admission_acknowledgement,
        "kind",
        MCLocalXPCInteractiveAdmissionAcknowledgementKind
    );
    xpc_dictionary_set_int64(admission_acknowledgement, "version", 1);
    xpc_dictionary_set_data(
        admission_acknowledgement,
        "payload",
        admission_payload,
        sizeof(admission_payload)
    );
    valid = valid && MCLocalXPCMessageGetExactData(
        admission_acknowledgement,
        MCLocalXPCInteractiveAdmissionAcknowledgementKind,
        MCLocalXPCMaximumInteractiveAdmissionPayloadBytes,
        NULL,
        NULL
    );
    xpc_release(admission_acknowledgement);

    const uint8_t presentation_payload[] = {0x7b, 0x7d};
    const uint8_t review_uuid[16] = {
        0x01, 0x8f, 0x43, 0x00, 0x00, 0x00, 0x70, 0x00,
        0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xc1,
    };
    const uint8_t *parsed_presentation_payload = NULL;
    size_t parsed_presentation_length = 0;
    valid = valid
        && strcmp(
            MCLocalXPCPairingReviewPublishKind,
            "presentation.pairing-review.publish"
        ) == 0
        && strcmp(
            MCLocalXPCPairingReviewPublishAcknowledgementKind,
            "presentation.pairing-review.publish.ack"
        ) == 0
        && strcmp(
            MCLocalXPCPairingReviewPublishRejectionKind,
            "presentation.pairing-review.publish.error"
        ) == 0
        && strcmp(
            MCLocalXPCPairingReviewWithdrawalKind,
            "presentation.pairing-review.withdraw"
        ) == 0
        && strcmp(
            MCLocalXPCPairingReviewWithdrawalAcknowledgementKind,
            "presentation.pairing-review.withdraw.ack"
        ) == 0
        && strcmp(
            MCLocalXPCHostRecoveryReviewPublishKind,
            "presentation.host-recovery-review.publish"
        ) == 0
        && strcmp(
            MCLocalXPCHostRecoveryReviewPublishAcknowledgementKind,
            "presentation.host-recovery-review.publish.ack"
        ) == 0
        && strcmp(
            MCLocalXPCHostRecoveryReviewPublishRejectionKind,
            "presentation.host-recovery-review.publish.error"
        ) == 0
        && strcmp(
            MCLocalXPCHostRecoveryResumePublishKind,
            "presentation.host-recovery-resume.publish"
        ) == 0
        && strcmp(
            MCLocalXPCHostRecoveryResumePublishAcknowledgementKind,
            "presentation.host-recovery-resume.publish.ack"
        ) == 0
        && strcmp(
            MCLocalXPCHostRecoveryResumePublishRejectionKind,
            "presentation.host-recovery-resume.publish.error"
        ) == 0
        && strcmp(
            MCLocalXPCHostRecoveryWithdrawalKind,
            "presentation.host-recovery.withdraw"
        ) == 0
        && strcmp(
            MCLocalXPCHostRecoveryWithdrawalAcknowledgementKind,
            "presentation.host-recovery.withdraw.ack"
        ) == 0;

    xpc_object_t pairing_publish = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        pairing_publish,
        "kind",
        "presentation.pairing-review.publish"
    );
    xpc_dictionary_set_int64(pairing_publish, "version", 1);
    xpc_dictionary_set_data(
        pairing_publish,
        "payload",
        presentation_payload,
        sizeof(presentation_payload)
    );
    valid = valid && MCLocalXPCMessageGetExactPairingReviewPublish(
        (MCLocalXPCMessageRef)pairing_publish,
        &parsed_presentation_payload,
        &parsed_presentation_length
    );
    valid = valid
        && parsed_presentation_length == sizeof(presentation_payload)
        && memcmp(
            parsed_presentation_payload,
            presentation_payload,
            sizeof(presentation_payload)
        ) == 0;
    valid = valid && !MCLocalXPCMessageGetExactHostRecoveryReviewPublish(
        (MCLocalXPCMessageRef)pairing_publish,
        NULL,
        NULL
    );
    valid = valid && !MCLocalXPCMessageGetExactHostRecoveryResumePublish(
        (MCLocalXPCMessageRef)pairing_publish,
        NULL,
        NULL
    );
    xpc_dictionary_set_bool(pairing_publish, "extra", true);
    valid = valid && !MCLocalXPCMessageGetExactPairingReviewPublish(
        (MCLocalXPCMessageRef)pairing_publish,
        NULL,
        NULL
    );
    xpc_release(pairing_publish);

    xpc_object_t recovery_review_publish = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        recovery_review_publish,
        "kind",
        "presentation.host-recovery-review.publish"
    );
    xpc_dictionary_set_int64(recovery_review_publish, "version", 1);
    xpc_dictionary_set_data(
        recovery_review_publish,
        "payload",
        presentation_payload,
        sizeof(presentation_payload)
    );
    valid = valid && MCLocalXPCMessageGetExactHostRecoveryReviewPublish(
        (MCLocalXPCMessageRef)recovery_review_publish,
        NULL,
        NULL
    );
    valid = valid && !MCLocalXPCMessageGetExactHostRecoveryResumePublish(
        (MCLocalXPCMessageRef)recovery_review_publish,
        NULL,
        NULL
    );
    xpc_release(recovery_review_publish);

    xpc_object_t recovery_resume_publish = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        recovery_resume_publish,
        "kind",
        "presentation.host-recovery-resume.publish"
    );
    xpc_dictionary_set_int64(recovery_resume_publish, "version", 1);
    xpc_dictionary_set_data(
        recovery_resume_publish,
        "payload",
        presentation_payload,
        sizeof(presentation_payload)
    );
    valid = valid && MCLocalXPCMessageGetExactHostRecoveryResumePublish(
        (MCLocalXPCMessageRef)recovery_resume_publish,
        NULL,
        NULL
    );
    valid = valid && !MCLocalXPCMessageGetExactHostRecoveryReviewPublish(
        (MCLocalXPCMessageRef)recovery_resume_publish,
        NULL,
        NULL
    );
    xpc_release(recovery_resume_publish);

    xpc_object_t empty_presentation = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        empty_presentation,
        "kind",
        "presentation.pairing-review.publish"
    );
    xpc_dictionary_set_int64(empty_presentation, "version", 1);
    xpc_dictionary_set_data(
        empty_presentation,
        "payload",
        presentation_payload,
        0
    );
    valid = valid && !MCLocalXPCMessageGetExactPairingReviewPublish(
        (MCLocalXPCMessageRef)empty_presentation,
        NULL,
        NULL
    );
    xpc_release(empty_presentation);

    uint8_t oversized_presentation[
        MCLocalXPCMaximumMenuPresentationPayloadBytes + 1
    ] = {0};
    xpc_object_t oversized_presentation_request =
        xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        oversized_presentation_request,
        "kind",
        "presentation.pairing-review.publish"
    );
    xpc_dictionary_set_int64(
        oversized_presentation_request,
        "version",
        1
    );
    xpc_dictionary_set_data(
        oversized_presentation_request,
        "payload",
        oversized_presentation,
        sizeof(oversized_presentation)
    );
    valid = valid && !MCLocalXPCMessageGetExactPairingReviewPublish(
        (MCLocalXPCMessageRef)oversized_presentation_request,
        NULL,
        NULL
    );
    xpc_release(oversized_presentation_request);

    xpc_object_t wrong_presentation_scalar = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        wrong_presentation_scalar,
        "kind",
        "presentation.pairing-review.publish"
    );
    xpc_dictionary_set_uint64(wrong_presentation_scalar, "version", 1);
    xpc_dictionary_set_string(wrong_presentation_scalar, "payload", "{}");
    valid = valid && !MCLocalXPCMessageGetExactPairingReviewPublish(
        (MCLocalXPCMessageRef)wrong_presentation_scalar,
        NULL,
        NULL
    );
    xpc_release(wrong_presentation_scalar);

    xpc_object_t double_presentation_version =
        xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        double_presentation_version,
        "kind",
        "presentation.pairing-review.publish"
    );
    xpc_dictionary_set_double(
        double_presentation_version,
        "version",
        1.0
    );
    xpc_dictionary_set_data(
        double_presentation_version,
        "payload",
        presentation_payload,
        sizeof(presentation_payload)
    );
    valid = valid && !MCLocalXPCMessageGetExactPairingReviewPublish(
        (MCLocalXPCMessageRef)double_presentation_version,
        NULL,
        NULL
    );
    xpc_release(double_presentation_version);

    xpc_object_t boolean_presentation_version =
        xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        boolean_presentation_version,
        "kind",
        "presentation.pairing-review.publish"
    );
    xpc_dictionary_set_bool(
        boolean_presentation_version,
        "version",
        true
    );
    xpc_dictionary_set_data(
        boolean_presentation_version,
        "payload",
        presentation_payload,
        sizeof(presentation_payload)
    );
    valid = valid && !MCLocalXPCMessageGetExactPairingReviewPublish(
        (MCLocalXPCMessageRef)boolean_presentation_version,
        NULL,
        NULL
    );
    xpc_release(boolean_presentation_version);

    xpc_object_t pairing_withdraw = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        pairing_withdraw,
        "kind",
        "presentation.pairing-review.withdraw"
    );
    xpc_dictionary_set_int64(pairing_withdraw, "version", 1);
    xpc_dictionary_set_uuid(pairing_withdraw, "reviewID", review_uuid);
    const uint8_t *parsed_pairing_uuid =
        MCLocalXPCMessageGetExactPairingReviewWithdrawal(
            (MCLocalXPCMessageRef)pairing_withdraw
        );
    valid = valid
        && parsed_pairing_uuid != NULL
        && memcmp(parsed_pairing_uuid, review_uuid, sizeof(review_uuid)) == 0;
    valid = valid
        && MCLocalXPCMessageGetExactHostRecoveryWithdrawal(
            (MCLocalXPCMessageRef)pairing_withdraw
        ) == NULL;
    xpc_release(pairing_withdraw);

    xpc_object_t recovery_withdraw = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        recovery_withdraw,
        "kind",
        "presentation.host-recovery.withdraw"
    );
    xpc_dictionary_set_int64(recovery_withdraw, "version", 1);
    xpc_dictionary_set_uuid(recovery_withdraw, "reviewID", review_uuid);
    valid = valid
        && MCLocalXPCMessageGetExactHostRecoveryWithdrawal(
            (MCLocalXPCMessageRef)recovery_withdraw
        ) != NULL;
    valid = valid
        && MCLocalXPCMessageGetExactPairingReviewWithdrawal(
            (MCLocalXPCMessageRef)recovery_withdraw
        ) == NULL;
    xpc_release(recovery_withdraw);

    const uint8_t zero_uuid[16] = {0};
    xpc_object_t zero_withdraw = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        zero_withdraw,
        "kind",
        "presentation.pairing-review.withdraw"
    );
    xpc_dictionary_set_int64(zero_withdraw, "version", 1);
    xpc_dictionary_set_uuid(zero_withdraw, "reviewID", zero_uuid);
    valid = valid
        && MCLocalXPCMessageGetExactPairingReviewWithdrawal(
            (MCLocalXPCMessageRef)zero_withdraw
        ) == NULL;
    xpc_release(zero_withdraw);

    xpc_object_t wrong_withdraw_type = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        wrong_withdraw_type,
        "kind",
        "presentation.pairing-review.withdraw"
    );
    xpc_dictionary_set_int64(wrong_withdraw_type, "version", 1);
    xpc_dictionary_set_data(
        wrong_withdraw_type,
        "reviewID",
        review_uuid,
        sizeof(review_uuid)
    );
    valid = valid
        && MCLocalXPCMessageGetExactPairingReviewWithdrawal(
            (MCLocalXPCMessageRef)wrong_withdraw_type
        ) == NULL;
    xpc_release(wrong_withdraw_type);
    valid = valid && !MCLocalXPCReviewIDBytesAreValid(review_uuid, 15);
    valid = valid && MCLocalXPCReviewIDBytesAreValid(review_uuid, 16);
    valid = valid && !MCLocalXPCReviewIDBytesAreValid(review_uuid, 17);
    valid = valid && !MCLocalXPCReviewIDBytesAreValid(zero_uuid, 16);

    xpc_object_t publish_ack = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        publish_ack,
        "kind",
        MCLocalXPCPairingReviewPublishAcknowledgementKind
    );
    xpc_dictionary_set_int64(publish_ack, "version", 1);
    valid = valid && MCLocalXPCMessageIsExact(
        publish_ack,
        "presentation.pairing-review.publish.ack"
    );
    xpc_release(publish_ack);

    xpc_object_t publish_rejection = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        publish_rejection,
        "kind",
        MCLocalXPCPairingReviewPublishRejectionKind
    );
    xpc_dictionary_set_int64(publish_rejection, "version", 1);
    xpc_dictionary_set_string(
        publish_rejection,
        "code",
        "presentationRejected"
    );
    valid = valid && MCLocalXPCMessageIsExactPresentationRejected(
        publish_rejection,
        "presentation.pairing-review.publish.error"
    );
    valid = valid && !MCLocalXPCMessageIsExactPresentationRejected(
        publish_rejection,
        "presentation.host-recovery-review.publish.error"
    );
    xpc_dictionary_set_string(publish_rejection, "code", "other");
    valid = valid && !MCLocalXPCMessageIsExactPresentationRejected(
        publish_rejection,
        "presentation.pairing-review.publish.error"
    );
    xpc_release(publish_rejection);

    const char *presentation_acknowledgements[] = {
        "presentation.pairing-review.publish.ack",
        "presentation.pairing-review.withdraw.ack",
        "presentation.host-recovery-review.publish.ack",
        "presentation.host-recovery-resume.publish.ack",
        "presentation.host-recovery.withdraw.ack",
    };
    const char *presentation_optional_rejections[] = {
        "presentation.pairing-review.publish.error",
        NULL,
        "presentation.host-recovery-review.publish.error",
        "presentation.host-recovery-resume.publish.error",
        NULL,
    };
    for (size_t index = 0;
         index < sizeof(presentation_acknowledgements)
            / sizeof(presentation_acknowledgements[0]);
         index += 1) {
        xpc_object_t acknowledgement = xpc_dictionary_create_empty();
        xpc_dictionary_set_string(
            acknowledgement,
            "kind",
            presentation_acknowledgements[index]
        );
        xpc_dictionary_set_int64(acknowledgement, "version", 1);
        valid = valid && MCLocalXPCMessageIsExact(
            acknowledgement,
            presentation_acknowledgements[index]
        );
        valid = valid
            && MCLocalXPCClassifyMenuPresentationReply(
                acknowledgement,
                NULL,
                presentation_acknowledgements[index],
                presentation_optional_rejections[index]
            ) == MCLocalXPCMenuPresentationReplyAcknowledged;
        size_t wrong_index = (index + 1)
            % (sizeof(presentation_acknowledgements)
                / sizeof(presentation_acknowledgements[0]));
        valid = valid
            && MCLocalXPCClassifyMenuPresentationReply(
                acknowledgement,
                NULL,
                presentation_acknowledgements[wrong_index],
                presentation_optional_rejections[wrong_index]
            )
                == MCLocalXPCMenuPresentationReplyMalformedOrTransportError;
        xpc_dictionary_set_bool(acknowledgement, "extra", true);
        valid = valid
            && MCLocalXPCClassifyMenuPresentationReply(
                acknowledgement,
                NULL,
                presentation_acknowledgements[index],
                presentation_optional_rejections[index]
            )
                == MCLocalXPCMenuPresentationReplyMalformedOrTransportError;
        xpc_release(acknowledgement);
    }

    const char *presentation_rejections[] = {
        "presentation.pairing-review.publish.error",
        "presentation.host-recovery-review.publish.error",
        "presentation.host-recovery-resume.publish.error",
    };
    for (size_t index = 0;
         index < sizeof(presentation_rejections)
            / sizeof(presentation_rejections[0]);
         index += 1) {
        xpc_object_t rejection = xpc_dictionary_create_empty();
        xpc_dictionary_set_string(
            rejection,
            "kind",
            presentation_rejections[index]
        );
        xpc_dictionary_set_int64(rejection, "version", 1);
        xpc_dictionary_set_string(
            rejection,
            "code",
            "presentationRejected"
        );
        valid = valid && MCLocalXPCMessageIsExactPresentationRejected(
            rejection,
            presentation_rejections[index]
        );
        valid = valid
            && MCLocalXPCClassifyMenuPresentationReply(
                rejection,
                NULL,
                "not-an-acknowledgement",
                presentation_rejections[index]
            ) == MCLocalXPCMenuPresentationReplyRejected;
        xpc_dictionary_set_uint64(rejection, "version", 1);
        valid = valid
            && MCLocalXPCClassifyMenuPresentationReply(
                rejection,
                NULL,
                "not-an-acknowledgement",
                presentation_rejections[index]
            )
                == MCLocalXPCMenuPresentationReplyMalformedOrTransportError;
        xpc_release(rejection);
    }

    valid = valid
        && MCLocalXPCClassifyMenuPresentationReply(
            NULL,
            NULL,
            "presentation.pairing-review.publish.ack",
            "presentation.pairing-review.publish.error"
        ) == MCLocalXPCMenuPresentationReplyMalformedOrTransportError;

    xpc_object_t withdrawal_error = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        withdrawal_error,
        "kind",
        "presentation.pairing-review.withdraw.error"
    );
    xpc_dictionary_set_int64(withdrawal_error, "version", 1);
    xpc_dictionary_set_string(
        withdrawal_error,
        "code",
        "presentationRejected"
    );
    valid = valid
        && MCLocalXPCClassifyMenuPresentationReply(
            withdrawal_error,
            NULL,
            "presentation.pairing-review.withdraw.ack",
            NULL
        )
            == MCLocalXPCMenuPresentationReplyMalformedOrTransportError;
    xpc_release(withdrawal_error);

    const uint8_t interactive_input_bytes[] = {0x7b, 0x7d};
    const uint8_t *parsed_interactive_input = NULL;
    size_t parsed_interactive_input_length = 0;
    xpc_object_t interactive_input = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        interactive_input,
        "kind",
        MCLocalXPCInteractiveInputKind
    );
    xpc_dictionary_set_int64(interactive_input, "version", 1);
    xpc_dictionary_set_data(
        interactive_input,
        "payload",
        interactive_input_bytes,
        sizeof(interactive_input_bytes)
    );
    valid = valid && MCLocalXPCMessageGetExactInteractiveInput(
        (MCLocalXPCMessageRef)interactive_input,
        &parsed_interactive_input,
        &parsed_interactive_input_length
    );
    valid = valid
        && parsed_interactive_input_length == sizeof(interactive_input_bytes)
        && memcmp(
            parsed_interactive_input,
            interactive_input_bytes,
            sizeof(interactive_input_bytes)
        ) == 0;
    xpc_dictionary_set_bool(interactive_input, "extra", true);
    valid = valid && !MCLocalXPCMessageGetExactInteractiveInput(
        (MCLocalXPCMessageRef)interactive_input,
        NULL,
        NULL
    );
    xpc_release(interactive_input);

    uint8_t interactive_media_header[
        MCLocalXPCInteractiveMediaHeaderBytes
    ] = {0};
    const uint8_t interactive_media_payload[] = {0x01, 0x02};
    const uint8_t *parsed_interactive_media_header = NULL;
    size_t parsed_interactive_media_header_length = 0;
    const uint8_t *parsed_interactive_media_payload = NULL;
    size_t parsed_interactive_media_payload_length = 0;
    xpc_object_t interactive_media = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        interactive_media,
        "kind",
        MCLocalXPCInteractiveMediaPublicationKind
    );
    xpc_dictionary_set_int64(interactive_media, "version", 1);
    xpc_dictionary_set_data(
        interactive_media,
        "header",
        interactive_media_header,
        sizeof(interactive_media_header)
    );
    xpc_dictionary_set_data(
        interactive_media,
        "payload",
        interactive_media_payload,
        sizeof(interactive_media_payload)
    );
    valid = valid && MCLocalXPCMessageGetExactInteractiveMediaPublication(
        (MCLocalXPCMessageRef)interactive_media,
        &parsed_interactive_media_header,
        &parsed_interactive_media_header_length,
        &parsed_interactive_media_payload,
        &parsed_interactive_media_payload_length
    );
    valid = valid
        && parsed_interactive_media_header_length
            == sizeof(interactive_media_header)
        && parsed_interactive_media_payload_length
            == sizeof(interactive_media_payload)
        && memcmp(
            parsed_interactive_media_header,
            interactive_media_header,
            sizeof(interactive_media_header)
        ) == 0
        && memcmp(
            parsed_interactive_media_payload,
            interactive_media_payload,
            sizeof(interactive_media_payload)
        ) == 0;
    xpc_dictionary_set_data(
        interactive_media,
        "header",
        interactive_media_header,
        sizeof(interactive_media_header) - 1
    );
    valid = valid && !MCLocalXPCMessageGetExactInteractiveMediaPublication(
        (MCLocalXPCMessageRef)interactive_media,
        NULL,
        NULL,
        NULL,
        NULL
    );
    xpc_release(interactive_media);

    static const uint8_t empty_interactive_media_payload = 0;
    xpc_object_t empty_interactive_media = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(
        empty_interactive_media,
        "kind",
        MCLocalXPCInteractiveMediaPublicationKind
    );
    xpc_dictionary_set_int64(empty_interactive_media, "version", 1);
    xpc_dictionary_set_data(
        empty_interactive_media,
        "header",
        interactive_media_header,
        sizeof(interactive_media_header)
    );
    xpc_dictionary_set_data(
        empty_interactive_media,
        "payload",
        &empty_interactive_media_payload,
        0
    );
    valid = valid && MCLocalXPCMessageGetExactInteractiveMediaPublication(
        (MCLocalXPCMessageRef)empty_interactive_media,
        NULL,
        NULL,
        NULL,
        NULL
    );
    xpc_release(empty_interactive_media);

    return valid;
}

static MCLocalXPCResult MCLocalXPCSessionReplyExact(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request,
    const char *kind
) {
    xpc_object_t reply = xpc_dictionary_create_reply(
        (xpc_object_t)request
    );
    if (reply == NULL) {
        return MCLocalXPCResultConstructionFailed;
    }
    xpc_dictionary_set_string(reply, "kind", kind);
    xpc_dictionary_set_int64(reply, "version", 1);
    xpc_rich_error_t error = xpc_session_send_message(
        (xpc_session_t)session,
        reply
    );
    xpc_release(reply);
    if (error != NULL) {
        xpc_release(error);
        return MCLocalXPCResultSendFailed;
    }
    return MCLocalXPCResultOK;
}

static void MCLocalXPCSessionSendExact(
    MCLocalXPCSessionRef session,
    const char *kind,
    MCLocalXPCReplyHandler handler
) {
    xpc_object_t request = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(request, "kind", kind);
    xpc_dictionary_set_int64(request, "version", 1);
    xpc_session_send_message_with_reply_async(
        (xpc_session_t)session,
        request,
        ^(xpc_object_t reply, xpc_rich_error_t error) {
            handler((MCLocalXPCMessageRef)reply, error != NULL);
        }
    );
    xpc_release(request);
}

MCLocalXPCResult MCLocalXPCSessionReplyToHello(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef hello
) {
    return MCLocalXPCSessionReplyExact(session, hello, "hello.ack");
}

void MCLocalXPCSessionSendHello(
    MCLocalXPCSessionRef session,
    MCLocalXPCReplyHandler handler
) {
    MCLocalXPCSessionSendExact(session, "hello", handler);
}

MCLocalXPCResult MCLocalXPCSessionReplyToMenuReady(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request
) {
    return MCLocalXPCSessionReplyExact(
        session,
        request,
        "lifecycle.menu-ready.ack"
    );
}

void MCLocalXPCSessionSendMenuReady(
    MCLocalXPCSessionRef session,
    MCLocalXPCReplyHandler handler
) {
    MCLocalXPCSessionSendExact(
        session,
        "lifecycle.menu-ready",
        handler
    );
}

static MCLocalXPCResult MCLocalXPCSessionReplyData(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request,
    const char *kind,
    const uint8_t *payload,
    size_t payload_length,
    size_t maximum_payload_length
) {
    if (payload == NULL
        || payload_length == 0
        || payload_length > maximum_payload_length) {
        return MCLocalXPCResultConstructionFailed;
    }
    xpc_object_t reply = xpc_dictionary_create_reply(
        (xpc_object_t)request
    );
    if (reply == NULL) {
        return MCLocalXPCResultConstructionFailed;
    }
    xpc_dictionary_set_string(reply, "kind", kind);
    xpc_dictionary_set_int64(reply, "version", 1);
    xpc_dictionary_set_data(reply, "payload", payload, payload_length);
    xpc_rich_error_t error = xpc_session_send_message(
        (xpc_session_t)session,
        reply
    );
    xpc_release(reply);
    if (error != NULL) {
        xpc_release(error);
        return MCLocalXPCResultSendFailed;
    }
    return MCLocalXPCResultOK;
}

static void MCLocalXPCSessionSendExactExpectingData(
    MCLocalXPCSessionRef session,
    const char *request_kind,
    const char *acknowledgement_kind,
    size_t maximum_payload_length,
    MCLocalXPCBootstrapPayloadReplyHandler handler
) {
    xpc_object_t request = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(request, "kind", request_kind);
    xpc_dictionary_set_int64(request, "version", 1);
    xpc_session_send_message_with_reply_async(
        (xpc_session_t)session,
        request,
        ^(xpc_object_t reply, xpc_rich_error_t error) {
            if (error != NULL) {
                handler(NULL, 0, true);
                return;
            }
            const uint8_t *payload = NULL;
            size_t payload_length = 0;
            if (!MCLocalXPCMessageGetExactData(
                    reply,
                    acknowledgement_kind,
                    maximum_payload_length,
                    &payload,
                    &payload_length
                )) {
                handler(NULL, 0, true);
                return;
            }
            handler(payload, payload_length, false);
        }
    );
    xpc_release(request);
}

static MCLocalXPCResult MCLocalXPCSessionSendDataExpectingData(
    MCLocalXPCSessionRef session,
    const char *request_kind,
    const char *acknowledgement_kind,
    const uint8_t *payload,
    size_t payload_length,
    size_t maximum_payload_length,
    MCLocalXPCBootstrapPayloadReplyHandler handler
) {
    if (payload == NULL
        || payload_length == 0
        || payload_length > maximum_payload_length) {
        return MCLocalXPCResultConstructionFailed;
    }
    xpc_object_t request = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(request, "kind", request_kind);
    xpc_dictionary_set_int64(request, "version", 1);
    xpc_dictionary_set_data(request, "payload", payload, payload_length);
    xpc_session_send_message_with_reply_async(
        (xpc_session_t)session,
        request,
        ^(xpc_object_t reply, xpc_rich_error_t error) {
            if (error != NULL) {
                handler(NULL, 0, true);
                return;
            }
            const uint8_t *reply_payload = NULL;
            size_t reply_payload_length = 0;
            if (!MCLocalXPCMessageGetExactData(
                    reply,
                    acknowledgement_kind,
                    maximum_payload_length,
                    &reply_payload,
                    &reply_payload_length
                )) {
                handler(NULL, 0, true);
                return;
            }
            handler(reply_payload, reply_payload_length, false);
        }
    );
    xpc_release(request);
    return MCLocalXPCResultOK;
}

MCLocalXPCResult MCLocalXPCSessionReplyToRemoteAccessBootstrapOffer(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request,
    const uint8_t *payload,
    size_t payload_length
) {
    return MCLocalXPCSessionReplyData(
        session,
        request,
        MCLocalXPCRemoteAccessBootstrapReadAcknowledgementKind,
        payload,
        payload_length,
        MCLocalXPCMaximumBootstrapPayloadBytes
    );
}

void MCLocalXPCSessionSendRemoteAccessBootstrapRead(
    MCLocalXPCSessionRef session,
    MCLocalXPCBootstrapPayloadReplyHandler handler
) {
    MCLocalXPCSessionSendExactExpectingData(
        session,
        MCLocalXPCRemoteAccessBootstrapReadKind,
        MCLocalXPCRemoteAccessBootstrapReadAcknowledgementKind,
        MCLocalXPCMaximumBootstrapPayloadBytes,
        handler
    );
}

MCLocalXPCResult MCLocalXPCSessionReplyToRemoteAccessEnabled(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request,
    const uint8_t *payload,
    size_t payload_length
) {
    return MCLocalXPCSessionReplyData(
        session,
        request,
        MCLocalXPCRemoteAccessEnableAcknowledgementKind,
        payload,
        payload_length,
        MCLocalXPCMaximumBootstrapPayloadBytes
    );
}

MCLocalXPCResult MCLocalXPCSessionSendRemoteAccessEnable(
    MCLocalXPCSessionRef session,
    const uint8_t *payload,
    size_t payload_length,
    MCLocalXPCBootstrapPayloadReplyHandler handler
) {
    return MCLocalXPCSessionSendDataExpectingData(
        session,
        MCLocalXPCRemoteAccessEnableKind,
        MCLocalXPCRemoteAccessEnableAcknowledgementKind,
        payload,
        payload_length,
        MCLocalXPCMaximumBootstrapPayloadBytes,
        handler
    );
}

static bool MCLocalXPCMenuPairingRequestMatchesKind(
    MCLocalXPCMessageRef request,
    MCLocalXPCMenuPairingCommandKind expected_kind
) {
    const char *request_kind =
        MCLocalXPCMenuPairingCommandRequestKind(expected_kind);
    return request_kind != NULL
        && MCLocalXPCMessageGetExactData(
            (xpc_object_t)request,
            request_kind,
            MCLocalXPCMaximumMenuPairingCommandPayloadBytes,
            NULL,
            NULL
        );
}

MCLocalXPCResult MCLocalXPCSessionReplyToMenuPairingCommandSuccess(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request,
    MCLocalXPCMenuPairingCommandKind kind,
    const uint8_t *payload,
    size_t payload_length
) {
    const char *acknowledgement_kind =
        MCLocalXPCMenuPairingCommandAcknowledgementKind(kind);
    if (acknowledgement_kind == NULL
        || !MCLocalXPCMenuPairingRequestMatchesKind(request, kind)) {
        return MCLocalXPCResultConstructionFailed;
    }
    return MCLocalXPCSessionReplyData(
        session,
        request,
        acknowledgement_kind,
        payload,
        payload_length,
        MCLocalXPCMaximumMenuPairingCommandPayloadBytes
    );
}

MCLocalXPCResult MCLocalXPCSessionReplyToMenuPairingCommandFailure(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request,
    MCLocalXPCMenuPairingCommandKind kind
) {
    const char *failure_kind =
        MCLocalXPCMenuPairingCommandFailureKind(kind);
    if (failure_kind == NULL
        || !MCLocalXPCMenuPairingRequestMatchesKind(request, kind)) {
        return MCLocalXPCResultConstructionFailed;
    }
    return MCLocalXPCSessionReplyExact(session, request, failure_kind);
}

MCLocalXPCResult MCLocalXPCSessionSendMenuPairingCommand(
    MCLocalXPCSessionRef session,
    MCLocalXPCMenuPairingCommandKind kind,
    const uint8_t *payload,
    size_t payload_length,
    MCLocalXPCMenuPairingCommandReplyHandler handler
) {
    const char *request_kind =
        MCLocalXPCMenuPairingCommandRequestKind(kind);
    const char *acknowledgement_kind =
        MCLocalXPCMenuPairingCommandAcknowledgementKind(kind);
    const char *failure_kind =
        MCLocalXPCMenuPairingCommandFailureKind(kind);
    if (request_kind == NULL
        || acknowledgement_kind == NULL
        || failure_kind == NULL
        || payload == NULL
        || payload_length == 0
        || payload_length
            > MCLocalXPCMaximumMenuPairingCommandPayloadBytes) {
        return MCLocalXPCResultConstructionFailed;
    }

    xpc_object_t request = xpc_dictionary_create_empty();
    if (request == NULL) {
        return MCLocalXPCResultConstructionFailed;
    }
    xpc_dictionary_set_string(request, "kind", request_kind);
    xpc_dictionary_set_int64(request, "version", 1);
    xpc_dictionary_set_data(request, "payload", payload, payload_length);
    xpc_session_send_message_with_reply_async(
        (xpc_session_t)session,
        request,
        ^(xpc_object_t reply, xpc_rich_error_t error) {
            if (error != NULL) {
                handler(NULL, 0, false, true);
                return;
            }
            const uint8_t *reply_payload = NULL;
            size_t reply_payload_length = 0;
            if (MCLocalXPCMessageGetExactData(
                    reply,
                    acknowledgement_kind,
                    MCLocalXPCMaximumMenuPairingCommandPayloadBytes,
                    &reply_payload,
                    &reply_payload_length
                )) {
                handler(
                    reply_payload,
                    reply_payload_length,
                    false,
                    false
                );
                return;
            }
            if (MCLocalXPCMessageIsExact(reply, failure_kind)) {
                handler(NULL, 0, true, false);
                return;
            }
            handler(NULL, 0, false, true);
        }
    );
    xpc_release(request);
    return MCLocalXPCResultOK;
}

static bool MCLocalXPCInteractiveLeaseRequestMatchesKind(
    MCLocalXPCMessageRef request,
    MCLocalXPCInteractiveLeaseCommandKind expected_kind
) {
    const char *request_kind =
        MCLocalXPCInteractiveLeaseRequestKind(expected_kind);
    return request_kind != NULL
        && MCLocalXPCMessageGetExactData(
            (xpc_object_t)request,
            request_kind,
            MCLocalXPCMaximumInteractiveLeasePayloadBytes,
            NULL,
            NULL
        );
}

MCLocalXPCResult MCLocalXPCSessionReplyToInteractiveLeaseCommandSuccess(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request,
    MCLocalXPCInteractiveLeaseCommandKind kind,
    const uint8_t *payload,
    size_t payload_length
) {
    const char *acknowledgement_kind =
        MCLocalXPCInteractiveLeaseAcknowledgementKind(kind);
    if (acknowledgement_kind == NULL
        || !MCLocalXPCInteractiveLeaseRequestMatchesKind(request, kind)) {
        return MCLocalXPCResultConstructionFailed;
    }
    if (MCLocalXPCInteractiveLeaseReplyCarriesPayload(kind)) {
        return MCLocalXPCSessionReplyData(
            session,
            request,
            acknowledgement_kind,
            payload,
            payload_length,
            MCLocalXPCMaximumInteractiveLeasePayloadBytes
        );
    }
    if (payload != NULL || payload_length != 0) {
        return MCLocalXPCResultConstructionFailed;
    }
    return MCLocalXPCSessionReplyExact(
        session,
        request,
        acknowledgement_kind
    );
}

MCLocalXPCResult MCLocalXPCSessionSendInteractiveLeaseCommand(
    MCLocalXPCSessionRef session,
    MCLocalXPCInteractiveLeaseCommandKind kind,
    const uint8_t *payload,
    size_t payload_length,
    MCLocalXPCInteractiveLeaseReplyHandler handler
) {
    const char *request_kind =
        MCLocalXPCInteractiveLeaseRequestKind(kind);
    const char *acknowledgement_kind =
        MCLocalXPCInteractiveLeaseAcknowledgementKind(kind);
    if (request_kind == NULL
        || acknowledgement_kind == NULL
        || payload == NULL
        || payload_length == 0
        || payload_length > MCLocalXPCMaximumInteractiveLeasePayloadBytes) {
        return MCLocalXPCResultConstructionFailed;
    }

    xpc_object_t request = xpc_dictionary_create_empty();
    if (request == NULL) {
        return MCLocalXPCResultConstructionFailed;
    }
    xpc_dictionary_set_string(request, "kind", request_kind);
    xpc_dictionary_set_int64(request, "version", 1);
    xpc_dictionary_set_data(request, "payload", payload, payload_length);
    xpc_session_send_message_with_reply_async(
        (xpc_session_t)session,
        request,
        ^(xpc_object_t reply, xpc_rich_error_t error) {
            if (error != NULL) {
                handler(NULL, 0, true);
                return;
            }
            if (!MCLocalXPCInteractiveLeaseReplyCarriesPayload(kind)) {
                handler(
                    NULL,
                    0,
                    !MCLocalXPCMessageIsExact(
                        reply,
                        acknowledgement_kind
                    )
                );
                return;
            }
            const uint8_t *reply_payload = NULL;
            size_t reply_payload_length = 0;
            if (MCLocalXPCMessageGetExactData(
                    reply,
                    acknowledgement_kind,
                    MCLocalXPCMaximumInteractiveLeasePayloadBytes,
                    &reply_payload,
                    &reply_payload_length
                )) {
                handler(reply_payload, reply_payload_length, false);
                return;
            }
            handler(NULL, 0, true);
        }
    );
    xpc_release(request);
    return MCLocalXPCResultOK;
}

MCLocalXPCResult MCLocalXPCSessionReplyToInteractiveAdmissionPublication(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request,
    const uint8_t *payload,
    size_t payload_length
) {
    if (!MCLocalXPCMessageGetExactInteractiveAdmissionPublication(
            request,
            NULL,
            NULL
        )) {
        return MCLocalXPCResultConstructionFailed;
    }
    return MCLocalXPCSessionReplyData(
        session,
        request,
        MCLocalXPCInteractiveAdmissionAcknowledgementKind,
        payload,
        payload_length,
        MCLocalXPCMaximumInteractiveAdmissionPayloadBytes
    );
}

MCLocalXPCResult MCLocalXPCSessionSendInteractiveAdmissionPublication(
    MCLocalXPCSessionRef session,
    const uint8_t *payload,
    size_t payload_length,
    MCLocalXPCInteractiveAdmissionReplyHandler handler
) {
    return MCLocalXPCSessionSendDataExpectingData(
        session,
        MCLocalXPCInteractiveAdmissionPublicationKind,
        MCLocalXPCInteractiveAdmissionAcknowledgementKind,
        payload,
        payload_length,
        MCLocalXPCMaximumInteractiveAdmissionPayloadBytes,
        handler
    );
}

MCLocalXPCResult MCLocalXPCSessionReplyToInteractiveInputSuccess(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request
) {
    if (!MCLocalXPCMessageGetExactInteractiveInput(request, NULL, NULL)) {
        return MCLocalXPCResultConstructionFailed;
    }
    return MCLocalXPCSessionReplyExact(
        session,
        request,
        MCLocalXPCInteractiveInputAcknowledgementKind
    );
}

MCLocalXPCResult MCLocalXPCSessionSendInteractiveInput(
    MCLocalXPCSessionRef session,
    const uint8_t *payload,
    size_t payload_length,
    MCLocalXPCInteractiveRoleDataReplyHandler handler
) {
    if (session == NULL || handler == NULL || payload == NULL
        || payload_length == 0
        || payload_length > MCLocalXPCMaximumInteractiveInputPayloadBytes) {
        return MCLocalXPCResultConstructionFailed;
    }
    xpc_object_t request = xpc_dictionary_create_empty();
    if (request == NULL) {
        return MCLocalXPCResultConstructionFailed;
    }
    xpc_dictionary_set_string(request, "kind", MCLocalXPCInteractiveInputKind);
    xpc_dictionary_set_int64(request, "version", 1);
    xpc_dictionary_set_data(request, "payload", payload, payload_length);
    xpc_session_send_message_with_reply_async(
        (xpc_session_t)session,
        request,
        ^(xpc_object_t reply, xpc_rich_error_t error) {
            handler(error != NULL || !MCLocalXPCMessageIsExact(
                reply,
                MCLocalXPCInteractiveInputAcknowledgementKind
            ));
        }
    );
    xpc_release(request);
    return MCLocalXPCResultOK;
}

MCLocalXPCResult MCLocalXPCSessionReplyToInteractiveMediaPublication(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request
) {
    if (!MCLocalXPCMessageGetExactInteractiveMediaPublication(
            request,
            NULL,
            NULL,
            NULL,
            NULL
        )) {
        return MCLocalXPCResultConstructionFailed;
    }
    return MCLocalXPCSessionReplyExact(
        session,
        request,
        MCLocalXPCInteractiveMediaAcknowledgementKind
    );
}

MCLocalXPCResult MCLocalXPCSessionSendInteractiveMediaPublication(
    MCLocalXPCSessionRef session,
    const uint8_t *header,
    size_t header_length,
    const uint8_t *payload,
    size_t payload_length,
    MCLocalXPCInteractiveRoleDataReplyHandler handler
) {
    if (session == NULL || handler == NULL || header == NULL
        || header_length != MCLocalXPCInteractiveMediaHeaderBytes
        || (payload == NULL && payload_length != 0)
        || payload_length > MCLocalXPCMaximumInteractiveMediaPayloadBytes) {
        return MCLocalXPCResultConstructionFailed;
    }
    xpc_object_t request = xpc_dictionary_create_empty();
    if (request == NULL) {
        return MCLocalXPCResultConstructionFailed;
    }
    static const uint8_t empty_payload = 0;
    xpc_dictionary_set_string(
        request,
        "kind",
        MCLocalXPCInteractiveMediaPublicationKind
    );
    xpc_dictionary_set_int64(request, "version", 1);
    xpc_dictionary_set_data(request, "header", header, header_length);
    xpc_dictionary_set_data(
        request,
        "payload",
        payload_length == 0 ? &empty_payload : payload,
        payload_length
    );
    xpc_session_send_message_with_reply_async(
        (xpc_session_t)session,
        request,
        ^(xpc_object_t reply, xpc_rich_error_t error) {
            handler(error != NULL || !MCLocalXPCMessageIsExact(
                reply,
                MCLocalXPCInteractiveMediaAcknowledgementKind
            ));
        }
    );
    xpc_release(request);
    return MCLocalXPCResultOK;
}

MCLocalXPCResult MCLocalXPCSessionReplyToStatusReadSuccess(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request,
    const uint8_t *payload,
    size_t payload_length
) {
    if (payload == NULL
        || payload_length == 0
        || payload_length > MCLocalXPCMaximumStatusPayloadBytes) {
        return MCLocalXPCResultConstructionFailed;
    }
    xpc_object_t reply = xpc_dictionary_create_reply(
        (xpc_object_t)request
    );
    if (reply == NULL) {
        return MCLocalXPCResultConstructionFailed;
    }
    xpc_dictionary_set_string(reply, "kind", "status.read.ack");
    xpc_dictionary_set_int64(reply, "version", 1);
    xpc_dictionary_set_data(reply, "payload", payload, payload_length);
    xpc_rich_error_t error = xpc_session_send_message(
        (xpc_session_t)session,
        reply
    );
    xpc_release(reply);
    if (error != NULL) {
        xpc_release(error);
        return MCLocalXPCResultSendFailed;
    }
    return MCLocalXPCResultOK;
}

MCLocalXPCResult MCLocalXPCSessionReplyToStatusReadUnavailable(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request
) {
    xpc_object_t reply = xpc_dictionary_create_reply(
        (xpc_object_t)request
    );
    if (reply == NULL) {
        return MCLocalXPCResultConstructionFailed;
    }
    xpc_dictionary_set_string(reply, "kind", "status.read.error");
    xpc_dictionary_set_int64(reply, "version", 1);
    xpc_dictionary_set_string(reply, "code", "sourceUnavailable");
    xpc_rich_error_t error = xpc_session_send_message(
        (xpc_session_t)session,
        reply
    );
    xpc_release(reply);
    if (error != NULL) {
        xpc_release(error);
        return MCLocalXPCResultSendFailed;
    }
    return MCLocalXPCResultOK;
}

void MCLocalXPCSessionSendStatusRead(
    MCLocalXPCSessionRef session,
    MCLocalXPCStatusReplyHandler handler
) {
    xpc_object_t request = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(request, "kind", "status.read");
    xpc_dictionary_set_int64(request, "version", 1);
    xpc_session_send_message_with_reply_async(
        (xpc_session_t)session,
        request,
        ^(xpc_object_t reply, xpc_rich_error_t error) {
            if (error != NULL) {
                handler(NULL, 0, false, true);
                return;
            }
            const void *payload = NULL;
            size_t payload_length = 0;
            if (MCLocalXPCMessageIsExactStatusSuccess(
                    reply,
                    &payload,
                    &payload_length
                )) {
                handler(
                    (const uint8_t *)payload,
                    payload_length,
                    false,
                    false
                );
                return;
            }
            if (MCLocalXPCMessageIsExactStatusUnavailable(reply)) {
                handler(NULL, 0, true, false);
                return;
            }
            handler(NULL, 0, false, true);
        }
    );
    xpc_release(request);
}

static MCLocalXPCResult MCLocalXPCSessionReplyPresentationRejection(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request,
    const char *kind
) {
    xpc_object_t reply = xpc_dictionary_create_reply(
        (xpc_object_t)request
    );
    if (reply == NULL) {
        return MCLocalXPCResultConstructionFailed;
    }
    xpc_dictionary_set_string(reply, "kind", kind);
    xpc_dictionary_set_int64(reply, "version", 1);
    xpc_dictionary_set_string(
        reply,
        "code",
        "presentationRejected"
    );
    xpc_rich_error_t error = xpc_session_send_message(
        (xpc_session_t)session,
        reply
    );
    xpc_release(reply);
    if (error != NULL) {
        xpc_release(error);
        return MCLocalXPCResultSendFailed;
    }
    return MCLocalXPCResultOK;
}

MCLocalXPCResult MCLocalXPCSessionReplyToPairingReviewPublishAcknowledgement(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request
) {
    return MCLocalXPCSessionReplyExact(
        session,
        request,
        MCLocalXPCPairingReviewPublishAcknowledgementKind
    );
}

MCLocalXPCResult MCLocalXPCSessionReplyToPairingReviewPublishRejection(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request
) {
    return MCLocalXPCSessionReplyPresentationRejection(
        session,
        request,
        MCLocalXPCPairingReviewPublishRejectionKind
    );
}

MCLocalXPCResult
MCLocalXPCSessionReplyToPairingReviewWithdrawalAcknowledgement(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request
) {
    return MCLocalXPCSessionReplyExact(
        session,
        request,
        MCLocalXPCPairingReviewWithdrawalAcknowledgementKind
    );
}

MCLocalXPCResult
MCLocalXPCSessionReplyToHostRecoveryReviewPublishAcknowledgement(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request
) {
    return MCLocalXPCSessionReplyExact(
        session,
        request,
        MCLocalXPCHostRecoveryReviewPublishAcknowledgementKind
    );
}

MCLocalXPCResult MCLocalXPCSessionReplyToHostRecoveryReviewPublishRejection(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request
) {
    return MCLocalXPCSessionReplyPresentationRejection(
        session,
        request,
        MCLocalXPCHostRecoveryReviewPublishRejectionKind
    );
}

MCLocalXPCResult
MCLocalXPCSessionReplyToHostRecoveryResumePublishAcknowledgement(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request
) {
    return MCLocalXPCSessionReplyExact(
        session,
        request,
        MCLocalXPCHostRecoveryResumePublishAcknowledgementKind
    );
}

MCLocalXPCResult MCLocalXPCSessionReplyToHostRecoveryResumePublishRejection(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request
) {
    return MCLocalXPCSessionReplyPresentationRejection(
        session,
        request,
        MCLocalXPCHostRecoveryResumePublishRejectionKind
    );
}

MCLocalXPCResult
MCLocalXPCSessionReplyToHostRecoveryWithdrawalAcknowledgement(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef request
) {
    return MCLocalXPCSessionReplyExact(
        session,
        request,
        MCLocalXPCHostRecoveryWithdrawalAcknowledgementKind
    );
}

static MCLocalXPCMenuPresentationReply
MCLocalXPCClassifyMenuPresentationReply(
    xpc_object_t reply,
    xpc_rich_error_t error,
    const char *acknowledgement_kind,
    const char *rejection_kind
) {
    if (error != NULL || reply == NULL) {
        return MCLocalXPCMenuPresentationReplyMalformedOrTransportError;
    }
    if (MCLocalXPCMessageIsExact(reply, acknowledgement_kind)) {
        return MCLocalXPCMenuPresentationReplyAcknowledged;
    }
    if (rejection_kind != NULL
        && MCLocalXPCMessageIsExactPresentationRejected(
            reply,
            rejection_kind
        )) {
        return MCLocalXPCMenuPresentationReplyRejected;
    }
    return MCLocalXPCMenuPresentationReplyMalformedOrTransportError;
}

static MCLocalXPCResult MCLocalXPCSessionSendConstructedPresentation(
    MCLocalXPCSessionRef session,
    xpc_object_t _Nullable request,
    const char *acknowledgement_kind,
    const char * _Nullable rejection_kind,
    MCLocalXPCMenuPresentationReplyHandler handler
) {
    if (request == NULL) {
        return MCLocalXPCResultConstructionFailed;
    }
    xpc_session_send_message_with_reply_async(
        (xpc_session_t)session,
        request,
        ^(xpc_object_t reply, xpc_rich_error_t error) {
            handler(MCLocalXPCClassifyMenuPresentationReply(
                reply,
                error,
                acknowledgement_kind,
                rejection_kind
            ));
        }
    );
    xpc_release(request);
    return MCLocalXPCResultOK;
}

MCLocalXPCResult MCLocalXPCSessionSendPairingReviewPublish(
    MCLocalXPCSessionRef session,
    const uint8_t *payload,
    size_t payload_length,
    MCLocalXPCMenuPresentationReplyHandler handler
) {
    return MCLocalXPCSessionSendConstructedPresentation(
        session,
        (xpc_object_t)MCLocalXPCMessageCreatePairingReviewPublish(
            payload,
            payload_length
        ),
        MCLocalXPCPairingReviewPublishAcknowledgementKind,
        MCLocalXPCPairingReviewPublishRejectionKind,
        handler
    );
}

MCLocalXPCResult MCLocalXPCSessionSendPairingReviewWithdrawal(
    MCLocalXPCSessionRef session,
    const uint8_t review_id[16],
    size_t review_id_length,
    MCLocalXPCMenuPresentationReplyHandler handler
) {
    return MCLocalXPCSessionSendConstructedPresentation(
        session,
        (xpc_object_t)MCLocalXPCMessageCreatePairingReviewWithdrawal(
            review_id,
            review_id_length
        ),
        MCLocalXPCPairingReviewWithdrawalAcknowledgementKind,
        NULL,
        handler
    );
}

MCLocalXPCResult MCLocalXPCSessionSendHostRecoveryReviewPublish(
    MCLocalXPCSessionRef session,
    const uint8_t *payload,
    size_t payload_length,
    MCLocalXPCMenuPresentationReplyHandler handler
) {
    return MCLocalXPCSessionSendConstructedPresentation(
        session,
        (xpc_object_t)MCLocalXPCMessageCreateHostRecoveryReviewPublish(
            payload,
            payload_length
        ),
        MCLocalXPCHostRecoveryReviewPublishAcknowledgementKind,
        MCLocalXPCHostRecoveryReviewPublishRejectionKind,
        handler
    );
}

MCLocalXPCResult MCLocalXPCSessionSendHostRecoveryResumePublish(
    MCLocalXPCSessionRef session,
    const uint8_t *payload,
    size_t payload_length,
    MCLocalXPCMenuPresentationReplyHandler handler
) {
    return MCLocalXPCSessionSendConstructedPresentation(
        session,
        (xpc_object_t)MCLocalXPCMessageCreateHostRecoveryResumePublish(
            payload,
            payload_length
        ),
        MCLocalXPCHostRecoveryResumePublishAcknowledgementKind,
        MCLocalXPCHostRecoveryResumePublishRejectionKind,
        handler
    );
}

MCLocalXPCResult MCLocalXPCSessionSendHostRecoveryWithdrawal(
    MCLocalXPCSessionRef session,
    const uint8_t review_id[16],
    size_t review_id_length,
    MCLocalXPCMenuPresentationReplyHandler handler
) {
    return MCLocalXPCSessionSendConstructedPresentation(
        session,
        (xpc_object_t)MCLocalXPCMessageCreateHostRecoveryWithdrawal(
            review_id,
            review_id_length
        ),
        MCLocalXPCHostRecoveryWithdrawalAcknowledgementKind,
        NULL,
        handler
    );
}

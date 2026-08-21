#include "CompanionLocalXPCPlatformC.h"

#include <string.h>

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

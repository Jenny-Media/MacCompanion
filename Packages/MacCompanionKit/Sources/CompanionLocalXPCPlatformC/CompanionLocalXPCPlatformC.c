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

MCLocalXPCResult MCLocalXPCListenerRequireSameTeamIdentifier(
    MCLocalXPCListenerRef listener,
    const char *signing_identifier
) {
    xpc_rich_error_t error = NULL;
    xpc_peer_requirement_t requirement =
        xpc_peer_requirement_create_team_identity(signing_identifier, &error);
    if (requirement == NULL) {
        MCLocalXPCReleaseError(error);
        return MCLocalXPCResultRequirementFailed;
    }
    MCLocalXPCReleaseError(error);
    xpc_listener_set_peer_requirement(
        (xpc_listener_t)listener,
        requirement
    );
    xpc_release(requirement);
    return MCLocalXPCResultOK;
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

MCLocalXPCResult MCLocalXPCSessionRequireSameTeamIdentifier(
    MCLocalXPCSessionRef session,
    const char *signing_identifier
) {
    xpc_rich_error_t error = NULL;
    xpc_peer_requirement_t requirement =
        xpc_peer_requirement_create_team_identity(signing_identifier, &error);
    if (requirement == NULL) {
        MCLocalXPCReleaseError(error);
        return MCLocalXPCResultRequirementFailed;
    }
    MCLocalXPCReleaseError(error);
    xpc_session_set_peer_requirement(
        (xpc_session_t)session,
        requirement
    );
    xpc_release(requirement);
    return MCLocalXPCResultOK;
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

MCLocalXPCResult MCLocalXPCSessionReplyToHello(
    MCLocalXPCSessionRef session,
    MCLocalXPCMessageRef hello
) {
    xpc_object_t reply = xpc_dictionary_create_reply(
        (xpc_object_t)hello
    );
    if (reply == NULL) {
        return MCLocalXPCResultConstructionFailed;
    }
    xpc_dictionary_set_string(reply, "kind", "hello.ack");
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

void MCLocalXPCSessionSendHello(
    MCLocalXPCSessionRef session,
    MCLocalXPCReplyHandler handler
) {
    xpc_object_t hello = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(hello, "kind", "hello");
    xpc_dictionary_set_int64(hello, "version", 1);
    xpc_session_send_message_with_reply_async(
        (xpc_session_t)session,
        hello,
        ^(xpc_object_t reply, xpc_rich_error_t error) {
            handler((MCLocalXPCMessageRef)reply, error != NULL);
        }
    );
    xpc_release(hello);
}

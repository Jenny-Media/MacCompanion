#include <dispatch/dispatch.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <xpc/xpc.h>

#define SERVICE_NAME "media.jenny.maccompanion.identity-probe"
#define MENU_IDENTIFIER "media.jenny.maccompanion"

static xpc_peer_requirement_t menu_requirement;

static bool is_exact_message(
    xpc_object_t message,
    const char *expected_kind,
    int64_t expected_version
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
        && xpc_dictionary_get_int64(message, "version") == expected_version;
}

static void fail_rich(const char *operation, xpc_rich_error_t error) {
    char *description = error == NULL
        ? NULL
        : xpc_rich_error_copy_description(error);
    fprintf(stderr, "%s failed%s%s\n", operation,
        description == NULL ? "" : ": ",
        description == NULL ? "" : description);
    free(description);
    exit(1);
}

static void handle_message(xpc_session_t peer, xpc_object_t message) {
    if (!is_exact_message(message, "hello", 1)) {
        xpc_session_cancel(peer);
        return;
    }

    fprintf(stderr, "handled-constant-hello\n");
    fflush(stderr);

    xpc_object_t reply = xpc_dictionary_create_reply(message);
    if (reply == NULL) {
        xpc_session_cancel(peer);
        return;
    }
    xpc_dictionary_set_string(reply, "kind", "hello.ack");
    xpc_dictionary_set_int64(reply, "version", 1);
    xpc_rich_error_t error = xpc_session_send_message(peer, reply);
    xpc_release(reply);
    if (error != NULL) {
        char *description = xpc_rich_error_copy_description(error);
        fprintf(stderr, "reply failed%s%s\n",
            description == NULL ? "" : ": ",
            description == NULL ? "" : description);
        free(description);
        xpc_release(error);
    }
}

int main(void) {
    xpc_rich_error_t error = NULL;
    menu_requirement = xpc_peer_requirement_create_team_identity(
        MENU_IDENTIFIER,
        &error
    );
    if (menu_requirement == NULL) {
        fail_rich("menu requirement construction", error);
    }

    dispatch_queue_t queue = dispatch_queue_create(
        "media.jenny.maccompanion.identity-probe.agent",
        DISPATCH_QUEUE_SERIAL
    );
    xpc_listener_t listener = xpc_listener_create(
        SERVICE_NAME,
        queue,
        XPC_LISTENER_CREATE_INACTIVE | XPC_LISTENER_CREATE_FORCE_MACH,
        ^(xpc_session_t peer) {
            xpc_session_set_peer_requirement(peer, menu_requirement);
            xpc_session_set_cancel_handler(peer, ^(xpc_rich_error_t _) {});
            xpc_session_set_incoming_message_handler(
                peer,
                ^(xpc_object_t message) {
                    handle_message(peer, message);
                }
            );
        },
        &error
    );
    if (listener == NULL) {
        fail_rich("listener construction", error);
    }

    xpc_listener_set_peer_requirement(listener, menu_requirement);
    if (!xpc_listener_activate(listener, &error)) {
        fail_rich("listener activation", error);
    }

    fprintf(stderr, "listener-ready\n");
    fflush(stderr);
    dispatch_main();
}

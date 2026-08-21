#include <dispatch/dispatch.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <xpc/xpc.h>

#define SERVICE_NAME "media.jenny.maccompanion.identity-probe"
#define AGENT_IDENTIFIER "media.jenny.maccompanion.agent"

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

static void print_rich(const char *operation, xpc_rich_error_t error) {
    char *description = error == NULL
        ? NULL
        : xpc_rich_error_copy_description(error);
    fprintf(stderr, "%s%s%s\n", operation,
        description == NULL ? "" : ": ",
        description == NULL ? "" : description);
    free(description);
}

int main(int argc, char **argv) {
    bool require_agent = true;
    int64_t hello_version = 1;
    bool add_extra_field = false;
    for (int argument_index = 1; argument_index < argc; argument_index += 1) {
        if (strcmp(argv[argument_index], "--no-peer-requirement") == 0) {
            require_agent = false;
        } else if (strcmp(argv[argument_index], "--unsupported-version") == 0) {
            hello_version = 2;
        } else if (strcmp(argv[argument_index], "--malformed") == 0) {
            add_extra_field = true;
        } else {
            fprintf(
                stderr,
                "usage: %s [--no-peer-requirement] "
                "[--unsupported-version] [--malformed]\n",
                argv[0]
            );
            return 64;
        }
    }

    dispatch_queue_t queue = dispatch_queue_create(
        "media.jenny.maccompanion.identity-probe.client",
        DISPATCH_QUEUE_SERIAL
    );
    xpc_rich_error_t error = NULL;
    xpc_session_t session = xpc_session_create_mach_service(
        SERVICE_NAME,
        queue,
        XPC_SESSION_CREATE_INACTIVE,
        &error
    );
    if (session == NULL) {
        print_rich("session construction failed", error);
        return 2;
    }

    if (require_agent) {
        xpc_peer_requirement_t requirement =
            xpc_peer_requirement_create_team_identity(
                AGENT_IDENTIFIER,
                &error
            );
        if (requirement == NULL) {
            print_rich("agent requirement construction failed", error);
            return 2;
        }
        xpc_session_set_peer_requirement(session, requirement);
        xpc_release(requirement);
    }

    dispatch_semaphore_t completed = dispatch_semaphore_create(0);
    __block int result = 2;
    xpc_session_set_cancel_handler(
        session,
        ^(xpc_rich_error_t cancellation) {
            print_rich("session cancelled", cancellation);
            dispatch_semaphore_signal(completed);
        }
    );

    if (!xpc_session_activate(session, &error)) {
        print_rich("session activation failed", error);
        return 2;
    }

    xpc_object_t hello = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(hello, "kind", "hello");
    xpc_dictionary_set_int64(hello, "version", hello_version);
    if (add_extra_field) {
        xpc_dictionary_set_bool(hello, "extra", true);
    }
    xpc_session_send_message_with_reply_async(
        session,
        hello,
        ^(xpc_object_t reply, xpc_rich_error_t reply_error) {
            if (reply_error != NULL) {
                print_rich("hello rejected", reply_error);
            } else if (is_exact_message(reply, "hello.ack", 1)) {
                result = 0;
            }
            dispatch_semaphore_signal(completed);
        }
    );
    xpc_release(hello);

    dispatch_time_t deadline = dispatch_time(
        DISPATCH_TIME_NOW,
        3 * NSEC_PER_SEC
    );
    if (dispatch_semaphore_wait(completed, deadline) != 0) {
        fprintf(stderr, "hello timed out\n");
        result = 3;
    }
    xpc_session_cancel(session);
    return result;
}

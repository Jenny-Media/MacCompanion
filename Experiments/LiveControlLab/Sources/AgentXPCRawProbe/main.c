// Disposable malformed/unsigned peer; sends only the content-free hello.
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <string.h>
#include <xpc/xpc.h>
#include <uuid/uuid.h>

int main(int argc, char **argv) {
    const char prefix[] = "media.jenny.maccompanion.xpc-test.";
    uuid_t test_id;
    if (argc != 3 || strncmp(argv[1], prefix, sizeof(prefix) - 1) != 0
        || uuid_parse(argv[1] + sizeof(prefix) - 1, test_id) != 0)
        return 64;
    dispatch_queue_t queue = dispatch_queue_create("isolated.raw-peer", DISPATCH_QUEUE_SERIAL);
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    xpc_rich_error_t error = NULL;
    xpc_session_t session = xpc_session_create_mach_service(
        argv[1], queue, XPC_SESSION_CREATE_INACTIVE, &error);
    if (!session) return 2;
    // No identity requirement: this adversarial client is testing the SERVER's
    // requirement, not using the reply as authority. It sends no credentials.
    xpc_session_set_cancel_handler(session, ^(xpc_rich_error_t ignored) {});
    if (!xpc_session_activate(session, &error)) return 2;
    xpc_object_t hello = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(hello, "kind", "hello");
    xpc_dictionary_set_int64(hello, "version", strcmp(argv[2], "version") == 0 ? 999 : 1);
    if (strcmp(argv[2], "extra") == 0) xpc_dictionary_set_bool(hello, "extra", true);
    __block int outcome = 1;
    xpc_session_send_message_with_reply_async(session, hello,
        ^(xpc_object_t reply, xpc_rich_error_t reply_error) {
            if (reply_error != NULL) outcome = 0;
            dispatch_semaphore_signal(done);
        });
    xpc_release(hello);
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)))
        outcome = 3; // Timeout is NOT a successful rejection.
    xpc_session_cancel(session);
    if (outcome == 0) puts("raw-peer-rejected");
    return outcome;
}

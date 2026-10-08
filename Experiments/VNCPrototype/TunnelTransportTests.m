#import <Foundation/Foundation.h>
#import <sys/socket.h>
#import <unistd.h>
#import <assert.h>
#import "../../Native/VNC/CompanionVNCTransport.h"

// Synthetic bytes only. Exercises the normal viewer's in-process socket bridge;
// this test executable is never linked into an app target.
static void Wait(dispatch_semaphore_t signal) {
    assert(dispatch_semaphore_wait(signal, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0);
}
int main(void) {
    @autoreleasepool {
        CompanionVNCTransport *pipe = [CompanionVNCTransport new]; assert(pipe);
        int client = [pipe takeClientSocket]; assert(client >= 0);
        assert([pipe takeClientSocket] == -1);
        NSData *expected = [@"RFB 003.889\n" dataUsingEncoding:NSASCIIStringEncoding];
        dispatch_semaphore_t sent = dispatch_semaphore_create(0), ended = dispatch_semaphore_create(0);
        NSMutableData *outgoing = [NSMutableData new];
        pipe.outbound = ^(NSData *data, void (^completion)(BOOL)) {
            [outgoing appendData:data]; completion(YES); dispatch_semaphore_signal(sent);
        };
        pipe.ended = ^{ dispatch_semaphore_signal(ended); };
        [pipe start]; [pipe start];
        assert(write(client, expected.bytes, expected.length) == expected.length);
        Wait(sent); assert([outgoing isEqualToData:expected]);
        dispatch_semaphore_t received = dispatch_semaphore_create(0);
        [pipe receiveData:expected completion:^(BOOL success) { assert(success); dispatch_semaphore_signal(received); }];
        uint8_t bytes[64]; ssize_t count = read(client, bytes, sizeof(bytes));
        assert(count == expected.length && memcmp(bytes, expected.bytes, count) == 0); Wait(received);
        [pipe stop]; [pipe stop]; Wait(ended);
        assert(read(client, bytes, sizeof(bytes)) == 0); close(client);
        // Closing an unstarted bridge must also release its transferred socket.
        CompanionVNCTransport *early = [CompanionVNCTransport new]; int other = [early takeClientSocket];
        [early stop]; [early start]; assert(read(other, bytes, sizeof(bytes)) == 0); close(other);
        puts("normal VNC socket bridge: ordering, ownership, EOF and idempotent stop passed");
    }
}

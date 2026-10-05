#import "CompanionVNCDirectConnection.h"
#import "CompanionVNCDirectEndpoint.h"
#import <netdb.h>
#import <netinet/tcp.h>
#import <fcntl.h>
#import <poll.h>
#import <unistd.h>
#import <errno.h>

static int ConnectAddress(NSString *host, NSInteger port, double phaseBudget, double totalDeadline, BOOL (^cancelled)(void), BOOL (^registerSocket)(int), NSInteger *failure) {
    *failure = 10;
    // getaddrinfo can block. Bound the owner's wait; resolver output has independent lifetime.
    dispatch_semaphore_t resolved = dispatch_semaphore_create(0);
    NSLock *resultLock = [NSLock new]; __block NSArray<NSData *> *addresses;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        struct addrinfo hints = {.ai_family = AF_UNSPEC, .ai_socktype = SOCK_STREAM, .ai_protocol = IPPROTO_TCP};
        struct addrinfo *result = NULL; NSMutableArray *local = [NSMutableArray new];
        if (getaddrinfo(host.UTF8String, [NSString stringWithFormat:@"%ld", (long)port].UTF8String, &hints, &result) == 0) {
            for (struct addrinfo *p = result; p; p = p->ai_next) {
                if (CompanionVNCLocalEndpoint(p->ai_addr, p->ai_addrlen))
                    [local addObject:[NSData dataWithBytes:p->ai_addr length:p->ai_addrlen]];
            }
            freeaddrinfo(result);
        }
        [resultLock lock]; addresses = [local copy]; [resultLock unlock];
        dispatch_semaphore_signal(resolved);
    });
    double deadline = MIN(totalDeadline, NSProcessInfo.processInfo.systemUptime + phaseBudget);
    while (dispatch_semaphore_wait(resolved, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC))) {
        if (cancelled() || NSProcessInfo.processInfo.systemUptime >= deadline) return -1;
    }
    [resultLock lock]; NSArray *candidates = addresses; [resultLock unlock];
    deadline = MIN(totalDeadline, NSProcessInfo.processInfo.systemUptime + phaseBudget);
    if (!candidates.count) *failure = 10; else *failure = 11;
    for (NSData *data in candidates) {
        if (cancelled() || NSProcessInfo.processInfo.systemUptime >= deadline) return -1;
        const struct sockaddr *address = data.bytes;
        int fd = socket(address->sa_family, SOCK_STREAM, IPPROTO_TCP);
        if (fd < 0) continue;
        int yes = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &yes, sizeof(yes));
        fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
        if (!registerSocket(fd)) { close(fd); return -1; }
        BOOL connected = connect(fd, address, (socklen_t)data.length) == 0;
        if (!connected && errno == EINPROGRESS) {
            while (!cancelled() && NSProcessInfo.processInfo.systemUptime < deadline) {
                struct pollfd p = {.fd = fd, .events = POLLOUT};
                int ready = poll(&p, 1, 100);
                if (ready < 0 && errno == EINTR) continue;
                if (ready != 0) {
                    int error = 0; socklen_t size = sizeof(error);
                    connected = ready > 0 && getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) == 0 && error == 0;
                    break;
                }
            }
        }
        if (connected && !cancelled()) { fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK); return fd; }
        registerSocket(-1); close(fd);
    }
    return -1;
}

int CompanionVNCConnectAddresses(NSArray<NSString *> *hosts, NSInteger port,
    BOOL (^cancelled)(void), BOOL (^registerSocket)(int), void (^progress)(NSUInteger, NSUInteger), NSInteger *failure) {
    if (!hosts.count || hosts.count > 8 || port < 1 || port > 65535) { *failure = 10; return -1; }
    double deadline = NSProcessInfo.processInfo.systemUptime + 16;
    double budget = hosts.count == 1 ? 8 : 2;
    for (NSUInteger i = 0; i < hosts.count; i++) {
        if (cancelled() || NSProcessInfo.processInfo.systemUptime >= deadline) break;
        if (progress) progress(i + 1, hosts.count);
        int socket = ConnectAddress(hosts[i], port, budget, deadline, cancelled, registerSocket, failure);
        if (socket >= 0) return socket;
    }
    return -1;
}
int CompanionVNCConnectLocal(NSString *host, BOOL (^cancelled)(void), BOOL (^registerSocket)(int)) {
    NSInteger failure = 0;
    return CompanionVNCConnectAddresses(@[host], 5900, cancelled, registerSocket, nil, &failure);
}

#import "CompanionNativeTLS.h"
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 5) return 10;
        NSString *directory = @(argv[1]), *mode = @(argv[2]);
        uint16_t portBase = (uint16_t)strtoul(argv[3], NULL, 10);
        NSError *error = nil;
        CompanionNativeTLS *tls = [[CompanionNativeTLS alloc] initWithError:&error];
        if (!tls) return 11;
        NSData *der = tls.certificateDER;
        if (![der writeToFile:[directory stringByAppendingPathComponent:@"client.der"] atomically:YES]) return 12;
        NSMutableData *trailing = [der mutableCopy]; [trailing appendBytes:"x" length:1];
        if ([CompanionNativeTLS validateCertificateDER:trailing server:NO]
            || [CompanionNativeTLS validateCertificateDER:der server:YES]) return 13;
        // Parent generates its test server and signals with public pin bytes.
        NSString *pinPath = [directory stringByAppendingPathComponent:@"host.der"];
        double start = NSProcessInfo.processInfo.systemUptime;
        while (![[NSFileManager defaultManager] fileExistsAtPath:pinPath]) {
            if (NSProcessInfo.processInfo.systemUptime - start > 5) return 14;
            [NSThread sleepForTimeInterval:0.005];
        }
        NSData *pin = [NSData dataWithContentsOfFile:pinPath];
        BOOL bound = [tls bindAddress:@"127.0.0.1" portBase:portBase hostCertificateDER:pin error:&error];
        if ([mode isEqualToString:@"invalid-pin"]) {
            [tls retire]; return bound ? 23 : 0;
        }
        if (!bound) return 15;
        if ([tls bindAddress:@"127.0.0.1" portBase:portBase hostCertificateDER:pin error:&error]) return 16;
        if ([tls requestPath:@"/pair?uniqueid=x" error:&error] != nil) return 17;
        if ([mode isEqualToString:@"cancel"]) {
            dispatch_semaphore_t done = dispatch_semaphore_create(0);
            __block NSData *result;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                result = [tls requestPath:@"/serverinfo?pause=1" error:nil]; dispatch_semaphore_signal(done);
            });
            [NSThread sleepForTimeInterval:0.15];
            [tls retire];
            if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) != 0 || result) return 18;
        } else {
            NSData *response = [tls requestPath:@"/serverinfo?uniqueid=test" error:&error];
            BOOL expected = [mode isEqualToString:@"valid"];
            if ((response != nil) != expected) return 19;
            if (expected && ![[[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding] isEqualToString:@"<root status_code=\"200\"><PairStatus>1</PairStatus></root>"]) return 20;
            [tls retire];
        }
        if (tls.certificateDER || [tls requestPath:@"/serverinfo" error:&error] != nil) return 21;
        if ([tls bindAddress:@"127.0.0.1" portBase:portBase hostCertificateDER:pin error:&error]) return 22;
        (void)argv[4];
        return 0;
    }
}

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

// Diagnostic comparison only: count callbacks without accessing IOSurface pixels.
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 2;
        char *end;
        unsigned long input = strtoul(argv[1], &end, 10);
        if (*end != '\0' || input > UINT32_MAX) return 2;
        CGDirectDisplayID display = (CGDirectDisplayID)input;
        NSMutableDictionary *counts = [NSMutableDictionary dictionary];
        dispatch_queue_t queue = dispatch_queue_create("metadata-only-legacy-capture", DISPATCH_QUEUE_SERIAL);
        CGDisplayStreamRef stream = CGDisplayStreamCreateWithDispatchQueue(
            display, CGDisplayPixelsWide(display), CGDisplayPixelsHigh(display),
            0x42475241, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGDisplayStreamShowCursor: @NO}, queue,
            ^(CGDisplayStreamFrameStatus status, uint64_t time, IOSurfaceRef surface, CGDisplayStreamUpdateRef update) {
                NSString *key = [NSString stringWithFormat:@"%d", (int)status];
                counts[key] = @([counts[key] unsignedIntegerValue] + 1);
                // Do not access the surface or its pixel data.
            });
        if (!stream) { puts("{\"legacyStreamCreated\":false}"); return 0; }
        CGError start = CGDisplayStreamStart(stream);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), queue, ^{
            CGError stop = CGDisplayStreamStop(stream);
            NSDictionary *result = @{@"legacyFrameStatuses": counts, @"startCode": @(start), @"stopCode": @(stop)};
            NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:nil];
            puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
            exit(0);
        });
        dispatch_main();
    }
}

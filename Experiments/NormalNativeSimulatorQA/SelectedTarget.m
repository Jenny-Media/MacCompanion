#import <AppKit/AppKit.h>
#include <stdio.h>
#include <unistd.h>

// Disposable, content-free App/Window target for the signed Mac menu probe.
// This process captures nothing and accepts no remote input.
int main(int argc, char **argv) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        application.activationPolicy = NSApplicationActivationPolicyAccessory;
        NSWindow *window = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(120, 120, 800, 500)
                      styleMask:NSWindowStyleMaskTitled
                        backing:NSBackingStoreBuffered
                          defer:NO];
        window.title = @"Mac Companion QA Target";
        window.backgroundColor = NSColor.redColor;
        window.releasedWhenClosed = NO;
        [window makeKeyAndOrderFront:nil];
        // A changing synthetic surface proves that the selected App stream
        // continues to deliver frames after Sunshine's encoder probes.
        __block BOOL alternate = NO;
        [NSTimer scheduledTimerWithTimeInterval:1.0 / 15.0 repeats:YES block:^(NSTimer *timer) {
            (void)timer;
            alternate = !alternate;
            window.backgroundColor = alternate ? NSColor.blueColor : NSColor.redColor;
        }];
        if (argc != 2 && argc != 3) return 2;
        if (argc == 3) {
            NSString *changePath = [NSString stringWithUTF8String:argv[2]];
            if (!changePath) return 2;
            [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) {
                if (![[NSFileManager defaultManager] fileExistsAtPath:changePath]) return;
                NSString *change = [[NSString stringWithContentsOfFile:changePath encoding:NSUTF8StringEncoding error:nil]
                    stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if ([change isEqualToString:@"close"]) [window close];
                else if ([change isEqualToString:@"move"]) [window setFrameOrigin:NSMakePoint(300, 180)];
                else if ([change isEqualToString:@"resize"]) [window setContentSize:NSMakeSize(640, 420)];
                else return;
                [change writeToFile:[changePath stringByAppendingString:@".done"] atomically:YES
                            encoding:NSUTF8StringEncoding error:nil];
                [timer invalidate];
            }];
        }
        FILE *ready = fopen(argv[1], "w");
        if (ready == NULL) return 3;
        fprintf(ready, "selected-target-ready %ld\n", (long)getpid());
        fclose(ready);
        // The twenty-transition UI journey can exceed five minutes. The
        // runner owns this disposable process and terminates it on cleanup.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1200LL * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ [application terminate:nil]; });
        [application run];
    }
    return 0;
}

#import "CompanionVNCDuoSample.h"
#if TARGET_OS_IOS && DEBUG
#import "CompanionVNCViewer.h"

@interface CompanionVNCViewer (DuoSample)
- (void)frame:(UIImage *)image;
- (void)updateConnectionChrome;
@end

/// No transport is opened and no input contents are retained by this fixture.
@interface CompanionVNCDuoSampleSession : CompanionVNCSession
@property(nonatomic, copy) NSString *sampleSequence;
@end
@implementation CompanionVNCDuoSampleSession
- (BOOL)running { return YES; }
- (BOOL)established { return YES; }
- (BOOL)connected { return YES; }
- (BOOL)desktopFrameReady { return YES; }
- (BOOL)composedTextReady { return YES; }
- (void)connectSocket:(int)socket username:(NSString *)username password:(NSString *)password {}
- (void)connectHost:(NSString *)host username:(NSString *)username password:(NSString *)password {}
- (void)connectAddresses:(NSArray<NSString *> *)addresses port:(NSInteger)port username:(NSString *)username password:(NSString *)password {}
- (void)pointerX:(NSInteger)x y:(NSInteger)y mask:(NSInteger)mask {}
- (BOOL)tryClickX:(NSInteger)x y:(NSInteger)y mask:(NSInteger)mask { return YES; }
- (void)key:(uint32_t)key down:(BOOL)down {}
- (void)keyEvents:(NSArray<NSDictionary *> *)events {}
- (BOOL)tryKeyEvents:(NSArray<NSDictionary *> *)events { return YES; }
- (BOOL)tryComposedTextEvents:(NSArray<NSDictionary *> *)events completion:(void (^)(BOOL))completion { if (completion) completion(YES); return YES; }
- (NSString *)beginControlSequence {
    if (self.sampleSequence) return nil;
    self.sampleSequence = NSUUID.UUID.UUIDString; return self.sampleSequence;
}
- (BOOL)ownsControlSequence:(NSString *)identifier { return [self.sampleSequence isEqual:identifier]; }
- (BOOL)tryControlSequenceEvents:(NSArray<NSDictionary *> *)events identifier:(NSString *)identifier completion:(void (^)(BOOL))completion {
    if (![self ownsControlSequence:identifier]) return NO;
    if (completion) completion(YES); return YES;
}
- (void)endControlSequence:(NSString *)identifier { if ([self ownsControlSequence:identifier]) self.sampleSequence = nil; }
- (void)cancelControlSequence:(NSString *)identifier { [self endControlSequence:identifier]; }
- (void)stop { self.sampleSequence = nil; }
- (void)pauseWithCompletion:(void (^)(void))completion { self.sampleSequence = nil; if (completion) completion(); }
@end

@interface CompanionVNCDuoSampleViewer : CompanionVNCViewer
@end
@implementation CompanionVNCDuoSampleViewer
- (void)viewDidLoad {
    self.preventsAutomaticConnection = YES;
    self.macName = @"Local sample · no Mac connected";
    [super viewDidLoad];
    self.session = [CompanionVNCDuoSampleSession new];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1440,900)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor colorWithRed:.06 green:.13 blue:.27 alpha:1] setFill]; [context fillRect:CGRectMake(0,0,1440,900)];
        [UIColor.systemGray6Color setFill]; [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(90,90,1260,720) cornerRadius:20] fill];
        NSDictionary *title = @{NSFontAttributeName:[UIFont systemFontOfSize:42 weight:UIFontWeightBold],NSForegroundColorAttributeName:UIColor.labelColor};
        [@"Sample workspace" drawAtPoint:CGPointMake(150,150) withAttributes:title];
        [@"Local preview · input stays on this device" drawAtPoint:CGPointMake(150,220) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:25],NSForegroundColorAttributeName:UIColor.secondaryLabelColor}];
        for (int i=0;i<3;i++) {
            [UIColor.systemBlueColor setFill]; [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(150+i*390,340,340,270) cornerRadius:18] fill];
            [[NSString stringWithFormat:@"Project %d",i+1] drawAtPoint:CGPointMake(180+i*390,380) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:28 weight:UIFontWeightSemibold],NSForegroundColorAttributeName:UIColor.whiteColor}];
        }
    }];
    [self frame:image]; [(UIView *)[self valueForKey:@"login"] setHidden:YES]; [self updateConnectionChrome];
}
@end
UIViewController *CompanionVNCDuoSampleWorkspace(void) { return [CompanionVNCDuoSampleViewer new]; }
#endif

#import "PrototypeViewer.h"
#include <math.h>
@implementation MCPrototypeViewer {
    NSTimer *_probeTimer;
    MCBenchmarkJournal *_journal;
    __weak CompanionVNCSession *_sampleOwner;
    BOOL _probeVisible;
    double _sampleStartedAt, _lastRecordedUptime;
    NSInteger _lastProbeOutcome;
    BOOL _lastRunning;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    _journal = [[MCBenchmarkJournal alloc] initWithURL:[NSURL fileURLWithPath:[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"ScreenTransportBenchmark-v1.jsonl"]] maximumBytes:4 * 1024 * 1024];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stopProbeSampling) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(startProbeSampling) name:UIApplicationDidBecomeActiveNotification object:nil];
}
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; _probeVisible = YES; [self startProbeSampling]; }
- (void)viewDidDisappear:(BOOL)animated { _probeVisible = NO; [self stopProbeSampling]; [super viewDidDisappear:animated]; }
- (void)dealloc { [_probeTimer invalidate]; [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)startProbeSampling {
    if (!_probeVisible || _probeTimer || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    __weak MCPrototypeViewer *weak = self;
    _probeTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { [weak samplePrototype]; }];
    [NSRunLoop.mainRunLoop addTimer:_probeTimer forMode:NSRunLoopCommonModes];
    [self samplePrototype];
}
- (void)stopProbeSampling { [_probeTimer invalidate]; _probeTimer = nil; if (_sampleOwner) [_journal endOwner:_sampleOwner]; _sampleOwner = nil; }
- (void)samplePrototype {
    CompanionVNCSession *owner = self.session;
    if (_sampleOwner != owner) { if (_sampleOwner) [_journal endOwner:_sampleOwner]; _sampleOwner = owner; _sampleStartedAt = NSProcessInfo.processInfo.systemUptime; _lastRecordedUptime = 0; [_journal beginOwner:owner]; }
    if (self.diagnosticHandler) self.diagnosticHandler(owner.diagnosticCounters);
}
- (void)recordPrototypeSnapshot:(NSDictionary *)snapshot {
    id stamp = snapshot[@"sampleUptime"];
    if (![stamp isKindOfClass:NSNumber.class] || !isfinite([stamp doubleValue])) return;
    double captured = [stamp doubleValue];
    NSInteger outcome = [snapshot[@"probeOutcome"] integerValue]; BOOL running = [snapshot[@"sessionRunning"] boolValue];
    BOOL transition = outcome != _lastProbeOutcome || running != _lastRunning;
    if (captured < _sampleStartedAt || (!transition && captured - _lastRecordedUptime < .95)) return;
    if (_probeVisible && _probeTimer && self.session == _sampleOwner) {
        _lastRecordedUptime = captured; _lastProbeOutcome = outcome; _lastRunning = running;
        [_journal appendCounters:snapshot owner:self.session];
    }
}
@end

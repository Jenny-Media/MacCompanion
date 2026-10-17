#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface MCBenchmarkJournal : NSObject
@property(nonatomic, readonly) BOOL full;
@property(nonatomic, readonly) NSUInteger droppedSamples;
- (instancetype)initWithURL:(NSURL *)url maximumBytes:(NSUInteger)maximumBytes;
- (void)beginOwner:(id)owner;
- (void)endOwner:(id)owner;
- (void)appendCounters:(NSDictionary *)counters owner:(id)owner;
/// Test/drain barrier on the journal's own I/O queue, never the main thread.
- (void)flush:(void (^)(void))completion;
+ (NSDictionary *)filteredCounters:(NSDictionary *)counters;
@end
NS_ASSUME_NONNULL_END

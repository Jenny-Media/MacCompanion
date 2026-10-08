#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface CompanionVNCTransport : NSObject
- (nullable instancetype)init;
@property(nonatomic, copy, nullable) void (^outbound)(NSData *, void (^)(BOOL));
@property(nonatomic, copy, nullable) void (^ended)(void);
- (int)takeClientSocket;
- (void)start;
- (void)receiveData:(NSData *)data completion:(void (^)(BOOL))completion;
- (void)stop;
@end
NS_ASSUME_NONNULL_END

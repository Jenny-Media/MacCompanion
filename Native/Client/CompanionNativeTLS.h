#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Disposable native TLS identity. No exported private key, pairing, or input.
/// requestPath is blocking and must run off the UI thread. retire interrupts it.
@interface CompanionNativeTLS : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nullable, readonly, copy) NSData *certificateDER;
- (nullable instancetype)initWithError:(NSError **)error;
+ (nullable instancetype)createWithError:(NSError **)error;
+ (BOOL)validateCertificateDER:(NSData *)der server:(BOOL)server;
- (BOOL)bindAddress:(NSString *)address portBase:(uint16_t)portBase hostCertificateDER:(NSData *)der error:(NSError **)error;
- (nullable NSData *)requestPath:(NSString *)path error:(NSError **)error;
- (void)retire;
@end
NS_ASSUME_NONNULL_END

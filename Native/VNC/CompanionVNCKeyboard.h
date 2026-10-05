#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Main-thread keyboard selection. Every emitted group has balanced key pairs.
@interface CompanionVNCKeyboard : NSObject
@property(nonatomic, readonly) NSArray<NSNumber *> *armedModifiers;
- (instancetype)initWithEvents:(void (^)(NSArray<NSDictionary *> *))events;
- (void)toggleModifier:(uint32_t)key;
- (void)pressModifierAlone:(uint32_t)key;
- (void)pressKey:(uint32_t)key;
- (void)text:(NSString *)text;
- (void)reset;
@end

/// Admit the entire group or none of it; never strand an incomplete shortcut.
static inline BOOL CompanionVNCKeyGroupFits(NSUInteger queued, NSUInteger incoming, NSUInteger capacity) {
    return queued <= capacity && incoming <= capacity - queued;
}
NS_ASSUME_NONNULL_END

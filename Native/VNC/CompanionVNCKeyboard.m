#import "CompanionVNCKeyboard.h"

@implementation CompanionVNCKeyboard {
    NSMutableSet<NSNumber *> *_armed;
    void (^_events)(NSArray<NSDictionary *> *);
}
static NSArray<NSNumber *> *ModifierOrder(void) {
    return @[@(0xffe1), @(0xffe3), @(0xffe9), @(0xffeb)];
}
static NSDictionary *KeyEvent(uint32_t key, BOOL down) {
    return @{@"key": @(key), @"down": @(down)};
}
- (instancetype)initWithEvents:(void (^)(NSArray<NSDictionary *> *))events {
    if ((self = [super init])) { _armed = [NSMutableSet new]; _events = [events copy]; }
    return self;
}
- (NSArray<NSNumber *> *)armedModifiers {
    NSMutableArray *ordered = [NSMutableArray new];
    for (NSNumber *key in ModifierOrder()) if ([_armed containsObject:key]) [ordered addObject:key];
    return ordered;
}
- (void)toggleModifier:(uint32_t)key {
    NSNumber *value = @(key);
    if (![ModifierOrder() containsObject:value]) return;
    if ([_armed containsObject:value]) [_armed removeObject:value]; else [_armed addObject:value];
}
- (void)pressModifierAlone:(uint32_t)key {
    if (![ModifierOrder() containsObject:@(key)]) return;
    [self reset]; _events(@[KeyEvent(key, YES), KeyEvent(key, NO)]);
}
- (void)pressKey:(uint32_t)key {
    NSArray<NSNumber *> *modifiers = self.armedModifiers;
    [self reset];
    NSMutableArray *events = [NSMutableArray new];
    for (NSNumber *modifier in modifiers) [events addObject:KeyEvent(modifier.unsignedIntValue, YES)];
    [events addObject:KeyEvent(key, YES)]; [events addObject:KeyEvent(key, NO)];
    for (NSNumber *modifier in modifiers.reverseObjectEnumerator) [events addObject:KeyEvent(modifier.unsignedIntValue, NO)];
    _events(events);
}
- (void)text:(NSString *)text {
    // Committed Unicode scalars only. The first scalar consumes the one-shot chord.
    NSData *data = [text dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
    const uint32_t *scalars = data.bytes;
    for (NSUInteger i = 0; i < data.length / sizeof(uint32_t); i++) {
        uint32_t scalar = scalars[i];
        [self pressKey:scalar == 10 ? 0xff0d : scalar < 256 ? scalar : 0x01000000 | scalar];
    }
}
- (void)reset { [_armed removeAllObjects]; }
@end

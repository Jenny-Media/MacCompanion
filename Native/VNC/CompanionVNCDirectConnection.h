#import <Foundation/Foundation.h>
// Caller owns a successful descriptor. Registration synchronizes Stop with socket ownership.
int CompanionVNCConnectLocal(NSString *host, BOOL (^cancelled)(void), BOOL (^registerSocket)(int));
// connectedIndex is optional and receives the zero-based index only on success.
int CompanionVNCConnectAddresses(NSArray<NSString *> *hosts, NSInteger port,
    BOOL (^cancelled)(void), BOOL (^registerSocket)(int), void (^progress)(NSUInteger, NSUInteger),
    NSInteger *failure, NSInteger *connectedIndex);

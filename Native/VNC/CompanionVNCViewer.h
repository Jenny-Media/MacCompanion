#import <UIKit/UIKit.h>
#import "CompanionVNCSession.h"
NS_ASSUME_NONNULL_BEGIN
@interface CompanionVNCViewer : UIViewController
@property(nonatomic) NSInteger servicePort;
@property(nonatomic) BOOL fullscreen;
@property(nonatomic) BOOL inputOnly;
@property(nonatomic, copy) void (^presentationHandler)(BOOL fullscreen);
@property(nonatomic, strong) CompanionVNCSession *session;
@property(nonatomic, copy, nullable) NSString *macName;
@property(nonatomic, copy, nullable) NSArray<NSString *> *connectionMacNames;
@property(nonatomic, copy, nullable) NSString *preferenceID;
@property(nonatomic) CGFloat pointerSpeed;
@property(nonatomic) CGFloat scrollSpeed;
@property(nonatomic) BOOL showsTouchPoints;
@property(nonatomic) BOOL trackpadHapticsEnabled;
@property(nonatomic) BOOL preferredTrackpad;
@property(nonatomic) BOOL followCursorEnabled;
@property(nonatomic, copy, nullable) NSNumber *restoredDisplayID;
@property(nonatomic, copy) NSArray<NSDictionary *> *quickActions;
@property(nonatomic, copy, nullable) NSArray<NSDictionary *> * (^quickActionsProvider)(BOOL inputOnly);
@property(nonatomic, copy, nullable) void (^settingsHandler)(void);
@property(nonatomic, copy, nullable) void (^appSettingsHandler)(void);
@property(nonatomic, copy, nullable) void (^displaySelectionHandler)(NSNumber * _Nullable);
@property(nonatomic, copy, nullable) void (^inputModeHandler)(BOOL);
@property(nonatomic, copy, nullable) NSString *savedUsername;
@property(nonatomic, copy, nullable) NSString *savedPassword;
@property(nonatomic, copy, nullable) NSDictionary *displayLayout;
@property(nonatomic, copy, nullable) void (^connectHandler)(NSString *, NSString *, BOOL);
@property(nonatomic, copy, nullable) void (^disconnectHandler)(void);
@property(nonatomic, copy, nullable) void (^macsHandler)(void);
@property(nonatomic, copy, nullable) void (^connectedHandler)(void);
@property(nonatomic, copy, nullable) void (^sessionPhaseHandler)(NSString *);
/// Local presentation only: the desktop canvas is visible instead of sign-in.
@property(nonatomic, copy, nullable) void (^chromeHandler)(BOOL);
@property(nonatomic, copy, nullable) void (^diagnosticHandler)(NSDictionary *);
@property(nonatomic, copy, nullable) void (^windowBoundsHandler)(CGPoint, CGSize, void (^)(CGRect));
- (void)stopViewer;
- (void)prepareConnection;
- (void)showConnectionFailure;
- (void)showRecoveryStage:(NSInteger)stage;
- (void)showInvalidLogin;
- (void)showLoginRetentionFailure;
- (void)background;
- (void)backgroundWithCompletion:(nullable void (^)(void))completion;
- (void)foregrounded;
@end
NS_ASSUME_NONNULL_END

#import <UIKit/UIKit.h>
#import "CompanionVNCSession.h"
@class DirectConnectionPanelHost;
@class CompanionVNCInterfaceFeedback;
NS_ASSUME_NONNULL_BEGIN
@interface CompanionVNCViewer : UIViewController
@property(nonatomic, strong, nullable) DirectConnectionPanelHost *connectionPanelHost;
@property(nonatomic) BOOL preventsLoginRetention;
@property(nonatomic) NSInteger servicePort;
@property(nonatomic) NSInteger sshPort;
@property(nonatomic) BOOL fullscreen;
@property(nonatomic) BOOL inputOnly;
@property(nonatomic, copy) void (^presentationHandler)(BOOL fullscreen);
@property(nonatomic, strong) CompanionVNCSession *session;
@property(nonatomic, copy, nullable) NSString *macName;
@property(nonatomic, copy, nullable) NSArray<NSString *> *connectionMacNames;
/// Configured fallback addresses for local connection-detail presentation.
@property(nonatomic, copy, nullable) NSArray<NSString *> *connectionAddresses;
@property(nonatomic, copy, nullable) NSString *preferenceID;
@property(nonatomic) CGFloat pointerSpeed;
@property(nonatomic) CGFloat scrollSpeed;
@property(nonatomic) BOOL showsTouchPoints;
@property(nonatomic) BOOL trackpadHapticsEnabled;
@property(nonatomic) BOOL preferredTrackpad;
@property(nonatomic) BOOL followCursorEnabled;
@property(nonatomic, copy, nullable) NSNumber *restoredDisplayID;
/// Device-local choice: zero mirrors the Mac; 1–3 select a virtual landscape size.
@property(nonatomic) NSInteger restoredDesktopSizePreset;
@property(nonatomic, copy, nullable) void (^desktopSizeSelectionHandler)(NSInteger preset);
@property(nonatomic, copy) NSArray<NSDictionary *> *quickActions;
@property(nonatomic, copy, nullable) NSArray<NSDictionary *> * (^quickActionsProvider)(BOOL inputOnly);
@property(nonatomic, copy, nullable) void (^settingsHandler)(void);
@property(nonatomic, copy, nullable) void (^appSettingsHandler)(void);
@property(nonatomic, copy, nullable) void (^filesHandler)(void);
@property(nonatomic, copy, nullable) BOOL (^filesTransferActiveHandler)(void);
@property(nonatomic, copy, nullable) void (^accessHandler)(void);
@property(nonatomic, copy, nullable) BOOL (^accessEditingAllowed)(void);
@property(nonatomic, copy, nullable) BOOL (^requestExitHandler)(void);
- (void)reloadAccessUsername:(NSString *)username password:(NSString *)password;
- (void)refreshAccessEditing;
@property(nonatomic, copy, nullable) NSString *filesStatus;
@property(nonatomic, copy, nullable) void (^displaySelectionHandler)(NSNumber * _Nullable);
@property(nonatomic, copy, nullable) void (^inputModeHandler)(BOOL);
@property(nonatomic, copy, nullable) NSString *savedUsername;
@property(nonatomic, copy, nullable) NSString *savedPassword;
@property(nonatomic) BOOL preventsAutomaticConnection;
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
/// Shared iOS keyboard presentation uses the existing connection-owned queue.
@property(nonatomic, readonly) NSUInteger controlsEpoch;
@property(nonatomic, readonly) NSString *controlsConnectionID;
@property(nonatomic, readonly) CompanionVNCInterfaceFeedback *controlsFeedback;
- (BOOL)controlsInputAvailable;
- (BOOL)sendControlEvents:(NSArray<NSDictionary *> *)events completion:(void (^)(BOOL))completion;
- (nullable NSString *)beginControlSequence;
- (BOOL)sendControlSequenceEvents:(NSArray<NSDictionary *> *)events identifier:(NSString *)identifier completion:(void (^)(BOOL))completion;
- (void)endControlSequence:(NSString *)identifier;
- (void)cancelControlSequence:(NSString *)identifier;
- (void)sendOrdinaryControlEvents:(NSArray<NSDictionary *> *)events;
- (void)toggleControlsKeyboard;
- (void)beginKeyboardCustomization;
- (void)endKeyboardCustomization;
- (void)showControlsComposer;
- (void)showControlsComposerWithText:(NSString *)text title:(NSString *)title available:(BOOL (^)(void))available NS_SWIFT_NAME(showControlsComposer(text:title:available:));
- (void)showControlsSettings;
- (void)refreshControlsMenu;
- (BOOL)controlsCopyTextAvailable;
- (void)performSharedControlAction:(NSString *)kind;
- (void)stopViewer;
- (void)prepareConnection;
/// Snapshot before preparing the replacement; applied after joining SSH retirement.
@property(nonatomic, readonly) NSTimeInterval mirrorRetirementDelay;
@property(nonatomic, readonly) BOOL connectionForegroundAvailable;
- (void)showMirrorCleanupRemaining:(NSUInteger)seconds;
- (void)finishMirrorCleanup;
- (void)showConnectionFailure;
- (void)showConnectionFailureStage:(NSInteger)stage;
- (void)showConnectionProgress:(NSString *)message;
- (void)showRecoveryStage:(NSInteger)stage;
- (void)showInvalidLogin;
- (void)showLoginRetentionFailure;
- (void)showMacSaveFailure:(BOOL)loginRequested;
- (void)background;
- (void)becameInactive;
- (void)backgroundWithCompletion:(nullable void (^)(void))completion;
- (void)foregrounded;
@end
NS_ASSUME_NONNULL_END

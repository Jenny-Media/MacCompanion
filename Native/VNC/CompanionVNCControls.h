#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *const CompanionVNCControlsHapticsPreference;
/// Interface feedback is local action acknowledgement, never a transport ACK.
/// UIKit gracefully omits unsupported haptics; trackpad feedback stays separate.
FOUNDATION_EXPORT void CompanionVNCPlayInterfaceFeedback(NSString *kind);
NS_SWIFT_UI_ACTOR
@interface CompanionVNCInterfaceFeedback : NSObject
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
@property(nonatomic, readonly) BOOL foreground;
- (void)feedback:(NSString *)kind;
/// Output boundary overridden by native tests without vibrating hardware.
- (void)emitFeedback:(NSString *)kind;
@end
/// Locally captured tap/press-and-slide chrome, independent of remote gestures.
@interface CompanionVNCControls : UIView
@property(nonatomic, copy) NSString *macName;
@property(nonatomic, copy) NSArray<NSDictionary *> *quickActions;
/// Optional session-specific categories; nil retains the Desktop categories.
@property(nonatomic, copy, nullable) NSArray<NSDictionary *> *categoryActions;
@property(nonatomic) BOOL trackpad;
@property(nonatomic) BOOL hapticsEnabled;
@property(nonatomic) BOOL fullscreen, inputOnly;
@property(nonatomic) BOOL textCopyAvailable;
@property(nonatomic) CGFloat bottomInset;
/// Optional toolbar slot; the shared button and its gestures remain in this overlay.
@property(nonatomic, weak, nullable) UIView *buttonAnchorView;
@property(nonatomic, readonly) UIButton *button;
@property(nonatomic, readonly) BOOL menuOpen;
@property(nonatomic, copy, nullable) void (^actionHandler)(NSDictionary *);
@property(nonatomic, copy, nullable) void (^openingHandler)(void);
@property(nonatomic, copy, nullable) void (^customizeHandler)(void);
/// Uses the session renderer, but gestures only select/reorder draft actions.
@property(nonatomic) BOOL editingPreview;
@property(nonatomic, copy, nullable) NSString *selectedPreviewID;
@property(nonatomic, copy, nullable) void (^previewSelectionHandler)(NSString *);
@property(nonatomic, copy, nullable) void (^previewMoveHandler)(NSString *, NSString *);
- (void)refreshEditingPreview;
- (void)close;
- (void)cancelSlideForLayoutChange;
@end
NS_ASSUME_NONNULL_END

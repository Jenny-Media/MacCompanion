#import <UIKit/UIKit.h>
#import "CompanionVNCSession.h"
#import "CompanionVNCViewer.h"
#import "CompanionVNCDesktopSize.h"
#import "CompanionVNCKeyboard.h"
#import "CompanionVNCViewport.h"
#import "CompanionVNCFramebufferBounds.h"
#import "CompanionVNCAdaptiveLayout.h"
#import "CompanionVNCCursor.h"
#import "CompanionVNCDisplayPicker.h"
#import "CompanionVNCControls.h"
#import "CompanionVNCTapGesture.h"
#import "CompanionVNCTrackpadFeedback.h"
#import "CompanionVNCMenu.h"
#import "CompanionVNCTextReview.h"
#import "Mac_Companion-Swift.h"

@interface CompanionRemoteTextInput : UITextView
@property(nonatomic, copy) void (^remoteDelete)(void);
@end
@implementation CompanionRemoteTextInput
- (void)deleteBackward {
    if (self.text.length || self.markedTextRange) [super deleteBackward];
    else if (self.remoteDelete) self.remoteDelete();
}
@end

@interface CompanionVNCViewer () <UIScrollViewDelegate, UITextViewDelegate, UIGestureRecognizerDelegate>

@property UITextField *host, *username, *password;
@property DirectDesktopLoginState *credentialState;
@property UIViewController *recoveryController;
@property BOOL macSaveFailureVisible;
@property(nonatomic, copy) void (^recoveryInputOnlyAction)(void);
@property(nonatomic, copy) NSString *loginIssueDetails;
@property UIViewController *loginBackdrop;
@property UIScrollView *recoveryPanel;
@property UIStackView *login;
@property UIScrollView *loginScroll;
@property UIViewController *loginPanelContent;
@property UIViewController *loginProgressContent;
@property DirectConnectionProgressState *connectionProgress;
@property NSObject *loginPanelOwner;
@property UIStackView *saveLoginRow;
@property UIStackView *loginFields, *progressRow, *keyRow;
@property UIStackView *loginIntro, *loginIdentity, *credentialColumns;
@property UIStackView *loginActions;
@property CGFloat loginProgressHeight;
@property UILabel *loginSubtitle;
@property UILabel *loginPurpose;
@property UIButton *loginDetails;
@property UILabel *loginDetailsText;
@property BOOL loginDetailsExpanded;
@property UIButton *loginClose, *loginCancel, *loginTrackpad;
@property UIImageView *loginIcon;
@property NSLayoutConstraint *loginIconHeight, *loginIconWidth, *loginTop, *loginBottom, *loginMaxWidth;
@property NSLayoutConstraint *loginContentTop;
@property BOOL foldedLogin;
@property UIScrollView *toolbar;
@property UIView *tabletopPad;
@property UILabel *tabletopLabel;
@property NSArray<UIGestureRecognizer *> *tabletopGestures;
@property NSLayoutConstraint *tabletopCanvasBottom;
@property BOOL tabletop, adaptingViewport;
@property CGFloat layoutZoomRatio;
@property CGPoint layoutCenter;
@property CGRect layoutCrop;
@property CGRect tabletopInputRegion;
@property UILabel *progressLabel;
@property UIActivityIndicatorView *spinner;
@property CompanionVNCControls *controls;
@property CompanionVNCInterfaceFeedback *keyFeedback;
@property(weak) UINavigationController *sessionMenu;
@property NSUInteger sessionMenuGeneration;
@property BOOL retiringPointerGestures;
@property NSUInteger displaySelectionRejections, displaySelectionRejectMask;
@property BOOL initialDisplayApplied;
@property BOOL desktopSizeRestored;
@property NSInteger pendingDesktopSizePreset;
@property NSNumber *pendingStreamDisplayID;
@property BOOL changingDisplayMode, mirrorRestartScheduled, mirrorRequiresCleanup, mirrorFullRestartUsed;
@property NSUInteger mirrorRestoreAttempts, mirrorRestoreOutcome, mirrorCleanupRemaining;
@property NSInteger modeTargetPreset, modePreviousPreset, lateDesktopSizePreset;
@property NSUInteger modeRecoveryAttempts;
@property BOOL modeResizeRequested, modeVerificationTimed;
@property NSUInteger modeVerificationGeneration;
@property NSNumber *failedDisplayModePreset, *modeConfirmationPreset;
@property BOOL inputOnlyConfirmationPending;
@property(weak) CompanionVNCSession *modeConfirmationOwner;
@property(weak) UIAlertController *modeConfirmationAlert;
@property NSMutableArray<NSNumber *> *mirrorObservedLayouts;
@property BOOL restoringStreamViewport;
@property BOOL immersiveChrome;
@property CGPoint trackpadTranslation;
@property UISwitch *remember;
@property UILabel *status;
@property UIButton *connect, *views, *pan, *keyboardButton, *passwordVisibility;
@property UIScrollView *canvas;
@property UIImageView *image;
@property UIView *cursorOverlay, *cursorIndicator;
@property UIImageView *cursorImage;
@property CAShapeLayer *fallbackCursor;
@property UIImage *remoteCursorImage;
@property CGPoint cursorPosition, cursorHotspot;
@property BOOL cursorPositionKnown, hostCursorPositionKnown, localAimPinned;
@property CGPoint hostCursorPosition;
@property NSMutableOrderedSet<NSValue *> *localPointerTargets;
@property NSUInteger hostPositionsAdopted, hostPositionsFiltered;
@property NSTimeInterval lastLocalPointerInputAt;
@property BOOL cursorFollowingSuspended;
@property CompanionRemoteTextInput *input;
@property NSLayoutConstraint *toolbarBottom, *canvasToolbarBottom, *canvasFullscreenBottom;
@property NSLayoutConstraint *canvasTop;
@property UIEdgeInsets previousCanvasInset;
@property UILabel *trackpadHelp;
@property CompanionVNCTrackpadFeedback *trackpadFeedback, *tabletopFeedback;
@property UIGestureRecognizer *click;
@property UITapGestureRecognizer *secondaryTap, *smartTap, *tabletopSecondaryTap;
@property UIPanGestureRecognizer *drag, *remoteScroll;
@property UIPinchGestureRecognizer *remotePinch;
@property BOOL magnificationActive;
@property UILongPressGestureRecognizer *hold;
@property CGPoint trackpadOrigin, holdOrigin;
@property CGFloat scrollRemainder;
@property CGPoint scrollFraction;
@property BOOL scrollingActive, scrollUsesNative, scrollGestureActive;
@property NSArray *displayViews;
@property CGFloat displayAspect;
@property CGSize framebufferSize;
@property BOOL trackpadMode, reconnectWhenReady, foreground, fixtureExercised, starting;
@property BOOL textSendInterrupted;
@property NSMutableArray<UIButton *> *modifiers;
@property CompanionVNCKeyboard *remoteKeyboard;
@property DirectTextComposer *textComposer;
@property NSUInteger textGeneration;
@property NSDictionary *selectedDisplay;
@property UIImage *lastFramebuffer;
@property CGRect activeCrop, smartWindow;
@property CGSize previousCanvasSize;
@property CGFloat keyboardOverlap, keyboardSavedRatio, keyboardLayoutRatio;
@property CGPoint keyboardSavedCenter, keyboardLayoutCenter;
@property CGRect keyboardSavedCrop;
@property BOOL keyboardViewportSaved, keyboardLayoutPending;
@property CGPoint lastPointer;
@property BOOL pointerHeld, smartZoomed, smartZoomPending;
@property NSUInteger zoomGeneration, resumeGeneration;
@property BOOL checkingResume, exited, restoreViewportPending, inputInactive, awaitingReplacementLayout;
@property UIImage *pendingRestorationFrame;
@property NSUInteger statusGeneration;
@property UIStackView *statusRow;
@property UIVisualEffectView *statusBackdrop;
@property UIActivityIndicatorView *statusSpinner;
@property NSDictionary *latestCounters;
@property NSTimeInterval displayNoticeUntil;
@property NSNumber *resumeDisplayID;
@property CGSize resumeCropSize;
@property CGFloat resumeZoomRatio;
@property CGPoint resumeCenter;
@property(nonatomic, weak) CompanionVNCDisplayPicker *displayPicker;
@property CompanionVNCTextReview *textReview;
@property NSNumber *deferredTextReviewFailure;
@property NSUInteger textReviewGeneration;
@property CGRect textReviewCrop;
@property CGSize textReviewFramebuffer;
@property CGFloat textReviewZoom;
@property CGPoint textReviewCenter;
@property BOOL textReviewViewportPending;
@property BOOL diagnosticScheduled;
@property NSUInteger diagnosticGeneration, diagnosticWrites;
@property NSDictionary *diagnosticFlags;
@property(nonatomic, copy) NSDictionary *lastConnectionFailure;
- (BOOL)composedTextAvailable;
- (BOOL)sessionKeyInputAvailable;
- (void)retireSessionMenu;
@end

@implementation CompanionVNCViewer
- (UIStatusBarStyle)preferredStatusBarStyle {
    return self.immersiveChrome || self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? UIStatusBarStyleLightContent : UIStatusBarStyleDarkContent;
}
- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) { _followCursorEnabled = YES; _scrollSpeed = 1; _showsTouchPoints = YES; _trackpadHapticsEnabled = YES; }
    return self;
}
- (void)setDisplayLayout:(NSDictionary *)displayLayout {
    if (self.awaitingReplacementLayout && (!displayLayout || [displayLayout[@"aspectRatio"] doubleValue] <= 0 || ![displayLayout[@"views"] count])) return;
    _displayLayout = [displayLayout copy];
    self.displayViews = displayLayout[@"views"] ?: @[];
    self.displayAspect = [displayLayout[@"aspectRatio"] doubleValue];
    if (self.awaitingReplacementLayout) {
        self.awaitingReplacementLayout = NO;
        UIImage *pending = self.pendingRestorationFrame; self.pendingRestorationFrame = nil;
        if (pending) [self frame:pending];
        return;
    }
    [self updateDisplayPicker];
    [self restoreSavedDisplay];
    if (self.selectedDisplay) {
        NSDictionary *replacement = nil;
        for (NSDictionary *display in self.displayViews) {
            if ([display[@"id"] isEqual:self.selectedDisplay[@"id"]]) { replacement = display; break; }
        }
        [self selectDisplay:replacement];
    }
}
- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]; button.titleLabel.adjustsFontForContentSizeCategory = YES;
    button.backgroundColor = UIColor.secondarySystemBackgroundColor;
    button.layer.cornerRadius = 10;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    return button;
}
- (UITextField *)field:(NSString *)placeholder {
    UITextField *field = [UITextField new]; field.placeholder = placeholder;
    field.borderStyle = UITextBorderStyleNone;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; field.adjustsFontForContentSizeCategory = YES;
    [field.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    return field;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.connectionProgress = [DirectConnectionProgressState new];
    self.keyFeedback = [[CompanionVNCInterfaceFeedback alloc] initWithView:self.view];
    self.view.backgroundColor = UIColor.systemBackgroundColor; self.foreground = YES;
    self.modifiers = [NSMutableArray new];
    [self prepareConnection];
    __weak CompanionVNCViewer *weak = self;
    self.remoteKeyboard = [[CompanionVNCKeyboard alloc] initWithEvents:^(NSArray<NSDictionary *> *events) {
        if (weak && weak.foreground && !weak.inputInactive && !weak.exited && !weak.checkingResume && !weak.restoreViewportPending) [weak.session keyEvents:events];
    }];
    self.status = [UILabel new]; self.status.text = @"macOS Screen Sharing · over SSH";
    self.status.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1] scaledFontForFont:[UIFont systemFontOfSize:12]];
    self.status.adjustsFontForContentSizeCategory = YES;
    self.status.backgroundColor = UIColor.clearColor;
    self.status.textColor = UIColor.secondaryLabelColor; self.status.numberOfLines = 2;
    self.status.hidden = YES;
    self.statusSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.statusSpinner.hidden = YES;
    self.statusRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.statusSpinner, self.status]];
    self.statusRow.spacing = 8; self.statusRow.alignment = UIStackViewAlignmentCenter;
    self.statusRow.layoutMarginsRelativeArrangement = YES; self.statusRow.layoutMargins = UIEdgeInsetsMake(9,14,9,14);
    self.statusRow.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusBackdrop = [[UIVisualEffectView alloc] initWithEffect:[UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular]];
    self.statusBackdrop.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusBackdrop.hidden = YES; self.statusBackdrop.userInteractionEnabled = NO;
    self.statusBackdrop.layer.cornerRadius = 20; self.statusBackdrop.clipsToBounds = YES;
    self.statusBackdrop.accessibilityIdentifier = @"desktop-resume-indicator";
    [self.statusBackdrop.contentView addSubview:self.statusRow];
    [NSLayoutConstraint activateConstraints:@[
        [self.statusRow.leadingAnchor constraintEqualToAnchor:self.statusBackdrop.contentView.leadingAnchor],
        [self.statusRow.trailingAnchor constraintEqualToAnchor:self.statusBackdrop.contentView.trailingAnchor],
        [self.statusRow.topAnchor constraintEqualToAnchor:self.statusBackdrop.contentView.topAnchor],
        [self.statusRow.bottomAnchor constraintEqualToAnchor:self.statusBackdrop.contentView.bottomAnchor]]];
    self.connect = [self button:@"Connect" action:@selector(connectionAction)];
    self.pan = [self button:@"Pointer" action:@selector(chooseInputMode)];
    self.controls = [CompanionVNCControls new]; self.controls.translatesAutoresizingMaskIntoConstraints = NO;
    self.controls.macName = self.macName ?: @"Mac";
    self.controls.quickActions = self.quickActions ?: [DirectConnectionBridge defaultQuickActionsForInputOnly:self.inputOnly];
    self.controls.actionHandler = ^(NSDictionary *action) { [weak performControlAction:action]; };
    self.controls.customizeHandler = ^{ if (weak.settingsHandler) weak.settingsHandler(); };
    self.controls.openingHandler = ^{
        [weak retirePointerForMenu];
        if (weak.quickActionsProvider) weak.quickActions = weak.quickActionsProvider(weak.inputOnly);
        weak.controls.textCopyAvailable = [weak canCopyScreenText];
        NSMutableArray *snapshot = [NSMutableArray new];
        for (NSDictionary *item in weak.controls.quickActions) {
            NSMutableDictionary *choice = item.mutableCopy;
            NSString *kind = item[@"kind"];
            if ([kind isEqual:@"composeText"] || [kind isEqual:@"rightClick"] || [kind isEqual:@"shortcut"] || [kind isEqual:@"text"]
                || [kind isEqual:@"escape"] || [kind isEqual:@"tab"] || [kind isEqual:@"returnKey"])
                choice[@"disabled"] = @(![weak composedTextAvailable]);
            [snapshot addObject:choice];
        }
        weak.controls.quickActions = snapshot;
    };
    self.views = self.controls.button;
    self.status.translatesAutoresizingMaskIntoConstraints = NO;
    self.canvas = [UIScrollView new]; self.canvas.delegate = self; self.canvas.backgroundColor = UIColor.blackColor;
    self.canvas.translatesAutoresizingMaskIntoConstraints = NO; self.canvas.maximumZoomScale = 5;
    self.canvas.bounces = NO;
    self.canvas.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    if (@available(iOS 26, *)) self.canvas.topEdgeEffect.style = UIScrollEdgeEffectStyle.automaticStyle;
    self.image = [UIImageView new]; self.image.userInteractionEnabled = YES;
    [self.canvas addSubview:self.image]; [self.view addSubview:self.canvas];
    self.cursorOverlay = [UIView new]; self.cursorOverlay.userInteractionEnabled = NO;
    self.cursorOverlay.clipsToBounds = YES; self.cursorOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.cursorOverlay];
    self.cursorIndicator = [UIView new]; self.cursorIndicator.userInteractionEnabled = NO; self.cursorIndicator.hidden = YES;
    [self.cursorOverlay addSubview:self.cursorIndicator];
    self.cursorImage = [UIImageView new]; [self.cursorIndicator addSubview:self.cursorImage];
    self.fallbackCursor = [CAShapeLayer layer];
    UIBezierPath *arrow = [UIBezierPath bezierPath];
    [arrow moveToPoint:CGPointMake(1, 1)]; [arrow addLineToPoint:CGPointMake(1, 23)];
    [arrow addLineToPoint:CGPointMake(7, 18)]; [arrow addLineToPoint:CGPointMake(12, 27)];
    [arrow addLineToPoint:CGPointMake(16, 25)]; [arrow addLineToPoint:CGPointMake(11, 16)];
    [arrow addLineToPoint:CGPointMake(20, 16)]; [arrow closePath];
    self.fallbackCursor.path = arrow.CGPath; self.fallbackCursor.fillColor = UIColor.blackColor.CGColor;
    self.fallbackCursor.strokeColor = UIColor.whiteColor.CGColor; self.fallbackCursor.lineWidth = 1.5;
    [self.cursorIndicator.layer addSublayer:self.fallbackCursor];
    self.click = [[CompanionVNCTapGesture alloc] initWithTarget:self action:@selector(clickAt:)];
    self.drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragAt:)];
    self.drag.maximumNumberOfTouches = 1;
    self.hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(holdAt:)];
    self.hold.minimumPressDuration = .35;
    [self.drag requireGestureRecognizerToFail:self.hold];
    [self.drag requireGestureRecognizerToFail:self.click];
    [self.canvas addGestureRecognizer:self.click]; [self.canvas addGestureRecognizer:self.drag];
    [self.canvas addGestureRecognizer:self.hold];
    self.remoteScroll = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(scrollRemote:)];
    self.remoteScroll.minimumNumberOfTouches = 2; self.remoteScroll.maximumNumberOfTouches = 2;
    self.remoteScroll.enabled = NO;
    [self.canvas addGestureRecognizer:self.remoteScroll];
    self.remotePinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchRemote:)];
    self.remotePinch.enabled = self.inputOnly;
    [self.canvas addGestureRecognizer:self.remotePinch];
    self.smartTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(smartZoom:)];
    self.smartTap.numberOfTapsRequired = 2; self.smartTap.numberOfTouchesRequired = 2;
    self.smartTap.enabled = !self.inputOnly;
    [self.canvas addGestureRecognizer:self.smartTap];
    self.secondaryTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(secondaryClickAt:)];
    self.secondaryTap.numberOfTouchesRequired = 2;
    // Preserve Desktop's existing double-tap zoom. Input-only has no image
    // zoom, so its secondary tap need not wait for another tap.
    self.secondaryTap.delegate = self;
    [self.canvas addGestureRecognizer:self.secondaryTap];
    self.canvas.panGestureRecognizer.minimumNumberOfTouches = 2;
    self.host = [self field:@"Paired Mac"]; self.host.hidden = YES;
    self.host.keyboardType = UIKeyboardTypeASCIICapable;
    self.username = [self field:@"Username"]; self.username.accessibilityLabel = @"Username";
    self.password = [self field:@"Password"]; self.password.accessibilityLabel = @"Password"; self.password.secureTextEntry = YES;
    self.password.textContentType = DirectConnectionBridge.remoteCredentialContentType;
    self.username.textContentType = DirectConnectionBridge.remoteCredentialContentType;
    self.username.accessibilityIdentifier = @"mac-login-username";
    self.password.accessibilityIdentifier = @"mac-login-password";
    UIButton *visibility = [self button:@"" action:@selector(togglePassword)];
    [visibility setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20] forImageInState:UIControlStateNormal];
    [visibility setImage:[UIImage systemImageNamed:@"eye"] forState:UIControlStateNormal]; visibility.accessibilityLabel = @"Show Password";
    [visibility.widthAnchor constraintEqualToConstant:44].active = YES;
    visibility.accessibilityIdentifier = @"mac-login-visibility"; self.passwordVisibility = visibility;
    visibility.backgroundColor = UIColor.clearColor; visibility.tintColor = UIColor.secondaryLabelColor;
    self.remember = [UISwitch new];
    UILabel *rememberLabel = [UILabel new]; rememberLabel.text = @"Save Login";
    UIStackView *saveRow = [[UIStackView alloc] initWithArrangedSubviews:@[rememberLabel, self.remember]];
    saveRow.alignment = UIStackViewAlignmentCenter; self.saveLoginRow = saveRow;
    rememberLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    UIView *usernameInput = [DirectConnectionBridge credentialInputForField:self.username title:@"Username"];
    UIView *passwordInput = [DirectConnectionBridge credentialInputForField:self.password title:@"Password"];
    UIStackView *account = [[UIStackView alloc] initWithArrangedSubviews:@[usernameInput]];
    account.axis = UILayoutConstraintAxisHorizontal; account.alignment = UIStackViewAlignmentCenter;
    account.layoutMarginsRelativeArrangement = YES; account.layoutMargins = UIEdgeInsetsMake(4,14,4,14); account.backgroundColor = DirectConnectionBridge.fieldColor;
    UIStackView *passwordRow = [[UIStackView alloc] initWithArrangedSubviews:@[passwordInput, visibility]]; passwordRow.spacing = 4;
    UIStackView *password = [[UIStackView alloc] initWithArrangedSubviews:@[passwordRow]];
    password.axis = UILayoutConstraintAxisHorizontal; password.alignment = UIStackViewAlignmentCenter;
    password.layoutMarginsRelativeArrangement = YES; password.layoutMargins = UIEdgeInsetsMake(4,14,4,14); password.backgroundColor = DirectConnectionBridge.fieldColor;
    [usernameInput setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [passwordInput setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIView *separatorRow = [UIView new], *separator = [UIView new]; separator.backgroundColor = UIColor.separatorColor;
    separator.translatesAutoresizingMaskIntoConstraints = NO; [separatorRow addSubview:separator];
    [NSLayoutConstraint activateConstraints:@[[separatorRow.heightAnchor constraintEqualToConstant:1.0 / MAX(1, self.traitCollection.displayScale)],
        [separator.leadingAnchor constraintEqualToAnchor:separatorRow.leadingAnchor constant:14], [separator.trailingAnchor constraintEqualToAnchor:separatorRow.trailingAnchor],
        [separator.topAnchor constraintEqualToAnchor:separatorRow.topAnchor], [separator.bottomAnchor constraintEqualToAnchor:separatorRow.bottomAnchor]]];
    self.credentialColumns = [[UIStackView alloc] initWithArrangedSubviews:@[account, separatorRow, password]];
    self.credentialColumns.axis = UILayoutConstraintAxisVertical; self.credentialColumns.spacing = 0;
    self.credentialColumns.backgroundColor = DirectConnectionBridge.fieldColor; self.credentialColumns.layer.cornerRadius = 12; self.credentialColumns.clipsToBounds = YES;
    UIButton *cancel = [self button:@"Cancel" action:@selector(showMacs)]; cancel.accessibilityIdentifier = @"mac-login-cancel";
    self.loginCancel = cancel; cancel.backgroundColor = UIColor.clearColor; cancel.tintColor = UIColor.systemBlueColor;
    UIButtonConfiguration *cancelStyle = UIButtonConfiguration.plainButtonConfiguration;
    cancelStyle.title = @"Cancel"; cancelStyle.baseForegroundColor = UIColor.systemBlueColor;
    cancelStyle.background.cornerRadius = 16;
    cancelStyle.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
        NSMutableDictionary *result = [attributes mutableCopy];
        result[NSFontAttributeName] = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]; return result;
    };
    cancel.configuration = cancelStyle;
    [cancel.heightAnchor constraintGreaterThanOrEqualToConstant:48].active = YES;
    self.connect.backgroundColor = UIColor.systemBlueColor; [self.connect setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.connect.layer.cornerRadius = 16; self.connect.accessibilityIdentifier = @"mac-login-connect";
    self.loginTrackpad = [self button:@"Use Trackpad & Keyboard" action:@selector(useInputOnlyConnection)];
    self.loginTrackpad.backgroundColor = UIColor.clearColor; self.loginTrackpad.tintColor = UIColor.systemBlueColor;
    self.loginTrackpad.accessibilityIdentifier = @"connection-inputOnly";
    self.loginTrackpad.titleLabel.numberOfLines = 0; self.loginTrackpad.titleLabel.textAlignment = NSTextAlignmentCenter;
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[self.connect, self.loginTrackpad, cancel]];
    self.loginActions = actions;
    actions.axis = UILayoutConstraintAxisVertical; actions.spacing = 0;
    self.loginFields = [[UIStackView alloc] initWithArrangedSubviews:@[self.credentialColumns, saveRow]];
    self.loginFields.axis = UILayoutConstraintAxisVertical; self.loginFields.spacing = 14;
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"desktopcomputer"]];
    icon.contentMode = UIViewContentModeScaleAspectFit; icon.tintColor = UIColor.systemBlueColor;
    self.loginIcon = icon;
    UIView *tile = [UIView new]; tile.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:.10]; tile.layer.cornerRadius = 16;
    icon.translatesAutoresizingMaskIntoConstraints = NO; [tile addSubview:icon];
    [NSLayoutConstraint activateConstraints:@[[icon.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor], [icon.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor], [icon.widthAnchor constraintEqualToConstant:28], [icon.heightAnchor constraintEqualToConstant:28]]];
    self.loginIconHeight = [tile.heightAnchor constraintEqualToConstant:52]; self.loginIconHeight.active = YES;
    self.loginIconWidth = [tile.widthAnchor constraintEqualToConstant:52]; self.loginIconWidth.active = YES;
    UILabel *title = [UILabel new]; title.text = self.macName ?: @"Mac"; title.numberOfLines = 2;
    title.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleTitle3] scaledFontForFont:[UIFont systemFontOfSize:20 weight:UIFontWeightSemibold]]; title.textAlignment = NSTextAlignmentLeft;
    UILabel *subtitle = [UILabel new]; subtitle.text = @"Screen Sharing"; subtitle.textColor = UIColor.secondaryLabelColor; subtitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    subtitle.numberOfLines = 0; subtitle.accessibilityHint = @"View and control this Mac"; self.loginSubtitle = subtitle;
    UIStackView *identityText = [[UIStackView alloc] initWithArrangedSubviews:@[title, subtitle]]; identityText.axis = UILayoutConstraintAxisVertical; identityText.spacing = 4;
    self.loginClose = [self button:@"" action:@selector(showMacs)]; [self.loginClose setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    [self.loginClose setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium] forImageInState:UIControlStateNormal];
    self.loginClose.accessibilityLabel = @"Cancel connection"; self.loginClose.accessibilityIdentifier = @"mac-login-close"; self.loginClose.tintColor = UIColor.secondaryLabelColor;
    self.loginClose.layer.cornerRadius = 22; [self.loginClose.widthAnchor constraintEqualToConstant:44].active = YES;
    self.loginIdentity = [[UIStackView alloc] initWithArrangedSubviews:@[tile, identityText]]; self.loginIdentity.axis = UILayoutConstraintAxisHorizontal; self.loginIdentity.spacing = 12; self.loginIdentity.alignment = UIStackViewAlignmentCenter;
    self.loginPurpose = [UILabel new]; self.loginPurpose.text = @"Use your Mac account to connect.";
    self.loginPurpose.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; self.loginPurpose.textColor = UIColor.secondaryLabelColor; self.loginPurpose.numberOfLines = 0;
    self.loginIntro = [[UIStackView alloc] initWithArrangedSubviews:@[self.loginIdentity, self.loginPurpose]];
    self.loginIntro.axis = UILayoutConstraintAxisVertical; self.loginIntro.spacing = 16;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.progressLabel = [UILabel new]; self.progressLabel.numberOfLines = 0;
    self.progressLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]; self.progressLabel.textAlignment = NSTextAlignmentCenter;
    self.progressRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.spinner, self.progressLabel]];
    self.progressRow.axis = UILayoutConstraintAxisVertical; self.progressRow.alignment = UIStackViewAlignmentCenter; self.progressRow.spacing = 16;
    self.progressRow.layoutMarginsRelativeArrangement = YES; self.progressRow.layoutMargins = UIEdgeInsetsMake(24,0,24,0);
    self.loginDetails = [self button:@"Connection Details" action:@selector(showLoginDetails)];
    self.loginDetails.accessibilityIdentifier = @"mac-login-details";
    self.loginDetails.backgroundColor = UIColor.clearColor; self.loginDetails.tintColor = UIColor.secondaryLabelColor; self.loginDetails.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    [self.loginDetails setImage:[UIImage systemImageNamed:@"chevron.down"] forState:UIControlStateNormal];
    self.loginDetailsText = [UILabel new]; self.loginDetailsText.numberOfLines = 0;
    self.loginDetailsText.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.loginDetailsText.adjustsFontForContentSizeCategory = YES;
    self.loginDetailsText.textColor = UIColor.secondaryLabelColor; self.loginDetailsText.hidden = YES;
    self.login = [[UIStackView alloc] initWithArrangedSubviews:@[self.loginIntro, self.progressRow, self.loginFields, actions, self.loginDetails, self.loginDetailsText]];
    self.login.axis = UILayoutConstraintAxisVertical; self.login.spacing = 18;
    self.login.layoutMargins = UIEdgeInsetsMake(22, 22, 22, 22); self.login.layoutMarginsRelativeArrangement = YES;
    if (!self.connectionPanelHost) [DirectConnectionBridge styleCard:self.login];
    [self registerForTraitChanges:@[UITraitUserInterfaceStyle.class, UITraitUserInterfaceLevel.class, UITraitAccessibilityContrast.class]
                     withHandler:^(id<UITraitEnvironment> environment, UITraitCollection *previous) { if (!weak.connectionPanelHost) [DirectConnectionBridge styleCard:weak.login]; }];
    self.login.translatesAutoresizingMaskIntoConstraints = NO;
    self.loginScroll = [UIScrollView new]; self.loginScroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.loginScroll.backgroundColor = UIColor.clearColor; self.loginScroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive; self.loginScroll.accessibilityIdentifier = @"mac-login-scroll";
    [self.loginScroll addSubview:self.login]; [self.view addSubview:self.loginScroll];
    self.loginBackdrop = [DirectConnectionBridge backgroundWithNames:self.connectionMacNames ?: @[self.macName ?: @"Mac"]];
    [self addChildViewController:self.loginBackdrop]; self.loginBackdrop.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view insertSubview:self.loginBackdrop.view belowSubview:self.loginScroll];
    [NSLayoutConstraint activateConstraints:@[[self.loginBackdrop.view.topAnchor constraintEqualToAnchor:self.view.topAnchor], [self.loginBackdrop.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor], [self.loginBackdrop.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.loginBackdrop.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]];
    [self.loginBackdrop didMoveToParentViewController:self];
    [self.username addTarget:self action:@selector(loginEdited) forControlEvents:UIControlEventEditingChanged];
    [self.password addTarget:self action:@selector(loginEdited) forControlEvents:UIControlEventEditingChanged];
    NSMutableArray *keys = [NSMutableArray new];
    self.keyboardButton = [self button:@"" action:@selector(keyboard)];
    self.keyboardButton.accessibilityIdentifier = @"remote-keyboard-toggle";
    [keys addObject:self.keyboardButton]; [self updateKeyboardButton];
    NSArray *titles = @[@"esc", @"⇥", @"⇧", @"⌃", @"⌥", @"⌘"];
    NSArray *symbols = @[@(0xff1b), @(0xff09), @(0xffe1), @(0xffe3), @(0xffe9), @(0xffeb), @0];
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *key = [self button:titles[i] action:i == 6 ? @selector(moreKeys:) : @selector(remoteKey:)];
        key.tag = [symbols[i] integerValue]; [keys addObject:key];
        [key addTarget:self action:@selector(prepareKeyFeedback) forControlEvents:UIControlEventTouchDown];
        if (i >= 2 && i <= 5) {
            [self.modifiers addObject:key];
            key.accessibilityLabel = @[@"Shift", @"Control", @"Option", @"Command"][i - 2];
            key.accessibilityHint = @"Tap to apply to the next key. Hold to send this modifier alone.";
            [key addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(singleModifier:)]];
        }
    }
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:keys];
    row.spacing = 4; row.distribution = UIStackViewDistributionFillEqually;
    self.keyRow = row; row.translatesAutoresizingMaskIntoConstraints = NO;
    UIScrollView *toolbar = [UIScrollView new]; self.toolbar = toolbar;
    toolbar.showsHorizontalScrollIndicator = NO; toolbar.alwaysBounceHorizontal = NO;
    toolbar.translatesAutoresizingMaskIntoConstraints = NO; [toolbar addSubview:row]; [self.view addSubview:toolbar];
    NSLayoutConstraint *fill = [row.widthAnchor constraintEqualToAnchor:toolbar.frameLayoutGuide.widthAnchor]; fill.priority = 750;
    self.loginTop = [self.loginScroll.topAnchor constraintEqualToAnchor:self.view.topAnchor];
    self.loginBottom = [self.loginScroll.bottomAnchor constraintEqualToAnchor:self.view.topAnchor];
    self.loginMaxWidth = [self.login.widthAnchor constraintLessThanOrEqualToConstant:440];
    self.loginContentTop = [self.login.topAnchor constraintEqualToAnchor:self.loginScroll.contentLayoutGuide.topAnchor constant:12];
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:toolbar.contentLayoutGuide.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:toolbar.contentLayoutGuide.trailingAnchor],
        [row.topAnchor constraintEqualToAnchor:toolbar.contentLayoutGuide.topAnchor],
        [row.bottomAnchor constraintEqualToAnchor:toolbar.contentLayoutGuide.bottomAnchor],
        [row.heightAnchor constraintEqualToAnchor:toolbar.frameLayoutGuide.heightAnchor],
        [row.widthAnchor constraintGreaterThanOrEqualToConstant:332], fill,
        [toolbar.heightAnchor constraintEqualToAnchor:row.heightAnchor]]];
    self.toolbarBottom = [toolbar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-4];
    [self.view addSubview:self.statusBackdrop]; [self.view addSubview:self.controls];
    self.canvasToolbarBottom = [self.canvas.bottomAnchor constraintEqualToAnchor:toolbar.topAnchor constant:-8];
    self.canvasFullscreenBottom = [self.canvas.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor];
    self.tabletopCanvasBottom = [self.canvas.bottomAnchor constraintEqualToAnchor:self.view.topAnchor];
    self.canvasTop = [self.canvas.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:8];
    [NSLayoutConstraint activateConstraints:@[
        [self.statusBackdrop.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.statusBackdrop.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.statusBackdrop.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
        [self.statusBackdrop.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [toolbar.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:6],
        [toolbar.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-68], self.toolbarBottom,
        self.canvasTop,
        self.canvasToolbarBottom,
        [self.canvas.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [self.canvas.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [self.cursorOverlay.leadingAnchor constraintEqualToAnchor:self.canvas.leadingAnchor],
        [self.cursorOverlay.trailingAnchor constraintEqualToAnchor:self.canvas.trailingAnchor],
        [self.cursorOverlay.topAnchor constraintEqualToAnchor:self.canvas.topAnchor],
        [self.cursorOverlay.bottomAnchor constraintEqualToAnchor:self.canvas.bottomAnchor],
        [self.controls.topAnchor constraintEqualToAnchor:self.view.topAnchor], [self.controls.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.controls.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.controls.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.loginTop, self.loginBottom,
        [self.loginScroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor], [self.loginScroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        self.loginContentTop,
        [self.login.bottomAnchor constraintEqualToAnchor:self.loginScroll.contentLayoutGuide.bottomAnchor constant:self.connectionPanelHost ? -4 : -12],
        [self.login.centerXAnchor constraintEqualToAnchor:self.loginScroll.centerXAnchor],
        self.loginMaxWidth,
        [self.login.widthAnchor constraintLessThanOrEqualToAnchor:self.loginScroll.frameLayoutGuide.widthAnchor constant:-32]
    ]];
    NSLayoutConstraint *cardWidth = [self.login.widthAnchor constraintEqualToAnchor:self.loginScroll.frameLayoutGuide.widthAnchor constant:-32]; cardWidth.priority = 750; cardWidth.active = YES;
    if (self.connectionPanelHost) {
        self.loginPanelOwner = [NSObject new]; self.loginPanelContent = [UIViewController new];
        self.loginPanelContent.view.backgroundColor = UIColor.clearColor;
        NSMutableArray *outer = [NSMutableArray array];
        for (NSLayoutConstraint *constraint in self.view.constraints) {
            if (constraint.firstItem == self.loginScroll || constraint.secondItem == self.loginScroll) [outer addObject:constraint];
        }
        [NSLayoutConstraint deactivateConstraints:outer];
        [self.loginScroll removeFromSuperview]; [self.loginPanelContent.view addSubview:self.loginScroll];
        [self.login removeArrangedSubview:actions]; [actions removeFromSuperview];
        actions.translatesAutoresizingMaskIntoConstraints = NO;
        actions.layoutMarginsRelativeArrangement = YES; actions.layoutMargins = UIEdgeInsetsMake(8,8,8,8);
        [self.loginPanelContent.view addSubview:actions];
        [NSLayoutConstraint activateConstraints:@[
            [self.loginScroll.leadingAnchor constraintEqualToAnchor:self.loginPanelContent.view.leadingAnchor],
            [self.loginScroll.trailingAnchor constraintEqualToAnchor:self.loginPanelContent.view.trailingAnchor],
            [self.loginScroll.topAnchor constraintEqualToAnchor:self.loginPanelContent.view.safeAreaLayoutGuide.topAnchor],
            [self.loginScroll.bottomAnchor constraintEqualToAnchor:actions.topAnchor],
            [actions.bottomAnchor constraintEqualToAnchor:self.loginPanelContent.view.keyboardLayoutGuide.topAnchor],
            [actions.centerXAnchor constraintEqualToAnchor:self.loginPanelContent.view.centerXAnchor],
            [actions.widthAnchor constraintEqualToAnchor:self.login.widthAnchor]
        ]];
        self.login.backgroundColor = UIColor.clearColor; self.login.layer.borderWidth = 0; self.login.layer.shadowOpacity = 0;
        self.loginBackdrop.view.hidden = YES;
        self.saveLoginRow.hidden = self.preventsLoginRetention;
    }
    self.input = [[CompanionRemoteTextInput alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
    self.input.alpha = 0.02; self.input.delegate = self;
    self.input.accessibilityLabel = @"Remote keyboard input";
    self.input.autocorrectionType = UITextAutocorrectionTypeNo;
    self.input.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.input.smartQuotesType = UITextSmartQuotesTypeNo; self.input.smartDashesType = UITextSmartDashesTypeNo;
    self.input.remoteDelete = ^{ [weak sendRemoteKey:0xff08]; };
    [self.view addSubview:self.input];
    [self prepareTabletopPad];
    [self prepareTrackpadFeedback];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100
    if (@available(iOS 27.1, *)) {
        [self.view addInteraction:[[UIHingeInteraction alloc] initWithUpdateHandler:^(UIHingeInteraction *interaction, UIHingeInteractionUpdate *update) {
            [weak.view setNeedsLayout]; // Query reserved regions when they change; never infer layout from angle.
        }]];
    }
#endif
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(keyboardFrame:) name:UIKeyboardWillChangeFrameNotification object:nil];
    self.displayViews = self.displayLayout[@"views"] ?: @[];
    self.displayAspect = [self.displayLayout[@"aspectRatio"] doubleValue];
    self.credentialState = [[DirectDesktopLoginState alloc] initWithMacID:self.preferenceID username:self.savedUsername ?: @"" password:self.savedPassword ?: @""];
    [self renderCredentialForm];
    [self.remember addTarget:self action:@selector(loginEdited) forControlEvents:UIControlEventValueChanged];
    self.savedPassword = nil;
    [self refreshAccessEditing];
    self.trackpadHelp = [UILabel new]; self.trackpadHelp.text = @"Trackpad & Keyboard\nSlide to move · Tap to click\nHold to drag · Two fingers to scroll\nTwo-finger tap to right-click";
    self.trackpadHelp.numberOfLines = 0; self.trackpadHelp.textAlignment = NSTextAlignmentCenter;
    self.trackpadHelp.textColor = UIColor.secondaryLabelColor; self.trackpadHelp.userInteractionEnabled = NO;
    self.trackpadHelp.translatesAutoresizingMaskIntoConstraints = NO; [self.view insertSubview:self.trackpadHelp aboveSubview:self.canvas];
    [NSLayoutConstraint activateConstraints:@[[self.trackpadHelp.centerXAnchor constraintEqualToAnchor:self.canvas.centerXAnchor], [self.trackpadHelp.centerYAnchor constraintEqualToAnchor:self.canvas.centerYAnchor], [self.trackpadHelp.widthAnchor constraintLessThanOrEqualToAnchor:self.canvas.widthAnchor constant:-32]]];
    for (UILabel *label in @[title, subtitle, rememberLabel, self.progressLabel]) {
        label.adjustsFontForContentSizeCategory = YES; label.numberOfLines = 0;
        if (!label.font || label.font.pointSize == 17) label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    }
    [self applyPresentation];
    [self setTrackpadModeEnabled:self.preferredTrackpad || self.inputOnly]; [self updateConnectionChrome];
    if (self.password.text.length) dispatch_async(dispatch_get_main_queue(), ^{ [weak start]; });
}
- (NSString *)connectionProgressMessage {
    if (self.changingDisplayMode && self.mirrorFullRestartUsed) return @"Switching display mode…";
    return self.inputOnly ? @"Connecting to Trackpad & Keyboard…" : @"Connecting to Screen Sharing…";
}
- (NSTimeInterval)mirrorRetirementDelay { return self.changingDisplayMode && self.mirrorRequiresCleanup ? 16 : 0; }
- (BOOL)connectionForegroundAvailable { return self.foreground && !self.inputInactive && !self.exited; }
- (void)showMirrorCleanupRemaining:(NSUInteger)seconds {
    if (!self.changingDisplayMode || !self.starting || !self.connectionForegroundAvailable) return;
    self.mirrorCleanupRemaining = seconds; self.statusGeneration++;
    NSString *message = @"Switching display mode…";
    self.progressLabel.text = message; self.status.text = message; self.status.hidden = NO;
    [self updateConnectionChrome]; [self reportDiagnostics:self.latestCounters];
}
- (void)finishMirrorCleanup {
    self.mirrorRequiresCleanup = NO; self.mirrorCleanupRemaining = 0;
    [self.connectionProgress finishedRestoringDisplays];
    [self showConnectionProgress:@"Switching display mode…"];
}
- (void)prepareConnection {
    [self retireSessionMenu];
    self.mirrorRestartScheduled = NO;
    if (self.changingDisplayMode) self.mirrorRestoreAttempts++;
    self.desktopSizeRestored = self.changingDisplayMode || self.inputOnly; self.pendingDesktopSizePreset = 0; self.pendingStreamDisplayID = nil;
    self.lateDesktopSizePreset = 0; self.modeResizeRequested = NO; self.modeVerificationTimed = NO; self.modeVerificationGeneration++;
    self.displaySelectionRejections = self.displaySelectionRejectMask = 0;
    self.initialDisplayApplied = NO; self.restoringStreamViewport = NO;
    self.deferredTextReviewFailure = nil;
    self.diagnosticGeneration++; self.diagnosticScheduled = NO; self.diagnosticFlags = nil;
    [self retireTextDraft];
    [self invalidateTextReview:NO]; self.textReviewViewportPending=NO;
    self.session = [CompanionVNCSession new];
    self.session.inputOnly = self.inputOnly;
    if (self.inputOnly) [self discardInputOnlyPresentation];
    self.session.displayHandoffInputBlocked = self.changingDisplayMode;
    [self clearCursor];
    self.latestCounters = @{};
    __weak CompanionVNCViewer *weak = self;
    __weak CompanionVNCSession *owner = self.session;
    self.session.frameHandler = ^(UIImage *image) { if (weak.session == owner) [weak frame:image]; };
    self.session.cursorHandler = ^(UIImage *image, CGPoint hotspot, CGPoint position, BOOL known) {
        if (weak.session == owner) [weak receivedCursor:image hotspot:hotspot position:position known:known];
    };
    self.session.displayLayoutHandler = ^(NSDictionary *layout) { if (weak.session == owner) weak.displayLayout = layout; };
    if (!self.inputOnly && (self.reconnectWhenReady || self.checkingResume)) self.restoreViewportPending = YES;
    self.awaitingReplacementLayout = self.restoreViewportPending && self.lastFramebuffer != nil && self.resumeDisplayID != nil;
    self.pendingRestorationFrame = nil;
    if (!self.awaitingReplacementLayout) self.displayLayout = nil;
    if (self.awaitingReplacementLayout) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 9000 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            if (weak.session == owner && weak.foreground && !weak.exited && weak.restoreViewportPending) {
                [owner stop]; if (weak.disconnectHandler) weak.disconnectHandler();
                [weak showConnectionFailureStage:102];
            }
        });
    }
    self.session.stateHandler = ^(NSString *state, NSDictionary *stats) {
        CompanionVNCViewer *strong = weak; if (!strong || strong.session != owner) return;
        strong.latestCounters = stats;
        if (strong.exited || strong.failedDisplayModePreset) return;
        if (!strong.session.running) [strong retireSessionMenu];
        [strong.connectionProgress recordNativeState:state];
        if (strong.changingDisplayMode && strong.foreground && !strong.inputInactive) [strong updateDisplayModeRestoration];
        if (strong.mirrorRestartScheduled || strong.failedDisplayModePreset) { [strong reportDiagnostics:stats]; return; }
        if (strong.changingDisplayMode) {
            if (!strong.session.running) {
                NSInteger failure = [stats[@"failureStage"] integerValue];
                if (strong.modeTargetPreset > 0 && failure == 102) failure = 117;
                [strong retireDisplayModeOwner]; [strong showConnectionFailureStage:failure];
            } else {
                strong.status.text = @"Switching display mode…"; strong.status.hidden = NO;
                [strong updateConnectionChrome];
            }
            [strong reportDiagnostics:stats]; return;
        }
        if (strong.inputOnly && strong.session.established) [strong updateInputOnlyGeometry];
        BOOL running = strong.session.running, connected = [state isEqualToString:@"Connected"] && strong.session.connected
            && (strong.inputOnly || (strong.lastFramebuffer != nil && !strong.restoreViewportPending)) && !strong.changingDisplayMode;
        if (!running && ![state isEqualToString:@"Disconnected"] && [stats[@"handshakeStage"] integerValue] >= 5) {
            // Session counters contain only bounded numeric aggregates/geometry.
            // Keep one failure across replacement owners, before teardown clears it.
            NSMutableDictionary *failure = [stats mutableCopy];
            [failure addEntriesFromDictionary:strong.session.diagnosticCounters ?: @{}];
            strong.lastConnectionFailure = [failure copy];
        }
        if (!running && strong.textReview) {
            [strong retireTextDraft];
            if (strong.disconnectHandler) strong.disconnectHandler();
            [strong showConnectionFailureStage:[stats[@"failureStage"] integerValue]];
            [strong reportDiagnostics:stats]; return;
        }
        if (!strong.foreground) {
            strong.status.text = @"Paused · Return to resume";
            if (!running) { if (strong.sessionPhaseHandler) strong.sessionPhaseHandler(@"ended"); if (strong.disconnectHandler) strong.disconnectHandler(); }
            [strong reportDiagnostics:stats];
            return;
        }
        BOOL displayNotice = NSProcessInfo.processInfo.systemUptime < strong.displayNoticeUntil;
        if (!displayNotice) strong.status.text = connected ? @"" : [strong connectionProgressMessage];
        if (connected && !displayNotice) strong.status.hidden = YES;
        strong.progressLabel.text = connected ? @"" : [strong connectionProgressMessage];
        if (connected) {
            strong.session.inputOnly = strong.inputOnly;
            if (strong.textSendInterrupted) [strong showTextSendWarning];
            else if (!strong.macSaveFailureVisible) { [strong clearRecovery]; strong.image.alpha = 1; }
            [strong completeResumeReadiness];
            [strong updateCursor];
            if (strong.sessionPhaseHandler) strong.sessionPhaseHandler(@"connected");
            if (strong.connectedHandler) strong.connectedHandler();
            [strong.credentialState authenticated]; [strong renderCredentialForm];
        }
        if (connected || !running) { strong.connect.enabled = YES; strong.starting = NO; }
        strong.login.hidden = connected || (running && strong.login.hidden);
        [strong.connect setTitle:@"Connect" forState:UIControlStateNormal];
        UIApplication.sharedApplication.idleTimerDisabled = running;
        if (!running) {
            [strong invalidateTextReview:NO];
            [strong retireTextDraft];
            [strong clearCursor]; [strong resetModifiers];
            if (strong.disconnectHandler) strong.disconnectHandler();
            if (strong.checkingResume) [strong reconnectAfterFailedResume];
            else { [strong finishCredentialSession]; [strong showRecoveryStage:[stats[@"failureStage"] integerValue]]; if (strong.sessionPhaseHandler) strong.sessionPhaseHandler(@"ended"); }
        }
        [strong updateConnectionChrome];
        [strong updateDesktopSizeState];
        [strong reportDiagnostics:stats];
    };
}
- (void)completeResumeReadiness {
    self.checkingResume = NO; self.reconnectWhenReady = NO;
    self.resumeGeneration++; self.statusGeneration++;
    if (!self.inputOnly) [self restoreSavedDisplay];
}
- (void)reportDiagnostics:(NSDictionary *)stats {
    if (!self.diagnosticHandler) return;
    NSMutableDictionary *diagnostics = [stats mutableCopy] ?: [NSMutableDictionary new];
    [diagnostics addEntriesFromDictionary:self.session.diagnosticCounters ?: @{}];
    diagnostics[@"cursorPresentation"] = [self cursorDiagnosticFlags];
    diagnostics[@"mirrorHandoff"] = @{@"attempts":@(self.mirrorRestoreAttempts), @"outcome":@(self.mirrorRestoreOutcome),
        @"awaitingPhysical":@(self.changingDisplayMode), @"retryScheduled":@(self.mirrorRestartScheduled),
        @"fullRestartUsed":@(self.mirrorFullRestartUsed), @"cleanupRequired":@(self.mirrorRequiresCleanup),
        @"cleanupRemainingSeconds":@(self.mirrorCleanupRemaining), @"observedVirtual":self.mirrorObservedLayouts ?: @[],
        @"targetPreset":@(self.modeTargetPreset), @"recoveryAttempts":@(self.modeRecoveryAttempts), @"resizeRequested":@(self.modeResizeRequested)};
    if (self.lastConnectionFailure) diagnostics[@"lastConnectionFailure"] = self.lastConnectionFailure;
    diagnostics[@"diagnosticWrites"] = @(++self.diagnosticWrites);
    diagnostics[@"viewer"] = @{@"canvasWidth": @(self.canvas.bounds.size.width), @"canvasHeight": @(self.canvas.bounds.size.height),
        @"imageWidth": @(self.image.bounds.size.width), @"imageHeight": @(self.image.bounds.size.height),
        @"imageFrameX": @(self.image.frame.origin.x), @"imageFrameY": @(self.image.frame.origin.y),
        @"imageFrameWidth": @(self.image.frame.size.width), @"imageFrameHeight": @(self.image.frame.size.height),
        @"zoom": @(self.canvas.zoomScale), @"minimumZoom": @(self.canvas.minimumZoomScale),
        @"offsetX": @(self.canvas.contentOffset.x), @"offsetY": @(self.canvas.contentOffset.y),
        @"canvasHidden": @(self.canvas.hidden), @"imageHidden": @(self.image.hidden), @"hasImage": @(self.image.image != nil)};
    self.diagnosticHandler(diagnostics);
}
- (void)renderCredentialForm {
    self.username.text = self.credentialState.username;
    self.password.text = self.credentialState.password;
    [DirectConnectionBridge refreshCredentialInputForField:self.username];
    [DirectConnectionBridge refreshCredentialInputForField:self.password];
    self.remember.on = !self.preventsLoginRetention && self.credentialState.remember;
}
- (void)finishCredentialSession {
    [self.credentialState endedWithActive:self.foreground allowed:self.credentialState.accessAllowed];
    [self renderCredentialForm];
}
- (void)start { [self startResuming:NO]; }
- (void)startResuming:(BOOL)resuming {
    NSDictionary *login;
    if (resuming) login = [self.credentialState loginForResume];
    else {
        [self.credentialState editWithUsername:self.username.text ?: @"" password:self.password.text ?: @"" remember:self.remember.on];
        login = [self.credentialState beginLogin];
    }
    if (!login || ![login[@"username"] length] || ![login[@"password"] length]) {
        [self finishCredentialSession]; self.login.hidden = NO; self.starting = NO; [self updateConnectionChrome]; return;
    }
    if (!resuming) {
        self.changingDisplayMode = !self.inputOnly;
        self.modeTargetPreset = self.modePreviousPreset = self.restoredDesktopSizePreset;
        self.modeRecoveryAttempts = 0; self.modeResizeRequested = NO; self.failedDisplayModePreset = nil;
        self.mirrorRestoreAttempts = 0; self.mirrorRestoreOutcome = 0; self.mirrorRestartScheduled = NO;
        self.mirrorRequiresCleanup = self.mirrorFullRestartUsed = NO; self.mirrorCleanupRemaining = 0;
        self.mirrorObservedLayouts = [NSMutableArray new];
    }
    [self invalidateTextReview:NO]; self.textReviewViewportPending=NO; self.deferredTextReviewFailure=nil;
    [self retireTextDraft];
    [self clearRecovery];
    if (!self.inputOnly && self.lastFramebuffer) { [self rememberViewport]; self.restoreViewportPending = YES; self.image.alpha = .45; }
    if (self.inputOnly) { self.restoreViewportPending = self.awaitingReplacementLayout = NO; self.pendingRestorationFrame = nil; }
    self.starting = YES; self.exited = NO;
    [self.connectionProgress beginWaitingForDisplays:self.mirrorRetirementDelay > 0];
    if (self.lastFramebuffer) [self scheduleResumeIndicator:self.changingDisplayMode && self.mirrorFullRestartUsed ? @"Switching display mode…" : @"Reconnecting…"];
    if (self.sessionPhaseHandler) self.sessionPhaseHandler(@"reconnecting");
    [self.view endEditing:YES]; [self.loginScroll endEditing:YES]; self.status.text = [self connectionProgressMessage];
    self.connect.enabled = NO; self.progressLabel.text = @"Contacting Mac…"; self.status.hidden = YES; [self updateConnectionChrome];
    if (self.connectHandler) self.connectHandler(login[@"username"], login[@"password"], self.credentialState.remember);
}
- (void)connectionAction {
    if (!self.session.running && !self.starting) {
        if (self.failedDisplayModePreset) [self restartDisplayModePreset:self.failedDisplayModePreset.integerValue];
        else [self start];
    }
}
- (void)showLoginDetails {
    [self.loginPanelContent.view layoutIfNeeded]; [self.view layoutIfNeeded];
    void (^update)(void) = ^{
        self.loginDetailsExpanded = !self.loginDetailsExpanded;
        [self updateConnectionChrome];
        [self.loginPanelContent.view layoutIfNeeded]; [self.view layoutIfNeeded];
    };
    if (UIAccessibilityIsReduceMotionEnabled()) update();
    else [UIView animateWithDuration:.22 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseInOut animations:update completion:nil];
}
- (NSString *)configuredConnectionDetails {
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    [self.connectionAddresses enumerateObjectsUsingBlock:^(NSString *address, NSUInteger index, BOOL *stop) {
        [lines addObject:[NSString stringWithFormat:index == 0 ? @"Address: %@" : @"Fallback: %@", address]];
    }];
    [lines addObject:[NSString stringWithFormat:@"Remote Login · SSH: %ld", (long)self.sshPort]];
    [lines addObject:[NSString stringWithFormat:@"Screen Sharing: %ld", (long)self.servicePort]];
    [lines addObject:@"Server identity is verified before login."];
    return [lines componentsJoinedByString:@"\n"];
}
- (void)loginEdited { [self.credentialState discardSessionRecovery]; [self.credentialState editWithUsername:self.username.text ?: @"" password:self.password.text ?: @"" remember:self.remember.on]; [self clearRecovery]; self.progressLabel.text = @""; [self updateConnectionChrome]; }
- (void)showMacs {
    if (self.requestExitHandler && self.requestExitHandler()) return;
    if (self.session.connected) CompanionVNCPlayInterfaceFeedback(@"end");
    [self stopViewer]; if (self.macsHandler) self.macsHandler();
}
- (void)showAccessSettings { if (self.accessHandler) self.accessHandler(); }
- (void)refreshAccessEditing {
    BOOL allowed = !self.accessEditingAllowed || self.accessEditingAllowed();
    self.username.enabled = allowed; self.password.enabled = allowed; self.remember.enabled = allowed;
}
- (void)reloadAccessUsername:(NSString *)username password:(NSString *)password {
    [self.credentialState replaceWithUsername:username password:password]; [self renderCredentialForm];
    [self loginEdited]; [self refreshAccessEditing];
}
- (void)stopViewer {
    [self retireSessionMenu];
    [self cancelDisplayModeConfirmation]; self.failedDisplayModePreset = nil;
    self.changingDisplayMode = self.mirrorRestartScheduled = self.mirrorRequiresCleanup = NO;
    self.mirrorCleanupRemaining = 0;
    self.deferredTextReviewFailure = nil;
    [self.credentialState invalidate]; [self renderCredentialForm];
    self.status.hidden = YES; [self updateStatusPresentation];
    [self invalidateTextReview:NO]; self.textReviewViewportPending=NO;
    [self retireTextDraft];
    [self.controls close]; self.starting = NO; self.exited = YES; self.reconnectWhenReady = NO; self.checkingResume = NO;
    self.resumeGeneration++; self.statusGeneration++; self.restoreViewportPending = NO; self.awaitingReplacementLayout = NO; self.pendingRestorationFrame = nil; self.resumeDisplayID = nil;
    self.keyboardViewportSaved = NO; self.keyboardLayoutPending = NO;
    if (self.sessionPhaseHandler) self.sessionPhaseHandler(@"ended");
    [self releasePointer]; self.zoomGeneration++; self.smartZoomed = NO; self.smartZoomPending = NO;
    [self updateTrackpadFeedback];
    [self clearCursor];
    [self.view endEditing:YES]; [self.loginScroll endEditing:YES]; [self.session stop]; [self resetModifiers];
    self.image.image = nil; self.lastFramebuffer = nil; self.activeCrop = CGRectNull;
    UIApplication.sharedApplication.idleTimerDisabled = NO;
}
- (void)clearRecovery {
    self.macSaveFailureVisible = NO;
    self.recoveryInputOnlyAction = nil; self.loginIssueDetails = nil;
    if (!self.recoveryController) return;
    [self.recoveryController willMoveToParentViewController:nil];
    [self.login removeArrangedSubview:self.recoveryController.view];
    [self.recoveryController.view removeFromSuperview]; [self.recoveryController removeFromParentViewController];
    self.recoveryController = nil; [self.recoveryPanel removeFromSuperview]; self.recoveryPanel = nil;
}
- (void)showRecoveryController:(UIViewController *)controller overFrame:(BOOL)overFrame {
    [self clearRecovery]; self.recoveryController = controller;
    UIViewController *parent = !overFrame && self.connectionPanelHost ? self.loginPanelContent : self;
    [parent addChildViewController:controller];
    controller.view.translatesAutoresizingMaskIntoConstraints = NO;
    if (overFrame) {
        self.login.hidden = YES; self.image.alpha = .4;
        UIScrollView *panel = [UIScrollView new]; self.recoveryPanel = panel;
        panel.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:panel]; [panel addSubview:controller.view];
        [NSLayoutConstraint activateConstraints:@[
            [panel.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
            [panel.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
            [panel.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-72],
            [panel.heightAnchor constraintEqualToConstant:MIN(320, self.view.bounds.size.height * .5)],
            [controller.view.leadingAnchor constraintEqualToAnchor:panel.contentLayoutGuide.leadingAnchor],
            [controller.view.trailingAnchor constraintEqualToAnchor:panel.contentLayoutGuide.trailingAnchor],
            [controller.view.topAnchor constraintEqualToAnchor:panel.contentLayoutGuide.topAnchor],
            [controller.view.bottomAnchor constraintEqualToAnchor:panel.contentLayoutGuide.bottomAnchor],
            [controller.view.widthAnchor constraintEqualToAnchor:panel.frameLayoutGuide.widthAnchor]]];
    } else { self.login.hidden = NO; [self.login insertArrangedSubview:controller.view atIndex:2]; }
    [controller didMoveToParentViewController:parent]; self.progressLabel.text = @""; self.status.hidden = YES;
    [self updateConnectionChrome];
}
- (void)editRecoveryLogin { [self finishCredentialSession]; [self clearRecovery]; self.login.hidden = NO; self.starting = NO; [self updateConnectionChrome]; [self.username becomeFirstResponder]; }
- (void)showRecoveryStage:(NSInteger)stage {
    __weak CompanionVNCViewer *weak = self;
    __weak CompanionVNCSession *owner = self.session;
    NSNumber *failed = self.failedDisplayModePreset;
    void (^inputOnly)(void) = nil;
    if (failed && !self.inputOnly && [DirectRecoveryBridgeV1 canOfferInputOnlyRecoveryAtStage:stage]) inputOnly = ^{
        if (weak.session == owner && [weak.failedDisplayModePreset isEqual:failed]) weak.inputOnly = YES;
    };
    UIViewController *card = [DirectRecoveryBridgeV1 desktopWithStage:stage hadFrame:self.lastFramebuffer != nil port:((stage == 10 || stage == 11 || (stage >= 110 && stage <= 115)) ? self.sshPort ?: 22 : self.servicePort ?: 5900) textInterrupted:self.textSendInterrupted retry:^{
        if (weak.failedDisplayModePreset) [weak restartDisplayModePreset:weak.failedDisplayModePreset.integerValue];
        else [weak start];
    } edit:^{ [weak editRecoveryLogin]; } inputOnly:inputOnly];
    [self showRecoveryController:card overFrame:self.lastFramebuffer != nil];
    self.recoveryInputOnlyAction = inputOnly;
    self.loginIssueDetails = [DirectRecoveryBridgeV1 desktopDetailsWithStage:stage hadFrame:self.lastFramebuffer != nil port:((stage == 10 || stage == 11 || (stage >= 110 && stage <= 115)) ? self.sshPort ?: 22 : self.servicePort ?: 5900)];
    [self updateConnectionChrome];
}
- (void)showConnectionProgress:(NSString *)message {
    if (!self.starting || self.exited) return;
    [self.connectionProgress recordTransportMessage:message];
    if (self.changingDisplayMode && self.mirrorFullRestartUsed) message = @"Switching display mode…";
    self.progressLabel.text = self.changingDisplayMode && self.mirrorFullRestartUsed ? @"Switching display mode…" : @"Connecting…";
    if (self.changingDisplayMode) { self.statusGeneration++; self.status.text = message; self.status.hidden = NO; }
    [self updateConnectionChrome];
}
- (void)showConnectionFailure { [self showConnectionFailureStage:0]; }
- (void)showConnectionFailureStage:(NSInteger)stage {
    if (self.exited) return;
    if (self.changingDisplayMode) {
        self.failedDisplayModePreset = @(self.modeTargetPreset);
        NSMutableDictionary *failure = [self.session.diagnosticCounters mutableCopy] ?: [NSMutableDictionary new];
        failure[@"displayModeTargetPreset"] = @(self.modeTargetPreset); failure[@"displayModeFailureStage"] = @(stage);
        failure[@"displayModeAttempts"] = @(self.mirrorRestoreAttempts); self.lastConnectionFailure = failure;
        self.session.stateHandler = nil; self.session.frameHandler = nil; self.session.cursorHandler = nil; self.session.displayLayoutHandler = nil;
        self.restoredDesktopSizePreset = self.modePreviousPreset; self.desktopSizeRestored = YES;
    }
    self.changingDisplayMode = self.mirrorRestartScheduled = NO; self.mirrorCleanupRemaining = 0;
    self.mirrorRestoreOutcome = stage == 116 ? 3 : stage == 117 ? 5 : 4;
    UIApplication.sharedApplication.idleTimerDisabled = NO;
    BOOL rejectedLoginOrTrust = [@[@2,@7,@8,@111,@112,@113,@115] containsObject:@(stage)];
    BOOL retryableModeFailure = (stage >= 116 && stage <= 118) || (self.mirrorFullRestartUsed && !rejectedLoginOrTrust);
    if (self.failedDisplayModePreset && retryableModeFailure) {
        // Keep only the existing bounded session recovery for explicit retry.
        // Visible unremembered fields stay empty; exit/edit still invalidate it.
        [self.credentialState suspendForModeRetry]; [self renderCredentialForm];
    } else [self finishCredentialSession];
    [self retireTextDraft];
    self.starting = NO; self.checkingResume = NO; self.resumeGeneration++; self.statusGeneration++; self.awaitingReplacementLayout = NO; self.pendingRestorationFrame = nil; self.restoreViewportPending = NO;
    if (self.sessionPhaseHandler) self.sessionPhaseHandler(@"ended");
    [self clearCursor]; [self resetModifiers]; self.connect.enabled = YES;
    if (self.textReview) {
        self.deferredTextReviewFailure = @(stage);
        return; // Local image, draft, Copy and Share remain usable.
    }
    self.deferredTextReviewFailure = nil;
    [self showRecoveryStage:stage];
}
- (void)revealDeferredTextReviewFailure {
    if (!self.deferredTextReviewFailure || self.textReview || !self.foreground || self.inputInactive || self.exited) return;
    NSInteger stage = self.deferredTextReviewFailure.integerValue; self.deferredTextReviewFailure = nil;
    [self showRecoveryStage:stage];
}
- (void)showInvalidLogin {
    [self clearRecovery]; self.starting = NO; self.connect.enabled = YES; self.login.hidden = NO;
    [self showRecoveryController:[DirectConnectionBridge validation] overFrame:NO];
}
- (void)showLoginRetentionFailure {
    __weak CompanionVNCViewer *weak = self;
    if (!self.session.connected) { self.starting = NO; self.connect.enabled = YES; }
    [self showRecoveryController:[DirectRecoveryBridgeV1 savedLoginWithConnected:self.session.connected done:^{ [weak clearRecovery]; weak.image.alpha = 1; [weak updateConnectionChrome]; }] overFrame:self.session.connected];
}
- (void)showMacSaveFailure:(BOOL)loginRequested {
    __weak CompanionVNCViewer *weak = self;
    [self showRecoveryController:[DirectRecoveryBridgeV1 macSaveFailedWithLoginRequested:loginRequested done:^{ [weak clearRecovery]; weak.image.alpha = 1; [weak updateConnectionChrome]; }] overFrame:YES];
    self.macSaveFailureVisible = YES;
}
- (void)rememberViewport {
    if (self.changingDisplayMode) {
        self.resumeDisplayID = nil; self.resumeCropSize = CGSizeZero; self.resumeZoomRatio = 1; self.resumeCenter = CGPointMake(.5,.5); return;
    }
    self.resumeDisplayID = self.changingDisplayMode ? nil : self.selectedDisplay[@"id"];
    self.resumeCropSize = self.changingDisplayMode ? CGSizeZero : self.activeCrop.size;
    self.resumeZoomRatio = self.canvas.minimumZoomScale > 0 ? self.canvas.zoomScale / self.canvas.minimumZoomScale : 1;
    self.resumeCenter = CGRectIsEmpty(self.activeCrop) || CGRectIsNull(self.activeCrop) ? CGPointMake(.5, .5) : [self viewportCenter];
}
- (void)discardPendingDisplayPreferences {
    self.pendingDesktopSizePreset = self.lateDesktopSizePreset = 0;
    self.pendingStreamDisplayID = nil; self.restoringStreamViewport = NO;
}
- (void)becameInactive {
    if (!self.foreground || self.exited || self.inputInactive) return;
    [self retireSessionMenu];
    self.inputInactive = YES; self.modeVerificationTimed = NO; self.modeVerificationGeneration++;
    [self discardPendingDisplayPreferences];
    [self cancelDisplayModeConfirmation];
    [self.controls close]; [self releasePointer]; [self resetModifiers]; [self cancelTrackpadTouches];
    [self invalidateTextReview:YES];
    [self.session suspendInputForInterruption];
    [self updateCursor]; [self updateTrackpadFeedback];
}
- (void)background { [self backgroundWithCompletion:nil]; }
- (void)backgroundWithCompletion:(void (^)(void))completion {
    [self retireSessionMenu];
    [self retireTextDraft];
    if (!self.foreground || self.exited) { if (completion) completion(); return; }
    [self discardPendingDisplayPreferences];
    self.reconnectWhenReady = self.session.running || self.starting;
    [self.credentialState suspend]; [self renderCredentialForm];
    self.modeVerificationTimed = NO; self.modeVerificationGeneration++;
    self.foreground = NO; self.inputInactive = YES; self.statusGeneration++; self.image.alpha = 1; self.resumeGeneration++; self.checkingResume = NO;
    self.pendingRestorationFrame = nil;
    self.status.hidden = YES; [self updateStatusPresentation];
    [self invalidateTextReview:NO]; self.textReviewViewportPending=NO;
    [self updateTrackpadFeedback];
    [self.controls close]; [self rememberViewport]; [self releasePointer]; [self resetModifiers]; [self invalidateCursorPosition];
    self.zoomGeneration++; self.smartZoomPending = NO;
    [self.view endEditing:YES]; [self.loginScroll endEditing:YES]; UIApplication.sharedApplication.idleTimerDisabled = NO;
    self.status.text = @"Paused · Return to resume";
    if (self.reconnectWhenReady && self.sessionPhaseHandler) self.sessionPhaseHandler(@"paused");
    if (self.session.established) { [self.session pauseWithCompletion:completion]; [self.session resumeInputAfterReview]; }
    else {
        [self.session stop]; if (self.disconnectHandler) self.disconnectHandler();
        if (completion) completion();
    }
}
- (void)foregrounded {
    if (self.exited) return;
    if (self.foreground) {
        if (self.inputInactive) { self.inputInactive = NO; [self.session resumeInputAfterInterruption]; [self updateCursor]; [self updateTrackpadFeedback]; }
        if (self.changingDisplayMode) [self updateDisplayModeRestoration];
        [self revealDeferredTextReviewFailure]; return;
    }
    self.foreground = YES; self.inputInactive = NO;
    [self.credentialState resumeWithActive:YES allowed:self.credentialState.accessAllowed]; [self renderCredentialForm];
    if (self.deferredTextReviewFailure) { self.reconnectWhenReady = NO; [self revealDeferredTextReviewFailure]; return; }
    if (!self.reconnectWhenReady) return;
    self.checkingResume = YES;
    self.status.hidden = YES; [self scheduleResumeIndicator:self.inputOnly ? @"Resuming Trackpad & Keyboard…" : @"Updating desktop…"]; self.image.alpha = 1;
    if (!self.session.running) { [self reconnectAfterFailedResume]; return; }
    [self.session resume];
    CompanionVNCSession *owner = self.session; NSUInteger generation = ++self.resumeGeneration;
    __weak CompanionVNCViewer *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 9000 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        CompanionVNCViewer *strong = weak;
        if (strong.foreground && !strong.exited && strong.checkingResume && strong.session == owner && strong.resumeGeneration == generation) {
            [owner stop]; if (strong.disconnectHandler) strong.disconnectHandler(); [strong reconnectAfterFailedResume];
        }
    });
}
- (void)reconnectAfterFailedResume {
    if (!self.foreground || self.exited || !self.checkingResume) return;
    self.checkingResume = NO; self.resumeGeneration++;
    // One replacement attempt. The Swift connection owner awaits retirement first.
    self.restoreViewportPending = YES; [self startResuming:YES];
}
- (void)restoreViewport {
    if (!self.restoreViewportPending || self.awaitingReplacementLayout || !self.lastFramebuffer) return;
    self.restoreViewportPending = NO;
    NSDictionary *display = nil;
    for (NSDictionary *candidate in self.displayViews) if ([candidate[@"id"] isEqual:self.resumeDisplayID]) { display = candidate; break; }
    BOOL missing = self.resumeDisplayID && !display;
    [self selectDisplay:display];
    BOOL selectionValid = !self.resumeDisplayID || [self.selectedDisplay[@"id"] isEqual:self.resumeDisplayID];
    if (display && self.restoredDesktopSizePreset == 0 && [self.session.desktopDisplayLayout[@"views"] count]) {
        self.restoredDisplayID = display[@"id"]; self.initialDisplayApplied = NO; self.restoringStreamViewport = YES;
    }
    self.resumeDisplayID = nil;
    if (missing) {
        self.displayNoticeUntil = NSProcessInfo.processInfo.systemUptime + 3;
        self.status.text = @"Selected display is unavailable. Showing all displays."; self.status.hidden = NO; [self updateStatusPresentation];
        __weak CompanionVNCViewer *weak = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (NSProcessInfo.processInfo.systemUptime >= weak.displayNoticeUntil && !weak.checkingResume && !weak.starting) { weak.status.hidden = YES; [weak updateStatusPresentation]; }
        });
    }
    if (missing || !selectionValid || CGRectIsNull(self.activeCrop) || CGRectIsEmpty(self.activeCrop)
        || !CGSizeEqualToSize(self.activeCrop.size, self.resumeCropSize)) return;
    [self applyViewportRatio:self.resumeZoomRatio center:self.resumeCenter];
}
- (void)resetModifiers {
    [self.remoteKeyboard reset]; [self refreshModifiers];
}
- (void)refreshModifiers {
    for (UIButton *key in self.modifiers) {
        key.selected = [self.remoteKeyboard.armedModifiers containsObject:@(key.tag)];
        key.backgroundColor = key.selected ? UIColor.systemBlueColor : UIColor.secondarySystemBackgroundColor;
    }
}
- (void)frame:(UIImage *)frame {
    if (self.awaitingReplacementLayout) { self.pendingRestorationFrame = frame; return; }
    BOOL restoring = self.restoreViewportPending;
    CGSize pixels = CGSizeMake(CGImageGetWidth(frame.CGImage), CGImageGetHeight(frame.CGImage));
    if (restoring && self.resumeDisplayID && (self.displayAspect <= 0 || fabs(pixels.width / pixels.height - self.displayAspect) / self.displayAspect >= .03)) {
        self.awaitingReplacementLayout = YES; self.pendingRestorationFrame = frame; return;
    }
    BOOL resized = !CGSizeEqualToSize(self.framebufferSize, pixels);
    if (resized) { [self.localPointerTargets removeAllObjects]; [self releasePointer]; self.zoomGeneration++; self.smartZoomed = NO; self.smartZoomPending = NO; [self invalidateCursorPosition]; }
    self.framebufferSize = pixels; self.lastFramebuffer = frame;
    if (resized || restoring) [self updateDisplayPicker];
    if (restoring) [self restoreViewport];
    else { [self restoreSavedDisplay]; [self renderFramebuffer:resized]; }
    if (restoring && !self.restoreViewportPending && self.session.connected && self.session.desktopFrameReady && self.session.stateHandler) {
        self.session.stateHandler(@"Connected", self.latestCounters ?: @{});
    }
    if (self.textReviewViewportPending) {
        self.textReviewViewportPending = NO;
        if (CGSizeEqualToSize(self.framebufferSize,self.textReviewFramebuffer) && CGRectEqualToRect(self.activeCrop,self.textReviewCrop))
            [self applyViewportRatio:self.textReviewZoom center:self.textReviewCenter];
    }
}
- (void)scheduleResumeIndicator:(NSString *)message {
    NSUInteger generation = ++self.statusGeneration;
    self.status.hidden = YES; [self updateStatusPresentation];
    __weak CompanionVNCViewer *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1000 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (!weak || weak.statusGeneration != generation || !weak.foreground || weak.inputInactive || weak.exited
            || !(weak.checkingResume || weak.starting || weak.restoreViewportPending)) return;
        weak.status.text = message; weak.status.hidden = NO; [weak updateStatusPresentation];
    });
}
- (void)updateStatusPresentation {
    BOOL busy = self.changingDisplayMode || self.checkingResume || self.starting || self.restoreViewportPending || self.pendingDesktopSizePreset != 0 || self.pendingStreamDisplayID != nil;
    self.statusBackdrop.hidden = self.status.hidden;
    self.statusSpinner.hidden = !busy || self.status.hidden;
    if (!self.statusSpinner.hidden) [self.statusSpinner startAnimating]; else [self.statusSpinner stopAnimating];
}
- (void)renderFramebuffer:(BOOL)reset {
    if (!self.lastFramebuffer || self.restoreViewportPending) return;
    NSDictionary *display = self.selectedDisplay;
    CGRect normalized = CGRectMake([display[@"x"] doubleValue], [display[@"y"] doubleValue],
        [display[@"width"] doubleValue], [display[@"height"] doubleValue]);
    CGRect crop = CompanionVNCViewportRect(self.framebufferSize, normalized, display != nil, self.displayAspect);
    if (CGRectIsNull(crop)) {
        [self releasePointer]; self.activeCrop = CGRectNull; self.image.image = nil;
        // Old display bounds must not blank the working desktop after a resize.
        self.selectedDisplay = nil;
        self.displayPicker.selectedID = nil;
        crop = (CGRect){CGPointZero, self.framebufferSize};
        self.status.text = @"Display layout changed. Showing all displays.";
    }
    BOOL changed = !CGRectEqualToRect(crop, self.activeCrop); self.activeCrop = crop;
    if (changed) [self.localPointerTargets removeAllObjects];
    if (!self.cursorPositionKnown || ((self.trackpadMode || self.tabletop) && !CGRectContainsPoint(crop,self.cursorPosition))) {
        self.cursorPosition = CGPointMake(CGRectGetMidX(crop),CGRectGetMidY(crop)); self.cursorPositionKnown = YES;
    }
    if (changed) { self.keyboardViewportSaved = NO; self.keyboardLayoutPending = NO; }
    CGImageRef image = CGImageCreateWithImageInRect(self.lastFramebuffer.CGImage, crop);
    self.image.image = image ? [UIImage imageWithCGImage:image] : nil;
    if (image) CGImageRelease(image);
    if (reset || changed) {
        self.canvas.zoomScale = 1; self.image.frame = (CGRect){CGPointZero, crop.size};
        self.canvas.contentSize = crop.size; [self fitDesktop];
    }
    [self updateCursor];
}
- (void)selectDisplay:(NSDictionary *)display {
    [self releasePointer]; self.zoomGeneration++; self.smartZoomed = NO; self.smartZoomPending = NO;
    self.selectedDisplay = display;
    self.displayPicker.selectedID = display[@"id"];
    self.views.accessibilityValue = display ? display[@"title"] : @"All Displays";
    [self.session viewChanged]; [self renderFramebuffer:YES];
}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView { return self.image; }
- (CGRect)canvasViewportBounds {
    // The canvas reaches behind system chrome; Fit and automatic cursor following
    // use only the unobscured region. Panning remains owned by UIScrollView.
    return UIEdgeInsetsInsetRect(self.canvas.bounds, self.canvas.contentInset);
}
- (CGPoint)clampedCanvasOffset:(CGPoint)offset {
    UIEdgeInsets inset = self.canvas.contentInset;
    CGFloat minX = -inset.left, minY = -inset.top;
    return CGPointMake(MAX(minX, MIN(MAX(minX, self.canvas.contentSize.width - self.canvas.bounds.size.width + inset.right), offset.x)),
                       MAX(minY, MIN(MAX(minY, self.canvas.contentSize.height - self.canvas.bounds.size.height + inset.bottom), offset.y)));
}
- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    CGSize visible = [self canvasViewportBounds].size;
    CGFloat x = MAX(0, (visible.width - self.image.frame.size.width) / 2);
    CGFloat y = MAX(0, (visible.height - self.image.frame.size.height) / 2);
    self.image.center = CGPointMake(self.image.frame.size.width / 2 + x, self.image.frame.size.height / 2 + y);
    [self updateCursor]; [self rememberLayoutViewport];
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView { [self updateCursor]; [self rememberLayoutViewport]; }
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView { if (scrollView == self.canvas) self.cursorFollowingSuspended = YES; }
- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view { if (scrollView == self.canvas) self.cursorFollowingSuspended = YES; }
- (void)fitDesktop {
    if (CGRectIsNull(self.activeCrop) || CGRectIsEmpty(self.activeCrop) || self.canvas.bounds.size.width <= 0 || self.canvas.bounds.size.height <= 0) return;
    self.smartZoomed = NO; self.smartZoomPending = NO; self.zoomGeneration++;
    CGSize visible = [self canvasViewportBounds].size;
    if (visible.width <= 0 || visible.height <= 0) return;
    CGFloat fit = MIN(visible.width / self.activeCrop.size.width, visible.height / self.activeCrop.size.height);
    self.canvas.minimumZoomScale = fit; [self.canvas setZoomScale:fit animated:NO];
    self.canvas.contentOffset = CGPointMake(-self.canvas.contentInset.left, -self.canvas.contentInset.top); [self scrollViewDidZoom:self.canvas];
    self.previousCanvasSize = self.canvas.bounds.size;
    self.previousCanvasInset = self.canvas.contentInset;
    if (!self.adaptingViewport) [self rememberLayoutViewport];
}
- (CGPoint)viewportCenter {
    CGRect visible = [self canvasViewportBounds];
    CGPoint point = [self.image convertPoint:CGPointMake(CGRectGetMidX(visible), CGRectGetMidY(visible)) fromView:self.canvas];
    return CGPointMake(MAX(0, MIN(1, point.x / self.activeCrop.size.width)), MAX(0, MIN(1, point.y / self.activeCrop.size.height)));
}
- (void)applyViewportRatio:(CGFloat)ratio center:(CGPoint)center {
    if (ratio <= 1.01) { [self fitDesktop]; return; }
    CGFloat scale = MIN(self.canvas.maximumZoomScale, self.canvas.minimumZoomScale * MAX(1, ratio));
    [self.canvas setZoomScale:scale animated:NO]; [self scrollViewDidZoom:self.canvas];
    CGPoint point = [self.image convertPoint:CGPointMake(center.x * self.activeCrop.size.width, center.y * self.activeCrop.size.height) toView:self.canvas];
    CGSize visible = [self canvasViewportBounds].size;
    CGPoint offset = CGPointMake(point.x - self.canvas.contentInset.left - visible.width / 2,
                                point.y - self.canvas.contentInset.top - visible.height / 2);
    [self.canvas setContentOffset:[self clampedCanvasOffset:offset] animated:NO];
}
- (void)rememberLayoutViewport {
    if (self.adaptingViewport || !CGSizeEqualToSize(self.canvas.bounds.size, self.previousCanvasSize)
        || !UIEdgeInsetsEqualToEdgeInsets(self.canvas.contentInset, self.previousCanvasInset)
        || CGRectIsEmpty(self.activeCrop) || CGRectIsNull(self.activeCrop) || self.canvas.minimumZoomScale <= 0) return;
    self.layoutZoomRatio = self.canvas.zoomScale / self.canvas.minimumZoomScale;
    self.layoutCenter = [self viewportCenter]; self.layoutCrop = self.activeCrop;
}
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets), content = CGRectNull, input = CGRectNull;
    self.canvasTop.constant = self.immersiveChrome ? 0 : CGRectGetMinY(safe) + 8;
    CGFloat leading = 0;
    if (self.immersiveChrome) {
        UIWindow *window = self.view.window;
        leading = window ? MAX(0, window.safeAreaInsets.top - [self.view convertPoint:CGPointZero toView:window].y) + 8 : CGRectGetMinY(safe) + 8;
    }
    if (self.canvas.contentInset.top != leading) {
        self.adaptingViewport = YES;
        self.canvas.contentInset = UIEdgeInsetsMake(leading, 0, 0, 0);
        self.canvas.verticalScrollIndicatorInsets = self.canvas.contentInset;
        self.adaptingViewport = NO;
    }
    // Both Screen Sharing modes use the same login layout. Only the connected
    // desktop needs a separate tabletop video region and input surface.
    BOOL divided = CompanionVNCTabletopRegions(safe, [self activeDivision], &content, &input);
    BOOL tabletop = !self.inputOnly && divided;
    CGRect loginRegion = self.connectionPanelHost ? self.loginPanelContent.view.bounds : safe;
    if (!self.connectionPanelHost) loginRegion.size.height = MAX(0, loginRegion.size.height - self.keyboardOverlap);
    BOOL lowerLogin = !self.connectionPanelHost && divided && CGRectGetMaxY(loginRegion) - input.origin.y >= 240;
    if (divided && !self.connectionPanelHost) {
        loginRegion = lowerLogin ? CGRectIntersection(loginRegion, input) : CGRectIntersection(loginRegion, content);
    }
    self.loginTop.constant = CGRectGetMinY(loginRegion);
    self.loginBottom.constant = CGRectGetMaxY(loginRegion);
    BOOL compact = !self.connectionPanelHost && (divided || loginRegion.size.height < 520) && !UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    self.loginMaxWidth.constant = self.connectionPanelHost ? 520 : compact ? 720 : 440;
    self.login.spacing = compact ? 8 : 18;
    self.login.layoutMargins = self.connectionPanelHost ? UIEdgeInsetsMake(12,8,8,8) : compact ? UIEdgeInsetsMake(16,16,16,16) : UIEdgeInsetsMake(22,22,22,22);
    self.loginFields.spacing = compact ? 8 : 14;
    self.loginIntro.spacing = compact ? 8 : 16;
    self.loginIdentity.axis = UILayoutConstraintAxisHorizontal;
    self.loginIdentity.alignment = UIStackViewAlignmentCenter;
    self.loginIconHeight.constant = compact ? 40 : 52; self.loginIconWidth.constant = compact ? 40 : 52;
    self.loginSubtitle.hidden = NO;
    if (lowerLogin != self.foldedLogin) {
        self.foldedLogin = lowerLogin;
        if (lowerLogin) {
            [self.login removeArrangedSubview:self.loginIntro]; [self.loginIntro removeFromSuperview];
            self.loginIntro.translatesAutoresizingMaskIntoConstraints = YES; [self.view addSubview:self.loginIntro];
        } else {
            [self.loginIntro removeFromSuperview]; self.loginIntro.translatesAutoresizingMaskIntoConstraints = NO;
            [self.login insertArrangedSubview:self.loginIntro atIndex:0];
        }
    }
    if (lowerLogin) {
        CGFloat width = MIN(440, MAX(0, content.size.width - 40));
        CGSize fitting = [self.loginIntro systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
        self.loginIntro.frame = CGRectMake(CGRectGetMidX(content)-width/2, CGRectGetMidY(content)-fitting.height/2, width, fitting.height);
        self.loginIntro.hidden = self.login.hidden;
    } else self.loginIntro.hidden = NO;
    if (!self.login.hidden) {
        CGFloat cardWidth = MIN(self.loginMaxWidth.constant, MAX(0, loginRegion.size.width - 32));
        CGSize fitting = [self.login systemLayoutSizeFittingSize:CGSizeMake(cardWidth, UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    self.loginContentTop.constant = self.connectionPanelHost ? 12 : MAX(12, loginRegion.size.height - fitting.height - 12);
        if (self.connectionPanelHost && !self.starting && !(self.session.running && !self.lastFramebuffer)) {
            CGSize footer = [self.loginActions systemLayoutSizeFittingSize:CGSizeMake(cardWidth, UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
            [self.connectionPanelHost setContentHeight:ceil(fitting.height + footer.height + 16) owner:self.loginPanelOwner];
        }
    }
    self.tabletop = tabletop; self.tabletopInputRegion = tabletop ? input : CGRectNull;
    CGFloat keyboardCeiling = CGRectGetMaxY(safe) - self.keyboardOverlap;
    if (!self.fullscreen) keyboardCeiling -= MAX(44, self.toolbar.bounds.size.height) + 12;
    self.tabletopCanvasBottom.constant = tabletop ? MIN(CGRectGetMaxY(content) - 8, keyboardCeiling) : 0;
    self.canvasToolbarBottom.active = !tabletop && !self.fullscreen;
    self.canvasFullscreenBottom.active = !tabletop && self.fullscreen;
    self.tabletopCanvasBottom.active = tabletop;
}
- (CGRect)activeDivision { return CompanionVNCActiveDivision(self.view); }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.connectionPanelHost) [DirectConnectionBridge styleCard:self.login];
    self.tabletopPad.hidden = !self.tabletop || !self.login.hidden || self.recoveryPanel != nil;
    if (self.tabletop) {
        CGRect input = self.tabletopInputRegion;
        CGFloat bottom = self.fullscreen ? CGRectGetMaxY(input) - self.keyboardOverlap - 68 : CGRectGetMinY(self.toolbar.frame) - 12;
        self.tabletopPad.frame = CGRectMake(input.origin.x + 12, input.origin.y + 12, MAX(0, input.size.width - 24), MAX(0, bottom - input.origin.y - 12));
        self.tabletopPad.hidden = self.tabletopPad.hidden || self.tabletopPad.bounds.size.height < 44;
        self.tabletopLabel.frame = CGRectMake(20, 12, MAX(0, self.tabletopPad.bounds.size.width - 40), MAX(0, self.tabletopPad.bounds.size.height - 24));
    }
    [self updateTrackpadFeedback];
    if (CGRectIsNull(self.activeCrop) || CGRectIsEmpty(self.activeCrop)) return;
    CGSize size = self.canvas.bounds.size;
    if (size.width <= 0 || size.height <= 0) return;
    BOOL resized = !CGSizeEqualToSize(size, self.previousCanvasSize)
        || !UIEdgeInsetsEqualToEdgeInsets(self.canvas.contentInset, self.previousCanvasInset);
    CGFloat ratio = self.layoutZoomRatio > 0 && CGRectEqualToRect(self.layoutCrop, self.activeCrop) ? self.layoutZoomRatio : 1;
    CGPoint center = self.layoutCenter;
    self.adaptingViewport = YES;
    CGSize visible = [self canvasViewportBounds].size;
    if (visible.width <= 0 || visible.height <= 0) { self.adaptingViewport = NO; return; }
    self.canvas.minimumZoomScale = MIN(visible.width / self.activeCrop.size.width, visible.height / self.activeCrop.size.height);
    if (resized) {
        self.previousCanvasSize = size; self.zoomGeneration++; self.smartZoomPending = NO;
        self.previousCanvasInset = self.canvas.contentInset;
        [self releasePointer];
        [self cancelTrackpadTouches];
        for (UIGestureRecognizer *gesture in [@[self.drag, self.hold, self.remoteScroll, self.remotePinch] arrayByAddingObjectsFromArray:self.tabletopGestures]) {
            BOOL enabled = gesture.enabled; gesture.enabled = NO; gesture.enabled = enabled;
        }
        [self.controls cancelSlideForLayoutChange];
    }
    if (self.keyboardLayoutPending) {
        self.keyboardLayoutPending = NO;
        [self applyViewportRatio:self.keyboardLayoutRatio center:self.keyboardLayoutCenter];
    } else if (resized) {
        if (self.smartZoomed) [self.canvas zoomToRect:self.smartWindow animated:NO];
        else [self applyViewportRatio:ratio center:center];
    }
    self.adaptingViewport = NO; [self rememberLayoutViewport];
    [self updateCursor];
}
- (void)prepareTabletopPad {
    self.tabletopPad = [UIView new]; self.tabletopPad.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.tabletopPad.layer.cornerRadius = 24; self.tabletopPad.hidden = YES;
    self.tabletopPad.accessibilityIdentifier = @"tabletop-trackpad";
    [self.view insertSubview:self.tabletopPad belowSubview:self.controls];
    self.tabletopLabel = [UILabel new]; self.tabletopLabel.numberOfLines = 0; self.tabletopLabel.textAlignment = NSTextAlignmentCenter;
    self.tabletopLabel.text = @"Trackpad\nTap to click · Hold to drag\nTwo fingers to scroll · Tap with two to right-click";
    self.tabletopLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; self.tabletopLabel.adjustsFontForContentSizeCategory = YES;
    self.tabletopLabel.textColor = UIColor.secondaryLabelColor; [self.tabletopPad addSubview:self.tabletopLabel];
    CompanionVNCTapGesture *tap = [[CompanionVNCTapGesture alloc] initWithTarget:self action:@selector(clickAt:)];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragAt:)]; pan.maximumNumberOfTouches = 1;
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(holdAt:)]; hold.minimumPressDuration = .35;
    [pan requireGestureRecognizerToFail:hold]; [pan requireGestureRecognizerToFail:tap];
    UIPanGestureRecognizer *scroll = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(scrollRemote:)];
    scroll.minimumNumberOfTouches = 2; scroll.maximumNumberOfTouches = 2;
    self.tabletopSecondaryTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(secondaryClickAt:)];
    self.tabletopSecondaryTap.numberOfTouchesRequired = 2;
    self.tabletopGestures = @[tap, pan, hold, scroll, self.tabletopSecondaryTap];
    for (UIGestureRecognizer *gesture in self.tabletopGestures) [self.tabletopPad addGestureRecognizer:gesture];
}
- (void)prepareTrackpadFeedback {
    self.trackpadFeedback = [[CompanionVNCTrackpadFeedback alloc] initWithSurface:self.canvas];
    self.trackpadFeedback.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view insertSubview:self.trackpadFeedback aboveSubview:self.cursorOverlay];
    [NSLayoutConstraint activateConstraints:@[
        [self.trackpadFeedback.leadingAnchor constraintEqualToAnchor:self.canvas.leadingAnchor],
        [self.trackpadFeedback.trailingAnchor constraintEqualToAnchor:self.canvas.trailingAnchor],
        [self.trackpadFeedback.topAnchor constraintEqualToAnchor:self.canvas.topAnchor],
        [self.trackpadFeedback.bottomAnchor constraintEqualToAnchor:self.canvas.bottomAnchor]]];
    self.tabletopFeedback = [[CompanionVNCTrackpadFeedback alloc] initWithSurface:self.tabletopPad];
    self.tabletopFeedback.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tabletopFeedback.frame = self.tabletopPad.bounds; [self.tabletopPad addSubview:self.tabletopFeedback];
    __weak CompanionVNCViewer *weak = self;
    for (CompanionVNCTrackpadFeedback *feedback in @[self.trackpadFeedback, self.tabletopFeedback]) {
        feedback.touchesAllowed = ^BOOL {
            CompanionVNCViewer *viewer = weak;
            return viewer && viewer.foreground && !viewer.exited && !viewer.inputInactive && !viewer.restoreViewportPending && !viewer.checkingResume && viewer.session.connected
                && viewer.login.hidden && !viewer.recoveryController && !viewer.presentedViewController;
        };
    }
    self.trackpadFeedback.touchActivityChanged = self.tabletopFeedback.touchActivityChanged = ^{
        CompanionVNCViewer *viewer = weak;
        if ((viewer.trackpadFeedback.hasTouches || viewer.tabletopFeedback.hasTouches)
            && (viewer.trackpadMode || !viewer.tabletopPad.hidden) && !CGRectIsEmpty(viewer.activeCrop) && !CGRectIsNull(viewer.activeCrop)) {
            [viewer recordLocalPointer:[viewer trackpadPointer]];
        }
        [viewer updateCursor];
    };
    [self updateTrackpadFeedback];
}
- (void)setShowsTouchPoints:(BOOL)value { _showsTouchPoints = value; [self updateTrackpadFeedback]; if (self.isViewLoaded) [self updateCursor]; }
- (void)setTrackpadHapticsEnabled:(BOOL)value { _trackpadHapticsEnabled = value; [self updateTrackpadFeedback]; }
- (void)updateTrackpadFeedback {
    BOOL ready = self.foreground && !self.exited && !self.inputInactive && !self.restoreViewportPending && !self.checkingResume && self.session.connected
        && self.login.hidden && !self.recoveryController;
    self.trackpadFeedback.showsTouchPoints = self.showsTouchPoints;
    self.tabletopFeedback.showsTouchPoints = self.showsTouchPoints;
    self.trackpadFeedback.hapticsEnabled = self.trackpadHapticsEnabled;
    self.tabletopFeedback.hapticsEnabled = self.trackpadHapticsEnabled;
    // Pointer uses the same passive finger feedback at the touched location.
    // Video-free input remains a trackpad even if a direct caller changes mode.
    self.trackpadFeedback.active = ready && (self.trackpadMode || !self.inputOnly) && !self.canvas.hidden;
    self.tabletopFeedback.active = ready && !self.tabletopPad.hidden;
}
- (void)cancelTrackpadTouches { [self.trackpadFeedback cancelTouches]; [self.tabletopFeedback cancelTouches]; }
- (CompanionVNCTrackpadFeedback *)feedbackForGesture:(UIGestureRecognizer *)gesture {
    return gesture.view == self.tabletopPad ? self.tabletopFeedback : self.trackpadFeedback;
}
- (void)retirePointerForMenu {
    if (self.retiringPointerGestures) return;
    self.retiringPointerGestures = YES;
    [self releasePointer]; [self cancelTrackpadTouches];
    NSArray *gestures = self.drag ? [@[self.click, self.drag, self.hold, self.remoteScroll, self.remotePinch]
        arrayByAddingObjectsFromArray:self.tabletopGestures ?: @[]] : @[];
    for (UIGestureRecognizer *gesture in gestures) {
        BOOL enabled = gesture.enabled; gesture.enabled = NO; gesture.enabled = enabled;
    }
    self.retiringPointerGestures = NO;
}
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    [self retirePointerForMenu]; [super presentViewController:controller animated:animated completion:completion];
}
- (void)chooseView {
    if (self.restoreViewportPending) return;
    if (!self.framebufferSize.width) return;
    CompanionVNCDisplayPicker *picker = [CompanionVNCDisplayPicker new];
    self.displayPicker = picker;
    [self updateDisplayPicker];
    __weak CompanionVNCViewer *weak = self;
    picker.selectionHandler = ^(NSNumber *displayID) {
        // A local choice explicitly hands control away from prior desktop touches.
        [weak retirePointerForMenu];
        // Resolve against the latest server layout, not a stale menu snapshot.
        NSDictionary *selected = nil;
        for (NSDictionary *d in weak.displayViews) if ([d[@"id"] isEqual:displayID]) { selected = d; break; }
        weak.initialDisplayApplied = YES; weak.restoredDisplayID = nil;
        BOOL changed = [weak.selectedDisplay[@"id"] unsignedIntValue] != displayID.unsignedIntValue;
        if ([weak.session.desktopDisplayLayout[@"views"] count]) {
            if ([weak applyStreamDisplay:displayID ?: @0]) {
                if (changed) [weak.keyFeedback feedback:@"selection"];
            } else {
                weak.displaySelectionRejections++;
                weak.displaySelectionRejectMask = (!weak.foreground || weak.exited ? 1 : 0)
                    | (weak.inputInactive || weak.inputOnly || weak.textReview ? 2 : 0)
                    | (weak.restoreViewportPending || weak.checkingResume ? 4 : 0)
                    | (weak.pendingDesktopSizePreset || weak.pendingStreamDisplayID ? 8 : 0)
                    | (weak.session.localPointerInteractionActive ? 16 : 0)
                    | (!weak.session.desktopSizeAvailable ? 32 : 0);
                weak.displayNoticeUntil = NSProcessInfo.processInfo.systemUptime + 4;
                weak.status.text = @"Display could not be changed right now. Try again in a moment."; weak.status.hidden = NO;
                [weak updateStatusPresentation]; [weak updateCursorDiagnostics];
            }
        } else {
            [weak selectDisplay:selected];
            if (changed && (!displayID || selected)) [weak.keyFeedback feedback:@"selection"];
            if (weak.displaySelectionHandler) weak.displaySelectionHandler(selected[@"id"]);
        }
    };
    if ([self.presentedViewController isKindOfClass:UINavigationController.class]) {
        UINavigationController *navigation = (id)self.presentedViewController;
        if ([navigation.topViewController isKindOfClass:CompanionVNCMenu.class]) {
            [navigation pushViewController:picker animated:YES]; return;
        }
    }
    UINavigationController *menu = [CompanionVNCMenu navigationControllerForContent:picker sourceView:self.views];
    menu.preferredContentSize = CGSizeMake(360, MIN(520, 116 + 72 * (picker.displays.count + 1)));
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)updateDisplayPicker {
    NSDictionary *catalogue = self.session.desktopDisplayLayout;
    if ([catalogue[@"views"] count] && ![self.displayLayout[@"virtual"] boolValue]) {
        self.displayPicker.layoutAspect = [catalogue[@"aspectRatio"] doubleValue];
        self.displayPicker.displays = catalogue[@"views"];
    } else {
        self.displayPicker.layoutAspect = self.displayAspect;
        CGFloat aspect = self.framebufferSize.width / self.framebufferSize.height;
        self.displayPicker.displays = self.displayAspect > 0 && fabs(aspect - self.displayAspect) / self.displayAspect < .03 ? self.displayViews : @[];
    }
    self.displayPicker.selectedID = self.selectedDisplay[@"id"];
}
- (void)chooseInputMode { [self showInputMenu]; }
- (void)setTrackpadModeEnabled:(BOOL)enabled {
    [self releasePointer]; [self cancelTrackpadTouches];
    // Cancel recognizers in progress before switching coordinate systems.
    for (UIGestureRecognizer *gesture in [@[self.drag, self.hold, self.remoteScroll, self.remotePinch] arrayByAddingObjectsFromArray:self.tabletopGestures]) {
        BOOL enabled = gesture.enabled; gesture.enabled = NO; gesture.enabled = enabled;
    }
    self.controls.trackpad = enabled;
    if (self.inputModeHandler) self.inputModeHandler(enabled);
    self.trackpadMode = enabled; self.scrollRemainder = 0;
    [self updateTrackpadFeedback];
    self.remoteScroll.enabled = enabled;
    self.canvas.panGestureRecognizer.minimumNumberOfTouches = enabled ? 3 : 2;
    [self.pan setTitle:enabled ? @"Trackpad ▾" : @"Pointer ▾" forState:UIControlStateNormal];
    [self updateCursor];
}
- (CGPoint)trackpadPointer {
    CGPoint p = self.cursorPositionKnown ? self.cursorPosition : CGPointMake(CGRectGetMidX(self.activeCrop), CGRectGetMidY(self.activeCrop));
    p.x = MAX(CGRectGetMinX(self.activeCrop), MIN(CGRectGetMaxX(self.activeCrop) - 1, p.x));
    p.y = MAX(CGRectGetMinY(self.activeCrop), MIN(CGRectGetMaxY(self.activeCrop) - 1, p.y));
    return p;
}
- (BOOL)pointerForGesture:(UIGestureRecognizer *)gesture point:(CGPoint *)p {
    if (self.retiringPointerGestures || self.controls.menuOpen || self.presentedViewController) {
        self.session.localPointerInteractionActive = NO; return NO;
    }
    if (CGRectIsNull(self.activeCrop) || CGRectIsEmpty(self.activeCrop)) { self.session.localPointerInteractionActive = NO; return NO; }
    self.session.localPointerInteractionActive = gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged;
    if (!self.trackpadMode && gesture.view != self.tabletopPad) return CompanionVNCPointerPoint(self.activeCrop, [gesture locationInView:self.image], self.pointerHeld, p);
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.trackpadOrigin = [self trackpadPointer]; self.trackpadTranslation = CGPointZero;
        self.cursorFollowingSuspended = NO;
    }
    CGPoint delta = CGPointZero;
    if ([gesture isKindOfClass:UIPanGestureRecognizer.class]) delta = [(UIPanGestureRecognizer *)gesture translationInView:gesture.view ?: self.canvas];
    else if ([gesture isKindOfClass:UILongPressGestureRecognizer.class]) {
        // The overlay's origin stays fixed when auto-follow scrolls the canvas.
        CGPoint location = [gesture locationInView:gesture.view == self.tabletopPad ? self.tabletopPad : self.cursorOverlay];
        if (gesture.state == UIGestureRecognizerStateBegan) self.holdOrigin = location;
        delta = CGPointMake(location.x - self.holdOrigin.x, location.y - self.holdOrigin.y);
    }
    CGPoint step = CGPointMake(delta.x - self.trackpadTranslation.x, delta.y - self.trackpadTranslation.y);
    self.trackpadTranslation = delta;
    CGFloat velocity = 0;
    if ([gesture isKindOfClass:UIPanGestureRecognizer.class]) { CGPoint v = [(UIPanGestureRecognizer *)gesture velocityInView:gesture.view ?: self.canvas]; velocity = hypot(v.x, v.y); }
    CGFloat backing = [self.displayLayout[@"backingScale"] doubleValue];
    if (!isfinite(backing) || backing < 1 || backing > 4) backing = 2;
    CGFloat speed = isfinite(self.pointerSpeed) && self.pointerSpeed > 0 ? MAX(.5, MIN(3, self.pointerSpeed)) : 1.5;
    CGFloat gain = backing * speed * (1 + MIN(1.5, MAX(0, velocity - 100) / 500));
    CGPoint local = CGPointMake(self.trackpadOrigin.x - self.activeCrop.origin.x + step.x * gain,
                               self.trackpadOrigin.y - self.activeCrop.origin.y + step.y * gain);
    BOOL valid = CompanionVNCPointerPoint(self.activeCrop, local, true, p);
    if (valid) self.trackpadOrigin = *p;
    return valid;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)other {
    return gesture == self.secondaryTap && other == self.smartTap && !self.inputOnly;
}
- (void)clickAt:(UIGestureRecognizer *)gesture { [self clickAt:gesture mask:1]; }
- (void)secondaryClickAt:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateRecognized || self.textReview || self.presentedViewController
        || self.recoveryController || !self.login.hidden) return;
    [self clickAt:gesture mask:4];
}
- (void)clickAt:(UIGestureRecognizer *)gesture mask:(NSInteger)mask {
    CGPoint p;
    if (self.trackpadMode || gesture.view == self.tabletopPad) { if (CGRectIsNull(self.activeCrop) || CGRectIsEmpty(self.activeCrop)) return; p = [self trackpadPointer]; }
    else if (!CompanionVNCPointerPoint(self.activeCrop, [gesture locationInView:self.image], false, &p)) return;
    if ([self clickPointer:p mask:mask]) {
        CompanionVNCTrackpadFeedback *feedback = [self feedbackForGesture:gesture];
        [feedback clickAtPoint:[gesture locationInView:feedback]];
    }
}
- (BOOL)clickPointer:(CGPoint)p mask:(NSInteger)mask {
    if (!self.foreground || self.exited || self.inputInactive || self.restoreViewportPending || self.checkingResume || ![self.session tryClickX:p.x y:p.y mask:mask]) {
        self.status.hidden = NO; self.status.text = @"Click not sent. Wait for your Mac to resume."; [self updateStatusPresentation]; return NO;
    }
    [self recordLocalPointer:p]; [self updateCursor]; [self pulseCursor];
    return YES;
}
- (void)dragAt:(UIPanGestureRecognizer *)gesture {
    CGPoint p; if (![self pointerForGesture:gesture point:&p]) { [self releasePointer]; return; }
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) [self followTrackpadPointer:p];
    [self sendPointer:p mask:0];
}
- (void)holdAt:(UILongPressGestureRecognizer *)gesture {
    CGPoint p; if (![self pointerForGesture:gesture point:&p]) { [self releasePointer]; return; }
    BOOL held = gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged;
    if (held) [self followTrackpadPointer:p];
    self.lastPointer = p; self.pointerHeld = held; [self sendPointer:p mask:held ? 1 : 0];
    [[self feedbackForGesture:gesture] setDragging:held && self.foreground && !self.exited && !self.inputInactive && !self.restoreViewportPending && !self.checkingResume && self.session.connected];
}
- (void)pinchRemote:(UIPinchGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded) {
        if (self.magnificationActive) [self.session endMagnification];
        self.magnificationActive = NO; return;
    }
    if (gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed
        || !self.inputOnly || !self.foreground || self.exited || self.inputInactive || self.restoreViewportPending || self.checkingResume || !self.session.connected) {
        [self.session cancelNativeGestures]; self.magnificationActive = NO; return;
    }
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self releasePointer];
        if (CGRectIsNull(self.activeCrop) || CGRectIsEmpty(self.activeCrop)) return;
        CGPoint anchor = [self trackpadPointer];
        self.magnificationActive = [self.session beginMagnificationX:anchor.x y:anchor.y];
        if (!self.magnificationActive && !self.session.nativeMagnificationSupported) {
            self.status.hidden = NO; self.status.text = @"Native pinch is unavailable for this connection."; [self updateStatusPresentation];
        }
    }
    // UIPinch scale is relative to its last reset. Use incremental magnification,
    // keeping the Mac cursor anchor fixed and rejecting invalid recognizer values.
    double scale = gesture.scale; gesture.scale = 1;
    if (!self.magnificationActive) return;
    if (!isfinite(scale) || scale <= 0 || fabs(scale - 1) > .5
        || (scale != 1 && ![self.session changeMagnification:scale - 1])) {
        [self.session cancelNativeGestures]; self.magnificationActive = NO;
    }
}
- (void)scrollRemote:(UIPanGestureRecognizer *)gesture {
    BOOL ended = gesture.state == UIGestureRecognizerStateEnded;
    if (gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed
        || CGRectIsNull(self.activeCrop) || CGRectIsEmpty(self.activeCrop)
        || !self.foreground || self.exited || self.inputInactive || self.restoreViewportPending || self.checkingResume || !self.session.connected) {
        [self.session cancelNativeGestures]; self.scrollingActive = NO; self.scrollUsesNative = NO; self.scrollGestureActive = NO; self.scrollRemainder = 0; self.scrollFraction = CGPointZero; return;
    }
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self releasePointer]; self.scrollRemainder = 0; self.scrollFraction = CGPointZero; self.scrollGestureActive = YES;
        self.scrollUsesNative = self.session.nativeScrollingSupported;
        if (self.scrollUsesNative) {
            CGPoint anchor = [self trackpadPointer];
            self.scrollingActive = [self.session beginScrollX:anchor.x y:anchor.y];
        }
    }
    if (!self.scrollGestureActive) return;
    CGPoint delta = [gesture translationInView:gesture.view ?: self.canvas];
    [gesture setTranslation:CGPointZero inView:gesture.view ?: self.canvas];
    if (!isfinite(delta.x) || !isfinite(delta.y)) {
        [self.session cancelNativeGestures]; self.scrollingActive = NO; self.scrollGestureActive = NO; self.scrollRemainder = 0; self.scrollFraction = CGPointZero; return;
    }
    CGFloat speed = isfinite(self.scrollSpeed) ? MAX(.25, MIN(4, self.scrollSpeed)) : 1;
    if (self.scrollUsesNative) {
        // Mac point deltas, independent of local image zoom or Retina scale.
        // A single bounded packet carries the full two-axis update, not many ticks.
        double x = MAX(-2048, MIN(2048, delta.x * 3 * speed + self.scrollFraction.x));
        double y = MAX(-2048, MIN(2048, delta.y * 3 * speed + self.scrollFraction.y));
        double dx = round(x), dy = round(y);
        // CG point fields are whole points. Carry fractions to the next update
        // so slow movement is neither lost nor rounded up on every sample.
        self.scrollFraction = CGPointMake(x - dx, y - dy);
        if (self.scrollingActive && (dx != 0 || dy != 0) && ![self.session changeScrollX:dx y:dy]) {
            [self.session cancelNativeGestures]; self.scrollingActive = NO;
        }
        if (ended) { if (self.scrollingActive) [self.session endScroll]; self.scrollingActive = NO; self.scrollUsesNative = NO; self.scrollGestureActive = NO; }
        return;
    }
    // Unknown hosts keep standard RFB wheel input. Never guess an extension.
    self.scrollRemainder = MAX(-48, MIN(48, self.scrollRemainder + delta.y * speed));
    NSInteger steps = (NSInteger)(fabs(self.scrollRemainder) / 6);
    NSInteger mask = self.scrollRemainder > 0 ? 8 : 16;
    for (NSInteger i = 0; i < steps; i++) { CGPoint p = [self trackpadPointer]; [self sendPointer:p mask:mask]; [self sendPointer:p mask:0]; }
    self.scrollRemainder -= steps * 6 * (self.scrollRemainder > 0 ? 1 : -1);
    if (ended) { self.scrollRemainder = 0; self.scrollGestureActive = NO; }
}
- (void)sendPointer:(CGPoint)point mask:(NSInteger)mask {
    if (!self.foreground || self.exited || self.inputInactive || self.restoreViewportPending || self.checkingResume) return;
    if (!self.session.connected) return;
    [self recordLocalPointer:point]; [self updateCursor];
    [self.session pointerX:point.x y:point.y mask:mask];
}
- (void)followTrackpadPointer:(CGPoint)point {
    if (self.inputOnly || !self.followCursorEnabled || (!self.trackpadMode && !self.tabletop) || self.cursorFollowingSuspended
        || !self.foreground || self.exited || self.inputInactive || self.restoreViewportPending || self.checkingResume || !self.login.hidden
        || self.presentedViewController || self.canvas.dragging || self.canvas.decelerating || self.canvas.zooming
        || self.canvas.zoomScale <= self.canvas.minimumZoomScale * 1.01) return;
    CGPoint local = CGPointZero;
    if (!self.image.image || !CompanionVNCCursorLocalPoint(self.activeCrop, point, &local)) return;
    CGPoint anchor = [self.image convertPoint:local toView:self.canvas];
    CGRect visible = [self canvasViewportBounds];
    CGPoint offset = CompanionVNCFollowOffset(self.canvas.contentSize, visible, anchor);
    offset.x -= self.canvas.contentInset.left; offset.y -= self.canvas.contentInset.top;
    offset = [self clampedCanvasOffset:offset];
    if (CGPointEqualToPoint(offset, self.canvas.contentOffset)) return;
    self.smartZoomed = NO; self.smartZoomPending = NO; self.zoomGeneration++;
    // Gesture-paced offset updates avoid queued animations and idle timers.
    [self.canvas setContentOffset:offset animated:NO];
}
- (NSDictionary *)cursorDiagnosticFlags {
    return @{@"hostShapeAvailable": @(self.remoteCursorImage != nil), @"positionKnown": @(self.cursorPositionKnown),
        @"hostPositionKnown": @(self.hostCursorPositionKnown), @"localAimPinned": @(self.localAimPinned),
        @"singlePersistentCursor": @YES, @"localControlActive": @([self localPointerContactActive]),
        @"hostPositionsAdopted": @(self.hostPositionsAdopted), @"hostPositionsFiltered": @(self.hostPositionsFiltered),
        @"indicatorShown": @(!self.cursorIndicator.hidden && !self.cursorOverlay.hidden),
        @"usesFallback": @(!self.cursorIndicator.hidden && !self.cursorOverlay.hidden && self.remoteCursorImage == nil),
        @"foreground": @(self.foreground), @"inputInactive": @(self.inputInactive),
        @"checkingResume": @(self.checkingResume), @"restoringViewport": @(self.restoreViewportPending),
        @"controlMenuOpen": @(self.controls.menuOpen), @"modalPresented": @(self.presentedViewController != nil),
        @"pendingDisplayChange": @(self.pendingStreamDisplayID != nil || self.pendingDesktopSizePreset != 0),
        @"displaySelectionRejections": @(self.displaySelectionRejections), @"displaySelectionRejectMask": @(self.displaySelectionRejectMask)};
}
- (void)updateCursorDiagnostics {
    NSDictionary *flags = [self cursorDiagnosticFlags];
    if ([flags isEqual:self.diagnosticFlags]) return;
    self.diagnosticFlags = flags; [self scheduleCursorDiagnostics];
}
- (void)scheduleCursorDiagnostics {
    if (!self.diagnosticHandler || self.diagnosticScheduled) return;
    self.diagnosticScheduled = YES;
    NSUInteger generation = self.diagnosticGeneration;
    __weak CompanionVNCViewer *weak = self; __weak CompanionVNCSession *owner = self.session;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        CompanionVNCViewer *strong = weak;
        if (!strong || strong.session != owner || strong.diagnosticGeneration != generation) return;
        strong.diagnosticScheduled = NO;
        [strong reportDiagnostics:strong.latestCounters];
    });
}
- (void)invalidateCursorPosition {
    self.hostCursorPositionKnown = NO; [self updateCursor];
}
- (void)clearCursor {
    self.cursorPositionKnown = NO; self.hostCursorPositionKnown = NO; self.localAimPinned = NO;
    [self.localPointerTargets removeAllObjects]; self.hostPositionsAdopted = 0; self.hostPositionsFiltered = 0; self.lastLocalPointerInputAt = 0;
    self.remoteCursorImage = nil; self.cursorHotspot = CGPointZero;
    [self updateCursor];
}
// Wire coordinates are integral. Retain only bounded, ephemeral replay targets;
// neither these coordinates nor their history enter diagnostics or persistence.
- (NSValue *)pointerTargetKey:(CGPoint)point {
    return [NSValue valueWithCGPoint:CGPointMake((NSInteger)point.x,(NSInteger)point.y)];
}
- (void)rememberPointerTarget:(CGPoint)point {
    if (!isfinite(point.x) || !isfinite(point.y)) return;
    if (!self.localPointerTargets) self.localPointerTargets = [NSMutableOrderedSet new];
    NSValue *key = [self pointerTargetKey:point];
    [self.localPointerTargets removeObject:key]; [self.localPointerTargets addObject:key];
    if (self.localPointerTargets.count > 512) [self.localPointerTargets removeObjectAtIndex:0];
}
- (void)recordLocalPointer:(CGPoint)point {
    self.lastLocalPointerInputAt = NSProcessInfo.processInfo.systemUptime;
    if (self.cursorPositionKnown) [self rememberPointerTarget:self.cursorPosition];
    [self rememberPointerTarget:point];
    self.cursorPosition = point; self.cursorPositionKnown = YES; self.localAimPinned = YES;
}
- (BOOL)localPointerContactActive {
    return self.trackpadFeedback.hasTouches || self.tabletopFeedback.hasTouches
        || self.session.localPointerInteractionActive || self.pointerHeld;
}
- (void)receivedCursor:(UIImage *)image hotspot:(CGPoint)hotspot position:(CGPoint)position known:(BOOL)known {
    self.remoteCursorImage = image; self.cursorHotspot = hotspot;
    if (known) {
        self.hostCursorPosition = position; self.hostCursorPositionKnown = YES;
        BOOL echo = self.cursorPositionKnown && ![[self pointerTargetKey:position] isEqual:[self pointerTargetKey:self.cursorPosition]]
            && [self.localPointerTargets containsObject:[self pointerTargetKey:position]];
        BOOL ready = self.foreground && !self.exited && !self.inputInactive && !self.checkingResume
            && !self.restoreViewportPending && self.login.hidden && !self.recoveryController
            && !self.presentedViewController && !self.textReview;
        BOOL settled = self.lastLocalPointerInputAt <= 0 || NSProcessInfo.processInfo.systemUptime - self.lastLocalPointerInputAt >= .2;
        BOOL inView = !(self.trackpadMode || self.tabletop) || CGRectContainsPoint(self.activeCrop,position);
        BOOL seed = !self.localAimPinned && (!self.login.hidden || !self.lastFramebuffer)
            && self.foreground && !self.exited && !self.inputInactive;
        if (![self localPointerContactActive] && (seed || (ready && settled && inView && !echo))) {
            // One source of truth: rendering and the next click change together.
            // This is an observation heuristic, never an input acknowledgement.
            self.cursorPosition = position; self.cursorPositionKnown = YES; self.hostPositionsAdopted++;
        } else self.hostPositionsFiltered++;
    }
    [self updateCursor]; [self scheduleCursorDiagnostics];
}
- (void)updateCursor {
    BOOL ready = self.foreground && !self.exited && !self.inputInactive && !self.checkingResume
        && !self.restoreViewportPending && !self.inputOnly && self.login.hidden && !self.recoveryController && self.image.image;
    CGPoint local = CGPointZero;
    CGPoint position = self.cursorPosition;
    BOOL known = self.cursorPositionKnown;
    if (!ready || !known || !CompanionVNCCursorLocalPoint(self.activeCrop,position,&local)) {
        self.cursorIndicator.hidden = YES; [self.cursorIndicator.layer removeAllAnimations]; [self updateCursorDiagnostics]; return;
    }
    CGPoint anchor = [self.image convertPoint:local toView:self.cursorOverlay];
    UIImage *shape = self.remoteCursorImage;
    CGRect bounds = CompanionVNCCursorScreenRect(anchor, shape ? shape.size : CGSizeMake(20,28),
        shape ? self.cursorHotspot : CGPointMake(1,1), shape ? self.canvas.zoomScale : 1);
    self.cursorIndicator.hidden = CGRectIsNull(bounds) || !CGRectContainsPoint(self.cursorOverlay.bounds,anchor);
    if (self.cursorIndicator.hidden) { [self updateCursorDiagnostics]; return; }
    self.cursorIndicator.alpha = 1;
    self.cursorIndicator.frame = bounds; self.cursorImage.frame = self.cursorIndicator.bounds;
    self.cursorImage.image = shape; self.cursorImage.hidden = shape == nil; self.fallbackCursor.hidden = shape != nil;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    self.fallbackCursor.frame = self.cursorIndicator.bounds; [CATransaction commit];
    [self updateCursorDiagnostics];
}
- (void)pulseCursor {
    if (self.cursorIndicator.hidden || !self.showsTouchPoints || UIAccessibilityIsReduceMotionEnabled()) return;
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
    pulse.fromValue = @.5; pulse.toValue = @1; pulse.duration = .18;
    [self.cursorIndicator.layer addAnimation:pulse forKey:@"local-click"];
}
- (void)cancelTapRecognizer:(UIGestureRecognizer *)recognizer {
    BOOL enabled = recognizer.enabled; recognizer.enabled = NO; recognizer.enabled = enabled;
}
- (void)cancelPendingTaps {
    [self cancelTapRecognizer:self.secondaryTap]; [self cancelTapRecognizer:self.smartTap];
    [self cancelTapRecognizer:self.tabletopSecondaryTap];
}
- (void)releasePointer {
    self.session.localPointerInteractionActive = NO;
    [self cancelPendingTaps];
    [self.trackpadFeedback setDragging:NO]; [self.tabletopFeedback setDragging:NO];
    [self.session cancelNativeGestures]; self.magnificationActive = NO;
    self.scrollingActive = NO; self.scrollUsesNative = NO; self.scrollGestureActive = NO; self.scrollRemainder = 0; self.scrollFraction = CGPointZero;
    if (self.pointerHeld) [self.session pointerX:self.lastPointer.x y:self.lastPointer.y mask:0];
    self.pointerHeld = NO;
}
- (void)smartZoom:(UITapGestureRecognizer *)gesture { [self smartZoomAt:[gesture locationInView:self.image]]; }
- (void)smartZoomAt:(CGPoint)point {
    if (self.smartZoomed || self.smartZoomPending || self.canvas.zoomScale > self.canvas.minimumZoomScale * 1.01) { [self fitDesktop]; return; }
    CGPoint remote = CGPointZero;
    if (!CompanionVNCPointerPoint(self.activeCrop, point, false, &remote)) return;
    NSUInteger generation = ++self.zoomGeneration; CGSize pixels = self.framebufferSize;
    self.smartZoomPending = YES;
    __weak CompanionVNCViewer *weak = self;
    void (^reply)(CGRect) = ^(CGRect window) {
        CompanionVNCViewer *strong = weak;
        if (!strong || generation != strong.zoomGeneration || !CGSizeEqualToSize(pixels, strong.framebufferSize)) return;
        strong.smartZoomPending = NO;
        CGRect local = CompanionVNCWindowInCrop(strong.activeCrop, window);
        CGFloat windowZoom = CGRectIsNull(local) ? 0 : MIN(strong.canvas.bounds.size.width / local.size.width, strong.canvas.bounds.size.height / local.size.height);
        if (windowZoom <= strong.canvas.minimumZoomScale * 1.01) {
            local = CompanionVNCSmartZoomRect(strong.activeCrop.size, strong.canvas.bounds.size, point,
                strong.canvas.minimumZoomScale, strong.canvas.maximumZoomScale);
        }
        if (CGRectIsNull(local)) return;
        strong.smartZoomed = YES; strong.smartWindow = local;
        [strong.canvas zoomToRect:local animated:YES];
    };
    if (self.windowBoundsHandler) self.windowBoundsHandler(remote, pixels, reply);
    else reply(CGRectNull);
}
- (void)updateKeyboardButton {
    BOOL active = self.input.isFirstResponder;
    UIImage *symbol = [UIImage systemImageNamed:active ? @"keyboard.chevron.compact.down" : @"keyboard"];
    [self.keyboardButton setImage:symbol forState:UIControlStateNormal];
    self.keyboardButton.accessibilityLabel = active ? @"Hide Keyboard" : @"Show Keyboard";
    self.keyboardButton.accessibilityHint = active ? @"Dismiss the keyboard and restore the desktop view." : @"Open the keyboard to type on your Mac.";
}
- (void)keyboard { [self toggleKeyboardWithFeedback:YES]; }
- (void)toggleKeyboardWithFeedback:(BOOL)feedback {
    if (self.textReview) return;
    BOOL before = self.input.isFirstResponder;
    if (before) [self.input resignFirstResponder]; else [self.input becomeFirstResponder];
    [self updateKeyboardButton];
    if (feedback && before != self.input.isFirstResponder) [self.keyFeedback feedback:@"selection"];
}
- (void)textViewDidBeginEditing:(UITextView *)textView { if (textView == self.input) [self updateKeyboardButton]; }
- (void)textViewDidEndEditing:(UITextView *)textView { if (textView == self.input) [self updateKeyboardButton]; }
- (void)keyboardFrame:(NSNotification *)notification {
    if (self.textReview) return;
    if (!self.view.window) return;
    [self.view layoutIfNeeded];
    CGRect keyboard = [self.view convertRect:[notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    CGRect intersection = CGRectIntersection(self.view.bounds, keyboard);
    BOOL docked = !CGRectIsNull(intersection) && !CGRectIsEmpty(intersection)
        && CGRectGetMaxY(keyboard) >= CGRectGetMaxY(self.view.bounds) - 1 && intersection.size.width >= self.view.bounds.size.width * .8;
    CGFloat overlap = docked ? MAX(0, intersection.size.height - self.view.safeAreaInsets.bottom) : 0;
    BOOL valid = self.login.hidden && !CGRectIsNull(self.activeCrop) && !CGRectIsEmpty(self.activeCrop) && self.canvas.minimumZoomScale > 0;
    if (valid && overlap != self.keyboardOverlap) {
        CGFloat ratio = self.canvas.zoomScale / self.canvas.minimumZoomScale; CGPoint center = [self viewportCenter];
        if (overlap > 0 && self.keyboardOverlap == 0) {
            self.keyboardViewportSaved = YES; self.keyboardSavedCrop = self.activeCrop;
            self.keyboardSavedRatio = ratio; self.keyboardSavedCenter = center;
        } else if (overlap == 0 && self.keyboardViewportSaved) {
            if (CGRectEqualToRect(self.keyboardSavedCrop, self.activeCrop)) { ratio = self.keyboardSavedRatio; center = self.keyboardSavedCenter; }
            self.keyboardViewportSaved = NO;
        }
        self.keyboardLayoutPending = YES; self.keyboardLayoutRatio = ratio; self.keyboardLayoutCenter = center;
    }
    self.keyboardOverlap = overlap;
    self.canvasFullscreenBottom.constant = -overlap;
    self.toolbarBottom.constant = -4 - overlap; self.controls.bottomInset = 4 + overlap; [self.controls setNeedsLayout];
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions curve = (UIViewAnimationOptions)[notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue] << 16;
    [UIView animateWithDuration:duration delay:0 options:curve | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{ [self.view layoutIfNeeded]; } completion:nil];
    [self updateKeyboardButton];
}
- (void)textViewDidChange:(UITextView *)textView {
    if (textView.markedTextRange || !textView.text.length) return;
    [self.remoteKeyboard text:textView.text]; textView.text = @""; [self refreshModifiers];
}
- (void)sendRemoteKey:(uint32_t)key {
    [self.remoteKeyboard pressKey:key]; [self refreshModifiers];
}
- (void)prepareKeyFeedback { [self.keyFeedback prepareKeyFeedback]; }
- (void)singleModifier:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    [self.remoteKeyboard pressModifierAlone:(uint32_t)gesture.view.tag];
    [self.keyFeedback feedback:@"selection"]; [self refreshModifiers];
}
- (void)remoteKey:(UIButton *)button {
    if ([self.modifiers containsObject:button]) {
        [self.remoteKeyboard toggleModifier:(uint32_t)button.tag];
        [self.keyFeedback feedback:@"selection"]; [self refreshModifiers];
    } else {
        [self.keyFeedback feedback:@"key"]; [self sendRemoteKey:(uint32_t)button.tag];
    }
}
- (void)moreKeys:(UIButton *)button {
    if (![self sessionKeyInputAvailable]) return;
    [self presentMenu:@"Extra Keys" sections:@[
        @{@"title": @"Editing", @"items": @[
            @{@"kind": @"key", @"title": @"Return", @"symbol": @"return", @"key": @0xff0d},
            @{@"kind": @"key", @"title": @"Backspace", @"symbol": @"delete.left", @"key": @0xff08},
            @{@"kind": @"key", @"title": @"Forward Delete", @"symbol": @"delete.right", @"key": @0xffff}]},
        @{@"title": @"Navigation", @"items": @[
            @{@"kind": @"key", @"title": @"Up", @"symbol": @"arrow.up", @"key": @0xff52},
            @{@"kind": @"key", @"title": @"Down", @"symbol": @"arrow.down", @"key": @0xff54},
            @{@"kind": @"key", @"title": @"Left", @"symbol": @"arrow.left", @"key": @0xff51},
            @{@"kind": @"key", @"title": @"Right", @"symbol": @"arrow.right", @"key": @0xff53},
            @{@"kind": @"key", @"title": @"Home", @"symbol": @"arrow.up.to.line", @"key": @0xff50},
            @{@"kind": @"key", @"title": @"End", @"symbol": @"arrow.down.to.line", @"key": @0xff57},
            @{@"kind": @"key", @"title": @"Page Up", @"symbol": @"chevron.up.2", @"key": @0xff55},
            @{@"kind": @"key", @"title": @"Page Down", @"symbol": @"chevron.down.2", @"key": @0xff56}]},
        @{@"title": @"Special Keys", @"items": @[
            @{@"kind": @"functionKeys", @"title": @"Function Keys", @"symbol": @"fn", @"submenu": @YES, @"push": @YES},
            @{@"kind": @"modifier", @"title": @"Send Shift Alone", @"symbol": @"shift", @"key": @0xffe1},
            @{@"kind": @"modifier", @"title": @"Send Control Alone", @"symbol": @"control", @"key": @0xffe3},
            @{@"kind": @"modifier", @"title": @"Send Option Alone", @"symbol": @"option", @"key": @0xffe9},
            @{@"kind": @"modifier", @"title": @"Send Command Alone", @"symbol": @"command", @"key": @0xffeb}]}]];
}
- (void)showFunctionKeys {
    if (![self sessionKeyInputAvailable]) return;
    NSMutableArray *items = [NSMutableArray new];
    for (NSUInteger i = 0; i < 12; i++) [items addObject:@{@"kind": @"key", @"title": [NSString stringWithFormat:@"F%lu", (unsigned long)i+1], @"key": @(0xffbe + i), @"symbol": @"keyboard"}];
    [self presentMenu:@"Function Keys" sections:@[@{@"title": @"F1–F12", @"items": items}]];
}
- (void)setQuickActions:(NSArray<NSDictionary *> *)quickActions {
    _quickActions = [quickActions copy];
    self.controls.quickActions = quickActions ?: [DirectConnectionBridge defaultQuickActionsForInputOnly:self.inputOnly];
}
- (void)updateConnectionChrome {
    if (self.sessionMenu && ![self sessionKeyInputAvailable]) [self retireSessionMenu];
    self.loginSubtitle.text = self.inputOnly ? @"Trackpad & Keyboard" : @"Screen Sharing";
    self.loginPurpose.hidden = self.inputOnly;
    self.loginSubtitle.accessibilityHint = self.inputOnly ? @"Control this Mac without video" : @"View and control this Mac";
    self.loginIcon.image = [UIImage systemImageNamed:self.inputOnly ? @"rectangle.and.hand.point.up.left" : @"desktopcomputer"];
    BOOL progress = self.starting || (self.session.running && !self.lastFramebuffer);
    BOOL loginVisible = !self.login.hidden;
    BOOL immersive = !loginVisible && !self.inputOnly;
    self.view.backgroundColor = loginVisible && self.connectionPanelHost ? UIColor.clearColor : immersive ? UIColor.blackColor : UIColor.systemBackgroundColor;
    self.overrideUserInterfaceStyle = immersive ? UIUserInterfaceStyleDark : UIUserInterfaceStyleUnspecified;
    if (self.immersiveChrome != immersive) {
        self.immersiveChrome = immersive;
        [self setContentScrollView:immersive ? self.canvas : nil forEdge:NSDirectionalRectEdgeTop];
        [self.view setNeedsLayout];
        [self setNeedsStatusBarAppearanceUpdate];
        if (self.chromeHandler) self.chromeHandler(immersive);
    }
    BOOL visibilityChanged = self.loginScroll.hidden == loginVisible;
    void (^showChrome)(void) = ^{
        self.loginScroll.hidden = !loginVisible;
        self.loginBackdrop.view.hidden = self.connectionPanelHost || !loginVisible;
        self.canvas.hidden = loginVisible;
        self.cursorOverlay.hidden = loginVisible || self.inputOnly;
    };
    if (visibilityChanged && self.view.window && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView transitionWithView:self.view duration:.18 options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction animations:showChrome completion:nil];
    } else { showChrome(); }
    if (self.connectionPanelHost) {
        if (loginVisible) {
            __weak typeof(self) weak = self;
            UIViewController *content = self.loginPanelContent;
            if (progress) {
                self.loginProgressContent = [DirectConnectionBridge updateProgress:self.loginProgressContent name:self.macName ?: @"Mac" inputOnly:self.inputOnly desktopSize:self.changingDisplayMode ? self.modeTargetPreset : self.restoredDesktopSizePreset message:self.mirrorFullRestartUsed ? @"Switching display mode…" : @"Connecting…" progress:self.connectionProgress addresses:self.connectionAddresses ?: @[] sshPort:self.sshPort ?: 22 screenSharingPort:self.servicePort ?: 5900 cancel:^{ [weak showMacs]; } heightChanged:^(CGFloat height) {
                    if (weak.starting || (weak.session.running && !weak.lastFramebuffer)) {
                        weak.loginProgressHeight = height;
                        [weak.connectionPanelHost setContentHeight:height owner:weak.loginPanelOwner];
                    }
                }];
                content = self.loginProgressContent;
            }
            [self.connectionPanelHost showContent:content owner:self.loginPanelOwner cancel:^{ [weak showMacs]; }];
            [self.connectionPanelHost setDismissalLocked:progress owner:self.loginPanelOwner];
            if (progress) [self.connectionPanelHost setContentHeight:self.loginProgressHeight > 0 ? self.loginProgressHeight : 240 owner:self.loginPanelOwner];
        } else [self.connectionPanelHost hideOwner:self.loginPanelOwner];
    }
    [self updateTrackpadFeedback];
    // Keep the fields mounted so editing retains identity, but give an active
    // attempt one progress indicator and Cancel instead of disabled form chrome.
    self.loginPurpose.hidden = progress || self.inputOnly;
    self.loginFields.hidden = progress;
    self.loginFields.userInteractionEnabled = !progress;
    self.loginDetails.hidden = progress || !self.loginIssueDetails.length;
    self.loginDetailsText.text = self.loginIssueDetails.length ? [NSString stringWithFormat:@"%@\n\n%@", [self configuredConnectionDetails], self.loginIssueDetails] : [self configuredConnectionDetails];
    self.loginDetailsText.hidden = self.loginDetails.hidden || !self.loginDetailsExpanded;
    self.loginDetails.imageView.transform = CGAffineTransformMakeRotation(self.loginDetailsExpanded ? -M_PI : 0);
    self.loginDetails.accessibilityValue = self.loginDetailsExpanded ? @"Expanded" : @"Collapsed";
    self.connect.hidden = progress;
    self.loginClose.hidden = YES; self.loginCancel.hidden = NO;
    // Input-only is a recovery action, never a competing action during normal progress.
    self.loginTrackpad.hidden = YES;
    self.loginTrackpad.enabled = self.connectionForegroundAvailable;
    BOOL canRetryMode = self.failedDisplayModePreset != nil && [self.credentialState loginForResume] != nil;
    self.connect.enabled = !progress && ((self.username.text.length > 0 && self.password.text.length > 0) || canRetryMode);
    self.connect.alpha = 1;
    self.connect.backgroundColor = self.connect.enabled ? UIColor.systemBlueColor : UIColor.tertiarySystemFillColor;
    [self.connect setTitleColor:self.connect.enabled ? UIColor.whiteColor : UIColor.secondaryLabelColor forState:UIControlStateNormal];
    [self.connect setTitleColor:UIColor.secondaryLabelColor forState:UIControlStateDisabled];
    [self.connect setTitle:self.failedDisplayModePreset ? @"Reconnect" : self.recoveryController ? @"Try Again" : @"Connect" forState:UIControlStateNormal];
    self.progressRow.hidden = !progress && !self.progressLabel.text.length; self.spinner.hidden = !progress;
    // Let validation feedback fill the card width and grow vertically. A
    // hidden spinner in a horizontal stack can retain a one-line label height.
    self.progressRow.axis = UILayoutConstraintAxisVertical;
    if (progress) [self.spinner startAnimating]; else [self.spinner stopAnimating];
    if (self.connectionPanelHost && loginVisible && !progress) {
        CGFloat width = MIN(520, MAX(0, self.loginPanelContent.view.bounds.size.width - 32));
        if (width > 0) {
            CGSize fitting = [self.login systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
            CGSize footer = [self.loginActions systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
            [self.connectionPanelHost setContentHeight:ceil(fitting.height + footer.height + 16) owner:self.loginPanelOwner];
        }
    }
    self.controls.hidden = !self.loginScroll.hidden;
    self.toolbar.hidden = !self.loginScroll.hidden || self.fullscreen || self.recoveryPanel != nil;
    self.trackpadHelp.hidden = !self.loginScroll.hidden || !self.inputOnly;
    if (!self.loginScroll.hidden || (self.session.connected && !self.changingDisplayMode && !self.checkingResume && !self.restoreViewportPending && NSProcessInfo.processInfo.systemUptime >= self.displayNoticeUntil)) self.status.hidden = YES;
    [self updateStatusPresentation];
    [self.view setNeedsLayout];
}
- (void)setFullscreen:(BOOL)value {
    _fullscreen = value; if (self.isViewLoaded) [self applyPresentation];
    if (self.presentationHandler) self.presentationHandler(value);
}
- (void)setInputOnly:(BOOL)value {
    BOOL replacingDisplay = self.failedDisplayModePreset != nil || self.changingDisplayMode || self.restoreViewportPending
        || self.pendingDesktopSizePreset || self.pendingStreamDisplayID || (!self.session.running && self.recoveryController);
    if (value && !_inputOnly && self.isViewLoaded && replacingDisplay) {
        if (self.filesTransferActiveHandler && self.filesTransferActiveHandler()) {
            if (!self.presentedViewController) {
                UIAlertController *alert = [self inputOnlyConfirmation];
                if (alert) [self presentViewController:alert animated:YES completion:nil];
            }
        } else [self restartInputOnlyConnection];
        return;
    }
    if (!value && (self.restoreViewportPending || (_inputOnly && (self.starting || self.checkingResume)))) return;
    if (self.session.established) {
        self.session.inputOnly = value;
        // Geometry can change between drawing the menu and selecting its action.
        // Reflect the native owner's admission rather than leaving UI and mode apart.
        if (self.session.inputOnly != value) {
            self.status.text = @"Screen Sharing is unavailable at this desktop size. Trackpad & Keyboard stays connected.";
            self.status.hidden = NO; [self updateStatusPresentation]; return;
        }
    }
    if (_inputOnly != value) { [self retireTextDraft]; self.textComposer = nil; }
    _inputOnly = value;
    if (self.quickActionsProvider) self.quickActions = self.quickActionsProvider(value);
    else if (!self.quickActions) self.controls.quickActions = [DirectConnectionBridge defaultQuickActionsForInputOnly:value];
    if (self.isViewLoaded) {
        [self releasePointer]; [self cancelTrackpadTouches]; [self resetModifiers];
        if (value) [self setTrackpadModeEnabled:YES];
        [self applyPresentation];
    }
}
- (void)useInputOnlyConnection {
    if (self.connectionForegroundAvailable && self.starting && self.changingDisplayMode && !self.inputOnly) self.inputOnly = YES;
}
- (void)restartInputOnlyConnection {
    if (!self.connectionForegroundAvailable || self.textReview) return;
    BOOL resumeLogin = [self.credentialState loginForResume] != nil;
    if (self.changingDisplayMode) self.restoredDesktopSizePreset = self.modePreviousPreset;
    [self cancelDisplayModeConfirmation];
    [self retireDisplayModeOwner];
    self.changingDisplayMode = self.mirrorRestartScheduled = self.mirrorRequiresCleanup = self.mirrorFullRestartUsed = NO;
    self.failedDisplayModePreset = nil; self.pendingDesktopSizePreset = self.lateDesktopSizePreset = 0; self.pendingStreamDisplayID = nil;
    self.mirrorCleanupRemaining = 0; self.modeVerificationTimed = NO; self.modeVerificationGeneration++;
    self.checkingResume = self.reconnectWhenReady = self.restoreViewportPending = self.awaitingReplacementLayout = NO;
    self.resumeGeneration++; self.statusGeneration++; self.pendingRestorationFrame = nil; self.resumeDisplayID = nil;
    [self discardInputOnlyPresentation];
    [self clearRecovery]; self.login.hidden = NO;
    self.inputOnly = YES;
    [self startResuming:resumeLogin];
}
- (void)discardInputOnlyPresentation {
    self.restoreViewportPending = self.awaitingReplacementLayout = NO;
    self.pendingRestorationFrame = nil; self.resumeDisplayID = nil;
    self.lastFramebuffer = nil; self.image.image = nil; self.framebufferSize = CGSizeZero; self.activeCrop = CGRectNull;
    self.selectedDisplay = nil; self.displayViews = @[]; self.displayLayout = nil; self.displayAspect = 0;
}
- (void)updateInputOnlyGeometry {
    NSDictionary *stats = self.session.diagnosticCounters;
    NSInteger width = [stats[@"framebufferWidth"] integerValue], height = [stats[@"framebufferHeight"] integerValue];
    if (!self.inputOnly || !self.session.established || !CompanionVNCInputGeometryValid(width,height)) return;
    CGSize size = CGSizeMake(width,height);
    if (!CGSizeEqualToSize(self.framebufferSize,size) || CGRectIsNull(self.activeCrop) || CGRectIsEmpty(self.activeCrop)) {
        [self cancelTrackpadTouches]; [self releasePointer]; [self invalidateCursorPosition];
        self.framebufferSize = size; self.activeCrop = (CGRect){CGPointZero,size};
    }
}
- (void)applyPresentation {
    if (!self.canvasToolbarBottom) return;
    CGFloat ratio = self.canvas.minimumZoomScale > 0 ? self.canvas.zoomScale / self.canvas.minimumZoomScale : 1;
    CGPoint center = [self viewportCenter];
    self.canvasToolbarBottom.active = !self.tabletop && !self.fullscreen; self.canvasFullscreenBottom.active = !self.tabletop && self.fullscreen;
    self.image.hidden = self.inputOnly; self.cursorOverlay.hidden = self.inputOnly;
    self.canvas.pinchGestureRecognizer.enabled = !self.inputOnly;
    self.remotePinch.enabled = self.inputOnly; self.smartTap.enabled = !self.inputOnly;
    self.canvas.backgroundColor = self.inputOnly ? UIColor.systemBackgroundColor : UIColor.blackColor;
    self.trackpadHelp.hidden = !self.inputOnly || !self.login.hidden;
    self.controls.fullscreen = self.fullscreen; self.controls.inputOnly = self.inputOnly;
    self.keyboardLayoutPending = YES; self.keyboardLayoutRatio = ratio; self.keyboardLayoutCenter = center;
    [self updateConnectionChrome]; [self.view setNeedsLayout];
}
- (void)togglePassword {
    self.password.secureTextEntry = !self.password.secureTextEntry;
    [self.passwordVisibility setImage:[UIImage systemImageNamed:self.password.secureTextEntry ? @"eye" : @"eye.slash"] forState:UIControlStateNormal];
    self.passwordVisibility.accessibilityLabel = self.password.secureTextEntry ? @"Show Password" : @"Hide Password";
}
- (void)restoreSavedDisplay {
    if (self.initialDisplayApplied || !self.restoredDisplayID || !self.displayViews.count || self.framebufferSize.height <= 0 || self.displayAspect <= 0) return;
    CGFloat aspect = self.framebufferSize.width / self.framebufferSize.height;
    if (fabs(aspect - self.displayAspect) / self.displayAspect >= .03) return;
    self.initialDisplayApplied = YES;
    NSDictionary *selected = nil;
    for (NSDictionary *d in self.displayViews) if ([d[@"id"] isEqual:self.restoredDisplayID]) { selected = d; break; }
    if ([self.session.desktopDisplayLayout[@"views"] count] && self.restoredDesktopSizePreset == 0) {
        // Retry admission after the first usable frame, not before authentication.
        if (!self.session.desktopSizeAvailable) { self.initialDisplayApplied = NO; return; }
        if (selected && ![self applyStreamDisplay:selected[@"id"]]) { self.initialDisplayApplied = NO; return; }
    } else [self selectDisplay:selected];
    self.restoredDisplayID = nil;
}
- (void)performControlAction:(NSDictionary *)action {
    NSString *kind = action[@"kind"];
    BOOL feedback = ![action[@"interfaceFeedbackHandled"] boolValue];
    if (self.textReview) return;
    if ([kind isEqual:@"copyText"]) { [self showCopyScreenText]; return; }
    if ([kind isEqual:@"viewMenu"]) { [self showViewMenu]; return; }
    if ([kind isEqual:@"desktopSizeMenu"]) { [self showDesktopSizeMenu]; return; }
    if ([kind isEqual:@"mirrorDisplay"]) { [self confirmDisplayModePreset:0]; return; }
    if ([kind isEqual:@"virtualDisplay"]) { [self confirmDisplayModePreset:self.restoredDesktopSizePreset > 0 ? self.restoredDesktopSizePreset : 2]; return; }
    if ([kind isEqual:@"desktopSize"]) {
        NSInteger preset = [action[@"preset"] integerValue];
        BOOL changed = ![self desktopSizeMatchesPreset:preset];
        if ([self applyDesktopSizePreset:preset] && changed && feedback) [self.keyFeedback feedback:@"selection"];
        return;
    }
    if ([kind isEqual:@"inputMenu"]) { [self showInputMenu]; return; }
    if ([kind isEqual:@"files"]) { if (self.filesHandler) self.filesHandler(); return; }
    if ([kind isEqual:@"composeText"]) { [self showTextComposer]; return; }
    if ([kind isEqual:@"appSettings"]) { if (self.appSettingsHandler) self.appSettingsHandler(); return; }
    if ([kind isEqual:@"exit"]) { [self showMacs]; return; }
    if ([kind isEqual:@"details"]) { [self showConnectionDetails]; return; }
    if ([kind isEqual:@"setPointer"] || [kind isEqual:@"setTrackpad"] || [kind isEqual:@"mode"]) {
        BOOL before = self.trackpadMode;
        if ([kind isEqual:@"setTrackpad"]) [self setTrackpadModeEnabled:YES];
        else if (!self.inputOnly) [self setTrackpadModeEnabled:[kind isEqual:@"mode"] ? !before : NO];
        if (feedback && before != self.trackpadMode) [self.keyFeedback feedback:@"selection"];
        return;
    }
    if ([kind isEqual:@"functionKeys"]) { [self showFunctionKeys]; return; }
    if ([kind isEqual:@"fullscreen"]) {
        self.fullscreen = !self.fullscreen;
        if (feedback) [self.keyFeedback feedback:@"selection"];
        return;
    }
    if ([kind isEqual:@"inputOnly"]) {
        BOOL before = self.inputOnly;
        if (self.connectionForegroundAvailable) self.inputOnly = !before;
        if (feedback && before != self.inputOnly) [self.keyFeedback feedback:@"selection"];
        return;
    }
    if ([kind isEqual:@"keyboard"]) { [self toggleKeyboardWithFeedback:feedback]; return; }
    if ([kind isEqual:@"displays"]) { [self chooseView]; return; }
    if ([kind isEqual:@"input"]) { if (self.settingsHandler) self.settingsHandler(); return; }
    if ([kind isEqual:@"fit"]) { [self fitDesktop]; return; }
    if ([kind isEqual:@"keys"]) { [self moreKeys:self.views]; return; }
    if ([kind isEqual:@"session"]) { [self showSessionMenu]; return; }
    if (![self sessionKeyInputAvailable]) {
        self.status.hidden = NO; self.status.text = @"Wait for the desktop to resume before sending input."; [self updateStatusPresentation]; return;
    }
    // Local admission is immediate; do not wait for a transport or Mac reply.
    BOOL menuFeedback = feedback && [action[@"menuFeedback"] boolValue];
    if (menuFeedback && [@[@"key", @"escape", @"tab", @"returnKey"] containsObject:kind]) [self.keyFeedback feedback:@"key"];
    else if (menuFeedback && [kind isEqual:@"modifier"]) [self.keyFeedback feedback:@"selection"];
    if ([kind isEqual:@"escape"]) { [self sendRemoteKey:0xff1b]; return; }
    if ([kind isEqual:@"tab"]) { [self sendRemoteKey:0xff09]; return; }
    if ([kind isEqual:@"returnKey"]) { [self sendRemoteKey:0xff0d]; return; }
    if ([kind isEqual:@"key"]) { [self sendRemoteKey:[action[@"key"] unsignedIntValue]]; return; }
    if ([kind isEqual:@"modifier"]) { [self.remoteKeyboard pressModifierAlone:[action[@"key"] unsignedIntValue]]; [self refreshModifiers]; return; }
    if ([kind isEqual:@"rightClick"]) {
        CGPoint p = [self trackpadPointer]; [self clickPointer:p mask:4];
    } else if ([kind isEqual:@"shortcut"] || [kind isEqual:@"text"]) {
        if (self.quickActionsProvider) {
            NSArray *current = self.quickActionsProvider(self.inputOnly);
            BOOL available = NO;
            for (NSDictionary *saved in current) if ([saved[@"id"] isEqual:action[@"id"]] && [saved[@"enabled"] boolValue]) { available = YES; break; }
            if (!available) return;
        }
        [self resetModifiers];
        NSMutableArray *events = [NSMutableArray new];
        CompanionVNCKeyboard *keyboard = [[CompanionVNCKeyboard alloc] initWithEvents:^(NSArray *group) { [events addObjectsFromArray:group]; }];
        if ([kind isEqual:@"shortcut"]) {
            for (NSNumber *modifier in action[@"modifiers"]) [keyboard toggleModifier:modifier.unsignedIntValue];
            [keyboard pressKey:[action[@"key"] unsignedIntValue]];
        } else [keyboard text:action[@"text"] ?: @""];
        if (![self.session tryKeyEvents:events]) {
            self.status.hidden = NO; self.status.text = @"Input is busy. Try the action again."; [self updateStatusPresentation];
        } else if (menuFeedback) [self.keyFeedback feedback:@"key"];
        [self refreshModifiers];
    }
}
- (BOOL)sessionKeyInputAvailable {
    return self.foreground && !self.exited && !self.inputInactive && !self.restoreViewportPending
        && !self.checkingResume && !self.textReview && self.session.connected;
}
- (void)retireSessionMenu {
    self.sessionMenuGeneration++;
    UINavigationController *menu = self.sessionMenu; self.sessionMenu = nil;
    if (!menu) return;
    menu.view.userInteractionEnabled = NO;
    for (UIViewController *controller in menu.viewControllers) {
        if ([controller isKindOfClass:CompanionVNCMenu.class]) ((CompanionVNCMenu *)controller).selectionHandler = nil;
        else if ([controller isKindOfClass:CompanionVNCDisplayPicker.class]) ((CompanionVNCDisplayPicker *)controller).selectionHandler = nil;
    }
    // A presentation in progress is dismissed by its completion below.
    if (menu.presentingViewController && !menu.isBeingPresented) [menu dismissViewControllerAnimated:NO completion:nil];
}
- (void)presentMenu:(NSString *)title sections:(NSArray<NSDictionary *> *)sections {
    UINavigationController *navigation = [self.presentedViewController isKindOfClass:UINavigationController.class] ? (id)self.presentedViewController : nil;
    BOOL push = [navigation.topViewController isKindOfClass:CompanionVNCMenu.class];
    if (self.presentedViewController && !push) return;
    if (!push) self.sessionMenuGeneration++;
    NSUInteger generation = self.sessionMenuGeneration;
    CompanionVNCMenu *picker = [CompanionVNCMenu new]; picker.title = title; picker.sections = sections;
    __weak CompanionVNCViewer *weak = self;
    __weak CompanionVNCSession *owner = self.session;
    picker.selectionHandler = ^(NSDictionary *item) {
        CompanionVNCViewer *strong = weak;
        // Dismissal is asynchronous. A copied callback must not reach a retired
        // connection or become usable again after a pause and resume.
        if (!strong || !owner || strong.session != owner || strong.sessionMenuGeneration != generation
            || ![strong sessionKeyInputAvailable]) return;
        NSMutableDictionary *action = item.mutableCopy; action[@"menuFeedback"] = @YES;
        [strong performControlAction:action];
    };
    if (push) {
        self.sessionMenu = navigation;
        [navigation pushViewController:picker animated:YES]; return;
    }
    UINavigationController *menu = [CompanionVNCMenu navigationControllerForMenu:picker sourceView:self.views];
    self.sessionMenu = menu;
    __weak UINavigationController *weakMenu = menu;
    [self presentViewController:menu animated:YES completion:^{
        if (weak.sessionMenu != weakMenu || weak.sessionMenuGeneration != generation)
            [weakMenu dismissViewControllerAnimated:NO completion:nil];
    }];
}
- (BOOL)canCopyScreenText {
    return self.foreground && !self.exited && !self.inputInactive && !self.changingDisplayMode && !self.restoreViewportPending && !self.checkingResume && !self.inputOnly && !self.textReview
        && self.session.desktopFrameReady && self.lastFramebuffer && !CGRectIsNull(self.activeCrop)
        && !CGRectIsEmpty(self.activeCrop) && self.activeCrop.size.width*self.activeCrop.size.height <= 32*1024*1024;
}
- (void)showCopyScreenText {
    if (![self canCopyScreenText] || self.presentedViewController) return;
    CGRect visible = [self.image convertRect:[self canvasViewportBounds] fromView:self.canvas];
    CGImageRef image = CGImageCreateWithImageInRect(self.lastFramebuffer.CGImage,self.activeCrop);
    if (!image) return;
    CompanionVNCTextReview *review = [[CompanionVNCTextReview alloc] initWithImage:[UIImage imageWithCGImage:image] visibleRect:visible];
    CGImageRelease(image);
    self.textReviewCrop=self.activeCrop; self.textReviewFramebuffer=self.framebufferSize;
    self.textReviewZoom=self.canvas.minimumZoomScale > 0 ? self.canvas.zoomScale/self.canvas.minimumZoomScale : 1;
    self.textReviewCenter=[self viewportCenter];
    [self releasePointer]; [self resetModifiers]; [self cancelTrackpadTouches]; [self.view endEditing:YES]; [self.loginScroll endEditing:YES];
    self.zoomGeneration++; self.smartZoomPending=NO;
    self.textReview=review; NSUInteger token=++self.textReviewGeneration;
    CompanionVNCSession *owner=self.session; __weak CompanionVNCViewer *weak=self;
    __weak CompanionVNCTextReview *weakReview=review;
    review.returnHandler=^{
        if (weak.session==owner && weak.textReview==weakReview && weak.textReviewGeneration==token) [weak invalidateTextReview:YES];
    };
    BOOL suspended=[owner suspendInputForReview:^{
        CompanionVNCViewer *strong=weak;
        if (!strong || strong.session!=owner || strong.textReview!=review || strong.textReviewGeneration!=token
            || !strong.foreground || strong.exited || !owner.established) return;
        if (strong.view.window) {
            if (strong.navigationController) [strong.navigationController pushViewController:review animated:!UIAccessibilityIsReduceMotionEnabled()];
            else [strong presentViewController:review animated:!UIAccessibilityIsReduceMotionEnabled() completion:nil];
        }
    }];
    if (!suspended) [self invalidateTextReview:NO];
}
- (void)invalidateTextReview:(BOOL)resume {
    CompanionVNCTextReview *review=self.textReview;
    self.textReviewGeneration++; self.textReview=nil;
    if (!review) return;
    [review invalidate];
    // Keyboard notifications from the local editor were deliberately isolated.
    // Retire any inset left by the remote keyboard before returning to desktop.
    self.keyboardOverlap=0; self.keyboardViewportSaved=NO; self.keyboardLayoutPending=NO;
    self.canvasFullscreenBottom.constant=0; self.toolbarBottom.constant=-4;
    self.controls.bottomInset=4; [self.controls setNeedsLayout];
    [self.view setNeedsLayout]; [self.view layoutIfNeeded];
    UINavigationController *navigation = self.navigationController;
    if ([navigation.viewControllers containsObject:review]) [navigation popToViewController:self animated:NO];
    if (self.presentedViewController==review) [self dismissViewControllerAnimated:NO completion:nil];
    if (resume && self.foreground && !self.exited && self.session.running) {
        [self.session resumeInputAfterReview];
        self.textReviewViewportPending = !self.session.desktopFrameReady;
        if (!self.textReviewViewportPending && CGSizeEqualToSize(self.framebufferSize,self.textReviewFramebuffer)
            && CGRectEqualToRect(self.activeCrop,self.textReviewCrop))
            [self applyViewportRatio:self.textReviewZoom center:self.textReviewCenter];
    }
    if (resume) [self revealDeferredTextReviewFailure];
}
- (BOOL)displayChangeAllowed {
    return self.foreground && !self.exited && !self.inputInactive && !self.inputOnly && !self.textReview
        && !self.changingDisplayMode && !self.restoreViewportPending && !self.checkingResume && !self.pendingDesktopSizePreset
        && !self.pendingStreamDisplayID && self.session.desktopSizeAvailable;
}
- (BOOL)applyStreamDisplay:(NSNumber *)identifier {
    if (![self displayChangeAllowed] || !identifier || identifier.longLongValue < 0 || identifier.unsignedLongLongValue > UINT32_MAX) return NO;
    [self releasePointer]; [self cancelTrackpadTouches]; [self resetModifiers];
    if (![self.session requestDesktopDisplayID:identifier.unsignedIntValue]) return NO;
    self.pendingStreamDisplayID = identifier;
    self.status.text = @"Switching Display…"; self.status.hidden = NO; [self updateStatusPresentation];
    [self updateDesktopSizeState]; // Already presented streams complete synchronously.
    return YES;
}
- (void)cancelDisplayModeConfirmation {
    self.inputOnlyConfirmationPending = NO; self.modeConfirmationPreset = nil; self.modeConfirmationOwner = nil;
    UIAlertController *alert = self.modeConfirmationAlert; self.modeConfirmationAlert = nil;
    if (alert && self.presentedViewController == alert) [alert dismissViewControllerAnimated:NO completion:nil];
}
- (UIAlertController *)inputOnlyConfirmation {
    if (!self.connectionForegroundAvailable || self.inputOnly || self.textReview) return nil;
    [self cancelDisplayModeConfirmation];
    self.inputOnlyConfirmationPending = YES; self.modeConfirmationOwner = self.session;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Use Trackpad & Keyboard?"
        message:@"File transfers using this connection will stop." preferredStyle:UIAlertControllerStyleAlert];
    __weak CompanionVNCViewer *weak = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){ [weak cancelDisplayModeConfirmation]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ [weak acceptDisplayModeConfirmation]; }]];
    self.modeConfirmationAlert = alert; return alert;
}
- (UIAlertController *)displayModeConfirmationForPreset:(NSInteger)preset {
    if (preset < 0 || preset > 3 || ![self displayChangeAllowed] || self.changingDisplayMode
        || ([self.session.diagnosticCounters[@"layoutVirtual"] boolValue] == (preset > 0))) return nil;
    [self cancelDisplayModeConfirmation];
    self.modeConfirmationPreset = @(preset); self.modeConfirmationOwner = self.session;
    BOOL filesActive = self.filesTransferActiveHandler && self.filesTransferActiveHandler();
    NSString *message = preset > 0 ? @"Your connection will restart. Your Mac’s screen may go dark."
        : @"Your connection will restart to show your Mac’s displays.";
    if (filesActive) message = [message stringByAppendingString:@" File transfers using this connection will stop."];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:preset > 0 ? @"Switch to Virtual Display?" : @"Switch to Mirror Mac Screen?"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    __weak CompanionVNCViewer *weak = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){ [weak cancelDisplayModeConfirmation]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Switch & Reconnect" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ [weak acceptDisplayModeConfirmation]; }]];
    self.modeConfirmationAlert = alert; return alert;
}
- (void)confirmDisplayModePreset:(NSInteger)preset {
    if (self.presentedViewController) return;
    UIAlertController *alert = [self displayModeConfirmationForPreset:preset];
    if (alert) [self presentViewController:alert animated:YES completion:nil];
}
- (BOOL)acceptDisplayModeConfirmation {
    NSNumber *target = self.modeConfirmationPreset; BOOL inputOnly = self.inputOnlyConfirmationPending;
    BOOL current = self.modeConfirmationOwner == self.session && (target != nil || inputOnly);
    self.inputOnlyConfirmationPending = NO; self.modeConfirmationPreset = nil; self.modeConfirmationOwner = nil; self.modeConfirmationAlert = nil;
    if (!current) return NO;
    if (inputOnly) {
        if (!self.connectionForegroundAvailable || self.inputOnly || self.textReview) return NO;
        [self restartInputOnlyConnection]; [self.keyFeedback feedback:@"selection"]; return YES;
    }
    if (![self displayChangeAllowed]) return NO;
    BOOL changed = [self.session.diagnosticCounters[@"layoutVirtual"] boolValue] != (target.integerValue > 0);
    BOOL accepted = [self restartDisplayModePreset:target.integerValue];
    if (accepted && changed) [self.keyFeedback feedback:@"selection"];
    return accepted;
}
- (void)retireDisplayModeOwner {
    [self retireSessionMenu];
    [self releasePointer]; [self cancelTrackpadTouches]; [self resetModifiers];
    // Intentional retirement cannot publish a generic failure over mode recovery.
    self.session.stateHandler = nil; self.session.frameHandler = nil; self.session.cursorHandler = nil; self.session.displayLayoutHandler = nil;
    [self.session stop];
    if (self.disconnectHandler) self.disconnectHandler();
}
- (BOOL)restartDisplayModePreset:(NSInteger)preset {
    if (preset < 0 || preset > 3 || !self.connectionForegroundAvailable || self.inputOnly || self.textReview) return NO;
    if (!self.failedDisplayModePreset && ![self displayChangeAllowed]) return NO;
    if (!self.failedDisplayModePreset && [self.session.diagnosticCounters[@"layoutVirtual"] boolValue] == (preset > 0)) return YES;
    BOOL wasVirtual = [self.session.diagnosticCounters[@"layoutVirtual"] boolValue]
        || (preset == 0 && self.failedDisplayModePreset != nil);
    if (![self.credentialState loginForResume]) {
        [self.credentialState editWithUsername:self.username.text ?: @"" password:self.password.text ?: @"" remember:self.remember.on];
        if (!self.credentialState.username.length || !self.credentialState.password.length) { [self showInvalidLogin]; return NO; }
        [self.credentialState beginLogin];
    }
    self.modePreviousPreset = self.restoredDesktopSizePreset; self.modeTargetPreset = preset;
    self.restoredDesktopSizePreset = preset; // Draft; persistence waits for verified pixels.
    self.desktopSizeRestored = YES; self.changingDisplayMode = YES;
    self.mirrorRequiresCleanup = preset == 0 && wasVirtual; self.mirrorFullRestartUsed = YES;
    self.modeRecoveryAttempts = 0; self.modeResizeRequested = NO;
    self.mirrorRestoreAttempts = self.mirrorRestoreOutcome = self.mirrorCleanupRemaining = 0;
    self.mirrorObservedLayouts = [NSMutableArray new]; self.mirrorRestartScheduled = NO;
    self.failedDisplayModePreset = nil; self.pendingDesktopSizePreset = 0; self.pendingStreamDisplayID = nil;
    self.session.displayHandoffInputBlocked = YES;
    [self retireDisplayModeOwner];
    self.selectedDisplay = nil; self.displayViews = @[]; self.displayLayout = nil; self.displayAspect = 0;
    self.resumeDisplayID = nil; self.resumeCropSize = CGSizeZero; self.awaitingReplacementLayout = NO;
    self.pendingRestorationFrame = nil; self.initialDisplayApplied = YES;
    [self startResuming:YES]; return self.starting;
}
- (BOOL)applyMirrorDisplay { return [self restartDisplayModePreset:0]; }
- (void)completeDisplayModeVerified:(BOOL)verified {
    NSInteger target = self.modeTargetPreset;
    self.changingDisplayMode = self.mirrorRequiresCleanup = NO; self.mirrorCleanupRemaining = 0;
    self.mirrorRestoreOutcome = verified ? 2 : 1; self.desktopSizeRestored = YES;
    self.session.displayHandoffInputBlocked = NO; self.statusGeneration++;
    self.failedDisplayModePreset = nil;
    if (verified) [self retainDesktopSizePreset:target];
    if (target == 0) [self restoreSavedDisplay];
}
- (void)expireDisplayModeVerification:(CompanionVNCSession *)owner generation:(NSUInteger)generation {
    if (self.session != owner || self.modeVerificationGeneration != generation
        || !self.changingDisplayMode || !self.connectionForegroundAvailable) return;
    NSInteger failure = self.modeTargetPreset > 0 ? 117 : 118;
    [self retireDisplayModeOwner]; [self showConnectionFailureStage:failure]; [self reportDiagnostics:self.latestCounters];
}
- (void)armDisplayModeVerification {
    if (self.modeVerificationTimed || !self.session.established || !self.connectionForegroundAvailable) return;
    self.modeVerificationTimed = YES; NSUInteger generation = ++self.modeVerificationGeneration;
    __weak CompanionVNCViewer *weak = self; __weak CompanionVNCSession *owner = self.session;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 40 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [weak expireDisplayModeVerification:owner generation:generation];
    });
}
- (void)updateDisplayModeRestoration {
    if (!self.changingDisplayMode || self.mirrorRestartScheduled || !self.connectionForegroundAvailable) return;
    [self armDisplayModeVerification];
    NSDictionary *stats = self.session.diagnosticCounters;
    if (self.modeTargetPreset > 0 && self.modeResizeRequested
        && ([stats[@"probeOutcome"] integerValue] == 3 || [stats[@"probeOutcome"] integerValue] == 4)) {
        [self retireDisplayModeOwner]; [self showConnectionFailureStage:117]; [self reportDiagnostics:stats]; return;
    }
    if (!self.session.desktopFrameReady || self.restoreViewportPending || !stats[@"layoutVirtual"]) return;
    BOOL virtual = [stats[@"layoutVirtual"] boolValue];
    if ([stats[@"layoutCount"] unsignedIntegerValue] == 0) {
        // Initial legacy connections keep their ordinary behavior. A mode change
        // on a previously validated Apple host must wait for its new metadata.
        if (!self.mirrorFullRestartUsed && ![stats[@"appleDisplayProtocol"] boolValue]) [self completeDisplayModeVerified:NO];
        return;
    }
    if (self.modeTargetPreset > 0) {
        if ([self desktopSizeMatchesPreset:self.modeTargetPreset]) { [self completeDisplayModeVerified:YES]; return; }
        if (!self.modeResizeRequested) self.modeResizeRequested = [self.session requestDesktopSizePresetForHandoff:self.modeTargetPreset];
        return;
    }
    if (!virtual) {
        NSInteger width = [stats[@"layoutWidth"] integerValue], height = [stats[@"layoutHeight"] integerValue];
        if (width <= 0 || height <= 0 || width != [stats[@"framebufferWidth"] integerValue]
            || height != [stats[@"framebufferHeight"] integerValue]) return;
    }
    [self.mirrorObservedLayouts addObject:@(virtual)];
    if (!virtual) { [self completeDisplayModeVerified:YES]; return; }
    self.checkingResume = NO; self.resumeGeneration++;
    self.mirrorRestartScheduled = YES; self.starting = YES;
    CompanionVNCSession *owner = self.session; __weak CompanionVNCViewer *weak = self;
    BOOL exhausted = self.modeRecoveryAttempts >= 1;
    dispatch_async(dispatch_get_main_queue(), ^{
        CompanionVNCViewer *strong = weak;
        if (!strong || strong.session != owner || strong.exited || !strong.changingDisplayMode) return;
        strong.mirrorRestartScheduled = NO;
        if (!strong.connectionForegroundAvailable) return;
        [strong retireDisplayModeOwner];
        if (exhausted) { [strong showConnectionFailureStage:116]; [strong reportDiagnostics:strong.latestCounters]; return; }
        strong.modeRecoveryAttempts++; strong.mirrorRequiresCleanup = strong.mirrorFullRestartUsed = YES;
        [strong startResuming:YES];
    });
}
- (BOOL)desktopSizeMatchesPreset:(NSInteger)preset {
    CompanionVNCDesktopSize size;
    if (preset < 1 || preset > 3 || !CompanionVNCDesktopSizeForPreset((int)preset, &size) || !self.session.desktopFrameReady) return NO;
    NSDictionary *stats = self.session.diagnosticCounters;
    return [stats[@"layoutVirtual"] boolValue] && [stats[@"layoutCount"] integerValue] == 1
        && [stats[@"framebufferWidth"] integerValue] == size.width * 2 && [stats[@"framebufferHeight"] integerValue] == size.height * 2
        && [stats[@"layoutWidth"] integerValue] == size.width * 2 && [stats[@"layoutHeight"] integerValue] == size.height * 2;
}
- (void)retainDesktopSizePreset:(NSInteger)preset {
    self.desktopSizeRestored = YES;
    self.restoredDesktopSizePreset = preset;
    if (self.desktopSizeSelectionHandler) self.desktopSizeSelectionHandler(preset);
}
- (BOOL)applyDesktopSizePreset:(NSInteger)preset {
    CompanionVNCDesktopSize size;
    if (preset < 1 || preset > 3 || !CompanionVNCDesktopSizeForPreset((int)preset, &size) || ![self displayChangeAllowed]) return NO;
    if ([self desktopSizeMatchesPreset:preset]) { [self retainDesktopSizePreset:preset]; return YES; }
    [self releasePointer]; [self cancelTrackpadTouches]; [self resetModifiers];
    if (![self.session requestDesktopSizePreset:preset]) return NO;
    self.desktopSizeRestored = YES; self.pendingDesktopSizePreset = preset; self.lateDesktopSizePreset = 0;
    self.status.text = @"Resizing Desktop…"; self.status.hidden = NO;
    [self updateStatusPresentation]; return YES;
}
- (void)updateDesktopSizeState {
    if (self.pendingStreamDisplayID) {
        NSInteger result = [self.session.diagnosticCounters[@"probeOutcome"] integerValue];
        if ((result == 2 && self.session.desktopFrameReady) || result == 3 || result == 4 || !self.session.running) {
            NSNumber *identifier = self.pendingStreamDisplayID; self.pendingStreamDisplayID = nil;
            if (result == 2 && self.session.desktopFrameReady) {
                NSDictionary *selected = nil;
                for (NSDictionary *d in self.displayViews) if ([d[@"id"] isEqual:identifier]) selected = d;
                [self selectDisplay:identifier.unsignedIntValue ? selected : nil];
                if (self.restoringStreamViewport && CGSizeEqualToSize(self.activeCrop.size, self.resumeCropSize))
                    [self applyViewportRatio:self.resumeZoomRatio center:self.resumeCenter];
                if (self.displaySelectionHandler) self.displaySelectionHandler(identifier.unsignedIntValue ? identifier : nil);
                self.status.hidden = YES;
            } else if (self.session.connected) {
                self.displayNoticeUntil = NSProcessInfo.processInfo.systemUptime + 4;
                self.status.text = @"The Mac couldn’t stream that display. Showing the current desktop."; self.status.hidden = NO;
            }
            self.restoringStreamViewport = NO;
            [self updateStatusPresentation]; [self updateDisplayPicker];
        }
    }
    if (self.changingDisplayMode && self.foreground && !self.inputInactive) [self updateDisplayModeRestoration];
    if (self.pendingDesktopSizePreset) {
        NSDictionary *stats = self.session.diagnosticCounters;
        NSInteger result = [stats[@"probeOutcome"] integerValue];
        if (result == 2 && self.session.desktopFrameReady) {
            if ([self desktopSizeMatchesPreset:self.pendingDesktopSizePreset]) {
                [self retainDesktopSizePreset:self.pendingDesktopSizePreset];
                self.status.hidden = YES;
            } else {
                self.displayNoticeUntil = NSProcessInfo.processInfo.systemUptime + 4;
                self.status.text = @"The Mac selected a different desktop size."; self.status.hidden = NO;
            }
            self.pendingDesktopSizePreset = 0;
        } else if (result == 3 || result == 4 || !self.session.running) {
            self.lateDesktopSizePreset = (result == 3 || result == 4) && self.session.running ? self.pendingDesktopSizePreset : 0;
            self.pendingDesktopSizePreset = 0;
            if (self.session.connected) {
                self.displayNoticeUntil = NSProcessInfo.processInfo.systemUptime + 4;
                self.status.text = result == 4 ? @"The Mac selected a different desktop size." : @"Desktop size could not be changed.";
                self.status.hidden = NO;
            }
        }
        [self updateStatusPresentation];
    }
    if (self.lateDesktopSizePreset && !self.changingDisplayMode && self.connectionForegroundAvailable
        && [self.session.diagnosticCounters[@"probeOutcome"] integerValue] == 2 && [self desktopSizeMatchesPreset:self.lateDesktopSizePreset]) {
        [self retainDesktopSizePreset:self.lateDesktopSizePreset]; self.lateDesktopSizePreset = 0;
        self.displayNoticeUntil = 0; self.status.hidden = YES; [self updateStatusPresentation];
    }
    if (!self.desktopSizeRestored && self.foreground && !self.inputInactive && !self.inputOnly
        && !self.restoreViewportPending && !self.checkingResume && self.session.desktopFrameReady) {
        if (self.restoredDesktopSizePreset == 0) { self.desktopSizeRestored = YES; [self restoreSavedDisplay]; }
        else if (self.session.desktopSizeAvailable) {
            self.desktopSizeRestored = YES;
            [self applyDesktopSizePreset:self.restoredDesktopSizePreset];
        }
    }
}
- (void)showDesktopSizeMenu {
    if (self.inputOnly || ![self.session.diagnosticCounters[@"layoutVirtual"] boolValue]
        || ![self.session.desktopDisplayLayout[@"views"] count]) return;
    NSMutableArray *items = [NSMutableArray new];
    NSArray *titles = @[@"Larger Text", @"Balanced", @"More Space"];
    for (NSInteger preset = 1; preset <= 3; preset++) {
        CompanionVNCDesktopSize size; CompanionVNCDesktopSizeForPreset((int)preset, &size);
        [items addObject:@{@"kind": @"desktopSize", @"preset": @(preset), @"title": titles[preset-1],
            @"subtitle": [NSString stringWithFormat:@"%u × %u%@", size.width, size.height, preset == 2 ? @" · Recommended" : @""],
            @"symbol": @"display", @"selected": @([self desktopSizeMatchesPreset:preset]),
            @"disabled": @(!self.session.desktopSizeAvailable || self.inputOnly || self.restoreViewportPending || self.inputInactive)}];
    }
    [self presentMenu:@"Desktop Size" sections:@[@{@"title": @"Desktop Size · Landscape", @"items": items}]];
}
// Build one immutable menu snapshot when it opens. Live frames and readiness
// changes must not replace a row while the user is reaching for it.
- (NSArray<NSDictionary *> *)displayMenuSections {
    NSMutableArray *sections = [NSMutableArray new];
    if (!self.inputOnly) {
        BOOL virtualDisplay = [self.session.diagnosticCounters[@"layoutVirtual"] boolValue];
        NSDictionary *catalogue = self.session.desktopDisplayLayout;
        BOOL sizingSupported = [catalogue[@"views"] count] > 0;
        // The active stream can contain one monitor while the retained host
        // catalogue still offers multiple monitors and All Displays.
        NSArray *availableDisplays = sizingSupported ? catalogue[@"views"] : self.displayViews;
        BOOL busy = !self.foreground || self.inputInactive || self.changingDisplayMode || self.restoreViewportPending || self.checkingResume
            || self.pendingDesktopSizePreset || self.pendingStreamDisplayID || !self.session.desktopFrameReady;
        BOOL unavailable = busy || ![self displayChangeAllowed];
        NSMutableArray *modeItems = [NSMutableArray new];
        if (sizingSupported) {
            [modeItems addObjectsFromArray:@[
                @{@"kind": @"virtualDisplay", @"title": @"Virtual Display", @"subtitle": @"Landscape desktop · Mac screen may go dark", @"symbol": @"display", @"selected": @(virtualDisplay), @"disabled": @(unavailable)},
                @{@"kind": @"mirrorDisplay", @"title": @"Mirror Mac Screen", @"subtitle": @"Original resolution · Mac screen stays visible", @"symbol": @"display.2", @"selected": @(!virtualDisplay && self.session.desktopFrameReady), @"disabled": @(unavailable)}]];
            if (virtualDisplay) [modeItems addObject:@{@"kind": @"desktopSizeMenu", @"title": @"Desktop Size", @"symbol": @"arrow.up.left.and.arrow.down.right", @"submenu": @YES, @"push": @YES, @"disabled": @(unavailable)}];
        }
        if (!virtualDisplay && availableDisplays.count > 1) {
            [modeItems addObject:@{@"kind": @"displays", @"title": @"Choose Display", @"symbol": @"display.2", @"submenu": @YES, @"push": @YES,
                @"disabled": @(busy || (sizingSupported && ![self displayChangeAllowed]))}];
        }
        if (modeItems.count) [sections addObject:@{@"title": @"Screen Sharing", @"items": modeItems}];
        CGPoint fittedOffset = CGPointMake(-self.canvas.contentInset.left, -self.canvas.contentInset.top);
        BOOL fitted = fabs(self.canvas.zoomScale - self.canvas.minimumZoomScale) < .001
            && fabs(self.canvas.contentOffset.x - fittedOffset.x) < 1 && fabs(self.canvas.contentOffset.y - fittedOffset.y) < 1;
        [sections addObject:@{@"title": @"View", @"items": @[
            @{@"kind": @"fit", @"title": @"Fit to Window", @"symbol": @"arrow.down.right.and.arrow.up.left", @"disabled": @(busy || !self.lastFramebuffer || fitted)},
            @{@"kind": @"copyText", @"title": @"Copy Text from Screen", @"symbol": @"text.viewfinder", @"disabled": @(![self canCopyScreenText])}]}];
    }
    [sections addObject:@{@"title": @"Presentation", @"items": @[
        @{@"kind": @"inputOnly", @"title": self.inputOnly ? @"Show Mac Screen" : @"Trackpad & Keyboard Only", @"symbol": self.inputOnly ? @"desktopcomputer" : @"rectangle.and.hand.point.up.left", @"disabled": @(!self.connectionForegroundAvailable || (self.inputOnly && (self.starting || self.restoreViewportPending || self.checkingResume)))},
        @{@"kind": @"fullscreen", @"title": self.fullscreen ? @"Show Keyboard Bar" : @"Hide Keyboard Bar", @"symbol": self.fullscreen ? @"keyboard" : @"keyboard.chevron.compact.down"}]}];
    return sections;
}
- (void)showViewMenu { [self presentMenu:@"Display" sections:[self displayMenuSections]]; }
- (NSArray<NSDictionary *> *)inputMenuSections {
    NSMutableArray *sections = [NSMutableArray new];
    if (!self.inputOnly) [sections addObject:@{@"title": @"Mouse Mode", @"items": @[
        @{@"kind": @"setPointer", @"title": @"Pointer", @"symbol": @"cursorarrow", @"selected": @(!self.trackpadMode)},
        @{@"kind": @"setTrackpad", @"title": @"Trackpad", @"symbol": @"cursorarrow.motionlines", @"selected": @(self.trackpadMode)}]}];
    [sections addObject:@{@"title": @"Keyboard", @"items": @[
        @{@"kind": @"composeText", @"title": @"Compose Text", @"symbol": @"square.and.pencil", @"disabled": @(![self composedTextAvailable])},
        @{@"kind": @"keyboard", @"title": self.input.isFirstResponder ? @"Hide Keyboard" : @"Show Keyboard", @"symbol": self.input.isFirstResponder ? @"keyboard.chevron.compact.down" : @"keyboard"},
        @{@"kind": @"keys", @"title": @"Extra Keys", @"symbol": @"keyboard", @"submenu": @YES, @"push": @YES}]}];
    return sections;
}
- (void)showInputMenu { [self presentMenu:@"Input" sections:[self inputMenuSections]]; }
- (void)retireTextDraft {
    if (self.textComposer.sending) self.textSendInterrupted = YES;
    self.textGeneration++; [self.textComposer invalidate];
}
- (void)showTextSendWarning {
    if (self.recoveryController) return;
    __weak CompanionVNCViewer *weak = self;
    [self showRecoveryController:[DirectRecoveryBridgeV1 interruptedTextWithDone:^{
        [weak acknowledgeTextSendWarning];
    }] overFrame:self.lastFramebuffer != nil];
}
- (void)acknowledgeTextSendWarning {
    self.textSendInterrupted = NO;
    [self clearRecovery]; self.image.alpha = 1; [self updateConnectionChrome];
}
- (BOOL)composedTextAvailable {
    return self.foreground && !self.exited && !self.inputInactive && !self.checkingResume
        && !self.restoreViewportPending && !self.textReview && self.session.composedTextReady;
}
- (void)showTextComposer {
    if (![self composedTextAvailable]) return;
    if (!self.textComposer) self.textComposer = [[DirectTextComposer alloc] initWithMacName:self.macName ?: @"Mac" mode:self.inputOnly ? @"trackpad" : @"desktop"];
    self.textComposer.shortcutBar = self.toolbar;
    [self.view endEditing:YES]; [self.loginScroll endEditing:YES]; [self resetModifiers]; [self releasePointer];
    [self cancelTrackpadTouches]; [self.controls close];
    __weak CompanionVNCViewer *weak = self;
    __weak CompanionVNCSession *owner = self.session;
    NSUInteger generation = self.textGeneration;
    self.textComposer.interruptionHandler = ^{ weak.textSendInterrupted = YES; };
    void (^present)(void) = ^{
        CompanionVNCViewer *strong = weak;
        if (!strong || strong.textReview || strong.session != owner || strong.textGeneration != generation
            || ![strong composedTextAvailable]) return;
        [strong.textComposer presentFrom:strong available:^BOOL {
            CompanionVNCViewer *current = weak;
            return current && owner && current.session == owner && current.textGeneration == generation
                && [current composedTextAvailable];
        } send:^(NSString *text, void (^complete)(NSString *)) {
            CompanionVNCViewer *current = weak;
            if (!current || !owner || current.session != owner || current.textGeneration != generation
                || ![current composedTextAvailable]) {
                complete(@"The session changed. Nothing was sent."); return;
            }
            [current resetModifiers];
            NSArray *events = [DirectTextComposer desktopEvents:text];
            if (![owner tryComposedTextEvents:events completion:^(BOOL written) {
                if (!written && weak.textGeneration == generation) weak.textSendInterrupted = YES;
                complete(written ? nil : @"Text may have been partially sent. Check your Mac before sending it again.");
            }]) complete(@"Input is busy. Nothing was queued. Try Send Text again.");
        }];
    };
    if (self.presentedViewController) [self dismissViewControllerAnimated:YES completion:present];
    else present();
}
- (void)showConnectionDetails {
    NSString *message = [NSString stringWithFormat:@"%@\n\n%@\n\nDesktop: %.0f × %.0f\nIndividual displays: %lu", self.status.text ?: @"", [self configuredConnectionDetails], self.framebufferSize.width, self.framebufferSize.height, (unsigned long)self.displayViews.count];
    UIAlertController *details = [UIAlertController alertControllerWithTitle:@"Connection Details" message:message preferredStyle:UIAlertControllerStyleAlert];
    [details addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:details animated:YES completion:nil];
}
- (void)showSessionMenu {
    [self presentMenu:self.macName ?: @"Session" sections:@[
        @{@"title": @"Session", @"items": @[
            @{@"kind": @"files", @"title": self.filesStatus.length ? [@"Files · " stringByAppendingString:self.filesStatus] : @"Files", @"symbol": @"folder", @"submenu": @YES},
            @{@"kind": @"details", @"title": @"Connection Details", @"symbol": @"info.circle"},
            @{@"kind": @"appSettings", @"title": @"App Settings", @"symbol": @"gearshape", @"submenu": @YES}]},
        @{@"title": @"", @"items": @[@{@"kind": @"exit", @"title": @"Disconnect", @"symbol": @"xmark.circle", @"destructive": @YES}]}]];
}

@end

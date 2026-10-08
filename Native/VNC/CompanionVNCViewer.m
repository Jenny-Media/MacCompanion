#import <UIKit/UIKit.h>
#import "CompanionVNCSession.h"
#import "CompanionVNCViewer.h"
#import "CompanionVNCKeyboard.h"
#import "CompanionVNCViewport.h"
#import "CompanionVNCAdaptiveLayout.h"
#import "CompanionVNCCursor.h"
#import "CompanionVNCDisplayPicker.h"
#import "CompanionVNCControls.h"
#import "CompanionVNCTapGesture.h"
#import "CompanionVNCTrackpadFeedback.h"
#import "CompanionVNCMenu.h"
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

@interface CompanionVNCViewer () <UIScrollViewDelegate, UITextViewDelegate>

@property UITextField *host, *username, *password;
@property UIViewController *recoveryController;
@property(nonatomic, copy) NSString *loginIssueDetails;
@property UIViewController *loginBackdrop;
@property UIScrollView *recoveryPanel;
@property UIStackView *login;
@property UIScrollView *loginScroll;
@property UIStackView *loginFields, *progressRow, *keyRow;
@property UIStackView *loginIntro, *loginIdentity, *credentialColumns;
@property UILabel *loginSubtitle;
@property UIButton *loginDetails;
@property UIButton *loginClose, *loginCancel;
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
@property BOOL initialDisplayApplied;
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
@property BOOL cursorPositionKnown;
@property BOOL cursorFollowingSuspended;
@property CompanionRemoteTextInput *input;
@property NSLayoutConstraint *toolbarBottom, *canvasToolbarBottom, *canvasFullscreenBottom;
@property NSLayoutConstraint *canvasTop;
@property UIEdgeInsets previousCanvasInset;
@property UILabel *trackpadHelp;
@property CompanionVNCTrackpadFeedback *trackpadFeedback, *tabletopFeedback;
@property UIGestureRecognizer *click;
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
@property NSMutableArray<UIButton *> *modifiers;
@property CompanionVNCKeyboard *remoteKeyboard;
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
@property BOOL checkingResume, exited, restoreViewportPending;
@property NSNumber *resumeDisplayID;
@property CGSize resumeFramebufferSize;
@property CGFloat resumeZoomRatio;
@property CGPoint resumeCenter;
@property(nonatomic, weak) CompanionVNCDisplayPicker *displayPicker;
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
    _displayLayout = [displayLayout copy];
    self.displayViews = displayLayout[@"views"] ?: @[];
    self.displayAspect = [displayLayout[@"aspectRatio"] doubleValue];
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
    [field.heightAnchor constraintGreaterThanOrEqualToConstant:32].active = YES;
    return field;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor; self.foreground = YES;
    self.modifiers = [NSMutableArray new];
    [self prepareConnection];
    __weak CompanionVNCViewer *weak = self;
    self.remoteKeyboard = [[CompanionVNCKeyboard alloc] initWithEvents:^(NSArray<NSDictionary *> *events) { [weak.session keyEvents:events]; }];
    self.status = [UILabel new]; self.status.text = @"macOS Screen Sharing · local network";
    self.status.font = [UIFont systemFontOfSize:12];
    self.status.backgroundColor = UIColor.secondarySystemBackgroundColor; self.status.layer.cornerRadius = 8; self.status.clipsToBounds = YES;
    self.status.textColor = UIColor.secondaryLabelColor; self.status.numberOfLines = 2;
    self.connect = [self button:@"Connect" action:@selector(connectionAction)];
    self.pan = [self button:@"Pointer" action:@selector(chooseInputMode)];
    self.controls = [CompanionVNCControls new]; self.controls.translatesAutoresizingMaskIntoConstraints = NO;
    self.controls.macName = self.macName ?: @"Mac";
    self.controls.quickActions = self.quickActions ?: @[
        @{@"kind": @"mode", @"title": @"Mouse Mode", @"enabled": @YES},
        @{@"kind": @"fit", @"title": @"Fit View", @"enabled": @YES},
        @{@"kind": @"rightClick", @"title": @"Right Click", @"enabled": @YES}];
    self.controls.actionHandler = ^(NSDictionary *action) { [weak performControlAction:action]; };
    self.controls.openingHandler = ^{
        [weak releasePointer]; [weak cancelTrackpadTouches];
        if (weak.quickActionsProvider) weak.quickActions = weak.quickActionsProvider(weak.inputOnly);
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
    self.fallbackCursor.path = arrow.CGPath; self.fallbackCursor.fillColor = UIColor.whiteColor.CGColor;
    self.fallbackCursor.strokeColor = UIColor.blackColor.CGColor; self.fallbackCursor.lineWidth = 1.5;
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
    UITapGestureRecognizer *smart = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(smartZoom:)];
    smart.numberOfTapsRequired = 2; smart.numberOfTouchesRequired = 2;
    [self.canvas addGestureRecognizer:smart];
    self.canvas.panGestureRecognizer.minimumNumberOfTouches = 2;
    self.host = [self field:@"Paired Mac"]; self.host.hidden = YES;
    self.host.keyboardType = UIKeyboardTypeASCIICapable;
    self.username = [self field:@"Mac account username"];
    self.password = [self field:@"Mac account password"]; self.password.secureTextEntry = YES;
    self.password.textContentType = UITextContentTypePassword;
    self.username.textContentType = UITextContentTypeUsername;
    self.username.accessibilityIdentifier = @"mac-login-username";
    self.password.accessibilityIdentifier = @"mac-login-password";
    UIButton *visibility = [self button:@"" action:@selector(togglePassword)];
    [visibility setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20] forImageInState:UIControlStateNormal];
    [visibility setImage:[UIImage systemImageNamed:@"eye"] forState:UIControlStateNormal]; visibility.accessibilityLabel = @"Show Password";
    [visibility.widthAnchor constraintEqualToConstant:44].active = YES;
    visibility.accessibilityIdentifier = @"mac-login-visibility"; self.passwordVisibility = visibility;
    visibility.backgroundColor = UIColor.clearColor; visibility.tintColor = UIColor.secondaryLabelColor;
    self.remember = [UISwitch new];
    UILabel *rememberLabel = [UILabel new]; rememberLabel.text = @"Save login";
    UIStackView *saveRow = [[UIStackView alloc] initWithArrangedSubviews:@[rememberLabel, self.remember]];
    saveRow.alignment = UIStackViewAlignmentCenter;
    rememberLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    UILabel *accountLabel = [UILabel new]; accountLabel.text = @"Mac account";
    UILabel *passwordLabel = [UILabel new]; passwordLabel.text = @"Password";
    UIStackView *account = [[UIStackView alloc] initWithArrangedSubviews:@[accountLabel, self.username]];
    account.axis = UILayoutConstraintAxisVertical; account.spacing = 4;
    account.layoutMarginsRelativeArrangement = YES; account.layoutMargins = UIEdgeInsetsMake(12,14,12,14); account.backgroundColor = DirectConnectionBridge.fieldColor;
    UIStackView *passwordRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.password, visibility]]; passwordRow.spacing = 4;
    UIStackView *password = [[UIStackView alloc] initWithArrangedSubviews:@[passwordLabel, passwordRow]];
    password.axis = UILayoutConstraintAxisVertical; password.spacing = 4;
    password.layoutMarginsRelativeArrangement = YES; password.layoutMargins = UIEdgeInsetsMake(12,14,12,14); password.backgroundColor = DirectConnectionBridge.fieldColor;
    for (UILabel *label in @[accountLabel, passwordLabel]) { label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; label.textColor = UIColor.secondaryLabelColor; }
    self.credentialColumns = [[UIStackView alloc] initWithArrangedSubviews:@[account, password]];
    self.credentialColumns.axis = UILayoutConstraintAxisVertical; self.credentialColumns.spacing = 1;
    self.credentialColumns.backgroundColor = [UIColor.separatorColor colorWithAlphaComponent:.25]; self.credentialColumns.layer.cornerRadius = 16; self.credentialColumns.clipsToBounds = YES;
    UIButton *cancel = [self button:@"Cancel" action:@selector(showMacs)]; cancel.accessibilityIdentifier = @"mac-login-cancel";
    self.loginCancel = cancel; cancel.backgroundColor = UIColor.clearColor; cancel.tintColor = UIColor.systemBlueColor;
    UIButtonConfiguration *cancelStyle = UIButtonConfiguration.tintedButtonConfiguration;
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
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[self.connect, cancel]];
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
    UILabel *subtitle = [UILabel new]; subtitle.text = @"Desktop"; subtitle.textColor = UIColor.secondaryLabelColor; subtitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    subtitle.numberOfLines = 0; self.loginSubtitle = subtitle;
    UIStackView *identityText = [[UIStackView alloc] initWithArrangedSubviews:@[title, subtitle]]; identityText.axis = UILayoutConstraintAxisVertical; identityText.spacing = 4;
    self.loginClose = [self button:@"" action:@selector(showMacs)]; [self.loginClose setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    [self.loginClose setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium] forImageInState:UIControlStateNormal];
    self.loginClose.accessibilityLabel = @"Cancel connection"; self.loginClose.accessibilityIdentifier = @"mac-login-close"; self.loginClose.tintColor = UIColor.secondaryLabelColor;
    self.loginClose.layer.cornerRadius = 22; [self.loginClose.widthAnchor constraintEqualToConstant:44].active = YES;
    self.loginIdentity = [[UIStackView alloc] initWithArrangedSubviews:@[tile, identityText, self.loginClose]]; self.loginIdentity.axis = UILayoutConstraintAxisHorizontal; self.loginIdentity.spacing = 12; self.loginIdentity.alignment = UIStackViewAlignmentCenter;
    self.loginIntro = [[UIStackView alloc] initWithArrangedSubviews:@[self.loginIdentity]];
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
    [self.loginDetails setImage:[UIImage systemImageNamed:@"info.circle"] forState:UIControlStateNormal];
    self.login = [[UIStackView alloc] initWithArrangedSubviews:@[self.loginIntro, self.progressRow, self.loginFields, actions, self.loginDetails]];
    self.login.axis = UILayoutConstraintAxisVertical; self.login.spacing = 18;
    self.login.layoutMargins = UIEdgeInsetsMake(22, 22, 22, 22); self.login.layoutMarginsRelativeArrangement = YES;
    [DirectConnectionBridge styleCard:self.login];
    [self registerForTraitChanges:@[UITraitUserInterfaceStyle.class, UITraitUserInterfaceLevel.class, UITraitAccessibilityContrast.class]
                     withHandler:^(id<UITraitEnvironment> environment, UITraitCollection *previous) { [DirectConnectionBridge styleCard:weak.login]; }];
    self.login.translatesAutoresizingMaskIntoConstraints = NO;
    self.loginScroll = [UIScrollView new]; self.loginScroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.loginScroll.backgroundColor = UIColor.clearColor; self.loginScroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
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
    [self.view addSubview:self.status]; [self.view addSubview:self.controls];
    self.canvasToolbarBottom = [self.canvas.bottomAnchor constraintEqualToAnchor:toolbar.topAnchor constant:-8];
    self.canvasFullscreenBottom = [self.canvas.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor];
    self.tabletopCanvasBottom = [self.canvas.bottomAnchor constraintEqualToAnchor:self.view.topAnchor];
    self.canvasTop = [self.canvas.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:8];
    [NSLayoutConstraint activateConstraints:@[
        [self.status.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.status.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
        [self.status.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
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
        [self.login.bottomAnchor constraintEqualToAnchor:self.loginScroll.contentLayoutGuide.bottomAnchor constant:-12],
        [self.login.centerXAnchor constraintEqualToAnchor:self.loginScroll.centerXAnchor],
        self.loginMaxWidth,
        [self.login.widthAnchor constraintLessThanOrEqualToAnchor:self.loginScroll.frameLayoutGuide.widthAnchor constant:-32]
    ]];
    NSLayoutConstraint *cardWidth = [self.login.widthAnchor constraintEqualToAnchor:self.loginScroll.frameLayoutGuide.widthAnchor constant:-32]; cardWidth.priority = 750; cardWidth.active = YES;
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
    self.username.text = self.savedUsername ?: @"";
    self.password.text = self.savedPassword ?: @"";
    self.remember.on = self.password.text.length > 0;
    self.savedPassword = nil;
    self.trackpadHelp = [UILabel new]; self.trackpadHelp.text = @"Trackpad & Keyboard\nSlide to move · Tap to click\nHold to drag · Two fingers to scroll";
    self.trackpadHelp.numberOfLines = 0; self.trackpadHelp.textAlignment = NSTextAlignmentCenter;
    self.trackpadHelp.textColor = UIColor.secondaryLabelColor; self.trackpadHelp.userInteractionEnabled = NO;
    self.trackpadHelp.translatesAutoresizingMaskIntoConstraints = NO; [self.view insertSubview:self.trackpadHelp aboveSubview:self.canvas];
    [NSLayoutConstraint activateConstraints:@[[self.trackpadHelp.centerXAnchor constraintEqualToAnchor:self.canvas.centerXAnchor], [self.trackpadHelp.centerYAnchor constraintEqualToAnchor:self.canvas.centerYAnchor], [self.trackpadHelp.widthAnchor constraintLessThanOrEqualToAnchor:self.canvas.widthAnchor constant:-32]]];
    for (UILabel *label in @[title, subtitle, accountLabel, passwordLabel, rememberLabel, self.progressLabel]) {
        label.adjustsFontForContentSizeCategory = YES; label.numberOfLines = 0;
        if (!label.font || label.font.pointSize == 17) label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    }
    [self applyPresentation];
    [self setTrackpadModeEnabled:self.preferredTrackpad || self.inputOnly]; [self updateConnectionChrome];
    if (self.password.text.length) dispatch_async(dispatch_get_main_queue(), ^{ [weak start]; });
}
- (void)prepareConnection {
    self.session = [CompanionVNCSession new];
    __weak CompanionVNCViewer *weak = self;
    __weak CompanionVNCSession *owner = self.session;
    self.session.frameHandler = ^(UIImage *image) { if (weak.session == owner) [weak frame:image]; };
    self.session.cursorHandler = ^(UIImage *image, CGPoint hotspot, CGPoint position, BOOL known) {
        if (weak.session == owner) [weak receivedCursor:image hotspot:hotspot position:position known:known];
    };
    self.session.displayLayoutHandler = ^(NSDictionary *layout) { if (weak.session == owner) weak.displayLayout = layout; };
    if (self.reconnectWhenReady || self.checkingResume) self.restoreViewportPending = YES;
    self.displayLayout = nil;
    self.session.stateHandler = ^(NSString *state, NSDictionary *stats) {
        CompanionVNCViewer *strong = weak; if (!strong || strong.session != owner) return;
        if (strong.exited) return;
        BOOL running = strong.session.running, connected = [state isEqualToString:@"Connected"] && strong.session.connected && strong.lastFramebuffer != nil;
        if (!strong.foreground) {
            strong.status.text = @"Paused · Return to resume";
            if (!running && strong.disconnectHandler) strong.disconnectHandler();
            [strong reportDiagnostics:stats];
            return;
        }
        strong.status.text = connected ? @"" : @"Connecting to Screen Sharing…"; strong.status.hidden = YES; strong.progressLabel.text = strong.status.text;
        if (connected) {
            strong.session.inputOnly = strong.inputOnly;
            [strong clearRecovery]; strong.image.alpha = 1;
            strong.checkingResume = NO; strong.reconnectWhenReady = NO; strong.resumeGeneration++;
            if (strong.sessionPhaseHandler) strong.sessionPhaseHandler(@"connected");
            if (strong.connectedHandler) strong.connectedHandler();
        }
        if (connected || !running) { strong.connect.enabled = YES; strong.starting = NO; }
        strong.login.hidden = connected || (running && strong.login.hidden);
        [strong.connect setTitle:@"Connect" forState:UIControlStateNormal];
        UIApplication.sharedApplication.idleTimerDisabled = running;
        if (!running) {
            [strong clearCursor]; [strong resetModifiers];
            if (strong.disconnectHandler) strong.disconnectHandler();
            if (strong.checkingResume) [strong reconnectAfterFailedResume];
            else { [strong showRecoveryStage:[stats[@"failureStage"] integerValue]]; if (strong.sessionPhaseHandler) strong.sessionPhaseHandler(@"ended"); }
        }
        [strong updateConnectionChrome];
        [strong reportDiagnostics:stats];
    };
}
- (void)reportDiagnostics:(NSDictionary *)stats {
    if (!self.diagnosticHandler) return;
    NSMutableDictionary *diagnostics = [stats mutableCopy];
    diagnostics[@"viewer"] = @{@"canvasWidth": @(self.canvas.bounds.size.width), @"canvasHeight": @(self.canvas.bounds.size.height),
        @"imageWidth": @(self.image.bounds.size.width), @"imageHeight": @(self.image.bounds.size.height),
        @"imageFrameX": @(self.image.frame.origin.x), @"imageFrameY": @(self.image.frame.origin.y),
        @"imageFrameWidth": @(self.image.frame.size.width), @"imageFrameHeight": @(self.image.frame.size.height),
        @"zoom": @(self.canvas.zoomScale), @"minimumZoom": @(self.canvas.minimumZoomScale),
        @"offsetX": @(self.canvas.contentOffset.x), @"offsetY": @(self.canvas.contentOffset.y),
        @"canvasHidden": @(self.canvas.hidden), @"imageHidden": @(self.image.hidden), @"hasImage": @(self.image.image != nil)};
    self.diagnosticHandler(diagnostics);
}
- (void)start {
    [self clearRecovery];
    if (self.lastFramebuffer) { [self rememberViewport]; self.restoreViewportPending = YES; self.image.alpha = .45; }
    self.starting = YES; self.exited = NO;
    if (self.sessionPhaseHandler) self.sessionPhaseHandler(@"reconnecting");
    [self.view endEditing:YES]; self.status.text = @"Connecting to Screen Sharing…";
    self.connect.enabled = NO; self.progressLabel.text = @"Contacting Mac…"; self.status.hidden = YES; [self updateConnectionChrome];
    if (self.connectHandler) self.connectHandler(self.username.text ?: @"", self.password.text ?: @"", self.remember.on);
}
- (void)connectionAction {
    if (!self.session.running && !self.starting) [self start];
}
- (void)showLoginDetails {
    NSString *message = @"Sign in with your Mac account. Saved logins are separate for each Mac and service.\n\nUse a trusted local network or your private VPN. Screen Sharing desktop and input traffic are not encrypted by this app.";
    if (self.loginIssueDetails.length) message = [NSString stringWithFormat:@"%@\n\n%@", self.loginIssueDetails, message];
    UIAlertController *details = [UIAlertController alertControllerWithTitle:@"Desktop Connection" message:message preferredStyle:UIAlertControllerStyleAlert];
    [details addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:details animated:YES completion:nil];
}
- (void)loginEdited { [self clearRecovery]; self.progressLabel.text = @""; [self updateConnectionChrome]; }
- (void)showMacs { [self stopViewer]; if (self.macsHandler) self.macsHandler(); }
- (void)stopViewer {
    [self.controls close]; self.starting = NO; self.exited = YES; self.reconnectWhenReady = NO; self.checkingResume = NO;
    self.resumeGeneration++; self.restoreViewportPending = NO; self.resumeDisplayID = nil;
    self.keyboardViewportSaved = NO; self.keyboardLayoutPending = NO;
    if (self.sessionPhaseHandler) self.sessionPhaseHandler(@"ended");
    [self releasePointer]; self.zoomGeneration++; self.smartZoomed = NO; self.smartZoomPending = NO;
    [self updateTrackpadFeedback];
    [self clearCursor];
    [self.view endEditing:YES]; [self.session stop]; [self resetModifiers];
    self.image.image = nil; self.lastFramebuffer = nil; self.activeCrop = CGRectNull;
    UIApplication.sharedApplication.idleTimerDisabled = NO;
}
- (void)clearRecovery {
    self.loginIssueDetails = nil;
    if (!self.recoveryController) return;
    [self.recoveryController willMoveToParentViewController:nil];
    [self.login removeArrangedSubview:self.recoveryController.view];
    [self.recoveryController.view removeFromSuperview]; [self.recoveryController removeFromParentViewController];
    self.recoveryController = nil; [self.recoveryPanel removeFromSuperview]; self.recoveryPanel = nil;
}
- (void)showRecoveryController:(UIViewController *)controller overFrame:(BOOL)overFrame {
    [self clearRecovery]; self.recoveryController = controller; [self addChildViewController:controller];
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
    [controller didMoveToParentViewController:self]; self.progressLabel.text = @""; self.status.hidden = YES;
    [self updateConnectionChrome];
}
- (void)editRecoveryLogin { [self clearRecovery]; self.login.hidden = NO; self.starting = NO; [self updateConnectionChrome]; [self.username becomeFirstResponder]; }
- (void)showRecoveryStage:(NSInteger)stage {
    __weak CompanionVNCViewer *weak = self;
    UIViewController *card = [DirectRecoveryBridgeV1 desktopWithStage:stage hadFrame:self.lastFramebuffer != nil port:self.servicePort ?: 5900 retry:^{ [weak start]; } edit:^{ [weak editRecoveryLogin]; }];
    [self showRecoveryController:card overFrame:self.lastFramebuffer != nil];
    self.loginIssueDetails = [DirectRecoveryBridgeV1 desktopDetailsWithStage:stage hadFrame:self.lastFramebuffer != nil port:self.servicePort ?: 5900];
}
- (void)showConnectionFailure {
    self.starting = NO; self.checkingResume = NO; self.resumeGeneration++;
    if (self.sessionPhaseHandler) self.sessionPhaseHandler(@"ended");
    [self clearCursor]; [self resetModifiers]; self.connect.enabled = YES;
    [self showRecoveryStage:0];
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
- (void)rememberViewport {
    self.resumeDisplayID = self.selectedDisplay[@"id"];
    self.resumeFramebufferSize = self.framebufferSize;
    self.resumeZoomRatio = self.canvas.minimumZoomScale > 0 ? self.canvas.zoomScale / self.canvas.minimumZoomScale : 1;
    self.resumeCenter = CGRectIsEmpty(self.activeCrop) || CGRectIsNull(self.activeCrop) ? CGPointMake(.5, .5) : [self viewportCenter];
}
- (void)background { [self backgroundWithCompletion:nil]; }
- (void)backgroundWithCompletion:(void (^)(void))completion {
    if (!self.foreground || self.exited) { if (completion) completion(); return; }
    self.reconnectWhenReady = self.session.running || self.starting;
    self.foreground = NO; self.image.alpha = .45; self.resumeGeneration++; self.checkingResume = NO;
    [self updateTrackpadFeedback];
    [self.controls close]; [self rememberViewport]; [self releasePointer]; [self resetModifiers]; [self clearCursor];
    self.zoomGeneration++; self.smartZoomPending = NO;
    [self.view endEditing:YES]; UIApplication.sharedApplication.idleTimerDisabled = NO;
    self.status.text = @"Paused · Return to resume";
    if (self.reconnectWhenReady && self.sessionPhaseHandler) self.sessionPhaseHandler(@"paused");
    if (self.session.connected) [self.session pauseWithCompletion:completion];
    else {
        [self.session stop]; if (self.disconnectHandler) self.disconnectHandler();
        if (completion) completion();
    }
}
- (void)foregrounded {
    if (self.foreground || self.exited) return;
    self.foreground = YES;
    if (!self.reconnectWhenReady) return;
    self.checkingResume = YES;
    if (self.sessionPhaseHandler) self.sessionPhaseHandler(@"reconnecting");
    self.status.hidden = NO; self.status.text = @"Resuming desktop…"; self.image.alpha = .6;
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
    self.restoreViewportPending = YES; [self start];
}
- (void)restoreViewport {
    if (!self.restoreViewportPending || !self.lastFramebuffer) return;
    self.restoreViewportPending = NO;
    if (!CGSizeEqualToSize(self.framebufferSize, self.resumeFramebufferSize)) { self.resumeDisplayID = nil; return; }
    NSDictionary *display = nil;
    for (NSDictionary *candidate in self.displayViews) if ([candidate[@"id"] isEqual:self.resumeDisplayID]) { display = candidate; break; }
    BOOL missing = self.resumeDisplayID && !display;
    [self selectDisplay:display]; self.resumeDisplayID = nil;
    if (missing || CGRectIsNull(self.activeCrop)) return;
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
    CGSize pixels = CGSizeMake(CGImageGetWidth(frame.CGImage), CGImageGetHeight(frame.CGImage));
    BOOL resized = !CGSizeEqualToSize(self.framebufferSize, pixels);
    if (resized) { [self releasePointer]; self.zoomGeneration++; self.smartZoomed = NO; self.smartZoomPending = NO; [self clearCursor]; }
    self.framebufferSize = pixels; self.lastFramebuffer = frame;
    if (resized) [self updateDisplayPicker];
    [self restoreSavedDisplay]; [self renderFramebuffer:resized]; [self restoreViewport];
}
- (void)renderFramebuffer:(BOOL)reset {
    if (!self.lastFramebuffer) return;
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
    CGRect loginRegion = safe;
    loginRegion.size.height = MAX(0, loginRegion.size.height - self.keyboardOverlap);
    BOOL lowerLogin = divided && CGRectGetMaxY(loginRegion) - input.origin.y >= 240;
    if (divided) {
        loginRegion = lowerLogin ? CGRectIntersection(loginRegion, input) : CGRectIntersection(loginRegion, content);
    }
    self.loginTop.constant = CGRectGetMinY(loginRegion);
    self.loginBottom.constant = CGRectGetMaxY(loginRegion);
    BOOL compact = (divided || loginRegion.size.height < 520) && !UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    self.loginMaxWidth.constant = compact ? 720 : 440;
    self.login.spacing = compact ? 8 : 18;
    self.login.layoutMargins = compact ? UIEdgeInsetsMake(16,16,16,16) : UIEdgeInsetsMake(22,22,22,22);
    self.loginFields.spacing = compact ? 8 : 14;
    self.loginIntro.spacing = compact ? 8 : 16;
    self.credentialColumns.axis = compact && safe.size.width >= 520 ? UILayoutConstraintAxisHorizontal : UILayoutConstraintAxisVertical;
    self.credentialColumns.distribution = self.credentialColumns.axis == UILayoutConstraintAxisHorizontal ? UIStackViewDistributionFillEqually : UIStackViewDistributionFill;
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
        self.loginContentTop.constant = MAX(12, (loginRegion.size.height - fitting.height) / 2);
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
    [DirectConnectionBridge styleCard:self.login];
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
    self.tabletopLabel.text = @"Trackpad\nTap to click · Hold to drag\nTwo fingers to scroll";
    self.tabletopLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; self.tabletopLabel.adjustsFontForContentSizeCategory = YES;
    self.tabletopLabel.textColor = UIColor.secondaryLabelColor; [self.tabletopPad addSubview:self.tabletopLabel];
    CompanionVNCTapGesture *tap = [[CompanionVNCTapGesture alloc] initWithTarget:self action:@selector(clickAt:)];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragAt:)]; pan.maximumNumberOfTouches = 1;
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(holdAt:)]; hold.minimumPressDuration = .35;
    [pan requireGestureRecognizerToFail:hold]; [pan requireGestureRecognizerToFail:tap];
    UIPanGestureRecognizer *scroll = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(scrollRemote:)];
    scroll.minimumNumberOfTouches = 2; scroll.maximumNumberOfTouches = 2;
    self.tabletopGestures = @[tap, pan, hold, scroll];
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
            return viewer && viewer.foreground && !viewer.exited && !viewer.checkingResume && viewer.session.connected
                && viewer.login.hidden && !viewer.recoveryController && !viewer.presentedViewController;
        };
    }
    [self updateTrackpadFeedback];
}
- (void)setShowsTouchPoints:(BOOL)value { _showsTouchPoints = value; [self updateTrackpadFeedback]; }
- (void)setTrackpadHapticsEnabled:(BOOL)value { _trackpadHapticsEnabled = value; [self updateTrackpadFeedback]; }
- (void)updateTrackpadFeedback {
    BOOL ready = self.foreground && !self.exited && !self.checkingResume && self.session.connected
        && self.login.hidden && !self.recoveryController;
    self.trackpadFeedback.showsTouchPoints = self.showsTouchPoints;
    self.tabletopFeedback.showsTouchPoints = self.showsTouchPoints;
    self.trackpadFeedback.hapticsEnabled = self.trackpadHapticsEnabled;
    self.tabletopFeedback.hapticsEnabled = self.trackpadHapticsEnabled;
    self.trackpadFeedback.active = ready && self.trackpadMode && !self.canvas.hidden;
    self.tabletopFeedback.active = ready && !self.tabletopPad.hidden;
}
- (void)cancelTrackpadTouches { [self.trackpadFeedback cancelTouches]; [self.tabletopFeedback cancelTouches]; }
- (CompanionVNCTrackpadFeedback *)feedbackForGesture:(UIGestureRecognizer *)gesture {
    return gesture.view == self.tabletopPad ? self.tabletopFeedback : (self.trackpadMode ? self.trackpadFeedback : nil);
}
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    [self cancelTrackpadTouches]; [super presentViewController:controller animated:animated completion:completion];
}
- (void)chooseView {
    if (!self.framebufferSize.width) return;
    CompanionVNCDisplayPicker *picker = [CompanionVNCDisplayPicker new];
    self.displayPicker = picker;
    [self updateDisplayPicker];
    __weak CompanionVNCViewer *weak = self;
    picker.selectionHandler = ^(NSNumber *displayID) {
        // Resolve against the latest server layout, not a stale menu snapshot.
        NSDictionary *selected = nil;
        for (NSDictionary *d in weak.displayViews) if ([d[@"id"] isEqual:displayID]) { selected = d; break; }
        weak.initialDisplayApplied = YES; weak.restoredDisplayID = nil;
        [weak selectDisplay:selected];
        if (weak.displaySelectionHandler) weak.displaySelectionHandler(selected[@"id"]);
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
    self.displayPicker.layoutAspect = self.displayAspect;
    CGFloat aspect = self.framebufferSize.width / self.framebufferSize.height;
    self.displayPicker.displays = self.displayAspect > 0 && fabs(aspect - self.displayAspect) / self.displayAspect < .03 ? self.displayViews : @[];
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
}
- (CGPoint)trackpadPointer {
    CGPoint p = self.cursorPositionKnown ? self.cursorPosition : CGPointMake(CGRectGetMidX(self.activeCrop), CGRectGetMidY(self.activeCrop));
    p.x = MAX(CGRectGetMinX(self.activeCrop), MIN(CGRectGetMaxX(self.activeCrop) - 1, p.x));
    p.y = MAX(CGRectGetMinY(self.activeCrop), MIN(CGRectGetMaxY(self.activeCrop) - 1, p.y));
    return p;
}
- (BOOL)pointerForGesture:(UIGestureRecognizer *)gesture point:(CGPoint *)p {
    if (CGRectIsNull(self.activeCrop) || CGRectIsEmpty(self.activeCrop)) return NO;
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
- (void)clickAt:(UIGestureRecognizer *)gesture {
    CGPoint p;
    if (self.trackpadMode || gesture.view == self.tabletopPad) { if (CGRectIsNull(self.activeCrop) || CGRectIsEmpty(self.activeCrop)) return; p = [self trackpadPointer]; }
    else if (!CompanionVNCPointerPoint(self.activeCrop, [gesture locationInView:self.image], false, &p)) return;
    if ([self clickPointer:p mask:1]) {
        CompanionVNCTrackpadFeedback *feedback = [self feedbackForGesture:gesture];
        [feedback clickAtPoint:[gesture locationInView:feedback]];
    }
}
- (BOOL)clickPointer:(CGPoint)p mask:(NSInteger)mask {
    if (!self.foreground || self.exited || self.checkingResume || ![self.session tryClickX:p.x y:p.y mask:mask]) {
        self.status.hidden = NO; self.status.text = @"Click not sent. Wait for your Mac to resume."; return NO;
    }
    self.cursorPosition = p; self.cursorPositionKnown = YES; [self updateCursor];
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
    [[self feedbackForGesture:gesture] setDragging:held && self.foreground && !self.exited && !self.checkingResume && self.session.connected];
}
- (void)pinchRemote:(UIPinchGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded) {
        if (self.magnificationActive) [self.session endMagnification];
        self.magnificationActive = NO; return;
    }
    if (gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed
        || !self.inputOnly || !self.foreground || self.exited || self.checkingResume || !self.session.connected) {
        [self.session cancelNativeGestures]; self.magnificationActive = NO; return;
    }
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self releasePointer];
        if (CGRectIsNull(self.activeCrop) || CGRectIsEmpty(self.activeCrop)) return;
        CGPoint anchor = [self trackpadPointer];
        self.magnificationActive = [self.session beginMagnificationX:anchor.x y:anchor.y];
        if (!self.magnificationActive && !self.session.nativeMagnificationSupported) {
            self.status.hidden = NO; self.status.text = @"Native pinch is unavailable for this connection.";
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
        || !self.foreground || self.exited || self.checkingResume || !self.session.connected) {
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
    if (!self.foreground || self.exited || self.checkingResume) return;
    if (!self.session.connected) return;
    self.cursorPosition = point; self.cursorPositionKnown = YES; [self updateCursor];
    [self.session pointerX:point.x y:point.y mask:mask];
}
- (void)followTrackpadPointer:(CGPoint)point {
    if (self.inputOnly || !self.followCursorEnabled || (!self.trackpadMode && !self.tabletop) || self.cursorFollowingSuspended
        || !self.foreground || self.exited || self.checkingResume || !self.login.hidden
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
- (void)clearCursor {
    self.cursorPositionKnown = NO; self.remoteCursorImage = nil; self.cursorHotspot = CGPointZero;
    [self updateCursor];
}
- (void)receivedCursor:(UIImage *)image hotspot:(CGPoint)hotspot position:(CGPoint)position known:(BOOL)known {
    self.remoteCursorImage = image; self.cursorHotspot = hotspot;
    if (known) { self.cursorPosition = position; self.cursorPositionKnown = YES; }
    [self updateCursor];
}
- (void)updateCursor {
    CGPoint local = CGPointZero;
    if (!self.cursorPositionKnown || !self.image.image || !CompanionVNCCursorLocalPoint(self.activeCrop, self.cursorPosition, &local)) {
        self.cursorIndicator.hidden = YES; return;
    }
    CGPoint anchor = [self.image convertPoint:local toView:self.cursorOverlay];
    UIImage *shape = self.remoteCursorImage;
    CGRect bounds = CompanionVNCCursorScreenRect(anchor, shape ? shape.size : CGSizeMake(20, 28),
        shape ? self.cursorHotspot : CGPointMake(1, 1), shape ? self.canvas.zoomScale : 1);
    self.cursorIndicator.hidden = CGRectIsNull(bounds) || !CGRectContainsPoint(self.cursorOverlay.bounds, anchor);
    if (self.cursorIndicator.hidden) return;
    self.cursorIndicator.frame = bounds; self.cursorImage.frame = self.cursorIndicator.bounds;
    self.cursorImage.image = shape; self.cursorImage.hidden = shape == nil; self.fallbackCursor.hidden = shape != nil;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    self.fallbackCursor.frame = self.cursorIndicator.bounds; [CATransaction commit];
}
- (void)releasePointer {
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
- (void)keyboard {
    if (self.input.isFirstResponder) [self.input resignFirstResponder]; else [self.input becomeFirstResponder];
    [self updateKeyboardButton];
}
- (void)textViewDidBeginEditing:(UITextView *)textView { if (textView == self.input) [self updateKeyboardButton]; }
- (void)textViewDidEndEditing:(UITextView *)textView { if (textView == self.input) [self updateKeyboardButton]; }
- (void)keyboardFrame:(NSNotification *)notification {
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
- (void)singleModifier:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    [self.remoteKeyboard pressModifierAlone:(uint32_t)gesture.view.tag]; [self refreshModifiers];
}
- (void)remoteKey:(UIButton *)button {
    if ([self.modifiers containsObject:button]) {
        [self.remoteKeyboard toggleModifier:(uint32_t)button.tag]; [self refreshModifiers];
    } else [self sendRemoteKey:(uint32_t)button.tag];
}
- (void)moreKeys:(UIButton *)button {
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
    NSMutableArray *items = [NSMutableArray new];
    for (NSUInteger i = 0; i < 12; i++) [items addObject:@{@"kind": @"key", @"title": [NSString stringWithFormat:@"F%lu", (unsigned long)i+1], @"key": @(0xffbe + i), @"symbol": @"keyboard"}];
    [self presentMenu:@"Function Keys" sections:@[@{@"title": @"F1–F12", @"items": items}]];
}
- (void)showGestureHelp {
    NSString *gestures = self.inputOnly
        ? [@"Slide anywhere to move the cursor. Tap to click. Hold, then move to drag. Scroll with two fingers.\n\n" stringByAppendingString:self.session.nativeMagnificationSupported ? @"Pinch to zoom the app on your Mac at the cursor." : @"Native pinch is unavailable for this connection."]
        : @"Pointer: tap where you want to click.\nTrackpad: slide anywhere to move the cursor; scroll with two fingers.\n\nTap to click. Hold, then move to drag.\nPan the zoomed view with two fingers in Pointer or three in Trackpad.\nPinch to zoom the desktop image. Double tap with two fingers to zoom in or fit.";
    NSString *message = [gestures stringByAppendingString:@"\n\nHold Session Controls, slide onto a quick action or category, then release. Slide away to cancel."];
    UIAlertController *help = [UIAlertController alertControllerWithTitle:@"Gestures" message:message preferredStyle:UIAlertControllerStyleAlert];
    [help addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:help animated:YES completion:nil];
}
- (void)setQuickActions:(NSArray<NSDictionary *> *)quickActions {
    _quickActions = [quickActions copy]; self.controls.quickActions = quickActions;
}
- (void)updateConnectionChrome {
    self.loginSubtitle.text = self.inputOnly ? @"Trackpad & Keyboard" : @"Desktop";
    self.loginIcon.image = [UIImage systemImageNamed:self.inputOnly ? @"rectangle.and.hand.point.up.left" : @"desktopcomputer"];
    BOOL progress = self.starting || (self.session.running && !self.lastFramebuffer);
    BOOL loginVisible = !self.login.hidden;
    BOOL immersive = !loginVisible && !self.inputOnly;
    self.view.backgroundColor = immersive ? UIColor.blackColor : UIColor.systemBackgroundColor;
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
        self.loginBackdrop.view.hidden = !loginVisible;
        self.canvas.hidden = loginVisible;
        self.cursorOverlay.hidden = loginVisible || self.inputOnly;
    };
    if (visibilityChanged && self.view.window && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView transitionWithView:self.view duration:.18 options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction animations:showChrome completion:nil];
    } else { showChrome(); }
    [self updateTrackpadFeedback];
    // Keep the fields mounted so editing retains identity, but give an active
    // attempt one progress indicator and Cancel instead of disabled form chrome.
    self.loginFields.hidden = progress;
    self.loginFields.userInteractionEnabled = !progress;
    self.loginDetails.hidden = progress;
    self.connect.hidden = progress;
    self.loginClose.hidden = progress; self.loginCancel.hidden = !progress;
    self.connect.enabled = !progress && self.username.text.length > 0 && self.password.text.length > 0;
    self.connect.alpha = self.connect.enabled ? 1 : .35;
    [self.connect setTitle:self.recoveryController ? @"Try Again" : @"Connect" forState:UIControlStateNormal];
    self.progressRow.hidden = !progress && !self.progressLabel.text.length; self.spinner.hidden = !progress;
    // Let validation feedback fill the card width and grow vertically. A
    // hidden spinner in a horizontal stack can retain a one-line label height.
    self.progressRow.axis = UILayoutConstraintAxisVertical;
    if (progress) [self.spinner startAnimating]; else [self.spinner stopAnimating];
    self.controls.hidden = !self.loginScroll.hidden;
    self.toolbar.hidden = !self.loginScroll.hidden || self.fullscreen || self.recoveryPanel != nil;
    self.trackpadHelp.hidden = !self.loginScroll.hidden || !self.inputOnly;
    if (!self.loginScroll.hidden || (self.session.connected && !self.checkingResume)) self.status.hidden = YES;
    [self.view setNeedsLayout];
}
- (void)setFullscreen:(BOOL)value {
    _fullscreen = value; if (self.isViewLoaded) [self applyPresentation];
    if (self.presentationHandler) self.presentationHandler(value);
}
- (void)setInputOnly:(BOOL)value {
    _inputOnly = value;
    if (self.quickActionsProvider) self.quickActions = self.quickActionsProvider(value);
    if (self.isViewLoaded) {
        [self releasePointer]; [self cancelTrackpadTouches]; [self resetModifiers];
        if (self.session.connected) self.session.inputOnly = value;
        if (value) [self setTrackpadModeEnabled:YES];
        [self applyPresentation];
    }
}
- (void)applyPresentation {
    if (!self.canvasToolbarBottom) return;
    CGFloat ratio = self.canvas.minimumZoomScale > 0 ? self.canvas.zoomScale / self.canvas.minimumZoomScale : 1;
    CGPoint center = [self viewportCenter];
    self.canvasToolbarBottom.active = !self.tabletop && !self.fullscreen; self.canvasFullscreenBottom.active = !self.tabletop && self.fullscreen;
    self.image.hidden = self.inputOnly; self.cursorOverlay.hidden = self.inputOnly;
    self.canvas.pinchGestureRecognizer.enabled = !self.inputOnly;
    self.remotePinch.enabled = self.inputOnly;
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
    self.restoredDisplayID = nil; [self selectDisplay:selected];
}
- (void)performControlAction:(NSDictionary *)action {
    NSString *kind = action[@"kind"];
    if ([kind isEqual:@"viewMenu"]) { [self showViewMenu]; return; }
    if ([kind isEqual:@"inputMenu"]) { [self showInputMenu]; return; }
    if ([kind isEqual:@"appSettings"]) { if (self.appSettingsHandler) self.appSettingsHandler(); return; }
    if ([kind isEqual:@"gestures"]) { [self showGestureHelp]; return; }
    if ([kind isEqual:@"exit"]) { [self showMacs]; return; }
    if ([kind isEqual:@"details"]) { [self showConnectionDetails]; return; }
    if ([kind isEqual:@"setPointer"]) { if (!self.inputOnly) [self setTrackpadModeEnabled:NO]; return; }
    if ([kind isEqual:@"setTrackpad"]) { [self setTrackpadModeEnabled:YES]; return; }
    if ([kind isEqual:@"functionKeys"]) { [self showFunctionKeys]; return; }
    if ([kind isEqual:@"fullscreen"]) { self.fullscreen = !self.fullscreen; return; }
    if ([kind isEqual:@"inputOnly"]) { self.inputOnly = !self.inputOnly; return; }
    if ([kind isEqual:@"keyboard"]) { [self keyboard]; return; }
    if ([kind isEqual:@"displays"]) { [self chooseView]; return; }
    if ([kind isEqual:@"input"]) { if (self.settingsHandler) self.settingsHandler(); return; }
    if ([kind isEqual:@"mode"]) { if (!self.inputOnly) [self setTrackpadModeEnabled:!self.trackpadMode]; return; }
    if ([kind isEqual:@"fit"]) { [self fitDesktop]; return; }
    if ([kind isEqual:@"keys"]) { [self moreKeys:self.views]; return; }
    if ([kind isEqual:@"session"]) { [self showSessionMenu]; return; }
    if (!self.foreground || self.exited || self.checkingResume || !self.session.connected) {
        self.status.hidden = NO; self.status.text = @"Wait for the desktop to resume before sending input."; return;
    }
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
            self.status.hidden = NO; self.status.text = @"Input is busy. Try the action again.";
        }
        [self refreshModifiers];
    }
}
- (void)presentMenu:(NSString *)title sections:(NSArray<NSDictionary *> *)sections {
    CompanionVNCMenu *picker = [CompanionVNCMenu new]; picker.title = title; picker.sections = sections;
    __weak CompanionVNCViewer *weak = self;
    picker.selectionHandler = ^(NSDictionary *item) { [weak performControlAction:item]; };
    if ([self.presentedViewController isKindOfClass:UINavigationController.class]) {
        UINavigationController *navigation = (id)self.presentedViewController;
        if ([navigation.topViewController isKindOfClass:CompanionVNCMenu.class]) {
            [navigation pushViewController:picker animated:YES]; return;
        }
    }
    if (self.presentedViewController) return;
    UINavigationController *menu = [CompanionVNCMenu navigationControllerForMenu:picker sourceView:self.views];
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)showViewMenu {
    [self presentMenu:@"View & Display" sections:@[
        @{@"title": @"Desktop", @"items": @[
            @{@"kind": @"displays", @"title": @"Choose Display", @"symbol": @"display.2", @"submenu": @YES, @"push": @YES, @"disabled": @(self.inputOnly)},
            @{@"kind": @"fit", @"title": @"Fit View", @"symbol": @"arrow.down.right.and.arrow.up.left", @"disabled": @(self.inputOnly)}]},
        @{@"title": @"Presentation", @"items": @[
            @{@"kind": @"fullscreen", @"title": self.fullscreen ? @"Show Keyboard Bar" : @"Hide Keyboard Bar", @"symbol": self.fullscreen ? @"keyboard" : @"keyboard.chevron.compact.down"},
            @{@"kind": @"inputOnly", @"title": self.inputOnly ? @"Show Desktop" : @"Trackpad & Keyboard Only", @"symbol": self.inputOnly ? @"desktopcomputer" : @"rectangle.and.hand.point.up.left", @"subtitle": self.inputOnly ? @"Resume desktop video" : @"Control your Mac without video"}]}]];
}
- (void)showInputMenu {
    [self presentMenu:@"Keyboard & Input" sections:@[
        @{@"title": @"Mouse Mode", @"items": @[
            @{@"kind": @"setPointer", @"title": @"Pointer", @"symbol": @"cursorarrow", @"selected": @(!self.trackpadMode), @"disabled": @(self.inputOnly)},
            @{@"kind": @"setTrackpad", @"title": @"Trackpad", @"symbol": @"cursorarrow.motionlines", @"selected": @(self.trackpadMode)}]},
        @{@"title": @"Keyboard", @"items": @[
            @{@"kind": @"keyboard", @"title": self.input.isFirstResponder ? @"Hide Keyboard" : @"Show Keyboard", @"symbol": self.input.isFirstResponder ? @"keyboard.chevron.compact.down" : @"keyboard"},
            @{@"kind": @"keys", @"title": @"Extra Keys", @"symbol": @"keyboard", @"submenu": @YES, @"push": @YES}]},
        @{@"title": @"Preferences & Help", @"items": @[
            @{@"kind": @"input", @"title": @"Input & Quick Actions", @"symbol": @"slider.horizontal.3", @"submenu": @YES},
            @{@"kind": @"gestures", @"title": @"Gesture Guide", @"symbol": @"hand.draw"}]}]];
}
- (void)showConnectionDetails {
    NSString *message = [NSString stringWithFormat:@"%@\nBuilt-in macOS Screen Sharing\nDesktop: %.0f × %.0f\nIndividual displays: %lu", self.status.text ?: @"", self.framebufferSize.width, self.framebufferSize.height, (unsigned long)self.displayViews.count];
    UIAlertController *details = [UIAlertController alertControllerWithTitle:@"Connection Details" message:message preferredStyle:UIAlertControllerStyleAlert];
    [details addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:details animated:YES completion:nil];
}
- (void)showSessionMenu {
    [self presentMenu:self.macName ?: @"Session" sections:@[
        @{@"title": @"Session", @"items": @[
            @{@"kind": @"details", @"title": @"Connection Details", @"symbol": @"info.circle"},
            @{@"kind": @"appSettings", @"title": @"App Settings", @"symbol": @"gearshape", @"submenu": @YES}]},
        @{@"title": @"", @"items": @[@{@"kind": @"exit", @"title": @"Disconnect", @"symbol": @"xmark.circle", @"destructive": @YES}]}]];
}

@end

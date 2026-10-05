#import <UIKit/UIKit.h>
#import "CompanionVNCSession.h"
#import "CompanionVNCViewer.h"
#import "CompanionVNCKeyboard.h"
#import "CompanionVNCViewport.h"
#import "CompanionVNCCursor.h"
#import "CompanionVNCDisplayPicker.h"
#import "CompanionVNCControls.h"
#import "CompanionVNCTapGesture.h"
#import "CompanionVNCMenu.h"

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
@property UIStackView *login;
@property UIScrollView *loginScroll;
@property UIStackView *loginFields, *progressRow, *toolbar;
@property UILabel *progressLabel;
@property UIActivityIndicatorView *spinner;
@property CompanionVNCControls *controls;
@property BOOL initialDisplayApplied;
@property CGPoint trackpadTranslation;
@property UISwitch *remember;
@property UILabel *status;
@property UIButton *connect, *views, *pan, *keyboardButton;
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
@property UILabel *trackpadHelp;
@property UIGestureRecognizer *click;
@property UIPanGestureRecognizer *drag, *remoteScroll;
@property UILongPressGestureRecognizer *hold;
@property CGPoint trackpadOrigin, holdOrigin;
@property CGFloat scrollRemainder;
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
- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) _followCursorEnabled = YES;
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
    button.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    button.backgroundColor = UIColor.secondarySystemBackgroundColor;
    button.layer.cornerRadius = 10;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    return button;
}
- (UITextField *)field:(NSString *)placeholder {
    UITextField *field = [UITextField new]; field.placeholder = placeholder;
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    [field.heightAnchor constraintEqualToConstant:48].active = YES;
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
    self.controls.openingHandler = ^{ [weak releasePointer]; };
    self.views = self.controls.button;
    self.status.translatesAutoresizingMaskIntoConstraints = NO;
    self.canvas = [UIScrollView new]; self.canvas.delegate = self; self.canvas.backgroundColor = UIColor.blackColor;
    self.canvas.translatesAutoresizingMaskIntoConstraints = NO; self.canvas.maximumZoomScale = 5;
    self.canvas.bounces = NO;
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
    UIButton *visibility = [self button:@"Show Password" action:@selector(togglePassword)];
    visibility.accessibilityIdentifier = @"mac-login-visibility";
    self.remember = [UISwitch new];
    UILabel *rememberLabel = [UILabel new]; rememberLabel.text = @"Save login for this Mac";
    UIStackView *saveRow = [[UIStackView alloc] initWithArrangedSubviews:@[rememberLabel, self.remember]];
    UILabel *credentialHelp = [UILabel new];
    credentialHelp.text = @"Choose this Mac’s login in Passwords or 1Password. Saved logins in Mac Companion are separate for each Mac.";
    credentialHelp.numberOfLines = 0; credentialHelp.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; credentialHelp.textColor = UIColor.secondaryLabelColor;
    self.loginFields = [[UIStackView alloc] initWithArrangedSubviews:@[self.username, self.password, visibility, saveRow, self.connect, credentialHelp]];
    self.loginFields.axis = UILayoutConstraintAxisVertical; self.loginFields.spacing = 14;
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"desktopcomputer"]];
    icon.contentMode = UIViewContentModeScaleAspectFit; icon.tintColor = UIColor.systemBlueColor;
    [icon.heightAnchor constraintEqualToConstant:56].active = YES;
    UILabel *title = [UILabel new]; title.text = self.macName ?: @"Mac"; title.numberOfLines = 2;
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle1]; title.textAlignment = NSTextAlignmentCenter;
    UILabel *subtitle = [UILabel new]; subtitle.text = @"Sign in with your Mac account"; subtitle.textColor = UIColor.secondaryLabelColor; subtitle.textAlignment = NSTextAlignmentCenter;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.progressLabel = [UILabel new]; self.progressLabel.numberOfLines = 2;
    self.progressRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.spinner, self.progressLabel]];
    self.progressRow.spacing = 12;
    UILabel *notice = [UILabel new];
    notice.text = @"Use a trusted local network or your private VPN. Screen Sharing desktop and input traffic are not encrypted by this app.";
    notice.numberOfLines = 0; notice.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; notice.textColor = UIColor.secondaryLabelColor;
    UIButton *cancel = [self button:@"Cancel" action:@selector(showMacs)];
    cancel.accessibilityIdentifier = @"mac-login-cancel";
    self.login = [[UIStackView alloc] initWithArrangedSubviews:@[icon, title, subtitle, self.progressRow, self.loginFields, notice, cancel]];
    self.login.axis = UILayoutConstraintAxisVertical; self.login.spacing = 20;
    self.login.layoutMargins = UIEdgeInsetsMake(24, 20, 24, 20); self.login.layoutMarginsRelativeArrangement = YES;
    self.login.backgroundColor = UIColor.secondarySystemBackgroundColor; self.login.layer.cornerRadius = 24;
    self.login.translatesAutoresizingMaskIntoConstraints = NO;
    self.loginScroll = [UIScrollView new]; self.loginScroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.loginScroll.backgroundColor = UIColor.systemBackgroundColor; self.loginScroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.loginScroll addSubview:self.login]; [self.view addSubview:self.loginScroll];
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
    UIStackView *toolbar = [[UIStackView alloc] initWithArrangedSubviews:keys];
    toolbar.spacing = 4; toolbar.distribution = UIStackViewDistributionFillEqually;
    self.toolbar = toolbar;
    toolbar.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:toolbar];
    self.toolbarBottom = [toolbar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-4];
    [self.view addSubview:self.status]; [self.view addSubview:self.controls];
    self.canvasToolbarBottom = [self.canvas.bottomAnchor constraintEqualToAnchor:toolbar.topAnchor constant:-8];
    self.canvasFullscreenBottom = [self.canvas.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [self.status.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.status.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
        [self.status.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [toolbar.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:6],
        [toolbar.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-68], self.toolbarBottom,
        [self.canvas.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        self.canvasToolbarBottom,
        [self.canvas.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.canvas.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.cursorOverlay.leadingAnchor constraintEqualToAnchor:self.canvas.leadingAnchor],
        [self.cursorOverlay.trailingAnchor constraintEqualToAnchor:self.canvas.trailingAnchor],
        [self.cursorOverlay.topAnchor constraintEqualToAnchor:self.canvas.topAnchor],
        [self.cursorOverlay.bottomAnchor constraintEqualToAnchor:self.canvas.bottomAnchor],
        [self.controls.topAnchor constraintEqualToAnchor:self.view.topAnchor], [self.controls.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.controls.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.controls.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.loginScroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [self.loginScroll.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
        [self.loginScroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.loginScroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.login.topAnchor constraintEqualToAnchor:self.loginScroll.contentLayoutGuide.topAnchor constant:16],
        [self.login.bottomAnchor constraintEqualToAnchor:self.loginScroll.contentLayoutGuide.bottomAnchor constant:-16],
        [self.login.centerXAnchor constraintEqualToAnchor:self.loginScroll.centerXAnchor],
        [self.login.widthAnchor constraintLessThanOrEqualToConstant:440],
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
        if (strong.diagnosticHandler) strong.diagnosticHandler(stats);
        if (strong.exited) return;
        BOOL running = strong.session.running, connected = [state isEqualToString:@"Connected"] && strong.session.connected && strong.lastFramebuffer != nil;
        if (!strong.foreground) {
            strong.status.text = @"Paused · Return to resume";
            if (!running && strong.disconnectHandler) strong.disconnectHandler();
            return;
        }
        strong.status.text = state; strong.status.hidden = connected; strong.progressLabel.text = state;
        if (connected) {
            strong.session.inputOnly = strong.inputOnly;
            strong.image.alpha = 1;
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
            else { strong.login.hidden = NO; if (strong.sessionPhaseHandler) strong.sessionPhaseHandler(@"ended"); }
        }
        [strong updateConnectionChrome];
    };
}
- (void)start {
    self.starting = YES; self.exited = NO;
    if (self.sessionPhaseHandler) self.sessionPhaseHandler(@"reconnecting");
    [self.view endEditing:YES]; self.status.text = @"Connecting to Screen Sharing…";
    self.connect.enabled = NO; self.progressLabel.text = @"Contacting Mac…"; self.status.hidden = YES; [self updateConnectionChrome];
    if (self.connectHandler) self.connectHandler(self.username.text ?: @"", self.password.text ?: @"", self.remember.on);
}
- (void)connectionAction {
    if (!self.session.running && !self.starting) [self start];
}
- (void)showMacs { [self stopViewer]; if (self.macsHandler) self.macsHandler(); }
- (void)stopViewer {
    [self.controls close]; self.starting = NO; self.exited = YES; self.reconnectWhenReady = NO; self.checkingResume = NO;
    self.resumeGeneration++; self.restoreViewportPending = NO; self.resumeDisplayID = nil;
    self.keyboardViewportSaved = NO; self.keyboardLayoutPending = NO;
    if (self.sessionPhaseHandler) self.sessionPhaseHandler(@"ended");
    [self releasePointer]; self.zoomGeneration++; self.smartZoomed = NO; self.smartZoomPending = NO;
    [self clearCursor];
    [self.view endEditing:YES]; [self.session stop]; [self resetModifiers];
    self.image.image = nil; self.lastFramebuffer = nil; self.activeCrop = CGRectNull;
    UIApplication.sharedApplication.idleTimerDisabled = NO;
}
- (void)showConnectionFailure {
    self.starting = NO; self.checkingResume = NO; self.resumeGeneration++;
    if (self.sessionPhaseHandler) self.sessionPhaseHandler(@"ended");
    [self clearCursor];
    [self resetModifiers];
    self.connect.enabled = YES; self.status.text = @"Desktop unavailable. Check Screen Sharing, then reconnect.";
    self.progressLabel.text = self.status.text;
    self.login.hidden = NO; self.image.image = nil; self.status.hidden = NO; [self updateConnectionChrome];
}
- (void)showInvalidLogin {
    [self showConnectionFailure];
    self.progressLabel.text = @"Enter your Mac account username and password (up to 63 UTF-8 bytes each).";
    self.status.text = self.progressLabel.text;
}
- (void)showLoginRetentionFailure {
    NSString *message = @"Could not update the saved login. Check device access and retry.";
    if (self.session.connected) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Saved Login Unavailable" message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        if (!self.presentedViewController) [self presentViewController:alert animated:YES completion:nil];
    } else {
        [self showConnectionFailure]; self.status.text = message; self.progressLabel.text = message;
    }
}
- (void)rememberViewport {
    self.resumeDisplayID = self.selectedDisplay[@"id"];
    self.resumeFramebufferSize = self.framebufferSize;
    self.resumeZoomRatio = self.canvas.minimumZoomScale > 0 ? self.canvas.zoomScale / self.canvas.minimumZoomScale : 1;
    CGPoint point = [self.image convertPoint:CGPointMake(CGRectGetMidX(self.canvas.bounds), CGRectGetMidY(self.canvas.bounds)) fromView:self.canvas];
    self.resumeCenter = CGPointMake(self.activeCrop.size.width > 0 ? point.x / self.activeCrop.size.width : .5,
                                   self.activeCrop.size.height > 0 ? point.y / self.activeCrop.size.height : .5);
}
- (void)background { [self backgroundWithCompletion:nil]; }
- (void)backgroundWithCompletion:(void (^)(void))completion {
    if (!self.foreground || self.exited) { if (completion) completion(); return; }
    self.reconnectWhenReady = self.session.running || self.starting;
    self.foreground = NO; self.image.alpha = .45; self.resumeGeneration++; self.checkingResume = NO;
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
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
    CGFloat scale = MIN(self.canvas.maximumZoomScale, self.canvas.minimumZoomScale * MAX(1, self.resumeZoomRatio));
    [self.canvas setZoomScale:scale animated:NO]; [self scrollViewDidZoom:self.canvas];
    CGPoint center = CGPointMake(MAX(0, MIN(1, self.resumeCenter.x)) * self.activeCrop.size.width,
                                MAX(0, MIN(1, self.resumeCenter.y)) * self.activeCrop.size.height);
    CGPoint p = [self.image convertPoint:center toView:self.canvas];
    CGPoint offset = CGPointMake(MAX(0, MIN(self.canvas.contentSize.width - self.canvas.bounds.size.width, p.x - self.canvas.bounds.size.width / 2)),
                                MAX(0, MIN(self.canvas.contentSize.height - self.canvas.bounds.size.height, p.y - self.canvas.bounds.size.height / 2)));
    [self.canvas setContentOffset:offset animated:NO];
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
- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    CGFloat x = MAX(0, (scrollView.bounds.size.width - self.image.frame.size.width) / 2);
    CGFloat y = MAX(0, (scrollView.bounds.size.height - self.image.frame.size.height) / 2);
    self.image.center = CGPointMake(self.image.frame.size.width / 2 + x, self.image.frame.size.height / 2 + y);
    [self updateCursor];
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView { [self updateCursor]; }
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView { if (scrollView == self.canvas) self.cursorFollowingSuspended = YES; }
- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view { if (scrollView == self.canvas) self.cursorFollowingSuspended = YES; }
- (void)fitDesktop {
    if (CGRectIsNull(self.activeCrop) || CGRectIsEmpty(self.activeCrop) || self.canvas.bounds.size.width <= 0 || self.canvas.bounds.size.height <= 0) return;
    self.smartZoomed = NO; self.smartZoomPending = NO; self.zoomGeneration++;
    CGFloat fit = MIN(self.canvas.bounds.size.width / self.activeCrop.size.width, self.canvas.bounds.size.height / self.activeCrop.size.height);
    self.canvas.minimumZoomScale = fit; [self.canvas setZoomScale:fit animated:NO];
    self.canvas.contentOffset = CGPointZero; [self scrollViewDidZoom:self.canvas];
}
- (CGPoint)viewportCenter {
    CGPoint point = [self.image convertPoint:CGPointMake(CGRectGetMidX(self.canvas.bounds), CGRectGetMidY(self.canvas.bounds)) fromView:self.canvas];
    return CGPointMake(MAX(0, MIN(1, point.x / self.activeCrop.size.width)), MAX(0, MIN(1, point.y / self.activeCrop.size.height)));
}
- (void)applyViewportRatio:(CGFloat)ratio center:(CGPoint)center {
    if (ratio <= 1.01) { [self fitDesktop]; return; }
    CGFloat scale = MIN(self.canvas.maximumZoomScale, self.canvas.minimumZoomScale * MAX(1, ratio));
    [self.canvas setZoomScale:scale animated:NO]; [self scrollViewDidZoom:self.canvas];
    CGPoint point = [self.image convertPoint:CGPointMake(center.x * self.activeCrop.size.width, center.y * self.activeCrop.size.height) toView:self.canvas];
    CGPoint offset = CGPointMake(MAX(0, MIN(self.canvas.contentSize.width - self.canvas.bounds.size.width, point.x - self.canvas.bounds.size.width / 2)),
                                MAX(0, MIN(self.canvas.contentSize.height - self.canvas.bounds.size.height, point.y - self.canvas.bounds.size.height / 2)));
    [self.canvas setContentOffset:offset animated:NO];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (CGRectIsNull(self.activeCrop) || CGRectIsEmpty(self.activeCrop)) return;
    BOOL wasFit = self.canvas.zoomScale <= self.canvas.minimumZoomScale * 1.01;
    CGSize size = self.canvas.bounds.size;
    if (size.width <= 0 || size.height <= 0) return;
    self.canvas.minimumZoomScale = MIN(size.width / self.activeCrop.size.width, size.height / self.activeCrop.size.height);
    BOOL resized = !CGSizeEqualToSize(size, self.previousCanvasSize);
    if (resized) {
        self.previousCanvasSize = size; self.zoomGeneration++; self.smartZoomPending = NO;
    }
    if (self.keyboardLayoutPending) {
        self.keyboardLayoutPending = NO;
        [self applyViewportRatio:self.keyboardLayoutRatio center:self.keyboardLayoutCenter];
    } else if (resized) {
        if (self.smartZoomed) [self.canvas zoomToRect:self.smartWindow animated:NO];
        else if (wasFit) [self fitDesktop];
        else [self scrollViewDidZoom:self.canvas];
    }
    [self updateCursor];
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
    UINavigationController *menu = [[UINavigationController alloc] initWithRootViewController:picker];
    menu.modalPresentationStyle = UIModalPresentationPopover;
    menu.preferredContentSize = CGSizeMake(360, MIN(520, 116 + 72 * (picker.displays.count + 1)));
    menu.popoverPresentationController.sourceView = self.views;
    menu.popoverPresentationController.sourceRect = self.views.bounds;
    menu.popoverPresentationController.delegate = picker;
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
    [self releasePointer];
    // Cancel recognizers in progress before switching coordinate systems.
    for (UIGestureRecognizer *gesture in @[self.drag, self.hold, self.remoteScroll]) { gesture.enabled = NO; gesture.enabled = YES; }
    self.controls.trackpad = enabled;
    if (self.inputModeHandler) self.inputModeHandler(enabled);
    self.trackpadMode = enabled; self.scrollRemainder = 0;
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
    if (!self.trackpadMode) return CompanionVNCPointerPoint(self.activeCrop, [gesture locationInView:self.image], self.pointerHeld, p);
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.trackpadOrigin = [self trackpadPointer]; self.trackpadTranslation = CGPointZero;
        self.cursorFollowingSuspended = NO;
    }
    CGPoint delta = CGPointZero;
    if ([gesture isKindOfClass:UIPanGestureRecognizer.class]) delta = [(UIPanGestureRecognizer *)gesture translationInView:self.canvas];
    else if ([gesture isKindOfClass:UILongPressGestureRecognizer.class]) {
        // The overlay's origin stays fixed when auto-follow scrolls the canvas.
        CGPoint location = [gesture locationInView:self.cursorOverlay];
        if (gesture.state == UIGestureRecognizerStateBegan) self.holdOrigin = location;
        delta = CGPointMake(location.x - self.holdOrigin.x, location.y - self.holdOrigin.y);
    }
    CGPoint step = CGPointMake(delta.x - self.trackpadTranslation.x, delta.y - self.trackpadTranslation.y);
    self.trackpadTranslation = delta;
    CGFloat velocity = 0;
    if ([gesture isKindOfClass:UIPanGestureRecognizer.class]) { CGPoint v = [(UIPanGestureRecognizer *)gesture velocityInView:self.canvas]; velocity = hypot(v.x, v.y); }
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
    if (self.trackpadMode) { if (CGRectIsNull(self.activeCrop) || CGRectIsEmpty(self.activeCrop)) return; p = [self trackpadPointer]; }
    else if (!CompanionVNCPointerPoint(self.activeCrop, [gesture locationInView:self.image], false, &p)) return;
    [self clickPointer:p mask:1];
}
- (void)clickPointer:(CGPoint)p mask:(NSInteger)mask {
    if (!self.foreground || self.exited || self.checkingResume || ![self.session tryClickX:p.x y:p.y mask:mask]) {
        self.status.hidden = NO; self.status.text = @"Click not sent. Wait for your Mac to resume."; return;
    }
    self.cursorPosition = p; self.cursorPositionKnown = YES; [self updateCursor];
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
}
- (void)scrollRemote:(UIPanGestureRecognizer *)gesture {
    if (CGRectIsNull(self.activeCrop) || CGRectIsEmpty(self.activeCrop)) return;
    if (gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) { self.scrollRemainder = 0; return; }
    if (gesture.state == UIGestureRecognizerStateBegan) self.scrollRemainder = 0;
    CGFloat delta = [gesture translationInView:self.canvas].y;
    [gesture setTranslation:CGPointZero inView:self.canvas];
    self.scrollRemainder += delta;
    NSInteger steps = MIN(8, (NSInteger)(fabs(self.scrollRemainder) / 18));
    NSInteger mask = self.scrollRemainder > 0 ? 8 : 16;
    for (NSInteger i = 0; i < steps; i++) { CGPoint p = [self trackpadPointer]; [self sendPointer:p mask:mask]; [self sendPointer:p mask:0]; }
    self.scrollRemainder -= steps * 18 * (self.scrollRemainder > 0 ? 1 : -1);
}
- (void)sendPointer:(CGPoint)point mask:(NSInteger)mask {
    if (!self.foreground || self.exited || self.checkingResume) return;
    if (!self.session.connected) return;
    self.cursorPosition = point; self.cursorPositionKnown = YES; [self updateCursor];
    [self.session pointerX:point.x y:point.y mask:mask];
}
- (void)followTrackpadPointer:(CGPoint)point {
    if (self.inputOnly || !self.followCursorEnabled || !self.trackpadMode || self.cursorFollowingSuspended
        || !self.foreground || self.exited || self.checkingResume || !self.login.hidden
        || self.presentedViewController || self.canvas.dragging || self.canvas.decelerating || self.canvas.zooming
        || self.canvas.zoomScale <= self.canvas.minimumZoomScale * 1.01) return;
    CGPoint local = CGPointZero;
    if (!self.image.image || !CompanionVNCCursorLocalPoint(self.activeCrop, point, &local)) return;
    CGPoint anchor = [self.image convertPoint:local toView:self.canvas];
    CGPoint offset = CompanionVNCFollowOffset(self.canvas.contentSize, self.canvas.bounds, anchor);
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
    UIAlertController *help = [UIAlertController alertControllerWithTitle:@"Gestures" message:@"Pointer: tap where you want to click.\nTrackpad: slide anywhere to move the cursor; scroll with two fingers.\n\nTap to click. Hold, then move to drag.\nPan the zoomed view with two fingers in Pointer or three in Trackpad.\nPinch to zoom. Double tap with two fingers to zoom in or fit.\n\nHold Session Controls, slide onto a quick action or category, then release. Slide away to cancel." preferredStyle:UIAlertControllerStyleAlert];
    [help addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:help animated:YES completion:nil];
}
- (void)setQuickActions:(NSArray<NSDictionary *> *)quickActions {
    _quickActions = [quickActions copy]; self.controls.quickActions = quickActions;
}
- (void)updateConnectionChrome {
    BOOL progress = self.starting || (self.session.running && !self.lastFramebuffer);
    self.loginScroll.hidden = self.login.hidden;
    self.loginFields.hidden = progress;
    self.progressRow.hidden = !progress && !self.progressLabel.text.length;
    if (progress) [self.spinner startAnimating]; else [self.spinner stopAnimating];
    self.controls.hidden = !self.loginScroll.hidden;
    self.toolbar.hidden = !self.loginScroll.hidden || self.fullscreen;
    self.trackpadHelp.hidden = !self.loginScroll.hidden || !self.inputOnly;
    if (!self.loginScroll.hidden || (self.session.connected && !self.checkingResume)) self.status.hidden = YES;
}
- (void)setFullscreen:(BOOL)value {
    _fullscreen = value; if (self.isViewLoaded) [self applyPresentation];
    if (self.presentationHandler) self.presentationHandler(value);
}
- (void)setInputOnly:(BOOL)value {
    _inputOnly = value;
    if (self.isViewLoaded) {
        [self releasePointer]; [self resetModifiers];
        if (self.session.connected) self.session.inputOnly = value;
        if (value) [self setTrackpadModeEnabled:YES];
        [self applyPresentation];
    }
}
- (void)applyPresentation {
    if (!self.canvasToolbarBottom) return;
    CGFloat ratio = self.canvas.minimumZoomScale > 0 ? self.canvas.zoomScale / self.canvas.minimumZoomScale : 1;
    CGPoint center = [self viewportCenter];
    self.canvasToolbarBottom.active = !self.fullscreen; self.canvasFullscreenBottom.active = self.fullscreen;
    self.image.hidden = self.inputOnly; self.cursorOverlay.hidden = self.inputOnly;
    self.canvas.backgroundColor = self.inputOnly ? UIColor.systemBackgroundColor : UIColor.blackColor;
    self.trackpadHelp.hidden = !self.inputOnly || !self.login.hidden;
    self.controls.fullscreen = self.fullscreen; self.controls.inputOnly = self.inputOnly;
    self.keyboardLayoutPending = YES; self.keyboardLayoutRatio = ratio; self.keyboardLayoutCenter = center;
    [self updateConnectionChrome]; [self.view setNeedsLayout];
}
- (void)togglePassword {
    self.password.secureTextEntry = !self.password.secureTextEntry;
    UIButton *button = (UIButton *)self.loginFields.arrangedSubviews[2];
    [button setTitle:self.password.secureTextEntry ? @"Show Password" : @"Hide Password" forState:UIControlStateNormal];
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
    if ([kind isEqual:@"key"]) { [self sendRemoteKey:[action[@"key"] unsignedIntValue]]; return; }
    if ([kind isEqual:@"modifier"]) { [self.remoteKeyboard pressModifierAlone:[action[@"key"] unsignedIntValue]]; [self refreshModifiers]; return; }
    if ([kind isEqual:@"rightClick"]) {
        CGPoint p = [self trackpadPointer]; [self clickPointer:p mask:4];
    } else if ([kind isEqual:@"shortcut"] || [kind isEqual:@"text"]) {
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
    UINavigationController *menu = [[UINavigationController alloc] initWithRootViewController:picker];
    menu.modalPresentationStyle = UIModalPresentationPopover; menu.preferredContentSize = CGSizeMake(360, 480);
    menu.popoverPresentationController.sourceView = self.views; menu.popoverPresentationController.sourceRect = self.views.bounds;
    menu.popoverPresentationController.delegate = picker;
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)showViewMenu {
    [self presentMenu:@"View & Display" sections:@[
        @{@"title": @"Desktop", @"items": @[
            @{@"kind": @"displays", @"title": @"Choose Display", @"symbol": @"display.2", @"submenu": @YES, @"push": @YES, @"disabled": @(self.inputOnly)},
            @{@"kind": @"fit", @"title": @"Fit View", @"symbol": @"arrow.up.left.and.arrow.down.right", @"disabled": @(self.inputOnly)}]},
        @{@"title": @"Presentation", @"items": @[
            @{@"kind": @"fullscreen", @"title": self.fullscreen ? @"Show Keyboard Bar" : @"Hide Keyboard Bar", @"symbol": self.fullscreen ? @"keyboard" : @"arrow.up.left.and.arrow.down.right"},
            @{@"kind": @"inputOnly", @"title": self.inputOnly ? @"Show Desktop" : @"Trackpad & Keyboard Only", @"symbol": @"rectangle.and.hand.point.up.left", @"subtitle": self.inputOnly ? @"Resume desktop video" : @"Control your Mac without video"}]}]];
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
            @{@"kind": @"details", @"title": @"Connection Details", @"symbol": @"network"},
            @{@"kind": @"appSettings", @"title": @"App Settings", @"symbol": @"gearshape", @"submenu": @YES}]},
        @{@"title": @"", @"items": @[@{@"kind": @"exit", @"title": @"Exit to My Macs", @"symbol": @"rectangle.portrait.and.arrow.right", @"destructive": @YES}]}]];
}

@end

#import <UIKit/UIKit.h>
#import "VNCSession.h"

@interface RemoteTextInput : UITextView
@property(nonatomic, copy) void (^remoteDelete)(void);
@end
@implementation RemoteTextInput
- (void)deleteBackward {
    if (self.text.length || self.markedTextRange) [super deleteBackward];
    else if (self.remoteDelete) self.remoteDelete();
}
@end

@interface Viewer : UIViewController <UIScrollViewDelegate, UITextViewDelegate, NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@property VNCSession *session;
@property UITextField *host, *username, *password;
@property UIStackView *login;
@property UILabel *status;
@property UIButton *connect, *views, *pan;
@property UIScrollView *canvas;
@property UIImageView *image;
@property RemoteTextInput *input;
@property NSLayoutConstraint *toolbarBottom;
@property UITapGestureRecognizer *click;
@property UIPanGestureRecognizer *drag;
@property NSArray *displayViews;
@property CGFloat displayAspect;
@property CGSize framebufferSize;
@property NSNetServiceBrowser *browser;
@property NSMutableArray<NSNetService *> *services;
@property BOOL panMode, dragMode, reconnectWhenReady, foreground, fixtureExercised;
@property NSMutableArray<UIButton *> *modifiers;
@end

@implementation Viewer
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
    self.view.backgroundColor = UIColor.blackColor; self.foreground = YES;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.modifiers = [NSMutableArray new]; self.services = [NSMutableArray new];
    self.session = [VNCSession new];
    __weak Viewer *weak = self;
    self.session.frameHandler = ^(UIImage *image) { [weak frame:image]; };
    self.session.stateHandler = ^(NSString *state, NSDictionary *stats) {
        Viewer *strong = weak; if (!strong) return;
        strong.status.text = [NSString stringWithFormat:@"%@ · connections %@ · views %@", state, stats[@"connectionStarts"], stats[@"viewChanges"]];
        BOOL running = strong.session.running;
        strong.login.hidden = running;
        [strong.connect setTitle:running ? @"Disconnect" : @"Connect" forState:UIControlStateNormal];
        UIApplication.sharedApplication.idleTimerDisabled = running;
        if (!running && strong.foreground && strong.reconnectWhenReady) {
            strong.reconnectWhenReady = NO; [strong start];
        }
    };
    self.status = [UILabel new]; self.status.text = @"VNC Prototype · local network";
    self.status.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.status.textColor = UIColor.secondaryLabelColor; self.status.numberOfLines = 2;
    self.connect = [self button:@"Connect" action:@selector(connectionAction)];
    self.views = [self button:@"Desktop ▾" action:@selector(chooseView)];
    self.pan = [self button:@"Pointer" action:@selector(togglePan)];
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[self.connect, self.views, self.pan]];
    header.distribution = UIStackViewDistributionFillEqually; header.spacing = 8;
    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[header, self.status]];
    top.axis = UILayoutConstraintAxisVertical; top.spacing = 8; top.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:top];
    self.canvas = [UIScrollView new]; self.canvas.delegate = self; self.canvas.backgroundColor = UIColor.blackColor;
    self.canvas.translatesAutoresizingMaskIntoConstraints = NO; self.canvas.maximumZoomScale = 5;
    self.canvas.bounces = NO;
    self.image = [UIImageView new]; self.image.userInteractionEnabled = YES;
    [self.canvas addSubview:self.image]; [self.view addSubview:self.canvas];
    self.click = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(clickAt:)];
    self.drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragAt:)];
    self.drag.maximumNumberOfTouches = 1;
    [self.image addGestureRecognizer:self.click]; [self.image addGestureRecognizer:self.drag];
    self.canvas.panGestureRecognizer.minimumNumberOfTouches = 2;
    self.host = [self field:@"Mac name.local or local IPv4 address"];
    self.host.keyboardType = UIKeyboardTypeASCIICapable;
    self.username = [self field:@"Mac account username"];
    self.password = [self field:@"Mac account password"]; self.password.secureTextEntry = YES;
    self.password.textContentType = UITextContentTypePassword;
    UILabel *instructions = [UILabel new];
    instructions.text = @"Connect to macOS Screen Sharing. Enter your Mac account directly here. Credentials stay in memory. This LAN prototype does not use Mac Companion pairing.\n\nTap to click; drag to move the pointer. Use two fingers to pan, or switch Pointer to Pan. Pinch to zoom. App focus is controlled using remote keys.";
    instructions.numberOfLines = 0; instructions.font = [UIFont systemFontOfSize:14];
    instructions.textColor = UIColor.secondaryLabelColor;
    self.login = [[UIStackView alloc] initWithArrangedSubviews:@[self.host, self.username, self.password, instructions]];
    self.login.axis = UILayoutConstraintAxisVertical; self.login.spacing = 14;
    self.login.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:self.login];
    NSMutableArray *keys = [NSMutableArray new];
    [keys addObject:[self button:@"⌨" action:@selector(keyboard)]];
    NSArray *titles = @[@"esc", @"⇥", @"⇧", @"⌃", @"⌥", @"⌘", @"⋯"];
    NSArray *symbols = @[@(0xff1b), @(0xff09), @(0xffe1), @(0xffe3), @(0xffe9), @(0xffeb), @0];
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *key = [self button:titles[i] action:i == 6 ? @selector(moreKeys:) : @selector(remoteKey:)];
        key.tag = [symbols[i] integerValue]; [keys addObject:key];
        if (i >= 2 && i <= 5) [self.modifiers addObject:key];
    }
    UIStackView *toolbar = [[UIStackView alloc] initWithArrangedSubviews:keys];
    toolbar.spacing = 4; toolbar.distribution = UIStackViewDistributionFillEqually;
    toolbar.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:toolbar];
    self.toolbarBottom = [toolbar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-4];
    [NSLayoutConstraint activateConstraints:@[
        [top.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [top.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [top.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [toolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:6],
        [toolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-6], self.toolbarBottom,
        [self.canvas.topAnchor constraintEqualToAnchor:top.bottomAnchor constant:8],
        [self.canvas.bottomAnchor constraintEqualToAnchor:toolbar.topAnchor constant:-8],
        [self.canvas.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.canvas.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.login.topAnchor constraintEqualToAnchor:top.bottomAnchor constant:24],
        [self.login.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [self.login.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24]
    ]];
    self.input = [[RemoteTextInput alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
    self.input.alpha = 0.02; self.input.delegate = self;
    self.input.accessibilityLabel = @"Remote keyboard input";
    self.input.autocorrectionType = UITextAutocorrectionTypeNo;
    self.input.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.input.smartQuotesType = UITextSmartQuotesTypeNo; self.input.smartDashesType = UITextSmartDashesTypeNo;
    self.input.remoteDelete = ^{ [weak.session key:0xff08 down:YES]; [weak.session key:0xff08 down:NO]; };
    [self.view addSubview:self.input];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(keyboardFrame:) name:UIKeyboardWillChangeFrameNotification object:nil];
    NSURL *layoutURL = [NSBundle.mainBundle URLForResource:@"DisplayLayout" withExtension:@"json"];
    NSDictionary *layout = layoutURL ? [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:layoutURL] options:0 error:nil] : nil;
    self.displayViews = layout[@"views"] ?: @[]; self.displayAspect = [layout[@"aspectRatio"] doubleValue];
    self.browser = [NSNetServiceBrowser new]; self.browser.delegate = self;
    [self.browser searchForServicesOfType:@"_rfb._tcp." inDomain:@"local."];
#if TARGET_OS_SIMULATOR
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--fixture"]) [self.session connectFixture];
    else if ([NSProcessInfo.processInfo.arguments containsObject:@"--probe-mac"]) [self.session probeMacHandshake];
#endif
}
- (void)start {
    [self.view endEditing:YES];
#if TARGET_OS_SIMULATOR
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--fixture"]) { [self.session connectFixture]; return; }
#endif
    [self.session connectHost:self.host.text username:self.username.text password:self.password.text];
}
- (void)connectionAction {
    self.reconnectWhenReady = NO;
    if (self.session.running) {
        [self.view endEditing:YES]; [self.session stop]; self.password.text = @"";
        [self resetModifiers];
    } else [self start];
}
- (void)background {
    self.foreground = NO; self.reconnectWhenReady = self.session.running;
    [self resetModifiers]; [self.session stop]; [self.input resignFirstResponder];
}
- (void)foregrounded {
    self.foreground = YES;
    if (self.reconnectWhenReady && !self.session.running) { self.reconnectWhenReady = NO; [self start]; }
}
- (void)resetModifiers {
    for (UIButton *key in self.modifiers) {
        key.selected = NO; key.backgroundColor = UIColor.secondarySystemBackgroundColor;
    }
}
- (void)frame:(UIImage *)frame {
    BOOL resized = !CGSizeEqualToSize(self.framebufferSize, frame.size);
    self.framebufferSize = frame.size;
    self.image.image = frame;
    if (resized) {
        self.canvas.zoomScale = 1; self.image.frame = (CGRect){CGPointZero, frame.size};
        self.canvas.contentSize = frame.size; [self fitDesktop];
    }
#if TARGET_OS_SIMULATOR
    if (!self.fixtureExercised && [NSProcessInfo.processInfo.arguments containsObject:@"--exercise"]) {
        self.fixtureExercised = YES;
        [self.session pointerX:40 y:50 mask:1];
        for (NSUInteger i = 0; i < 200; i++) [self.session pointerX:41 + i y:51 + i mask:1];
        [self.session pointerX:240 y:250 mask:0];
        [self.session text:@"test"];
        [self.session key:0xffeb down:YES]; [self.session key:'c' down:YES];
        [self.session key:'c' down:NO]; [self.session key:0xffeb down:NO];
        for (NSUInteger i = 0; i < 50; i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self.session viewChanged];
                if (i % 2) [self fitDesktop]; else [self.canvas zoomToRect:CGRectMake(0, 0, self.framebufferSize.width / 2, self.framebufferSize.height / 2) animated:NO];
            });
        }
    }
#endif
}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView { return self.image; }
- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    CGFloat x = MAX(0, (scrollView.bounds.size.width - self.image.frame.size.width) / 2);
    CGFloat y = MAX(0, (scrollView.bounds.size.height - self.image.frame.size.height) / 2);
    self.image.center = CGPointMake(self.image.frame.size.width / 2 + x, self.image.frame.size.height / 2 + y);
}
- (void)fitDesktop {
    if (self.framebufferSize.width <= 0 || self.canvas.bounds.size.width <= 0) return;
    CGFloat fit = MIN(self.canvas.bounds.size.width / self.framebufferSize.width, self.canvas.bounds.size.height / self.framebufferSize.height);
    self.canvas.minimumZoomScale = fit; [self.canvas setZoomScale:fit animated:NO];
    [self scrollViewDidZoom:self.canvas]; [self.views setTitle:@"Desktop ▾" forState:UIControlStateNormal];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.canvas.minimumZoomScale = self.framebufferSize.width > 0 ? MIN(self.canvas.bounds.size.width / self.framebufferSize.width, self.canvas.bounds.size.height / self.framebufferSize.height) : 1;
}
- (void)chooseView {
    if (!self.framebufferSize.width) return;
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Desktop view" message:@"These views share the same VNC connection." preferredStyle:UIAlertControllerStyleActionSheet];
    __weak Viewer *weak = self;
    [menu addAction:[UIAlertAction actionWithTitle:@"All Displays" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weak.session viewChanged]; [weak fitDesktop];
    }]];
    CGFloat aspect = self.framebufferSize.width / self.framebufferSize.height;
    if (self.displayAspect > 0 && fabs(aspect - self.displayAspect) / self.displayAspect < 0.03) {
        for (NSDictionary *display in self.displayViews) {
            [menu addAction:[UIAlertAction actionWithTitle:display[@"title"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [weak.session viewChanged];
                CGRect rect = CGRectMake([display[@"x"] doubleValue] * weak.framebufferSize.width,
                    [display[@"y"] doubleValue] * weak.framebufferSize.height,
                    [display[@"width"] doubleValue] * weak.framebufferSize.width,
                    [display[@"height"] doubleValue] * weak.framebufferSize.height);
                [weak.canvas zoomToRect:rect animated:YES];
                [weak.views setTitle:display[@"title"] forState:UIControlStateNormal];
            }]];
        }
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = self.views;
    menu.popoverPresentationController.sourceRect = self.views.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)togglePan {
    // Pointer -> Drag -> Pan; two-finger pan remains available in the first two modes.
    if (self.panMode) { self.panMode = NO; self.dragMode = NO; }
    else if (self.dragMode) { self.dragMode = NO; self.panMode = YES; }
    else self.dragMode = YES;
    self.click.enabled = !self.panMode; self.drag.enabled = !self.panMode;
    self.canvas.panGestureRecognizer.minimumNumberOfTouches = self.panMode ? 1 : 2;
    [self.pan setTitle:self.panMode ? @"Pan" : self.dragMode ? @"Drag" : @"Pointer" forState:UIControlStateNormal];
}
- (void)clickAt:(UITapGestureRecognizer *)gesture {
    CGPoint p = [gesture locationInView:self.image];
    [self.session pointerX:p.x y:p.y mask:1]; [self.session pointerX:p.x y:p.y mask:0];
}
- (void)dragAt:(UIPanGestureRecognizer *)gesture {
    CGPoint p = [gesture locationInView:self.image];
    BOOL held = self.dragMode && (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged);
    [self.session pointerX:p.x y:p.y mask:held ? 1 : 0];
}
- (void)keyboard { if (self.input.isFirstResponder) [self.input resignFirstResponder]; else [self.input becomeFirstResponder]; }
- (void)keyboardFrame:(NSNotification *)notification {
    CGRect keyboard = [self.view convertRect:[notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(keyboard) - self.view.safeAreaInsets.bottom);
    self.toolbarBottom.constant = -4 - overlap;
    [UIView animateWithDuration:0.2 animations:^{ [self.view layoutIfNeeded]; }];
}
- (void)textViewDidChange:(UITextView *)textView {
    if (textView.markedTextRange || !textView.text.length) return;
    [self.session text:textView.text]; textView.text = @"";
}
- (void)remoteKey:(UIButton *)button {
    if ([self.modifiers containsObject:button]) {
        button.selected = !button.selected;
        button.backgroundColor = button.selected ? UIColor.systemBlueColor : UIColor.secondarySystemBackgroundColor;
        [self.session key:(uint32_t)button.tag down:button.selected];
    } else { [self.session key:(uint32_t)button.tag down:YES]; [self.session key:(uint32_t)button.tag down:NO]; }
}
- (void)moreKeys:(UIButton *)button {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Remote keys" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *titles = @[@"Return", @"Backspace", @"↑", @"↓", @"←", @"→", @"Right click", @"Scroll up", @"Scroll down"];
    NSArray *symbols = @[@(0xff0d), @(0xff08), @(0xff52), @(0xff54), @(0xff51), @(0xff53)];
    __weak Viewer *weak = self;
    for (NSUInteger i = 0; i < titles.count; i++) {
        [menu addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            if (i < symbols.count) { uint32_t key = [symbols[i] unsignedIntValue]; [weak.session key:key down:YES]; [weak.session key:key down:NO]; }
            else { CGPoint p = [weak.image convertPoint:CGPointMake(CGRectGetMidX(weak.canvas.bounds), CGRectGetMidY(weak.canvas.bounds)) fromView:weak.canvas];
                NSInteger mask = i == 6 ? 4 : i == 7 ? 8 : 16;
                [weak.session pointerX:p.x y:p.y mask:mask]; [weak.session pointerX:p.x y:p.y mask:0]; }
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = button; menu.popoverPresentationController.sourceRect = button.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didFindService:(NSNetService *)service moreComing:(BOOL)more {
    [self.services addObject:service]; service.delegate = self; [service resolveWithTimeout:5];
}
- (void)netServiceDidResolveAddress:(NSNetService *)service {
    if (!self.host.text.length && service.port == 5900) self.host.text = service.hostName;
}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    return YES;
}
@end
@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [Viewer new]; [self.window makeKeyAndVisible];
}
- (void)sceneDidEnterBackground:(UIScene *)scene { [(Viewer *)self.window.rootViewController background]; }
- (void)sceneWillEnterForeground:(UIScene *)scene { [(Viewer *)self.window.rootViewController foregrounded]; }
@end
int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class)); }
}

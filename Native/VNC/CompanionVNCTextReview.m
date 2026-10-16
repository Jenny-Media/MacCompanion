#import "CompanionVNCTextReview.h"
#import "CompanionVNCTextGeometry.h"
#import <Vision/Vision.h>
#import "Mac_Companion-Swift.h"

@interface CompanionVNCTextButton : UIButton
@property(nonatomic) NSLayoutConstraint *textHeight;
@end
@implementation CompanionVNCTextButton
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _textHeight = [self.heightAnchor constraintGreaterThanOrEqualToConstant:44]; _textHeight.active = YES;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    // A configured button's intrinsic height can lag its scaled, wrapped title.
    NSDirectionalEdgeInsets insets = self.configuration.contentInsets;
    CGFloat width = self.bounds.size.width - insets.leading - insets.trailing;
    if (width <= 0) return;
    CGFloat height = MAX(44, ceil([self.titleLabel sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height) + insets.top + insets.bottom);
    if (fabs(self.textHeight.constant - height) > .5) self.textHeight.constant = height;
}
@end

@interface CompanionVNCTextCrop : UIView <UIScrollViewDelegate, UIGestureRecognizerDelegate>
@property(nonatomic) UIScrollView *scroll;
@property(nonatomic) UIImageView *imageView;
@property(nonatomic) CAShapeLayer *outline;
@property(nonatomic) NSArray<UIButton *> *handles;
@property(nonatomic) CGRect selection, initialRect, startRect;
@property(nonatomic) BOOL fitted;
@property(nonatomic) BOOL selectionEnabled;
@property(nonatomic) BOOL adjustingSelection;
@property(nonatomic) UIPanGestureRecognizer *moveGesture;
@property(nonatomic) UIImageView *magnifier;
@property(nonatomic, copy) void (^selectionChanged)(void);
- (void)clear;
- (void)selectVisible;
- (void)selectAll;
@end

@implementation CompanionVNCTextCrop
- (instancetype)initWithImage:(UIImage *)image visibleRect:(CGRect)visibleRect {
    if ((self = [super initWithFrame:CGRectZero])) {
        _scroll = [UIScrollView new]; _scroll.delegate = self; _scroll.bouncesZoom = NO;
        _scroll.backgroundColor = UIColor.secondarySystemBackgroundColor; _scroll.panGestureRecognizer.minimumNumberOfTouches = 1;
        _imageView = [[UIImageView alloc] initWithImage:image];
        CGSize size = CGSizeMake(CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage));
        _imageView.frame = (CGRect){CGPointZero, size}; [_scroll addSubview:_imageView]; [self addSubview:_scroll];
        _initialRect = CompanionVNCTextPixelRect(size, visibleRect);
        if (CGRectIsNull(_initialRect)) _initialRect = (CGRect){CGPointZero, size};
        _selection = _initialRect;
        _outline = [CAShapeLayer layer]; _outline.fillColor = UIColor.clearColor.CGColor;
        _outline.strokeColor = UIColor.systemBlueColor.CGColor; _outline.lineWidth = 2; [self.layer addSublayer:_outline];
        NSMutableArray *handles = [NSMutableArray new];
        NSArray *names = @[@"Top left", @"Top right", @"Bottom right", @"Bottom left"];
        for (NSUInteger i = 0; i < 4; i++) {
            UIButton *handle = [UIButton buttonWithType:UIButtonTypeSystem]; handle.tag = i;
            [handle setImage:[UIImage systemImageNamed:@"circle.fill"] forState:UIControlStateNormal];
            handle.tintColor = UIColor.systemBlueColor;
            handle.accessibilityLabel = [names[i] stringByAppendingString:@" selection corner"];
            handle.accessibilityHint = @"Drag to resize. Use selection actions to expand or shrink the area.";
            handle.accessibilityCustomActions = @[
                [[UIAccessibilityCustomAction alloc] initWithName:@"Expand Selection" target:self selector:@selector(expand)],
                [[UIAccessibilityCustomAction alloc] initWithName:@"Shrink Selection" target:self selector:@selector(shrink)]];
            [handle addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(resize:)]];
            [self addSubview:handle]; [handles addObject:handle];
        }
        _handles = handles;
        _moveGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveSelection:)];
        _moveGesture.maximumNumberOfTouches = 1; _moveGesture.delegate = self; [self addGestureRecognizer:_moveGesture];
        [_scroll.panGestureRecognizer requireGestureRecognizerToFail:_moveGesture];
        _magnifier = [UIImageView new]; _magnifier.contentMode = UIViewContentModeScaleAspectFill;
        _magnifier.clipsToBounds = YES; _magnifier.layer.cornerRadius = 16;
        _magnifier.layer.borderWidth = 2; _magnifier.layer.borderColor = UIColor.systemBlueColor.CGColor;
        _magnifier.userInteractionEnabled = NO; _magnifier.accessibilityElementsHidden = YES;
        _magnifier.hidden = YES; [self addSubview:_magnifier];
        self.selectionEnabled = NO;
        self.clipsToBounds = YES; self.accessibilityIdentifier = @"text-copy-selection";
    }
    return self;
}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView { return self.imageView; }
- (void)scrollViewDidScroll:(UIScrollView *)scrollView { [self updateOutline]; }
- (void)scrollViewDidZoom:(UIScrollView *)scrollView { [self updateOutline]; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    for (UIView *view = touch.view; view && view != self; view = view.superview)
        if ([view isKindOfClass:UIControl.class]) return NO;
    return YES;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    return self.selectionEnabled && CGRectContainsPoint(self.selection, [gesture locationInView:self.imageView]);
}
- (void)setSelectionEnabled:(BOOL)selectionEnabled {
    _selectionEnabled = selectionEnabled; self.moveGesture.enabled = selectionEnabled;
    self.outline.hidden = !selectionEnabled;
    for (UIButton *handle in self.handles) handle.hidden = !selectionEnabled;
    self.magnifier.hidden = YES; self.magnifier.image = nil;
}
- (void)layoutSubviews {
    [super layoutSubviews]; self.scroll.frame = self.bounds;
    CGSize size = self.imageView.bounds.size;
    if (size.width <= 0 || self.bounds.size.width <= 0 || self.bounds.size.height <= 0) return;
    CGFloat fit = MIN(self.bounds.size.width / size.width, self.bounds.size.height / size.height);
    self.scroll.minimumZoomScale = fit; self.scroll.maximumZoomScale = MAX(fit, fit * 16);
    if (!self.fitted) {
        self.fitted = YES; self.scroll.contentSize = size;
        CGFloat zoom = MIN(self.bounds.size.width / self.initialRect.size.width, self.bounds.size.height / self.initialRect.size.height);
        self.scroll.zoomScale = MIN(self.scroll.maximumZoomScale, MAX(fit, zoom));
        self.scroll.contentOffset = CGPointMake(MAX(0, CGRectGetMidX(self.initialRect) * self.scroll.zoomScale - self.bounds.size.width / 2),
                                               MAX(0, CGRectGetMidY(self.initialRect) * self.scroll.zoomScale - self.bounds.size.height / 2));
    }
    [self updateOutline];
}
- (void)updateOutline {
    if (!self.fitted || CGRectIsEmpty(self.bounds)) return;
    CGRect rect = [self.imageView convertRect:self.selection toView:self];
    if (!isfinite(rect.origin.x) || !isfinite(rect.origin.y) || !isfinite(rect.size.width) || !isfinite(rect.size.height)) return;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    self.outline.path = [UIBezierPath bezierPathWithRect:rect].CGPath; [CATransaction commit];
    CGPoint points[] = {CGPointMake(rect.origin.x, rect.origin.y), CGPointMake(CGRectGetMaxX(rect), rect.origin.y),
        CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect)), CGPointMake(rect.origin.x, CGRectGetMaxY(rect))};
    for (NSUInteger i = 0; i < 4; i++) {
        self.handles[i].frame = CGRectMake(MAX(22, MIN(self.bounds.size.width-22, points[i].x))-22,
                                          MAX(22, MIN(self.bounds.size.height-22, points[i].y))-22, 44, 44);
        self.handles[i].accessibilityValue = [NSString stringWithFormat:@"%.0f by %.0f pixels", self.selection.size.width, self.selection.size.height];
    }
}
- (void)setSelection:(CGRect)selection {
    CGRect rect = CompanionVNCTextPixelRect(self.imageView.bounds.size, selection);
    if (!CGRectIsNull(rect) && !CGRectEqualToRect(_selection, rect)) {
        _selection = rect; [self updateOutline];
        if (self.selectionEnabled && self.selectionChanged) self.selectionChanged();
    }
}
- (void)selectVisible { self.selection = [self.scroll convertRect:self.scroll.bounds toView:self.imageView]; }
- (void)selectAll { self.selection = self.imageView.bounds; }
- (BOOL)expand { self.selection = CGRectInset(self.selection, -MAX(8, self.selection.size.width*.05), -MAX(8, self.selection.size.height*.05)); return YES; }
- (BOOL)shrink {
    if (self.selection.size.width > 24 && self.selection.size.height > 24)
        self.selection = CGRectInset(self.selection, MIN(8, self.selection.size.width*.05), MIN(8, self.selection.size.height*.05));
    return YES;
}
- (void)moveSelection:(UIPanGestureRecognizer *)gesture {
    self.adjustingSelection = gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.startRect = self.selection;
        // Cancel any read even if pixel clamping leaves the rectangle unchanged.
        if (self.selectionChanged) self.selectionChanged();
    }
    CGPoint delta = [gesture translationInView:self.imageView]; CGSize size = self.imageView.bounds.size;
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged)
        self.selection = CGRectMake(MAX(0,MIN(size.width-self.startRect.size.width,self.startRect.origin.x+delta.x)),
                                    MAX(0,MIN(size.height-self.startRect.size.height,self.startRect.origin.y+delta.y)),
                                    self.startRect.size.width,self.startRect.size.height);
    if (!self.adjustingSelection && self.selectionChanged) self.selectionChanged();
}
- (void)resize:(UIPanGestureRecognizer *)gesture {
    self.adjustingSelection = gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.startRect = self.selection;
        if (self.selectionChanged) self.selectionChanged();
    }
    CGPoint delta = [gesture translationInView:self.imageView]; NSInteger corner = gesture.view.tag;
    CGFloat left=self.startRect.origin.x, top=self.startRect.origin.y, right=CGRectGetMaxX(self.startRect), bottom=CGRectGetMaxY(self.startRect);
    if (corner == 0 || corner == 3) left=MIN(right-1, left+delta.x); else right=MAX(left+1,right+delta.x);
    if (corner == 0 || corner == 1) top=MIN(bottom-1, top+delta.y); else bottom=MAX(top+1,bottom+delta.y);
    self.selection = CGRectMake(left,top,right-left,bottom-top);
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint point = [gesture locationInView:self.imageView]; CGFloat side = 70/MAX(.01,self.scroll.zoomScale);
        CGRect sample = CompanionVNCTextPixelRect(self.imageView.bounds.size,CGRectMake(point.x-side/2,point.y-side/2,side,side));
        if (!CGRectIsNull(sample) && self.window) {
            CGImageRef pixels = CGImageCreateWithImageInRect(self.imageView.image.CGImage,sample);
            if (pixels) { self.magnifier.image = [UIImage imageWithCGImage:pixels]; CGImageRelease(pixels); }
            CGPoint local = [gesture locationInView:self];
            self.magnifier.frame = CGRectMake(MAX(4,MIN(self.bounds.size.width-114,local.x-55)),MAX(4,local.y-110),110,82);
            self.magnifier.hidden = NO; [self bringSubviewToFront:self.magnifier];
        }
    } else {
        self.magnifier.hidden = YES; self.magnifier.image = nil;
        if (self.selectionChanged) self.selectionChanged();
    }
}
- (void)clear { self.selectionChanged = nil; self.imageView.image = nil; self.magnifier.image = nil; self.magnifier.hidden = YES; self.outline.path = nil; }
@end

@interface CompanionVNCTextReview () <UITextViewDelegate>
@property(nonatomic) UIImage *snapshot;
@property(nonatomic) CGRect initialRect;
@property(nonatomic) CompanionVNCTextCrop *crop;
@property(nonatomic) UIImageView *preview;
@property(nonatomic) UITextView *editor;
@property(nonatomic) UILabel *status, *help;
@property(nonatomic) UIStackView *bodyStack, *resultActions, *resultContent;
@property(nonatomic) UIScrollView *contentScroll;
@property(nonatomic) NSLayoutConstraint *cropHeight;
@property(nonatomic) UIButton *exportButton, *returnButton;
@property(nonatomic) UIActivityIndicatorView *spinner;
@property(nonatomic) VNRecognizeTextRequest *request;
@property(nonatomic) NSOperationQueue *recognitionQueue;
@property(nonatomic) NSArray<NSString *> *supportedLanguages;
@property(nonatomic) NSString *language;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL invalidated, busy;
@property(nonatomic) UIStackView *footer;
@property(nonatomic) UILabel *heading;
@property(nonatomic) UIStackView *header;
@property(nonatomic) NSArray<NSLayoutConstraint *> *pinnedFooterConstraints;
@property(nonatomic) NSLayoutConstraint *scrollKeyboardBottom;
@property(nonatomic) BOOL accessibilityLayout;
@property(nonatomic) UIButton *areaButton, *editButton, *moreButton;
@property(nonatomic) CompanionVNCTextSelection *nativeSelection;
@property(nonatomic) BOOL areaMode, editorOpen, started;
@property(nonatomic) BOOL hasNativeReview;
@property(nonatomic) BOOL hasAreaReview;
@property(nonatomic) NSUInteger automaticGeneration;
@end

@implementation CompanionVNCTextReview
+ (BOOL)prefersNativeSelectionForSize:(CGSize)size supported:(BOOL)supported {
    return supported && CompanionVNCTextAreaFits(size);
}
- (instancetype)initWithImage:(UIImage *)image visibleRect:(CGRect)visibleRect {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _snapshot = image; _initialRect = visibleRect;
        _recognitionQueue = [NSOperationQueue new]; _recognitionQueue.maxConcurrentOperationCount = 1;
        _recognitionQueue.qualityOfService = NSQualityOfServiceUserInitiated;
        self.modalPresentationStyle = UIModalPresentationFullScreen; self.modalInPresentation = YES;
    }
    return self;
}
- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button = [CompanionVNCTextButton new];
    UIButtonConfiguration *config = [UIButtonConfiguration borderedButtonConfiguration]; config.title = title;
    config.titleLineBreakMode = NSLineBreakByWordWrapping;
    button.configuration = config; if (action) [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    button.titleLabel.adjustsFontForContentSizeCategory = YES; button.titleLabel.numberOfLines = 0;
    return button;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.view.accessibilityViewIsModal = YES;
    UILabel *title = [UILabel new]; title.text = @"Copy Text";
    self.heading = title;
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    title.adjustsFontForContentSizeCategory = YES; title.numberOfLines = 0;
    self.returnButton = [self button:@"Done" action:@selector(returnToDesktop)];
    self.returnButton.accessibilityIdentifier = @"text-copy-return";
    self.moreButton = [self button:@"More" action:NULL]; self.moreButton.showsMenuAsPrimaryAction = YES;
    self.moreButton.accessibilityIdentifier = @"text-copy-more";
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[title,self.moreButton,self.returnButton]];
    self.header = header;
    header.spacing = 8; header.alignment = UIStackViewAlignmentCenter; header.translatesAutoresizingMaskIntoConstraints = NO;
    [title setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self.view addSubview:header];
    UILabel *badge = [UILabel new]; badge.text = @"Frozen screen"; badge.textColor = UIColor.secondaryLabelColor;
    badge.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; badge.adjustsFontForContentSizeCategory = YES;
    badge.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:badge];
    self.contentScroll = [UIScrollView new]; self.contentScroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentScroll.accessibilityIdentifier = @"text-copy-content";
    [self.view addSubview:self.contentScroll];
    self.bodyStack = [UIStackView new]; self.bodyStack.axis = UILayoutConstraintAxisVertical;
    self.bodyStack.spacing = 8; self.bodyStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentScroll addSubview:self.bodyStack];
    self.crop = [[CompanionVNCTextCrop alloc] initWithImage:self.snapshot visibleRect:self.initialRect];
    self.crop.layer.cornerRadius = 12; [self.bodyStack addArrangedSubview:self.crop];
    self.cropHeight = [self.crop.heightAnchor constraintEqualToConstant:300]; self.cropHeight.active = YES;
    self.resultContent = [UIStackView new]; self.resultContent.axis = UILayoutConstraintAxisVertical;
    self.resultContent.hidden = YES; [self.bodyStack addArrangedSubview:self.resultContent];
    // The original image remains visible above the editable review; don't repeat it.
    self.preview = [UIImageView new]; self.preview.hidden = YES;
    self.editor = [UITextView new]; self.editor.hidden = YES; self.editor.delegate = self;
    self.editor.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[UIFont monospacedSystemFontOfSize:17 weight:UIFontWeightRegular]];
    self.editor.adjustsFontForContentSizeCategory = YES;
    self.editor.backgroundColor = UIColor.secondarySystemBackgroundColor; self.editor.layer.cornerRadius = 10;
    self.editor.autocorrectionType = UITextAutocorrectionTypeNo; self.editor.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.editor.spellCheckingType = UITextSpellCheckingTypeNo; self.editor.smartQuotesType = UITextSmartQuotesTypeNo;
    self.editor.smartDashesType = UITextSmartDashesTypeNo;
    self.editor.accessibilityLabel = @"Recognized text, editable"; self.editor.accessibilityIdentifier = @"text-copy-result";
    [self.resultContent addArrangedSubview:self.editor]; [self.editor.heightAnchor constraintEqualToConstant:140].active = YES;
    self.status = [UILabel new]; self.status.text = @"Finding text…"; self.status.numberOfLines = 0;
    self.status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]; self.status.adjustsFontForContentSizeCategory = YES;
    self.status.accessibilityIdentifier = @"text-copy-status";
    self.help = [UILabel new]; self.help.numberOfLines = 0; self.help.textColor = UIColor.secondaryLabelColor;
    self.help.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; self.help.adjustsFontForContentSizeCategory = YES;
    self.areaButton = [self button:@"Select Area" action:@selector(toggleSelectionMode)];
    self.areaButton.accessibilityIdentifier = @"text-copy-area";
    self.editButton = [self button:@"Edit…" action:@selector(editText)]; self.editButton.accessibilityIdentifier = @"text-copy-edit";
    self.exportButton = [self button:@"Copy" action:@selector(copyText)]; self.exportButton.accessibilityIdentifier = @"text-copy-copy";
    self.resultActions = [[UIStackView alloc] initWithArrangedSubviews:@[self.areaButton,self.editButton,self.exportButton]];
    self.resultActions.spacing = 8; self.resultActions.distribution = UIStackViewDistributionFillEqually;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    UIStackView *statusRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.spinner,self.status]]; statusRow.spacing = 8;
    self.footer = [[UIStackView alloc] initWithArrangedSubviews:@[statusRow,self.help,self.resultActions]];
    self.footer.axis = UILayoutConstraintAxisVertical; self.footer.spacing = 6; self.footer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.footer];
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4],
        [header.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12],
        [header.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [badge.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:2],
        [badge.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [badge.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [self.contentScroll.topAnchor constraintEqualToAnchor:badge.bottomAnchor constant:8],
        [self.contentScroll.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [self.contentScroll.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [self.bodyStack.widthAnchor constraintEqualToAnchor:self.contentScroll.frameLayoutGuide.widthAnchor],
        [self.bodyStack.leadingAnchor constraintEqualToAnchor:self.contentScroll.contentLayoutGuide.leadingAnchor],
        [self.bodyStack.trailingAnchor constraintEqualToAnchor:self.contentScroll.contentLayoutGuide.trailingAnchor],
        [self.bodyStack.topAnchor constraintEqualToAnchor:self.contentScroll.contentLayoutGuide.topAnchor],
        [self.bodyStack.bottomAnchor constraintEqualToAnchor:self.contentScroll.contentLayoutGuide.bottomAnchor]]];
    self.pinnedFooterConstraints = @[
        [self.contentScroll.bottomAnchor constraintEqualToAnchor:self.footer.topAnchor constant:-8],
        [self.footer.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [self.footer.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [self.footer.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-8]];
    self.scrollKeyboardBottom = [self.contentScroll.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-8];
    [NSLayoutConstraint activateConstraints:self.pinnedFooterConstraints];
    VNRecognizeTextRequest *configuration = [VNRecognizeTextRequest new]; configuration.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    self.supportedLanguages = [configuration supportedRecognitionLanguagesAndReturnError:NULL] ?: @[];
    CGSize size = self.crop.imageView.bounds.size;
    if ([self.class prefersNativeSelectionForSize:size supported:CompanionVNCTextSelection.supported])
        self.nativeSelection = [[CompanionVNCTextSelection alloc] initWithImageView:self.crop.imageView];
    self.areaMode = self.nativeSelection == nil; self.crop.selectionEnabled = self.areaMode;
    __weak CompanionVNCTextReview *weak = self;
    self.nativeSelection.selectionChanged = ^{ [weak nativeSelectionChanged]; };
    self.crop.selectionChanged = ^{ [weak scheduleRecognition]; };
    [self updateActions];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(retireForBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.started || self.invalidated) return;
    self.started = YES;
    if (self.areaMode) [self scheduleRecognition]; else [self startNativeAnalysis];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    BOOL large = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    if (self.accessibilityLayout != large) {
        self.accessibilityLayout = large;
        [NSLayoutConstraint deactivateConstraints:self.pinnedFooterConstraints];
        self.scrollKeyboardBottom.active = NO;
        if (large) {
            // Keep Done/More fixed, but let the title, status, editor and actions
            // scroll rather than compress each other above the keyboard.
            [self.header removeArrangedSubview:self.heading]; [self.heading removeFromSuperview];
            [self.bodyStack insertArrangedSubview:self.heading atIndex:0];
            [self.footer removeFromSuperview]; [self.bodyStack addArrangedSubview:self.footer];
            self.scrollKeyboardBottom.active = YES;
        } else {
            [self.bodyStack removeArrangedSubview:self.heading]; [self.heading removeFromSuperview];
            [self.header insertArrangedSubview:self.heading atIndex:0];
            [self.bodyStack removeArrangedSubview:self.footer]; [self.footer removeFromSuperview];
            [self.view addSubview:self.footer];
            [NSLayoutConstraint activateConstraints:self.pinnedFooterConstraints];
        }
    }
    self.resultActions.axis = large ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    if (self.crop.adjustingSelection) return;
    CGFloat available = self.contentScroll.bounds.size.height - (self.editorOpen ? 148 : 0);
    CGFloat height = large ? MIN(180,MAX(100,available)) : MAX(100,available);
    if (fabs(self.cropHeight.constant-height)>.5) self.cropHeight.constant = height;
}
- (NSString *)exportText {
    return self.areaMode || self.editorOpen || self.hasNativeReview ? self.editor.text : self.nativeSelection.selectedText;
}
- (void)nativeSelectionChanged {
    // Hiding the review preserves corrections. A new native selection retires
    // them, even when another occurrence contains the same recognized string.
    if (!self.editorOpen && self.hasNativeReview) {
        self.hasNativeReview = NO; self.editor.text = @"";
    }
    [self updateActions];
}
- (void)updateActions {
    if (self.invalidated) return;
    NSString *text = [self exportText];
    self.exportButton.enabled = !self.busy && text.length > 0 && text.length <= 65536;
    self.editButton.enabled = !self.busy && (self.editorOpen || self.hasNativeReview || self.hasAreaReview || (self.areaMode ? self.editor.text.length : self.nativeSelection.text.length));
    UIButtonConfiguration *edit = self.editButton.configuration; edit.title = self.editorOpen ? @"Hide Review" : @"Edit…"; self.editButton.configuration = edit;
    UIButtonConfiguration *area = self.areaButton.configuration; area.title = self.areaMode ? @"Select Text" : @"Select Area"; self.areaButton.configuration = area;
    self.areaButton.hidden = self.nativeSelection == nil;
    self.nativeSelection.enabled = !self.areaMode && !self.editorOpen;
    self.help.text = self.areaMode ? @"Drag corners to resize; drag inside to move. Pinch to zoom." : @"Touch and hold text to select. Pinch to zoom.";
    NSMutableArray *items = [NSMutableArray new]; __weak CompanionVNCTextReview *weak = self;
    [items addObject:[UIAction actionWithTitle:@"Copy All Text" image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(__unused UIAction *action) { [weak copyAllText]; }]];
    UIAction *share = [UIAction actionWithTitle:@"Share Selected Text" image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(__unused UIAction *action) { [weak shareText]; }];
    share.attributes = text.length && text.length <= 65536 && !self.busy ? 0 : UIMenuElementAttributesDisabled; [items addObject:share];
    UIAction *copyAll = items.firstObject;
    NSUInteger allLength = self.areaMode || self.editorOpen || self.hasNativeReview ? self.editor.text.length : self.nativeSelection.text.length;
    copyAll.attributes = !self.busy && allLength && allLength <= 65536 ? 0 : UIMenuElementAttributesDisabled;
    if (self.areaMode) {
        [items addObject:[UIAction actionWithTitle:@"Select Visible Area" image:nil identifier:nil handler:^(__unused UIAction *action) { [weak selectVisible]; }]];
        [items addObject:[UIAction actionWithTitle:@"Select Full Image" image:nil identifier:nil handler:^(__unused UIAction *action) { [weak selectAll]; }]];
        NSMutableArray *languages = [NSMutableArray new];
        UIAction *automatic = [UIAction actionWithTitle:@"Automatic" image:nil identifier:nil handler:^(__unused UIAction *action) { weak.language = nil; [weak scheduleRecognition]; }];
        automatic.state = self.language == nil ? UIMenuElementStateOn : UIMenuElementStateOff; [languages addObject:automatic];
        for (NSString *language in self.supportedLanguages) {
            UIAction *choice = [UIAction actionWithTitle:[NSLocale.currentLocale displayNameForKey:NSLocaleIdentifier value:language] ?: language image:nil identifier:nil handler:^(__unused UIAction *action) { weak.language = language; [weak scheduleRecognition]; }];
            choice.state = [self.language isEqual:language] ? UIMenuElementStateOn : UIMenuElementStateOff; [languages addObject:choice];
        }
        [items addObject:[UIMenu menuWithTitle:@"Recognition Language" children:languages]];
    }
    [items addObject:[UIAction actionWithTitle:@"Read Text Again" image:[UIImage systemImageNamed:@"arrow.clockwise"] identifier:nil handler:^(__unused UIAction *action) {
        if (weak.areaMode) [weak scheduleRecognition]; else [weak startNativeAnalysis];
    }]];
    self.moreButton.menu = [UIMenu menuWithTitle:@"" children:items];
}
- (void)startNativeAnalysis {
    if (self.invalidated || self.areaMode || !self.nativeSelection) return;
    [self cancelRecognition]; self.automaticGeneration++; NSUInteger automatic = self.automaticGeneration;
    self.hasNativeReview = NO;
    self.hasAreaReview = NO;
    self.editorOpen = NO; self.editor.text = @""; self.resultContent.hidden = YES; self.editor.hidden = YES;
    [self.editor resignFirstResponder]; self.preview.image = nil;
    self.busy = YES; self.status.text = @"Finding text…"; [self.spinner startAnimating]; [self updateActions];
    [self runNativeAnalysis:automatic];
}
- (void)runNativeAnalysis:(NSUInteger)automatic {
    if (self.invalidated || self.areaMode || self.automaticGeneration != automatic) return;
    __weak CompanionVNCTextReview *weak = self;
    if (self.nativeSelection.busy || self.recognitionQueue.operationCount) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.1*NSEC_PER_SEC),dispatch_get_main_queue(), ^{ [weak runNativeAnalysis:automatic]; }); return;
    }
    NSUInteger token = ++self.generation;
    [self.nativeSelection analyzeImage:self.snapshot completion:^(BOOL found) {
        if (!weak || weak.invalidated || weak.generation != token || weak.areaMode) return;
        weak.busy = NO; [weak.spinner stopAnimating];
        weak.status.text = found ? @"Select the text you want to copy" : @"No selectable text found. Try Select Area.";
        [weak updateActions];
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(), ^{
        if (!weak.invalidated && weak.generation == token && weak.busy) {
            [weak.nativeSelection cancel]; [weak cancelRecognition]; weak.status.text = @"Reading took too long. Try Select Area.";
        }
    });
}
- (void)toggleSelectionMode {
    if (self.areaMode && self.nativeSelection) {
        self.areaMode = NO; self.crop.selectionEnabled = NO; [self startNativeAnalysis];
    } else [self selectArea];
}
- (void)selectArea {
    if (self.invalidated) return;
    [self.nativeSelection cancel]; [self cancelRecognition]; self.areaMode = YES; self.crop.selectionEnabled = YES;
    self.crop.hidden = NO; [self updateActions];
    if (self.started) [self scheduleRecognition];
}
- (void)selectVisible { [self.crop selectVisible]; [self scheduleRecognition]; }
- (void)selectAll { [self.crop selectAll]; [self scheduleRecognition]; }
- (void)scheduleRecognition {
    if (self.invalidated || !self.areaMode) return;
    [self cancelRecognition]; NSUInteger automatic = ++self.automaticGeneration;
    self.hasNativeReview = NO;
    self.hasAreaReview = NO;
    [self.editor resignFirstResponder]; self.editor.text = @""; self.preview.image = nil;
    self.editorOpen = NO; self.resultContent.hidden = YES; self.editor.hidden = YES;
    [self.view setNeedsLayout];
    self.status.text = @"Reading selected area…"; [self updateActions];
    if (!self.started) return;
    __weak CompanionVNCTextReview *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.35*NSEC_PER_SEC),dispatch_get_main_queue(), ^{ [weak runAutomaticRecognition:automatic]; });
}
- (void)runAutomaticRecognition:(NSUInteger)automatic {
    if (self.invalidated || !self.areaMode || self.automaticGeneration != automatic) return;
    // A paused drag is still an adjustment. Opening results would resize the
    // viewport under the user's finger; the gesture's end schedules a new read.
    if (self.crop.adjustingSelection) return;
    if (self.nativeSelection.busy || self.recognitionQueue.operationCount) {
        __weak CompanionVNCTextReview *weak = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.1*NSEC_PER_SEC),dispatch_get_main_queue(), ^{ [weak runAutomaticRecognition:automatic]; }); return;
    }
    [self recognize];
}
- (void)cancelRecognition {
    self.generation++; [self.request cancel]; self.request = nil; [self.recognitionQueue cancelAllOperations];
    self.busy = NO; [self.spinner stopAnimating];
    self.status.text = self.areaMode ? @"Adjust the area to read text" : @"Select the text you want to copy";
    [self updateActions];
}
- (void)recognize {
    if (self.invalidated || self.busy || !self.snapshot) return;
    if (!self.areaMode) { self.areaMode = YES; self.crop.selectionEnabled = YES; [self.nativeSelection cancel]; }
    if (self.nativeSelection.busy || self.recognitionQueue.operationCount) { self.status.text = @"Finishing the previous request…"; return; }
    self.automaticGeneration++;
    CGRect rect = CompanionVNCTextPixelRect(self.crop.imageView.bounds.size,self.crop.selection);
    if (CGRectIsNull(rect) || !CompanionVNCTextAreaFits(rect.size)) { self.status.text = @"Select a smaller area (up to 16 megapixels) to recognize text."; return; }
    CGImageRef cropped = CGImageCreateWithImageInRect(self.snapshot.CGImage,rect);
    if (!cropped) { self.status.text = @"Couldn’t read this area. Adjust the selection and retry."; return; }
    UIImage *image = [UIImage imageWithCGImage:cropped]; CGImageRelease(cropped); self.preview.image = image;
    self.busy = YES; self.status.text = @"Reading selected area…"; [self.spinner startAnimating]; [self updateActions];
    NSUInteger token = ++self.generation;
    VNRecognizeTextRequest *request = [VNRecognizeTextRequest new]; request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = NO; request.automaticallyDetectsLanguage = self.language == nil;
    if (self.language) request.recognitionLanguages = @[self.language]; self.request = request;
    __weak CompanionVNCTextReview *weak = self;
    [self.recognitionQueue addOperationWithBlock:^{
        NSError *error = nil; VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image.CGImage options:@{}];
        BOOL success = [handler performRequests:@[request] error:&error]; NSArray *results = success ? request.results : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!weak || weak.invalidated || weak.generation != token || !weak.areaMode) return;
            [weak finishRecognition:results success:success];
        });
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(), ^{
        if (!weak.invalidated && weak.generation == token && weak.busy) {
            [weak cancelRecognition]; weak.status.text = @"Reading took too long. Adjust the area and retry.";
        }
    });
}
- (void)finishRecognition:(NSArray<VNRecognizedTextObservation *> *)observations success:(BOOL)success {
    if (self.invalidated || !self.areaMode) return; [self cancelRecognition];
    if (!success) { self.preview.image = nil; self.status.text = @"Couldn’t read text. Adjust the area or try again."; return; }
    if (observations.count > 4096) { self.preview.image = nil; self.status.text = @"Too much text. Select a smaller area."; return; }
    NSArray *ordered = [observations sortedArrayUsingComparator:^NSComparisonResult(VNRecognizedTextObservation *a,VNRecognizedTextObservation *b) {
        CGFloat ay = CGRectGetMidY(a.boundingBox), by = CGRectGetMidY(b.boundingBox);
        if (ay != by) return ay > by ? NSOrderedAscending : NSOrderedDescending;
        CGFloat ax = a.boundingBox.origin.x, bx = b.boundingBox.origin.x; return ax < bx ? NSOrderedAscending : ax > bx ? NSOrderedDescending : NSOrderedSame;
    }];
    NSMutableArray<NSString *> *lines = [NSMutableArray new]; CGFloat minX = 1,totalWidth = 0; NSUInteger characters = 0,outputLength = 0;
    for (VNRecognizedTextObservation *row in ordered) {
        NSString *text = [row topCandidates:1].firstObject.string;
        if (text.length) { minX = MIN(minX,row.boundingBox.origin.x); totalWidth += row.boundingBox.size.width; characters += text.length; }
    }
    CGFloat characterWidth = characters ? totalWidth/characters : 1;
    for (VNRecognizedTextObservation *row in ordered) {
        NSString *text = [row topCandidates:1].firstObject.string; if (!text.length) continue;
        NSUInteger indent = (NSUInteger)MAX(0,MIN(80,round((row.boundingBox.origin.x-minX)/MAX(.001,characterWidth))));
        [lines addObject:[[@"" stringByPaddingToLength:indent withString:@" " startingAtIndex:0] stringByAppendingString:text]];
        outputLength += text.length + indent + 1;
        if (outputLength > 65536) { self.preview.image = nil; self.status.text = @"Too much text. Select a smaller area."; return; }
    }
    NSString *text = [lines componentsJoinedByString:@"\n"];
    if (!text.length) { self.preview.image = nil; self.status.text = @"No text found. Try a closer or clearer area."; return; }
    self.editor.text = text; self.hasAreaReview = YES; self.editorOpen = YES; self.editor.hidden = NO; self.resultContent.hidden = NO;
    self.status.text = @"Review text before copying"; [self updateActions]; [self.view setNeedsLayout];
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification,self.editor);
}
- (void)editText {
    if (self.invalidated || self.busy) return;
    if (self.editorOpen) { [self.editor resignFirstResponder]; self.editorOpen = NO; self.editor.hidden = YES; self.resultContent.hidden = YES; }
    else {
        BOOL existingReview = self.areaMode || self.hasNativeReview;
        NSString *text = existingReview ? self.editor.text : (self.nativeSelection.selectedText.length ? self.nativeSelection.selectedText : self.nativeSelection.text);
        if (!existingReview && (!text.length || text.length > 65536)) return;
        self.editor.text = text; self.editorOpen = YES; self.editor.hidden = NO; self.resultContent.hidden = NO;
        if (!self.areaMode) self.hasNativeReview = YES;
        self.status.text = @"Review text before copying";
    }
    [self updateActions]; [self.view setNeedsLayout];
}
- (void)reselect { [self selectArea]; [self scheduleRecognition]; }
- (void)copyAllText {
    if (self.invalidated || self.busy) return;
    NSString *text = self.areaMode || self.editorOpen || self.hasNativeReview ? self.editor.text : self.nativeSelection.text;
    [self copyString:text];
}
- (void)copyString:(NSString *)text {
    if (self.invalidated || self.busy || !text.length || text.length > 65536) return;
    UIPasteboard.generalPasteboard.string = text; self.status.text = @"Copied";
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,@"Text copied");
}
- (void)textViewDidChange:(UITextView *)textView {
    if (self.invalidated) return;
    if (textView.text.length > 65536) self.status.text = @"Text is too long to copy. Shorten it first.";
    else self.status.text = @"Review text before copying";
    [self updateActions];
}
- (void)copyText { [self copyString:[self exportText]]; }
- (void)shareText {
    NSString *text = [self exportText];
    if (self.invalidated || self.busy || !text.length || text.length > 65536 || self.presentedViewController) return;
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[text] applicationActivities:nil];
    share.popoverPresentationController.sourceView = self.moreButton; share.popoverPresentationController.sourceRect = self.moreButton.bounds;
    [self presentViewController:share animated:YES completion:nil];
}
- (void)returnToDesktop { void (^completion)(void) = self.returnHandler; [self invalidate]; if (completion) completion(); }
- (void)retireForBackground:(NSNotification *)notification { [self returnToDesktop]; }
- (void)invalidate {
    if (self.invalidated) return; self.invalidated = YES; self.automaticGeneration++;
    [self.nativeSelection invalidate]; [self cancelRecognition]; [self.view endEditing:YES];
    self.snapshot = nil; [self.crop clear]; self.preview.image = nil; self.editor.text = @"";
    self.hasNativeReview = NO;
    self.hasAreaReview = NO;
    self.status.text = @""; self.returnHandler = nil;
    if (self.presentedViewController) [self dismissViewControllerAnimated:NO completion:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (void)dealloc { [self.request cancel]; [self.recognitionQueue cancelAllOperations]; [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end

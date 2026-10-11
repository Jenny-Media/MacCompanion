#import "CompanionVNCTextReview.h"
#import "CompanionVNCTextGeometry.h"
#import <Vision/Vision.h>

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
@property(nonatomic) CGPoint startPoint;
@property(nonatomic) BOOL fitted;
- (void)clear;
- (void)selectVisible;
- (void)selectAll;
@end

@implementation CompanionVNCTextCrop
- (instancetype)initWithImage:(UIImage *)image visibleRect:(CGRect)visibleRect {
    if ((self = [super initWithFrame:CGRectZero])) {
        _scroll = [UIScrollView new]; _scroll.delegate = self; _scroll.bouncesZoom = NO;
        _scroll.backgroundColor = UIColor.blackColor; _scroll.panGestureRecognizer.minimumNumberOfTouches = 2;
        _imageView = [[UIImageView alloc] initWithImage:image];
        CGSize size = CGSizeMake(CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage));
        _imageView.frame = (CGRect){CGPointZero, size}; [_scroll addSubview:_imageView]; [self addSubview:_scroll];
        _initialRect = CompanionVNCTextPixelRect(size, visibleRect);
        if (CGRectIsNull(_initialRect)) _initialRect = (CGRect){CGPointZero, size};
        _selection = _initialRect;
        _outline = [CAShapeLayer layer]; _outline.fillColor = UIColor.clearColor.CGColor;
        _outline.strokeColor = UIColor.systemYellowColor.CGColor; _outline.lineWidth = 2; [self.layer addSublayer:_outline];
        NSMutableArray *handles = [NSMutableArray new];
        NSArray *names = @[@"Top left", @"Top right", @"Bottom right", @"Bottom left"];
        for (NSUInteger i = 0; i < 4; i++) {
            UIButton *handle = [UIButton buttonWithType:UIButtonTypeSystem]; handle.tag = i;
            [handle setImage:[UIImage systemImageNamed:@"circle.fill"] forState:UIControlStateNormal];
            handle.tintColor = UIColor.systemYellowColor;
            handle.accessibilityLabel = [names[i] stringByAppendingString:@" selection corner"];
            handle.accessibilityHint = @"Drag to resize. Use selection actions to expand or shrink the area.";
            handle.accessibilityCustomActions = @[
                [[UIAccessibilityCustomAction alloc] initWithName:@"Expand Selection" target:self selector:@selector(expand)],
                [[UIAccessibilityCustomAction alloc] initWithName:@"Shrink Selection" target:self selector:@selector(shrink)]];
            [handle addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(resize:)]];
            [self addSubview:handle]; [handles addObject:handle];
        }
        _handles = handles;
        UIPanGestureRecognizer *draw = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drawSelection:)];
        draw.maximumNumberOfTouches = 1; draw.delegate = self; [self addGestureRecognizer:draw];
        self.clipsToBounds = YES; self.accessibilityIdentifier = @"text-copy-selection";
    }
    return self;
}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView { return self.imageView; }
- (void)scrollViewDidScroll:(UIScrollView *)scrollView { [self updateOutline]; }
- (void)scrollViewDidZoom:(UIScrollView *)scrollView { [self updateOutline]; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    return ![touch.view isKindOfClass:UIButton.class];
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
    CGRect rect = [self.imageView convertRect:self.selection toView:self];
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
    if (!CGRectIsNull(rect)) { _selection = rect; [self updateOutline]; }
}
- (void)selectVisible { self.selection = [self.scroll convertRect:self.scroll.bounds toView:self.imageView]; }
- (void)selectAll { self.selection = self.imageView.bounds; }
- (BOOL)expand { self.selection = CGRectInset(self.selection, -MAX(8, self.selection.size.width*.05), -MAX(8, self.selection.size.height*.05)); return YES; }
- (BOOL)shrink {
    if (self.selection.size.width > 24 && self.selection.size.height > 24)
        self.selection = CGRectInset(self.selection, MIN(8, self.selection.size.width*.05), MIN(8, self.selection.size.height*.05));
    return YES;
}
- (void)drawSelection:(UIPanGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self.imageView];
    if (gesture.state == UIGestureRecognizerStateBegan) self.startPoint = point;
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged)
        self.selection = CGRectMake(MIN(point.x,self.startPoint.x), MIN(point.y,self.startPoint.y),
                                    MAX(1,fabs(point.x-self.startPoint.x)), MAX(1,fabs(point.y-self.startPoint.y)));
}
- (void)resize:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) self.startRect = self.selection;
    CGPoint delta = [gesture translationInView:self.imageView]; NSInteger corner = gesture.view.tag;
    CGFloat left=self.startRect.origin.x, top=self.startRect.origin.y, right=CGRectGetMaxX(self.startRect), bottom=CGRectGetMaxY(self.startRect);
    if (corner == 0 || corner == 3) left=MIN(right-1, left+delta.x); else right=MAX(left+1,right+delta.x);
    if (corner == 0 || corner == 1) top=MIN(bottom-1, top+delta.y); else bottom=MAX(top+1,bottom+delta.y);
    self.selection = CGRectMake(left,top,right-left,bottom-top);
}
- (void)clear { self.imageView.image = nil; self.selection = CGRectZero; self.outline.path = nil; }
@end

@interface CompanionVNCTextReview ()
@property(nonatomic) UIImage *snapshot;
@property(nonatomic) CGRect initialRect;
@property(nonatomic) CompanionVNCTextCrop *crop;
@property(nonatomic) UIImageView *preview;
@property(nonatomic) UITextView *editor;
@property(nonatomic) UILabel *status, *help;
@property(nonatomic) UIStackView *bodyStack, *selectionActions, *resultActions, *resultContent;
@property(nonatomic) UIScrollView *contentScroll;
@property(nonatomic) NSLayoutConstraint *cropHeight, *previewWidth;
@property(nonatomic) UIButton *recognizeButton, *cancelButton, *exportButton, *shareButton, *returnButton;
@property(nonatomic) UIActivityIndicatorView *spinner;
@property(nonatomic) VNRecognizeTextRequest *request;
@property(nonatomic) NSOperationQueue *recognitionQueue;
@property(nonatomic) NSArray<NSString *> *supportedLanguages;
@property(nonatomic) NSString *language;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL invalidated, busy;
@property(nonatomic) NSLayoutConstraint *previewHeight;
@end

@implementation CompanionVNCTextReview
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
    self.bodyStack = [[UIStackView alloc] init]; self.bodyStack.axis = UILayoutConstraintAxisVertical;
    self.bodyStack.spacing = 8; self.bodyStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentScroll=[UIScrollView new]; self.contentScroll.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:self.contentScroll]; [self.contentScroll addSubview:self.bodyStack];
    self.returnButton=[self button:@"Return to Live Desktop" action:@selector(returnToDesktop)];
    self.returnButton.accessibilityIdentifier=@"text-copy-return"; self.returnButton.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:self.returnButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.contentScroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [self.contentScroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [self.contentScroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.contentScroll.bottomAnchor constraintEqualToAnchor:self.returnButton.topAnchor constant:-8],
        [self.returnButton.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12],
        [self.returnButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [self.returnButton.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-8],
        [self.bodyStack.widthAnchor constraintEqualToAnchor:self.contentScroll.frameLayoutGuide.widthAnchor constant:-24]]];
    [NSLayoutConstraint activateConstraints:@[
        [self.bodyStack.leadingAnchor constraintEqualToAnchor:self.contentScroll.contentLayoutGuide.leadingAnchor constant:12],
        [self.bodyStack.trailingAnchor constraintEqualToAnchor:self.contentScroll.contentLayoutGuide.trailingAnchor constant:-12],
        [self.bodyStack.topAnchor constraintEqualToAnchor:self.contentScroll.contentLayoutGuide.topAnchor constant:8],
        [self.bodyStack.bottomAnchor constraintEqualToAnchor:self.contentScroll.contentLayoutGuide.bottomAnchor constant:-8]]];
    UILabel *title=[UILabel new]; title.text=@"Text from Screen"; title.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    title.adjustsFontForContentSizeCategory=YES; title.numberOfLines=0; [self.bodyStack addArrangedSubview:title];
    UILabel *badge=[UILabel new]; badge.text=@"Snapshot · Remote input paused";
    badge.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]; badge.numberOfLines=0;
    badge.adjustsFontForContentSizeCategory=YES; [self.bodyStack addArrangedSubview:badge];
    self.status=[UILabel new]; self.status.text=@"Select an area to recognize";
    self.status.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]; self.status.numberOfLines=0;
    self.status.adjustsFontForContentSizeCategory=YES; self.status.accessibilityIdentifier=@"text-copy-status";
    [self.bodyStack addArrangedSubview:self.status];
    self.help=[UILabel new]; self.help.text=@"Drag corners to adjust. Pinch to zoom; two fingers to pan.";
    self.help.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; self.help.textColor=UIColor.secondaryLabelColor;
    self.help.numberOfLines=0; self.help.adjustsFontForContentSizeCategory=YES; [self.bodyStack addArrangedSubview:self.help];
    self.crop=[[CompanionVNCTextCrop alloc] initWithImage:self.snapshot visibleRect:self.initialRect];
    [self.bodyStack addArrangedSubview:self.crop];
    self.cropHeight=[self.crop.heightAnchor constraintEqualToConstant:300]; self.cropHeight.active=YES;
    self.preview=[UIImageView new]; self.preview.contentMode=UIViewContentModeScaleAspectFit; self.preview.hidden=YES;
    self.preview.accessibilityLabel=@"Selected snapshot"; self.preview.isAccessibilityElement=YES;
    self.resultContent=[UIStackView new]; self.resultContent.axis=UILayoutConstraintAxisVertical; self.resultContent.spacing=8;
    self.resultContent.hidden=YES; [self.bodyStack addArrangedSubview:self.resultContent];
    [self.resultContent addArrangedSubview:self.preview];
    self.previewHeight=[self.preview.heightAnchor constraintEqualToConstant:140]; self.previewHeight.active=YES;
    self.editor=[UITextView new]; self.editor.hidden=YES; self.editor.font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[UIFont monospacedSystemFontOfSize:17 weight:UIFontWeightRegular]];
    self.editor.adjustsFontForContentSizeCategory=YES; self.editor.autocorrectionType=UITextAutocorrectionTypeNo;
    self.editor.autocapitalizationType=UITextAutocapitalizationTypeNone; self.editor.spellCheckingType=UITextSpellCheckingTypeNo;
    self.editor.smartQuotesType=UITextSmartQuotesTypeNo; self.editor.smartDashesType=UITextSmartDashesTypeNo;
    self.editor.accessibilityLabel=@"Recognized text, editable"; self.editor.accessibilityIdentifier=@"text-copy-result";
    [self.resultContent addArrangedSubview:self.editor];
    [self.editor.heightAnchor constraintEqualToConstant:220].active=YES;
    self.previewWidth=[self.preview.widthAnchor constraintEqualToAnchor:self.resultContent.widthAnchor multiplier:.45];
    UIButton *visible=[self button:@"Visible Area" action:@selector(selectVisible)];
    UIButton *all=[self button:@"Full Image" action:@selector(selectAll)];
    UIButton *languages=[self button:@"Language: Auto" action:NULL]; languages.showsMenuAsPrimaryAction=YES;
    VNRecognizeTextRequest *configuration=[VNRecognizeTextRequest new]; configuration.recognitionLevel=VNRequestTextRecognitionLevelAccurate;
    self.supportedLanguages=[configuration supportedRecognitionLanguagesAndReturnError:NULL] ?: @[];
    NSMutableArray *choices=[NSMutableArray new]; __weak CompanionVNCTextReview *weak=self; __weak UIButton *languageButton=languages;
    [choices addObject:[UIAction actionWithTitle:@"Automatic" image:nil identifier:nil handler:^(__unused UIAction *action) {
        weak.language=nil; UIButtonConfiguration *c=languageButton.configuration; c.title=@"Language: Auto"; languageButton.configuration=c;
    }]];
    NSLocale *locale=NSLocale.currentLocale;
    for (NSString *language in self.supportedLanguages) {
        NSString *name=[locale displayNameForKey:NSLocaleIdentifier value:language] ?: language;
        [choices addObject:[UIAction actionWithTitle:name image:nil identifier:nil handler:^(__unused UIAction *action) {
            weak.language=language; UIButtonConfiguration *c=languageButton.configuration; c.title=name; languageButton.configuration=c;
        }]];
    }
    languages.menu=[UIMenu menuWithTitle:@"Recognition Language" children:choices];
    self.selectionActions=[[UIStackView alloc] initWithArrangedSubviews:@[visible,all,languages]];
    self.selectionActions.spacing=8; self.selectionActions.distribution=UIStackViewDistributionFillEqually;
    [self.bodyStack addArrangedSubview:self.selectionActions];
    self.recognizeButton=[self button:@"Recognize Text" action:@selector(recognize)];
    self.recognizeButton.accessibilityIdentifier=@"text-copy-recognize"; [self.bodyStack addArrangedSubview:self.recognizeButton];
    self.spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped=YES; [self.bodyStack addArrangedSubview:self.spinner];
    self.cancelButton=[self button:@"Cancel Recognition" action:@selector(cancelRecognition)]; self.cancelButton.hidden=YES;
    [self.bodyStack addArrangedSubview:self.cancelButton];
    self.exportButton=[self button:@"Copy Text" action:@selector(copyText)]; self.exportButton.accessibilityIdentifier=@"text-copy-copy";
    self.shareButton=[self button:@"Share" action:@selector(shareText)];
    UIButton *reselect=[self button:@"Reselect Area" action:@selector(reselect)];
    self.resultActions=[[UIStackView alloc] initWithArrangedSubviews:@[self.exportButton,self.shareButton,reselect]];
    self.resultActions.spacing=8; self.resultActions.distribution=UIStackViewDistributionFillEqually; self.resultActions.hidden=YES;
    [self.bodyStack addArrangedSubview:self.resultActions];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(retireForBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    BOOL large=UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    BOOL wide=self.view.bounds.size.width>700 && !large;
    self.resultContent.axis=wide ? UILayoutConstraintAxisHorizontal : UILayoutConstraintAxisVertical;
    self.previewHeight.active=!wide; self.previewWidth.active=wide;
    self.cropHeight.constant=MAX(180,MIN(600,self.view.bounds.size.height*.48));
    self.selectionActions.axis=large ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    self.resultActions.axis=large ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    self.previewHeight.constant=MIN(160, self.view.bounds.size.height*.22);
}
- (void)selectVisible { [self.crop selectVisible]; }
- (void)selectAll { [self.crop selectAll]; }
- (void)cancelRecognition {
    self.generation++; [self.request cancel]; self.request=nil; [self.recognitionQueue cancelAllOperations];
    self.busy=NO; [self.spinner stopAnimating]; self.cancelButton.hidden=YES;
    self.recognizeButton.enabled=YES; self.crop.userInteractionEnabled=YES; self.selectionActions.userInteractionEnabled=YES;
    self.status.text=@"Select an area to recognize";
}
- (void)recognize {
    if (self.invalidated || self.busy || !self.snapshot) return;
    if (self.recognitionQueue.operationCount) { self.status.text=@"Finishing cancellation. Try again in a moment."; return; }
    CGRect rect=CompanionVNCTextPixelRect(self.crop.imageView.bounds.size,self.crop.selection);
    if (CGRectIsNull(rect) || !CompanionVNCTextAreaFits(rect.size)) {
        self.status.text=@"Select a smaller area (up to 16 megapixels) to recognize text."; return;
    }
    CGImageRef cropped=CGImageCreateWithImageInRect(self.snapshot.CGImage,rect);
    if (!cropped) { self.status.text=@"Couldn’t read this area. Select another area and retry."; return; }
    UIImage *image=[UIImage imageWithCGImage:cropped]; CGImageRelease(cropped);
    self.preview.image=image;
    self.busy=YES; self.recognizeButton.enabled=NO; self.cancelButton.hidden=NO;
    self.crop.userInteractionEnabled=NO; self.selectionActions.userInteractionEnabled=NO;
    self.status.text=@"Recognizing on this device…"; [self.spinner startAnimating];
    NSUInteger token=++self.generation;
    VNRecognizeTextRequest *request=[VNRecognizeTextRequest new];
    request.recognitionLevel=VNRequestTextRecognitionLevelAccurate; request.usesLanguageCorrection=NO;
    request.automaticallyDetectsLanguage=self.language==nil;
    if (self.language) request.recognitionLanguages=@[self.language];
    self.request=request; __weak CompanionVNCTextReview *weak=self;
    [self.recognitionQueue addOperationWithBlock:^{
        NSError *error=nil;
        VNImageRequestHandler *handler=[[VNImageRequestHandler alloc] initWithCGImage:image.CGImage options:@{}];
        BOOL success=[handler performRequests:@[request] error:&error];
        NSArray *results=success ? request.results : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            CompanionVNCTextReview *strong=weak;
            if (!strong || strong.invalidated || strong.generation!=token) return;
            [strong finishRecognition:results success:success];
        });
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(), ^{
        if (!weak.invalidated && weak.generation==token && weak.busy) {
            [weak cancelRecognition]; weak.status.text=@"Recognition took too long. Select a smaller area and retry.";
        }
    });
}
- (void)finishRecognition:(NSArray<VNRecognizedTextObservation *> *)observations success:(BOOL)success {
    if (self.invalidated) return;
    [self cancelRecognition];
    if (!success) { self.preview.image=nil; self.status.text=@"Recognition failed. Retry or select another area."; return; }
    if (observations.count>4096) { self.preview.image=nil; self.status.text=@"Too much text. Select a smaller area and retry."; return; }
    NSArray *ordered=[observations sortedArrayUsingComparator:^NSComparisonResult(VNRecognizedTextObservation *a,VNRecognizedTextObservation *b) {
        CGFloat ay=CGRectGetMidY(a.boundingBox), by=CGRectGetMidY(b.boundingBox);
        if (ay != by) return ay>by ? NSOrderedAscending : NSOrderedDescending;
        CGFloat ax=a.boundingBox.origin.x, bx=b.boundingBox.origin.x;
        return ax<bx ? NSOrderedAscending : ax>bx ? NSOrderedDescending : NSOrderedSame;
    }];
    NSMutableArray<NSString *> *lines=[NSMutableArray new]; CGFloat minX=1, totalWidth=0; NSUInteger characters=0, outputLength=0;
    for (VNRecognizedTextObservation *row in ordered) {
        NSString *text=[row topCandidates:1].firstObject.string;
        if (text.length) { minX=MIN(minX,row.boundingBox.origin.x); totalWidth+=row.boundingBox.size.width; characters+=text.length; }
    }
    CGFloat characterWidth=characters ? totalWidth/characters : 1;
    for (VNRecognizedTextObservation *row in ordered) {
        NSString *text=[row topCandidates:1].firstObject.string; if (!text.length) continue;
        NSUInteger indent=(NSUInteger)MAX(0,MIN(80,round((row.boundingBox.origin.x-minX)/MAX(.001,characterWidth))));
        [lines addObject:[[ @"" stringByPaddingToLength:indent withString:@" " startingAtIndex:0] stringByAppendingString:text]];
        outputLength+=text.length+indent+1;
        if (outputLength>65536) { self.preview.image=nil; self.status.text=@"Too much text. Select a smaller area and retry."; return; }
    }
    NSString *text=[lines componentsJoinedByString:@"\n"];
    if (!text.length) { self.preview.image=nil; self.status.text=@"No text found. Try a closer or clearer area."; return; }
    self.editor.text=text; self.resultContent.hidden=NO; self.editor.hidden=NO; self.preview.hidden=NO; self.crop.hidden=YES;
    self.selectionActions.hidden=YES; self.recognizeButton.hidden=YES; self.resultActions.hidden=NO;
    self.status.text=@"Snapshot · Review text before copying";
    self.help.text=@"Recognition can misread characters and spacing. Edit the result as needed.";
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification,self.editor);
}
- (void)reselect {
    [self cancelRecognition]; [self.editor resignFirstResponder]; self.editor.text=@""; self.preview.image=nil;
    self.resultContent.hidden=YES; self.editor.hidden=YES; self.preview.hidden=YES; self.crop.hidden=NO; self.selectionActions.hidden=NO;
    self.recognizeButton.hidden=NO; self.resultActions.hidden=YES;
    self.help.text=@"Drag corners to adjust. Pinch to zoom; two fingers to pan.";
}
- (void)copyText {
    if (self.invalidated || !self.editor.text.length) return;
    UIPasteboard.generalPasteboard.string=self.editor.text; self.status.text=@"Copied · Snapshot remains open";
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,@"Text copied");
}
- (void)shareText {
    if (self.invalidated || !self.editor.text.length || self.presentedViewController) return;
    UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[self.editor.text] applicationActivities:nil];
    share.popoverPresentationController.sourceView=self.shareButton;
    share.popoverPresentationController.sourceRect=self.shareButton.bounds;
    [self presentViewController:share animated:YES completion:nil];
}
- (void)returnToDesktop {
    void (^completion)(void)=self.returnHandler; [self invalidate]; if (completion) completion();
}
- (void)retireForBackground:(NSNotification *)notification { [self returnToDesktop]; }
- (void)invalidate {
    if (self.invalidated) return; self.invalidated=YES;
    [self cancelRecognition]; [self.view endEditing:YES];
    self.snapshot=nil; [self.crop clear]; self.preview.image=nil; self.editor.text=@"";
    self.status.text=@""; self.returnHandler=nil;
    if (self.presentedViewController) [self dismissViewControllerAnimated:NO completion:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (void)dealloc { [self.request cancel]; [self.recognitionQueue cancelAllOperations]; [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end

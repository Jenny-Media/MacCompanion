#import "CompanionVNCControls.h"
#import "CompanionVNCAdaptiveLayout.h"
NSString *const CompanionVNCControlsHapticsPreference = @"direct-controls-haptics";
@interface CompanionVNCInterfaceFeedback ()
@property NSUserDefaults *defaults;
@property UISelectionFeedbackGenerator *selection;
@property UIImpactFeedbackGenerator *light;
@property UIImpactFeedbackGenerator *medium;
@property UINotificationFeedbackGenerator *notification;
@end
@implementation CompanionVNCInterfaceFeedback
- (instancetype)init { return [self initWithDefaults:NSUserDefaults.standardUserDefaults]; }
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    if ((self = [super init])) { _defaults = defaults; }
    return self;
}
- (BOOL)foreground { return UIApplication.sharedApplication.applicationState == UIApplicationStateActive; }
- (void)feedback:(NSString *)kind {
    if (!NSThread.isMainThread || !self.foreground) return;
    if ([self.defaults objectForKey:CompanionVNCControlsHapticsPreference] != nil
        && ![self.defaults boolForKey:CompanionVNCControlsHapticsPreference]) return;
    if (![@[@"selection", @"open", @"commit", @"end", @"success", @"error"] containsObject:kind]) return;
    [self emitFeedback:kind];
}
- (void)emitFeedback:(NSString *)kind {
    if ([kind isEqual:@"selection"]) {
        if (!self.selection) self.selection = [UISelectionFeedbackGenerator new];
        [self.selection selectionChanged];
    } else if ([kind isEqual:@"success"] || [kind isEqual:@"error"]) {
        if (!self.notification) self.notification = [UINotificationFeedbackGenerator new];
        [self.notification notificationOccurred:[kind isEqual:@"success"] ? UINotificationFeedbackTypeSuccess : UINotificationFeedbackTypeError];
    } else if ([kind isEqual:@"end"]) {
        if (!self.medium) self.medium = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [self.medium impactOccurredWithIntensity:.55];
    } else {
        if (!self.light) self.light = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [self.light impactOccurredWithIntensity:[kind isEqual:@"commit"] ? .35 : .55];
    }
}
@end
void CompanionVNCPlayInterfaceFeedback(NSString *kind) {
    static CompanionVNCInterfaceFeedback *feedback;
    if (!NSThread.isMainThread) return;
    if (!feedback) feedback = [CompanionVNCInterfaceFeedback new];
    [feedback feedback:kind];
}
@interface CompanionVNCControls () <UIDragInteractionDelegate, UIDropInteractionDelegate>
@property UIButton *button;
@property UIVisualEffectView *panel;
@property UIScrollView *scroll;
@property UILabel *nameLabel;
@property UIButton *customizeButton;
@property NSMutableArray<UIButton *> *choices;
@property NSArray<NSDictionary *> *items;
@property UIButton *highlighted;
@property UILongPressGestureRecognizer *slide;
@property NSUInteger fadeGeneration;
@property NSUInteger quickCount;
@property NSString *renderedPreviewID;
@end
@implementation CompanionVNCControls
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        _macName = @"Mac"; _quickActions = @[]; _bottomInset = 8;
        _button = [UIButton buttonWithType:UIButtonTypeSystem];
        UIButtonConfiguration *config;
        if (@available(iOS 26.0, *)) config = [UIButtonConfiguration glassButtonConfiguration];
        else config = [UIButtonConfiguration grayButtonConfiguration];
        config.image = [UIImage systemImageNamed:@"ellipsis"];
        // Keep the symbol inside this fixed 52-point control even at the
        // largest text size; menu titles and actions still scale normally.
        config.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium];
        config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        _button.configuration = config; _button.accessibilityLabel = @"Session Controls";
        _button.accessibilityIdentifier = @"session-controls";
        _button.accessibilityHint = @"Tap to open. Hold, slide to an action, then release to choose.";
        [_button addTarget:self action:@selector(pressDown) forControlEvents:UIControlEventTouchDown];
        [_button addTarget:self action:@selector(pressUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [_button addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_button];
        _slide = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(slide:)];
        _slide.minimumPressDuration = 0.12; _slide.allowableMovement = CGFLOAT_MAX;
        [_button addGestureRecognizer:_slide];
    }
    return self;
}
- (BOOL)hapticsEnabled { return [NSUserDefaults.standardUserDefaults objectForKey:CompanionVNCControlsHapticsPreference] == nil || [NSUserDefaults.standardUserDefaults boolForKey:CompanionVNCControlsHapticsPreference]; }
- (void)setHapticsEnabled:(BOOL)value { [NSUserDefaults.standardUserDefaults setBool:value forKey:CompanionVNCControlsHapticsPreference]; }
- (void)emitFeedback:(NSString *)kind {
    CompanionVNCPlayInterfaceFeedback(kind);
}
- (void)feedback:(NSString *)kind { if (self.hapticsEnabled) [self emitFeedback:kind]; }
- (BOOL)reduceMotion { return UIAccessibilityIsReduceMotionEnabled(); }
- (void)pressDown {
    self.fadeGeneration++; self.button.alpha = 1;
    if (self.reduceMotion) return;
    [UIView animateWithDuration:.1 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{ self.button.transform = CGAffineTransformMakeScale(.94,.94); } completion:nil];
}
- (void)pressUp {
    [UIView animateWithDuration:self.reduceMotion ? 0 : .12 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{ self.button.transform = CGAffineTransformIdentity; } completion:nil];
}
- (void)setFullscreen:(BOOL)value {
    _fullscreen = value; self.button.alpha = 1; [self dimWhenIdle];
}
- (void)dimWhenIdle {
    NSUInteger generation = ++self.fadeGeneration;
    if (!self.fullscreen || self.panel) return;
    __weak CompanionVNCControls *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (weak.fullscreen && !weak.panel && weak.fadeGeneration == generation) {
            [UIView animateWithDuration:.25 animations:^{ weak.button.alpha = .65; }];
        }
    });
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? (self.panel ? self : nil) : hit;
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { if (!self.editingPreview) [self close]; }
- (CGRect)activeDivision { return CompanionVNCActiveDivision(self); }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect safe = UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets), content = CGRectNull, input = CGRectNull;
    CGRect available = safe;
    available.size.height = MAX(0, available.size.height - self.bottomInset);
    if (CompanionVNCTabletopRegions(safe, [self activeDivision], &content, &input)) {
        CGRect lower = CGRectIntersection(available, input);
        // A tall keyboard may consume the lower pane. Keep the menu reachable
        // above the keyboard instead of pinning its button behind it.
        if (!CGRectIsNull(lower) && lower.size.height >= 104) available = lower;
    }
    self.button.bounds = CGRectMake(0,0,52,52);
    self.button.center = CGPointMake(MAX(CGRectGetMinX(available) + 26, CGRectGetMaxX(available) - 36),
        MAX(CGRectGetMinY(available) + 26, CGRectGetMaxY(available) - 26));
    if (self.buttonAnchorView.superview) {
        CGRect slot = [self.buttonAnchorView convertRect:self.buttonAnchorView.bounds toView:self];
        self.button.center = CGPointMake(CGRectGetMidX(slot), CGRectGetMidY(slot));
    }
    if (!self.panel) return;
    CGFloat width = MAX(0, MIN(360, available.size.width - (self.editingPreview ? 0 : 24)));
    CGFloat panelRoom = self.editingPreview ? available.size.height : MAX(0, self.button.frame.origin.y - CGRectGetMinY(available) - 24);
    BOOL largeText = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory)
        || width < 250;
    CGFloat headerHeight = self.editingPreview ? 0 : MAX(44, ceil(self.nameLabel.font.lineHeight) + 16);
    CGFloat headingHeight = self.quickCount && !self.editingPreview ? MAX(32, ceil([UIFont preferredFontForTextStyle:UIFontTextStyleFootnote compatibleWithTraitCollection:self.traitCollection].lineHeight) + 8) : 0;
    NSUInteger columns = largeText ? 1 : 2;
    NSUInteger categoryCount = self.items.count - self.quickCount;
    CGFloat tileWidth = (width - 16 - (columns - 1) * 8) / columns;
    CGFloat categoryWidth = largeText ? width - 16 : (width - 16) / MAX(1, categoryCount);
    CGFloat tileHeight = largeText ? 44 : 72, categoryHeight = largeText ? 44 : 64;
    for (NSUInteger i = 0; i < self.choices.count; i++) {
        UIButton *choice = self.choices[i];
        UIButtonConfiguration *configuration = choice.configuration;
        configuration.imagePlacement = largeText ? NSDirectionalRectEdgeLeading : NSDirectionalRectEdgeTop;
        configuration.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithFont:[UIFont preferredFontForTextStyle:UIFontTextStyleBody compatibleWithTraitCollection:self.traitCollection]];
        configuration.titleLineBreakMode = NSLineBreakByWordWrapping;
        choice.configuration = configuration; choice.titleLabel.numberOfLines = 0;
        CGFloat fittingHeight = ceil([choice sizeThatFits:CGSizeMake(i < self.quickCount ? tileWidth : categoryWidth, CGFLOAT_MAX)].height);
        if (i < self.quickCount) tileHeight = MAX(tileHeight, fittingHeight);
        else categoryHeight = MAX(categoryHeight, fittingHeight);
    }
    BOOL scrollingHeader = panelRoom < headerHeight + categoryHeight + MIN(tileHeight, categoryHeight) + 20;
    BOOL scrollingCategories = largeText || scrollingHeader;
    CGFloat scrollHeaderHeight = scrollingHeader ? headerHeight : 0;
    CGFloat gridHeight = self.quickCount ? headingHeight + ceil(self.quickCount / (CGFloat)columns) * (tileHeight + 8) : 0;
    CGFloat categoryBody = scrollingCategories ? categoryHeight * (largeText ? categoryCount : (categoryCount ? 1 : 0)) + 8 : 0;
    CGFloat contentHeight = scrollHeaderHeight + gridHeight + categoryBody + 8;
    CGFloat fixedHeader = scrollingHeader ? 0 : headerHeight;
    CGFloat fixedFooter = scrollingCategories || !categoryCount ? 0 : categoryHeight + 8;
    CGFloat height = MIN(fixedHeader + contentHeight + fixedFooter, panelRoom);
    CGFloat x = self.editingPreview ? CGRectGetMidX(available) - width / 2 : MAX(CGRectGetMinX(available) + 12, CGRectGetMaxX(self.button.frame) - width);
    CGFloat y = self.editingPreview ? CGRectGetMinY(available) : self.button.frame.origin.y - height - 12;
    self.panel.frame = CGRectMake(x, y, width, height);
    UIView *nameParent = scrollingHeader ? self.scroll : self.panel.contentView;
    if (self.nameLabel.superview != nameParent) [nameParent addSubview:self.nameLabel];
    CGFloat customizeWidth = self.customizeButton ? MIN(140, width * .45) : 0;
    self.nameLabel.frame = CGRectMake(16, 8, MAX(0, width - 32 - customizeWidth), MAX(0, headerHeight - 16));
    if (self.customizeButton) {
        if (self.customizeButton.superview != nameParent) [nameParent addSubview:self.customizeButton];
        self.customizeButton.frame = CGRectMake(width - customizeWidth - 8, 0, customizeWidth, headerHeight);
    }
    self.scroll.frame = CGRectMake(0, fixedHeader, width, MAX(0, height - fixedHeader - fixedFooter));
    self.scroll.contentSize = CGSizeMake(width, contentHeight);
    UILabel *heading = (UILabel *)[self.scroll viewWithTag:1001];
    heading.frame = CGRectMake(16, scrollHeaderHeight + 4, MAX(0, width - 32), MAX(0, headingHeight - 8));
    for (NSUInteger i = 0; i < self.choices.count; i++) {
        UIView *parent = i < self.quickCount || scrollingCategories ? self.scroll : self.panel.contentView;
        if (self.choices[i].superview != parent) [parent addSubview:self.choices[i]];
        if (i < self.quickCount) {
            self.choices[i].frame = CGRectMake(8 + (i % columns) * (tileWidth + 8), scrollHeaderHeight + headingHeight + (i / columns) * (tileHeight + 8), tileWidth, tileHeight);
        } else {
            NSUInteger category = i - self.quickCount;
            CGFloat categoryY = scrollingCategories ? scrollHeaderHeight + gridHeight + 8 : height - fixedFooter;
            self.choices[i].frame = largeText ? CGRectMake(8, categoryY + category * categoryHeight, width - 16, categoryHeight)
                : CGRectMake(8 + category * categoryWidth, categoryY, categoryWidth, categoryHeight);
        }
    }
}
- (CGSize)sizeThatFits:(CGSize)size {
    if (!self.editingPreview) return [super sizeThatFits:size];
    CGFloat width = MAX(0, MIN(360, size.width));
    // Measuring the real renderer preserves long titles and Dynamic Type.
    CGRect previous = self.bounds;
    self.bounds = CGRectMake(0, 0, width, 100000);
    [self setNeedsLayout]; [self layoutIfNeeded];
    CGFloat height = self.scroll.contentSize.height;
    self.bounds = previous; [self setNeedsLayout];
    return CGSizeMake(width, height);
}
- (void)toggle { if (self.panel) [self close]; else [self open]; }
- (void)open {
    self.fadeGeneration++; self.button.alpha = 1;
    if (self.panel) return;
    if (!self.editingPreview && self.openingHandler) self.openingHandler();
    NSMutableArray *items = [NSMutableArray new];
    for (NSDictionary *item in self.quickActions) if ([item[@"enabled"] boolValue]) [items addObject:item];
    self.quickCount = items.count;
    if (!self.editingPreview) [items addObjectsFromArray:self.categoryActions ?: @[
        @{@"kind": @"viewMenu", @"title": @"View & Display", @"symbol": @"display.2"},
        @{@"kind": @"inputMenu", @"title": @"Keyboard & Input", @"symbol": @"keyboard"},
        @{@"kind": @"session", @"title": @"Session", @"symbol": @"link"}]];
    self.items = items; self.choices = [NSMutableArray new];
    UIVisualEffect *effect;
    if (@available(iOS 26.0, *)) { UIGlassEffect *glass = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular]; glass.interactive = YES; effect = glass; }
    else effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    self.panel = [[UIVisualEffectView alloc] initWithEffect:self.editingPreview ? nil : effect]; self.panel.layer.cornerRadius = 24; self.panel.clipsToBounds = YES;
    self.panel.accessibilityIdentifier = @"session-control-panel";
    self.scroll = [UIScrollView new]; self.scroll.showsVerticalScrollIndicator = YES; [self.panel.contentView addSubview:self.scroll];
    UILabel *name = [UILabel new]; name.text = self.macName; name.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline compatibleWithTraitCollection:self.traitCollection];
    name.numberOfLines = 1; name.tag = 1000; name.textColor = UIColor.labelColor;
    name.hidden = self.editingPreview; name.adjustsFontForContentSizeCategory = YES; self.nameLabel = name; [self.panel.contentView addSubview:name];
    if (self.customizeHandler && !self.editingPreview) {
        self.customizeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        UIButtonConfiguration *customize = [UIButtonConfiguration plainButtonConfiguration];
        customize.title = @"Customize"; customize.image = [UIImage systemImageNamed:@"pencil"];
        customize.imagePadding = 4;
        customize.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
            NSMutableDictionary *result = attributes.mutableCopy;
            result[NSFontAttributeName] = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; return result;
        };
        self.customizeButton.configuration = customize;
        self.customizeButton.accessibilityIdentifier = @"customize-quick-actions";
        [self.customizeButton addTarget:self action:@selector(customizeActions) forControlEvents:UIControlEventTouchUpInside];
        [self.panel.contentView addSubview:self.customizeButton];
    }
    UILabel *heading = [UILabel new]; heading.text = @"Quick Actions"; heading.tag = 1001;
    heading.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote compatibleWithTraitCollection:self.traitCollection]; heading.textColor = UIColor.secondaryLabelColor;
    heading.adjustsFontForContentSizeCategory = YES;
    heading.hidden = self.editingPreview || !self.quickCount; [self.scroll addSubview:heading];
    for (NSUInteger i = 0; i < items.count; i++) {
        NSDictionary *item = items[i]; NSString *kind = item[@"kind"];
        UIButton *choice = [UIButton buttonWithType:UIButtonTypeSystem];
        UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
        config.title = [kind isEqual:@"mode"] ? (self.trackpad ? @"Switch to Pointer" : @"Switch to Trackpad") : item[@"title"];
        NSDictionary *symbols = @{@"mode": @"cursorarrow.motionlines", @"fit": @"arrow.down.right.and.arrow.up.left", @"rightClick": @"cursorarrow.click", @"shortcut": @"keyboard", @"text": @"text.quote"};
        NSString *symbol = [kind isEqual:@"mode"] ? (self.trackpad ? @"cursorarrow" : @"cursorarrow.motionlines") : item[@"symbol"] ?: symbols[kind] ?: @"circle";
        config.image = [UIImage systemImageNamed:symbol];
        config.imagePadding = 12; config.contentInsets = NSDirectionalEdgeInsetsMake(8, 12, 8, 12);
        choice.configuration = config; choice.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
        {
            config.imagePlacement = NSDirectionalRectEdgeTop; config.imagePadding = 4;
            config.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithFont:[UIFont preferredFontForTextStyle:UIFontTextStyleBody compatibleWithTraitCollection:self.traitCollection]];
            config.contentInsets = NSDirectionalEdgeInsetsMake(4, 4, 4, 4);
            choice.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
            choice.backgroundColor = i < self.quickCount ? UIColor.secondarySystemFillColor : UIColor.clearColor; choice.layer.cornerRadius = 12;
            __weak CompanionVNCControls *weak = self;
            config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
                NSMutableDictionary *result = [attributes mutableCopy]; result[NSFontAttributeName] = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1 compatibleWithTraitCollection:weak.traitCollection]; return result;
            };
            choice.configuration = config; choice.titleLabel.numberOfLines = 2; choice.titleLabel.textAlignment = NSTextAlignmentCenter;
            if (self.inputOnly && ([kind isEqual:@"fit"] || [kind isEqual:@"mode"])) choice.enabled = NO;
            if ([kind isEqual:@"copyText"] && !self.editingPreview) choice.enabled = self.textCopyAvailable && !self.inputOnly;
        }
        choice.tag = i; choice.accessibilityIdentifier = [@"session-action-" stringByAppendingString:kind];
        [choice addTarget:self action:@selector(chosen:) forControlEvents:UIControlEventTouchUpInside];
        if (self.editingPreview) {
            if (i >= self.quickCount) { choice.enabled = NO; }
            else {
                choice.enabled = self.previewSelectionHandler != nil;
                NSString *identifier = item[@"id"];
                choice.accessibilityIdentifier = [@"preview-action-" stringByAppendingString:identifier ?: @""];
                choice.accessibilityHint = @"Select to edit. Drag to reorder. No input is sent to your Mac.";
                if ([identifier isEqual:self.selectedPreviewID]) {
                    choice.layer.borderColor = UIColor.systemBlueColor.CGColor; choice.layer.borderWidth = 2;
                    choice.accessibilityTraits |= UIAccessibilityTraitSelected;
                }
                UIDragInteraction *drag = [[UIDragInteraction alloc] initWithDelegate:self]; drag.enabled = YES;
                [choice addInteraction:drag];
                [choice addInteraction:[[UIDropInteraction alloc] initWithDelegate:self]];
                __weak CompanionVNCControls *weak = self;
                NSMutableArray *moves = [NSMutableArray new];
                for (NSNumber *direction in @[@(-1), @(1)]) {
                    NSInteger neighbor = (NSInteger)i + direction.integerValue;
                    if (neighbor < 0 || neighbor >= (NSInteger)self.quickCount) continue;
                    NSString *target = items[neighbor][@"id"];
                    [moves addObject:[[UIAccessibilityCustomAction alloc] initWithName:direction.integerValue < 0 ? @"Move Earlier" : @"Move Later" actionHandler:^BOOL(UIAccessibilityCustomAction *action) {
                        if (!weak.editingPreview || !weak.previewMoveHandler || !identifier || !target) return NO;
                        weak.previewMoveHandler(identifier, target); return YES;
                    }]];
                }
                choice.accessibilityCustomActions = moves;
            }
        }
        [(i < self.quickCount ? self.scroll : self.panel.contentView) addSubview:choice]; [self.choices addObject:choice];
    }
    [self insertSubview:self.panel belowSubview:self.button]; [self setNeedsLayout]; [self layoutIfNeeded];
    self.scroll.contentOffset = CGPointZero;
    self.button.accessibilityValue = @"Open";
    if (!self.editingPreview) [self feedback:@"open"];
    self.panel.alpha = 0;
    if (!self.editingPreview && !self.reduceMotion) self.panel.transform = CGAffineTransformTranslate(CGAffineTransformMakeScale(.98,.98),0,4);
    [UIView animateWithDuration:self.editingPreview ? 0 : self.reduceMotion ? .1 : .18 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{ self.panel.alpha = 1; self.panel.transform = CGAffineTransformIdentity; } completion:nil];
}
- (void)chosen:(UIButton *)button {
    if (!self.panel || !button.enabled || button.tag < 0 || (NSUInteger)button.tag >= self.items.count) return;
    NSDictionary *item = self.items[button.tag];
    if (self.editingPreview) {
        if ((NSUInteger)button.tag < self.quickCount && self.previewSelectionHandler && item[@"id"]) self.previewSelectionHandler(item[@"id"]);
        return;
    }
    if (![item[@"kind"] isEqual:@"exit"]) [self feedback:@"commit"]; [self close];
    if (self.actionHandler) self.actionHandler(item);
}
- (void)slide:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) { [self pressDown]; [self open]; }
    if (gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) { [self close]; return; }
    UIButton *target = nil;
    if (self.panel) {
        for (UIButton *choice in self.choices) {
            CGPoint point = [gesture locationInView:choice.superview];
            if (choice.enabled && CGRectContainsPoint(choice.superview.bounds, point) && CGRectContainsPoint(choice.frame, point)) { target = choice; break; }
        }
    }
    if (target != self.highlighted) {
        self.highlighted.backgroundColor = self.highlighted.tag < self.quickCount ? UIColor.secondarySystemFillColor : UIColor.clearColor;
        self.highlighted = target; target.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.2];
        target.layer.cornerRadius = 12; if (target) [self feedback:@"selection"];
    }
    if (gesture.state == UIGestureRecognizerStateEnded) {
        [self pressUp];
        if (target) [self chosen:target]; else [self close];
    }
}
- (void)close {
    [self pressUp];
    UIVisualEffectView *closing = self.panel; closing.userInteractionEnabled = NO;
    if (closing && self.window) {
        [UIView animateWithDuration:.1 animations:^{ closing.alpha = 0; } completion:^(BOOL finished) { [closing removeFromSuperview]; }];
    } else { [closing removeFromSuperview]; }
    self.panel = nil; self.scroll = nil; self.nameLabel = nil; self.customizeButton = nil; self.items = @[]; self.choices = nil; self.highlighted = nil;
    self.button.accessibilityValue = @"Closed"; [self dimWhenIdle];
}
- (void)customizeActions { if (!self.editingPreview) { [self close]; if (self.customizeHandler) self.customizeHandler(); } }
- (void)refreshEditingPreview {
    if (!self.editingPreview) return;
    // No animations, opening callback, session actions or global preferences.
    CGPoint offset = self.scroll.contentOffset;
    BOOL changedSelection = ![self.renderedPreviewID isEqual:self.selectedPreviewID];
    [self.panel removeFromSuperview]; self.panel = nil; self.customizeButton = nil;
    self.button.hidden = YES; self.slide.enabled = NO;
    [self open]; self.panel.alpha = 1; self.panel.transform = CGAffineTransformIdentity;
    self.scroll.contentOffset = CGPointMake(0, MIN(MAX(0, offset.y), MAX(0, self.scroll.contentSize.height - self.scroll.bounds.size.height)));
    if (changedSelection && self.selectedPreviewID) {
        for (UIButton *choice in self.choices) {
            if (choice.tag < self.quickCount && [self.items[choice.tag][@"id"] isEqual:self.selectedPreviewID]) {
                [self.scroll scrollRectToVisible:choice.frame animated:NO]; break;
            }
        }
    }
    self.renderedPreviewID = self.selectedPreviewID;
}
- (NSArray<UIDragItem *> *)dragInteraction:(UIDragInteraction *)interaction itemsForBeginningSession:(id<UIDragSession>)session {
    if (!self.editingPreview || !self.previewMoveHandler || ![interaction.view isKindOfClass:UIButton.class]) return @[];
    UIButton *choice = (id)interaction.view;
    if (choice.tag < 0 || choice.tag >= self.quickCount) return @[];
    NSString *identifier = self.items[choice.tag][@"id"]; if (!identifier) return @[];
    session.localContext = self;
    UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:[[NSItemProvider alloc] initWithObject:identifier]];
    item.localObject = identifier; return @[item];
}
- (BOOL)dropInteraction:(UIDropInteraction *)interaction canHandleSession:(id<UIDropSession>)session {
    return self.editingPreview && self.previewMoveHandler && session.localDragSession.localContext == self;
}
- (UIDropProposal *)dropInteraction:(UIDropInteraction *)interaction sessionDidUpdate:(id<UIDropSession>)session {
    return [[UIDropProposal alloc] initWithDropOperation:[self dropInteraction:interaction canHandleSession:session] ? UIDropOperationMove : UIDropOperationCancel];
}
- (void)dropInteraction:(UIDropInteraction *)interaction performDrop:(id<UIDropSession>)session {
    if (![self dropInteraction:interaction canHandleSession:session]) return;
    UIButton *choice = (id)interaction.view;
    if (choice.tag < 0 || choice.tag >= self.quickCount) return;
    NSString *source = session.items.firstObject.localObject, *target = self.items[choice.tag][@"id"];
    if (source && target && ![source isEqual:target]) self.previewMoveHandler(source, target);
}
- (void)cancelSlideForLayoutChange {
    if (self.slide.state == UIGestureRecognizerStateBegan || self.slide.state == UIGestureRecognizerStateChanged) {
        self.slide.enabled = NO; self.slide.enabled = YES; [self close];
    } else { [self setNeedsLayout]; }
}
@end

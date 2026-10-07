#import "CompanionVNCControls.h"
#import "CompanionVNCAdaptiveLayout.h"
NSString *const CompanionVNCControlsHapticsPreference = @"direct-controls-haptics";
@interface CompanionVNCControls ()
@property UIButton *button;
@property UIVisualEffectView *panel;
@property UIScrollView *scroll;
@property UILabel *nameLabel;
@property NSMutableArray<UIButton *> *choices;
@property NSArray<NSDictionary *> *items;
@property UIButton *highlighted;
@property UILongPressGestureRecognizer *slide;
@property UISelectionFeedbackGenerator *feedback;
@property UIImpactFeedbackGenerator *impact;
@property NSUInteger fadeGeneration;
@property NSUInteger quickCount;
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
        _feedback = [UISelectionFeedbackGenerator new]; _impact = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    }
    return self;
}
- (BOOL)hapticsEnabled { return [NSUserDefaults.standardUserDefaults objectForKey:CompanionVNCControlsHapticsPreference] == nil || [NSUserDefaults.standardUserDefaults boolForKey:CompanionVNCControlsHapticsPreference]; }
- (void)setHapticsEnabled:(BOOL)value { [NSUserDefaults.standardUserDefaults setBool:value forKey:CompanionVNCControlsHapticsPreference]; }
- (void)emitFeedback:(NSString *)kind {
    if ([kind isEqualToString:@"selection"]) [self.feedback selectionChanged];
    else [self.impact impactOccurredWithIntensity:[kind isEqualToString:@"open"] ? .55 : .35];
}
- (void)feedback:(NSString *)kind { if (self.hapticsEnabled) [self emitFeedback:kind]; }
- (BOOL)reduceMotion { return UIAccessibilityIsReduceMotionEnabled(); }
- (void)pressDown {
    self.fadeGeneration++; self.button.alpha = 1;
    if (self.hapticsEnabled) { [self.impact prepare]; [self.feedback prepare]; }
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
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self close]; }
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
    if (!self.panel) return;
    CGFloat width = MAX(0, MIN(360, available.size.width - 24));
    CGFloat panelRoom = MAX(0, self.button.frame.origin.y - CGRectGetMinY(available) - 24);
    BOOL largeText = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory)
        || width < 280 || panelRoom < 208;
    CGFloat headerHeight = MAX(44, ceil(self.nameLabel.font.lineHeight) + 16);
    CGFloat tileHeight = MAX(64, ceil([UIFont preferredFontForTextStyle:UIFontTextStyleCaption1 compatibleWithTraitCollection:self.traitCollection].lineHeight) * 2 + 28);
    CGFloat categoryHeight = largeText ? MAX(64, tileHeight) : 64;
    CGFloat headingHeight = MAX(32, ceil([UIFont preferredFontForTextStyle:UIFontTextStyleFootnote compatibleWithTraitCollection:self.traitCollection].lineHeight) + 8);
    NSUInteger columns = largeText ? 1 : 2;
    NSUInteger categoryCount = self.items.count - self.quickCount;
    CGFloat categoryBody = largeText ? categoryCount * categoryHeight : 0;
    CGFloat contentHeight = categoryBody + (self.quickCount ? headingHeight + ceil(self.quickCount / (CGFloat)columns) * (tileHeight + 8) + 8 : 0);
    CGFloat fixedHeight = headerHeight + (largeText ? 8 : categoryHeight + 12);
    CGFloat height = MIN(fixedHeight + contentHeight + 12, panelRoom);
    CGRect rect = CGRectMake(MAX(CGRectGetMinX(available) + 12, CGRectGetMaxX(self.button.frame) - width), self.button.frame.origin.y - height - 12, width, height);
    self.panel.bounds = CGRectMake(0,0,rect.size.width,rect.size.height); self.panel.center = CGPointMake(CGRectGetMidX(rect),CGRectGetMidY(rect));
    self.nameLabel.frame = CGRectMake(16, 8, MAX(0, width - 32), headerHeight - 16);
    self.scroll.frame = CGRectMake(0, fixedHeight, width, MAX(0, height - fixedHeight - 12));
    self.scroll.contentSize = CGSizeMake(width, contentHeight);
    UILabel *heading = (UILabel *)[self.scroll viewWithTag:1001]; heading.frame = CGRectMake(16, categoryBody + 4, MAX(0, width - 32), headingHeight - 8);
    CGFloat tileWidth = (width - (columns == 1 ? 16 : 28)) / columns;
    for (NSUInteger i = 0; i < self.choices.count; i++) {
        UIView *parent = i < self.quickCount || largeText ? self.scroll : self.panel.contentView;
        if (self.choices[i].superview != parent) [parent addSubview:self.choices[i]];
        UIButtonConfiguration *configuration = self.choices[i].configuration;
        configuration.imagePlacement = largeText ? NSDirectionalRectEdgeLeading : NSDirectionalRectEdgeTop;
        self.choices[i].configuration = configuration;
        self.choices[i].frame = i < self.quickCount
            ? CGRectMake(8 + (i % columns) * (tileWidth + 12), categoryBody + headingHeight + (ceil(self.quickCount / (CGFloat)columns) - 1 - (i / columns)) * (tileHeight + 8), tileWidth, tileHeight)
            : largeText ? CGRectMake(8, (i - self.quickCount) * categoryHeight, width - 16, categoryHeight)
                       : CGRectMake(8 + (i - self.quickCount) * ((width - 16) / MAX(1, categoryCount)), headerHeight + 4, (width - 16) / MAX(1, categoryCount), categoryHeight);
    }
}
- (void)toggle { if (self.panel) [self close]; else [self open]; }
- (void)open {
    self.fadeGeneration++; self.button.alpha = 1;
    if (self.panel) return;
    if (self.openingHandler) self.openingHandler();
    NSMutableArray *items = [NSMutableArray new];
    for (NSDictionary *item in self.quickActions) if ([item[@"enabled"] boolValue]) [items addObject:item];
    self.quickCount = items.count;
    [items addObjectsFromArray:self.categoryActions ?: @[
        @{@"kind": @"viewMenu", @"title": @"View & Display", @"symbol": @"display.2"},
        @{@"kind": @"inputMenu", @"title": @"Keyboard & Input", @"symbol": @"keyboard"},
        @{@"kind": @"session", @"title": @"Session", @"symbol": @"network"}]];
    self.items = items; self.choices = [NSMutableArray new];
    UIVisualEffect *effect;
    if (@available(iOS 26.0, *)) { UIGlassEffect *glass = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular]; glass.interactive = YES; effect = glass; }
    else effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    self.panel = [[UIVisualEffectView alloc] initWithEffect:effect]; self.panel.layer.cornerRadius = 24; self.panel.clipsToBounds = YES;
    self.panel.accessibilityIdentifier = @"session-control-panel";
    self.scroll = [UIScrollView new]; self.scroll.showsVerticalScrollIndicator = YES; [self.panel.contentView addSubview:self.scroll];
    UILabel *name = [UILabel new]; name.text = self.macName; name.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline compatibleWithTraitCollection:self.traitCollection];
    name.numberOfLines = 1; name.tag = 1000; name.textColor = UIColor.labelColor;
    name.adjustsFontForContentSizeCategory = YES; self.nameLabel = name; [self.panel.contentView addSubview:name];
    UILabel *heading = [UILabel new]; heading.text = @"Quick Actions"; heading.tag = 1001;
    heading.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote compatibleWithTraitCollection:self.traitCollection]; heading.textColor = UIColor.secondaryLabelColor;
    heading.hidden = !self.quickCount; [self.scroll addSubview:heading];
    for (NSUInteger i = 0; i < items.count; i++) {
        NSDictionary *item = items[i]; NSString *kind = item[@"kind"];
        UIButton *choice = [UIButton buttonWithType:UIButtonTypeSystem];
        UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
        config.title = [kind isEqual:@"mode"] ? (self.trackpad ? @"Switch to Pointer" : @"Switch to Trackpad") : item[@"title"];
        NSDictionary *symbols = @{@"mode": @"cursorarrow.motionlines", @"fit": @"arrow.up.left.and.arrow.down.right", @"rightClick": @"computermouse", @"shortcut": @"command", @"text": @"text.quote"};
        config.image = [UIImage systemImageNamed:item[@"symbol"] ?: symbols[kind] ?: @"circle"];
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
        }
        choice.tag = i; choice.accessibilityIdentifier = [@"session-action-" stringByAppendingString:kind];
        [choice addTarget:self action:@selector(chosen:) forControlEvents:UIControlEventTouchUpInside];
        [(i < self.quickCount ? self.scroll : self.panel.contentView) addSubview:choice]; [self.choices addObject:choice];
    }
    [self insertSubview:self.panel belowSubview:self.button]; [self setNeedsLayout]; [self layoutIfNeeded];
    self.scroll.contentOffset = CGPointMake(0, MAX(0, self.scroll.contentSize.height - self.scroll.bounds.size.height));
    self.button.accessibilityValue = @"Open";
    [self feedback:@"open"];
    self.panel.alpha = 0;
    if (!self.reduceMotion) self.panel.transform = CGAffineTransformTranslate(CGAffineTransformMakeScale(.98,.98),0,4);
    [UIView animateWithDuration:self.reduceMotion ? .1 : .18 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{ self.panel.alpha = 1; self.panel.transform = CGAffineTransformIdentity; } completion:nil];
}
- (void)chosen:(UIButton *)button {
    if (!self.panel || !button.enabled || button.tag < 0 || (NSUInteger)button.tag >= self.items.count) return;
    NSDictionary *item = self.items[button.tag]; [self feedback:@"commit"]; [self close];
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
    self.panel = nil; self.scroll = nil; self.nameLabel = nil; self.items = @[]; self.choices = nil; self.highlighted = nil;
    self.button.accessibilityValue = @"Closed"; [self dimWhenIdle];
}
- (void)cancelSlideForLayoutChange {
    if (self.slide.state == UIGestureRecognizerStateBegan || self.slide.state == UIGestureRecognizerStateChanged) {
        self.slide.enabled = NO; self.slide.enabled = YES; [self close];
    } else { [self setNeedsLayout]; }
}
@end

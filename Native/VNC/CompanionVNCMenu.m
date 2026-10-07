#import "CompanionVNCMenu.h"
static void *CompanionMenuContentSizeContext = &CompanionMenuContentSizeContext;
@interface CompanionVNCMenu ()
@property(nonatomic, strong, readwrite) UITableView *tableView;
@property BOOL sizeUpdateScheduled;
@property BOOL observingContentSize;
@property CGSize requestedSize;
@end
@implementation CompanionVNCMenu
- (instancetype)init {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _sections = @[];
        _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    }
    return self;
}
+ (UINavigationController *)navigationControllerForMenu:(CompanionVNCMenu *)menu sourceView:(UIView *)sourceView {
    UINavigationController *navigation = [self navigationControllerForContent:menu sourceView:sourceView];
    NSUInteger rows = 0;
    for (NSDictionary *section in menu.sections) rows += [section[@"items"] count];
    navigation.preferredContentSize = CGSizeMake(360, 16 + rows * 54 + menu.sections.count * 32);
    return navigation;
}
+ (UINavigationController *)navigationControllerForContent:(UIViewController<UIPopoverPresentationControllerDelegate> *)content sourceView:(UIView *)sourceView {
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:content];
    navigation.modalPresentationStyle = UIModalPresentationPopover;
    navigation.overrideUserInterfaceStyle = sourceView.traitCollection.userInterfaceStyle;
    navigation.navigationBar.prefersLargeTitles = NO;
    navigation.popoverPresentationController.sourceView = sourceView;
    navigation.popoverPresentationController.sourceRect = sourceView.bounds;
    // The controls button sits at the lower edge. Point down toward it so all
    // menus grow above it; UIKit still owns fitting and keyboard avoidance.
    navigation.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionDown;
    navigation.popoverPresentationController.delegate = content;
    return navigation;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    // The table begins below the navigation bar, including when the keyboard
    // forces UIKit to reduce a popover's height. Do not combine an underlapping
    // table with estimated automatic top insets during that resize.
    self.edgesForExtendedLayout = UIRectEdgeNone;
    self.view.backgroundColor = UIColor.clearColor;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self; self.tableView.delegate = self;
    self.tableView.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.tableView.contentInset = UIEdgeInsetsZero;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 54;
    self.tableView.estimatedSectionHeaderHeight = 0; self.tableView.estimatedSectionFooterHeight = 0;
    [self.tableView addObserver:self forKeyPath:@"contentSize" options:0 context:CompanionMenuContentSizeContext];
    self.observingContentSize = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStylePlain target:self action:@selector(done)];
    self.navigationItem.rightBarButtonItem.tintColor = UIColor.labelColor;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if (self.observingContentSize) [self.tableView removeObserver:self forKeyPath:@"contentSize" context:CompanionMenuContentSizeContext];
}
- (void)keyboardChanged:(NSNotification *)notification { [self scheduleSizeUpdate]; }
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == CompanionMenuContentSizeContext) { [self scheduleSizeUpdate]; return; }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Navigation transitions can initially measure estimated rows.
    [self.tableView setNeedsLayout]; [self.view setNeedsLayout];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; self.requestedSize = CGSizeZero;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self scheduleSizeUpdate];
}
- (void)scheduleSizeUpdate {
    if (self.sizeUpdateScheduled || self.navigationController.topViewController != self) return;
    // Updating a popover size synchronously here reenters UIKit layout. Only the
    // visible menu may resize it; an outgoing submenu must not fight the new one.
    self.sizeUpdateScheduled = YES;
    __weak CompanionVNCMenu *weak = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        CompanionVNCMenu *menu = weak; if (!menu) return;
        menu.sizeUpdateScheduled = NO;
        if (!menu.view.window || menu.navigationController.topViewController != menu) return;
        [menu.tableView layoutIfNeeded];
        CGFloat end = 0;
        for (NSInteger section = 0; section < menu.sections.count; section++) {
            NSInteger rows = [menu tableView:menu.tableView numberOfRowsInSection:section];
            if (rows) end = MAX(end, CGRectGetMaxY([menu.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:rows-1 inSection:section]]));
        }
        // Measure through the last actual row, excluding the grouped table's
        // trailing filler. Dynamic Type rows still determine the content size.
        UIWindow *window = menu.view.window;
        CGRect available = UIEdgeInsetsInsetRect(window.bounds, window.safeAreaInsets);
        UIViewController *presenter = menu.navigationController.presentingViewController;
        CGRect keyboard = [presenter.view convertRect:presenter.view.keyboardLayoutGuide.layoutFrame toView:window];
        if (keyboard.size.width >= available.size.width * .8 && CGRectGetMinY(keyboard) > CGRectGetMinY(available)) {
            available.size.height = MAX(0, MIN(CGRectGetMaxY(available), CGRectGetMinY(keyboard)) - CGRectGetMinY(available));
        }
        CGFloat chrome = menu.navigationController.navigationBar.bounds.size.height;
        CGFloat room = MAX(80, available.size.height - chrome - 24);
        CGFloat height = MIN(room, ceil(end) + 12 + menu.view.safeAreaInsets.top + menu.view.safeAreaInsets.bottom);
        CGSize size = CGSizeMake(360, height);
        // UIKit adds navigation chrome to this requested body size. Cache the
        // request, rather than comparing with its larger reported size.
        if (fabs(menu.requestedSize.height - height) > 1 || menu.requestedSize.width != size.width) {
            menu.requestedSize = size;
            menu.navigationController.preferredContentSize = size;
        }
    });
}
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller { return UIModalPresentationNone; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self.sections[section][@"items"] count]; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return self.sections[section][@"title"]; }
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (![self.sections[section][@"title"] length]) return CGFLOAT_MIN;
    CGFloat line = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote compatibleWithTraitCollection:self.traitCollection].lineHeight;
    return ceil(line) + (section == 0 ? 16 : 24);
}
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section { return 8; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *item = self.sections[path.section][@"items"][path.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    content.text = item[@"title"]; content.secondaryText = item[@"subtitle"];
    content.image = [UIImage systemImageNamed:item[@"symbol"] ?: @"circle"];
    BOOL disabled = [item[@"disabled"] boolValue];
    UIColor *color = disabled ? UIColor.tertiaryLabelColor : [item[@"destructive"] boolValue] ? UIColor.systemRedColor : UIColor.labelColor;
    content.textProperties.color = color; content.imageProperties.tintColor = disabled ? UIColor.tertiaryLabelColor : [item[@"destructive"] boolValue] ? UIColor.systemRedColor : UIColor.systemBlueColor;
    content.textProperties.numberOfLines = 0; content.secondaryTextProperties.numberOfLines = 0;
    cell.contentConfiguration = content;
    cell.accessoryType = [item[@"selected"] boolValue] ? UITableViewCellAccessoryCheckmark : [item[@"submenu"] boolValue] ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    cell.selectionStyle = disabled ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
    cell.accessibilityIdentifier = [@"session-menu-" stringByAppendingString:item[@"kind"]];
    cell.accessibilityTraits = UIAccessibilityTraitButton | (disabled ? UIAccessibilityTraitNotEnabled : 0) | ([item[@"selected"] boolValue] ? UIAccessibilityTraitSelected : 0);
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *item = self.sections[path.section][@"items"][path.row];
    if ([item[@"disabled"] boolValue]) { [tableView deselectRowAtIndexPath:path animated:NO]; return; }
    void (^handler)(NSDictionary *) = self.selectionHandler;
    if ([item[@"push"] boolValue]) {
        [tableView deselectRowAtIndexPath:path animated:YES];
        if (handler) handler(item);
        return;
    }
    [self dismissViewControllerAnimated:YES completion:^{ if (handler) handler(item); }];
}
@end

#import "CompanionVNCMenu.h"
@implementation CompanionVNCMenu
- (instancetype)init { if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) _sections = @[]; return self; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 54;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
}
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller { return UIModalPresentationNone; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self.sections[section][@"items"] count]; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return self.sections[section][@"title"]; }
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

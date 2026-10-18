#import "CompanionVNCDisplayPicker.h"

@implementation CompanionVNCDisplayPicker
- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) self.displays = @[];
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Choose Display";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72;
    [self registerForTraitChanges:@[UITraitPreferredContentSizeCategory.class] withHandler:^(CompanionVNCDisplayPicker *picker, UITraitCollection *previous) {
        [picker.tableView reloadData];
    }];
    self.preferredContentSize = CGSizeMake(360, MIN(520, 116 + 72 * (self.displays.count + 1)));
}
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller { return UIModalPresentationNone; }
- (void)setDisplays:(NSArray<NSDictionary *> *)displays {
    if ([_displays isEqualToArray:displays]) return;
    // Freeze row identities for this presentation, even if a monitor is added
    // or removed. Selection is revalidated against current session metadata;
    // reopening creates a fresh picker with the latest catalogue.
    if (self.viewIfLoaded.window) return;
    _displays = [displays copy];
    if (self.isViewLoaded) [self.tableView reloadData];
}
- (void)setSelectedID:(NSNumber *)selectedID {
    if (_selectedID == selectedID || (selectedID && [_selectedID isEqualToNumber:selectedID])) return;
    _selectedID = [selectedID copy];
    // A live checkmark update must not replace the row under a finger.
    if (self.isViewLoaded) for (UITableViewCell *cell in self.tableView.visibleCells) {
        NSIndexPath *path = [self.tableView indexPathForCell:cell];
        if (path && path.row <= self.displays.count) [self updateSelectionForCell:cell row:path.row];
    }
}
- (void)updateSelectionForCell:(UITableViewCell *)cell row:(NSInteger)row {
    NSDictionary *display = row < self.displays.count ? self.displays[row] : nil;
    BOOL selected = display ? [display[@"id"] isEqual:self.selectedID] : self.selectedID == nil;
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.displays.count + 1; }
- (UIImage *)arrangementForID:(NSNumber *)selectedID {
    CGSize size = CGSizeMake(80, 44);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        if (!self.displays.count) {
            [UIColor.systemBlueColor setStroke];
            UIBezierPath *screen = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(12, 8, 56, 28) cornerRadius:3];
            screen.lineWidth = 2; [screen stroke]; return;
        }
        CGRect unionRect = CGRectNull;
        for (NSDictionary *d in self.displays) {
            CGRect r = CGRectMake([d[@"x"] doubleValue] * self.layoutAspect, [d[@"y"] doubleValue], [d[@"width"] doubleValue] * self.layoutAspect, [d[@"height"] doubleValue]);
            unionRect = CGRectUnion(unionRect, r);
        }
        if (CGRectIsEmpty(unionRect) || CGRectIsNull(unionRect)) return;
        CGFloat scale = MIN(74 / unionRect.size.width, 38 / unionRect.size.height);
        CGPoint origin = CGPointMake((size.width - unionRect.size.width * scale) / 2, (size.height - unionRect.size.height * scale) / 2);
        for (NSDictionary *d in self.displays) {
            CGRect r = CGRectMake(origin.x + ([d[@"x"] doubleValue] * self.layoutAspect - unionRect.origin.x) * scale,
                origin.y + ([d[@"y"] doubleValue] - unionRect.origin.y) * scale,
                [d[@"width"] doubleValue] * self.layoutAspect * scale, [d[@"height"] doubleValue] * scale);
            BOOL highlighted = !selectedID || [d[@"id"] isEqual:selectedID];
            [(highlighted ? UIColor.systemBlueColor : UIColor.systemGray3Color) setFill];
            [(highlighted ? UIColor.systemBlueColor : UIColor.systemGrayColor) setStroke];
            UIBezierPath *screen = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(r, .5, .5) cornerRadius:1];
            screen.lineWidth = 1; [screen fill]; [screen stroke];
        }
    }];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    NSDictionary *display = indexPath.row < self.displays.count ? self.displays[indexPath.row] : nil;
    UIListContentConfiguration *content = [cell defaultContentConfiguration];
    content.text = display ? display[@"title"] : @"All Displays";
    if (display[@"pixelWidth"] && display[@"pixelHeight"]) {
        content.secondaryText = [NSString stringWithFormat:@"%@ × %@", display[@"pixelWidth"], display[@"pixelHeight"]];
    }
    content.image = [self arrangementForID:display[@"id"]];
    BOOL largeText = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    content.imageProperties.maximumSize = largeText ? CGSizeMake(40, 28) : CGSizeMake(80, 44);
    content.imageToTextPadding = 16;
    content.textProperties.numberOfLines = 0;
    cell.contentConfiguration = content;
    [self updateSelectionForCell:cell row:indexPath.row];
    cell.accessibilityLabel = display ? [NSString stringWithFormat:@"%@, %@ × %@", display[@"title"], display[@"pixelWidth"], display[@"pixelHeight"]] : @"All Displays";
    return cell;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.displays.count ? @"Stream one display to reduce data use, or choose All Displays for the full desktop." : @"The Mac has not supplied individual display positions yet.";
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSNumber *displayID = indexPath.row < self.displays.count ? self.displays[indexPath.row][@"id"] : nil;
    if (self.selectionHandler) self.selectionHandler(displayID);
    [self done];
}
@end

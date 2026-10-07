#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
/// Native grouped submenus; selection is local until the presenting viewer handles it.
@interface CompanionVNCMenu : UIViewController <UITableViewDataSource, UITableViewDelegate, UIPopoverPresentationControllerDelegate>
@property(nonatomic, strong, readonly) UITableView *tableView;
@property(nonatomic, copy) NSArray<NSDictionary *> *sections;
@property(nonatomic, copy, nullable) void (^selectionHandler)(NSDictionary *);
+ (UINavigationController *)navigationControllerForMenu:(CompanionVNCMenu *)menu sourceView:(UIView *)sourceView;
@end
NS_ASSUME_NONNULL_END

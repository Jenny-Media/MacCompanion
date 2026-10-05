#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
/// Native grouped submenus; selection is local until the presenting viewer handles it.
@interface CompanionVNCMenu : UITableViewController <UIPopoverPresentationControllerDelegate>
@property(nonatomic, copy) NSArray<NSDictionary *> *sections;
@property(nonatomic, copy, nullable) void (^selectionHandler)(NSDictionary *);
@end
NS_ASSUME_NONNULL_END

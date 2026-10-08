#import <UIKit/UIKit.h>

// Geometry only; the picker never contains desktop thumbnails or starts a
// connection. A nil selected ID means All Displays.
@interface CompanionVNCDisplayPicker : UITableViewController <UIPopoverPresentationControllerDelegate>
@property(nonatomic, copy) NSArray<NSDictionary *> *displays;
@property(nonatomic, copy) NSNumber *selectedID;
@property(nonatomic) CGFloat layoutAspect;
@property(nonatomic, copy) void (^selectionHandler)(NSNumber *displayID);
@end

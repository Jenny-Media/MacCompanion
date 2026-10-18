#import "CompanionVNCViewer.h"
#import "BenchmarkJournal.h"
@interface CompanionVNCSession (ResolutionPrototype)
- (BOOL)requestDesktopSizeWidth:(double)width height:(double)height;
- (BOOL)requestDesktopDisplayID:(uint32_t)identifier;
@end
@interface MCPrototypeViewer : CompanionVNCViewer
- (void)recordPrototypeSnapshot:(NSDictionary *)snapshot;
@end

#import <UIKit/UIKit.h>
#import <CoreServices/LSApplicationWorkspaceObserver-Protocol.h>

@interface TDApplicationListViewController : UITableViewController <UISearchResultsUpdating, LSApplicationWorkspaceObserverProtocol>
@end

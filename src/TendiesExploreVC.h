#pragma once
#import <UIKit/UIKit.h>

@interface TendiesExploreVC : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, copy) void (^onDownload)(void);
@end

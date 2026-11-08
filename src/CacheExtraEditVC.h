#pragma once
#import <UIKit/UIKit.h>

@interface CacheExtraEditVC : UITableViewController
- (instancetype)initWithKey:(NSString *)key
                      value:(id)value
                      isNew:(BOOL)isNew
                     onSave:(void (^)(NSString *key, id value))onSave
                   onDelete:(void (^)(NSString *key))onDelete;
@end

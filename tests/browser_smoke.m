#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "ReadOnlyBrowserVC.h"
@interface SmokeDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation SmokeDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    for (NSString *name in @[@"visible", @"setVisible:", @"search", @"setSearch:", @"generation", @"setGeneration:"]) {
        Method method = class_getInstanceMethod(UITableViewController.class, NSSelectorFromString(name));
        NSLog(@"SUPER_SELECTOR %@ %s", name, method ? method_getTypeEncoding(method) : "absent");
    }
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *blank = [UIViewController new];
    ReadOnlyBrowserVC *browser = [ReadOnlyBrowserVC new];
    UITabBarController *tabs = [UITabBarController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:browser];
    nav.navigationBar.prefersLargeTitles = YES;
    tabs.viewControllers = @[blank, nav];
    self.window.rootViewController = tabs;
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        tabs.selectedIndex = 1;
        [browser loadViewIfNeeded];
        NSLog(@"SMOKE_OPENED");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            NSInteger rows = [browser tableView:browser.tableView numberOfRowsInSection:0];
            NSCAssert(rows > 0, @"Authorized app root must list at least Library and tmp");
            NSLog(@"SMOKE_ROOT_ROWS %ld", (long)rows);
            tabs.selectedIndex = 0;
            tabs.selectedIndex = 1;
            NSLog(@"SMOKE_PASS");
        });
    });
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(SmokeDelegate.class)); }
}

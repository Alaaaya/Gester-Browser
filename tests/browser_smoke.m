#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "ReadOnlyBrowserVC.h"
#import "GBSafeWrite.h"
#import "RootTabBarController.h"
@interface ReadOnlyBrowserVC (Smoke)
- (id)locationForURL:(NSURL *)url scoped:(BOOL)scope;
- (BOOL)writableFolder;
- (BOOL)externalBackupURL:(NSURL *)url;
- (void)executePending;
- (void)cancelPending;
- (void)prepareOperation:(NSString *)op source:(NSString *)source destination:(NSString *)dest bytes:(NSData *)bytes;
- (void)editFile:(NSString *)name;
@end
// Suppress only test alerts/pickers. No Files export/provider interaction is simulated as real.
@interface GateBrowser : ReadOnlyBrowserVC
@property(nonatomic,strong) UIViewController *captured;
@property(nonatomic,copy) NSString *lastMessage;
@end
@implementation GateBrowser
- (void)presentViewController:(UIViewController *)vc animated:(BOOL)animated completion:(void (^)(void))completion {
    self.captured = vc; if (completion) completion();
}
- (void)message:(NSString *)text { self.lastMessage = text; }
- (void)editorMessage:(UIViewController *)editor text:(NSString *)text { self.lastMessage = text; }
@end
static void VerifySafeGates(UINavigationController *nav) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    NSCAssert([fm createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:NULL], @"Fixture folder");
    NSData *original = [@"untouched" dataUsingEncoding:NSUTF8StringEncoding];
    NSURL *source = [root URLByAppendingPathComponent:@"original.txt"];
    NSCAssert([original writeToURL:source atomically:NO], @"Fixture original");
    GateBrowser *test = [GateBrowser new];
    [test setValue:[test locationForURL:root scoped:NO] forKey:@"location"];
    [test setValue:@"" forKey:@"relative"];
    [test loadViewIfNeeded];
    NSCAssert([test writableFolder], @"Own tmp writable");
    NSCAssert(![test externalBackupURL:source], @"Local backup cannot qualify as external");
    for (NSString *part in @[@"", @"Library", @"SystemData"]) {
        GateBrowser *readonly = [GateBrowser new];
        [readonly setValue:[readonly locationForURL:[NSURL fileURLWithPath:NSHomeDirectory()] scoped:NO] forKey:@"location"];
        [readonly setValue:part forKey:@"relative"];
        NSCAssert(![readonly writableFolder], @"Root/Library/SystemData must stay read-only");
    }
    NSDictionary *plan = @{@"operation":@"copy", @"source":@"original.txt", @"destination":@"copy.txt",
        @"original":original, @"output":original};
    for (NSNumber *verified in @[@NO, @YES]) {
        [test setValue:[plan mutableCopy] forKey:@"pendingWrite"];
        [test setValue:verified forKey:@"backupVerified"];
        [test executePending];
        NSCAssert(![fm fileExistsAtPath:[root.path stringByAppendingPathComponent:@"copy.txt"]], @"No write without backup AND explicit confirmation");
        NSCAssert([[NSData dataWithContentsOfURL:source] isEqual:original], @"Source preserved");
    }
    for (NSString *name in @[@"original.txt", @"../outside", @"bad/name", @""]) {
        [test prepareOperation:@"copy" source:@"original.txt" destination:name bytes:nil];
        NSCAssert(![test valueForKey:@"pendingWrite"], @"Conflict/invalid name cannot stage");
    }
    NSCAssert(symlink("original.txt", [root URLByAppendingPathComponent:@"link"].fileSystemRepresentation)==0, @"Fixture link");
    [test prepareOperation:@"copy" source:@"original.txt" destination:@"link" bytes:nil];
    NSCAssert(![test valueForKey:@"pendingWrite"], @"Link destination refused");
    [test prepareOperation:@"copy" source:@"link" destination:@"from-link" bytes:nil];
    NSCAssert(![test valueForKey:@"pendingWrite"], @"Link source refused");
    [test prepareOperation:@"rename" source:@"original.txt" destination:@"renamed.txt" bytes:nil];
    NSCAssert(![test valueForKey:@"pendingWrite"], @"Rename disabled");
    for (NSString *op in @[@"copy", @"mkdir", @"edit-copy"]) {
        if ([op isEqual:@"edit-copy"]) [test setValue:original forKey:@"editingOriginal"];
        [test prepareOperation:op source:[op isEqual:@"mkdir"] ? nil : @"original.txt" destination:@"pending-new" bytes:original];
        NSCAssert([test valueForKey:@"pendingWrite"] && [[test valueForKey:@"backupPickerPhase"] integerValue]==1, @"Backup must be staged and export required");
        NSCAssert(![fm fileExistsAtPath:[root.path stringByAppendingPathComponent:@"pending-new"]], @"Preparation must not mutate source folder");
        [test cancelPending];
        NSCAssert(![fm fileExistsAtPath:[root.path stringByAppendingPathComponent:@"pending-new"]], @"Cancellation must not write");
    }
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:@{@"key":@"value"} format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    NSURL *plistURL = [root URLByAppendingPathComponent:@"valid.plist"];
    NSCAssert([plist writeToURL:plistURL atomically:NO], @"Fixture plist");
    [nav pushViewController:test animated:NO];
    [test editFile:@"valid.plist"];
    UIViewController *editor = nav.topViewController;
    NSCAssert(editor != test, @"Plist editor opened");
    void (^save)(NSString *) = [editor valueForKey:@"saveText"];
    NSCAssert(save != nil, @"Editor save action");
    save(@"<plist><broken");
    NSCAssert([test.lastMessage containsString:@"plist"] && ![test valueForKey:@"pendingWrite"], @"Invalid plist refused before backup or write");
    NSCAssert([[NSData dataWithContentsOfURL:plistURL] isEqual:plist], @"Invalid plist leaves original byte-identical");
    NSCAssert([[NSData dataWithContentsOfURL:source] isEqual:original], @"All tests preserve original bytes");
    [nav popToRootViewControllerAnimated:NO];
    NSCAssert([fm removeItemAtURL:root error:NULL], @"Remove test-owned fixtures only");
    NSLog(@"SMOKE_SAFE_GATES_PASS backup/confirmation, preparation/cancel, read-only scopes, names/conflicts/links, invalid plist");
}
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
    RootTabBarController *tabs = [RootTabBarController new];
    self.window.rootViewController = tabs;
    [tabs loadViewIfNeeded];
    NSCAssert(tabs.viewControllers.count == 1, @"Single Files root");
    NSCAssert(tabs.selectedIndex == 0, @"Files selected first");
    NSCAssert(tabs.view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionLeftToRight, @"Root LTR");
    UINavigationController *nav = (UINavigationController *)tabs.viewControllers.firstObject;
    NSCAssert([nav isKindOfClass:UINavigationController.class], @"Files nav");
    ReadOnlyBrowserVC *browser = (ReadOnlyBrowserVC *)nav.viewControllers.firstObject;
    NSCAssert([browser isKindOfClass:ReadOnlyBrowserVC.class], @"Root is actual Files browser");
    NSLog(@"SMOKE_ROOT_PASS single Files tab selected 0 LTR");
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [browser loadViewIfNeeded];
        NSLog(@"SMOKE_OPENED");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            NSInteger rows = [browser tableView:browser.tableView numberOfRowsInSection:0];
            NSCAssert(rows > 0, @"Authorized app root must list at least Library and tmp");
            NSLog(@"SMOKE_ROOT_ROWS %ld", (long)rows);
            VerifySafeGates(nav);
            [browser.view setNeedsLayout]; [browser.view layoutIfNeeded];
            UILabel *notice = [browser valueForKey:@"notice"];
            CGSize required = [notice sizeThatFits:CGSizeMake(notice.bounds.size.width, CGFLOAT_MAX)];
            NSCAssert(notice.bounds.size.height >= required.height, @"Header must contain full explanation");
            NSCAssert(browser.view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionLeftToRight, @"LTR layout in every language");
            NSLog(@"SMOKE_LAYOUT_PASS header %.0f required %.0f language %@", notice.bounds.size.height, required.height, NSLocale.preferredLanguages.firstObject);
            NSLog(@"SMOKE_PASS");
        });
    });
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(SmokeDelegate.class)); }
}

#import "AppDelegate.h"
#import "BQCore.h"
#import "BQUI.h"
#import "RootTabBarController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BQCoreInit();
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[RootTabBarController alloc] init];
    [self.window makeKeyAndVisible];

    if (!BQGroupID().length) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            BQAlert(nil, @"No app group entitlement",
                    @"This build has no com.apple.security.application-groups entry.\n\n"
                    @"The app will try the legacy class-13 traversal fallback (works on some 27.0.x builds). "
                    @"On 27.2 the class-7 path needs at least one app group. "
                    @"See Documents/bqtool.log for the per-strategy result.");
        });
    }

    if ([[NSProcessInfo processInfo].arguments containsObject:@"--bqselftest"]) {
        dispatch_async(BQWorkQueue(), ^{
            BQLog(@"selftest args=%@", [NSProcessInfo processInfo].arguments);
            NSDictionary *probe = BQProbeEscapeClasses(@"/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches");
            BQLog(@"selftest probe=%@", probe);
            NSDictionary *parts = BQProbeClass2Parts(@"/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches");
            BQLog(@"selftest class2 parts=%@", parts);
            NSString *mgErr = nil;
            NSMutableDictionary *mg = BQLoadGestalt(&mgErr);
            BQLog(@"selftest MG=%@ err=%@ keys=%lu",
                  mg ? @"OK" : @"FAIL", mgErr ?: @"-",
                  (unsigned long)[mg[@"CacheExtra"] count]);
            NSString *pbErr = nil;
            NSString *pb = BQFindPosterBoardContainer(&pbErr);
            BQLog(@"selftest PB=%@ err=%@", pb ?: @"nil", pbErr ?: @"-");
            if ([[[NSProcessInfo processInfo] arguments] containsObject:@"--bqapplyfirst"] ||
                [[NSFileManager defaultManager] fileExistsAtPath:[BQDocuments() stringByAppendingPathComponent:@"ApplyFirst"]]) {
                NSString *dir = [BQDocuments() stringByAppendingPathComponent:@"tendies"];
                NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil] ?: @[];
                for (NSString *f in files) {
                    NSString *l = f.lowercaseString;
                    if (![l hasSuffix:@".tendies"] && ![l hasSuffix:@".zip"]) continue;
                    NSString *err = nil;
                    int c = 0;
                    BOOL ok = BQApplyTendies([NSURL fileURLWithPath:[dir stringByAppendingPathComponent:f]], &c, &err);
                    BQLog(@"selftest apply %@ ok=%d count=%d err=%@", f, ok, c, err ?: @"-");
                    break;
                }
            }
            BQLog(@"selftest done");
        });
    }
    return YES;
}

@end

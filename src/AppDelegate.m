#import "AppDelegate.h"
#import "BQCore.h"
#import "BQUI.h"
#import "RootTabBarController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BQCoreInit();

    if (!BQGroupID().length) {
        BQLog(@"no app group; class2-parent fallback will be attempted");
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

#pragma mark - UISceneSession lifecycle

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}

- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
}

@end

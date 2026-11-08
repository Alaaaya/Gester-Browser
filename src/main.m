#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "BQCore.h"

static void BQUncaughtExceptionHandler(NSException *e) {
    BQLog(@"UNCAUGHT %@: %@\n%@", e.name, e.reason, [e.callStackSymbols componentsJoinedByString:@"\n"]);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSSetUncaughtExceptionHandler(&BQUncaughtExceptionHandler);
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}

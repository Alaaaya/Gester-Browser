#import "SceneDelegate.h"
#import "RootTabBarController.h"

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.backgroundColor = [UIColor systemBackgroundColor];
    self.window.rootViewController = [[RootTabBarController alloc] init];
    [self.window makeKeyAndVisible];
}

@end

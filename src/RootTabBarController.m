#import "RootTabBarController.h"
#import "GestaltVC.h"
#import "PosterBoardVC.h"
#import "SettingsVC.h"

@implementation RootTabBarController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    UINavigationController *(^nav)(UIViewController *, NSString *, NSString *) =
        ^UINavigationController *(UIViewController *root, NSString *title, NSString *icon) {
            root.title = title;
            UINavigationController *n = [[UINavigationController alloc] initWithRootViewController:root];
            n.tabBarItem = [[UITabBarItem alloc] initWithTitle:title
                                                         image:[UIImage systemImageNamed:icon]
                                                 selectedImage:[UIImage systemImageNamed:icon]];
            n.navigationBar.prefersLargeTitles = YES;
            return n;
        };

    self.viewControllers = @[
        nav([[GestaltVC alloc] init], @"Gestalt", @"slider.horizontal.3"),
        nav([[PosterBoardVC alloc] init], @"PosterBoard", @"photo.on.rectangle"),
        nav([[SettingsVC alloc] init], @"Settings", @"gearshape"),
    ];
    self.selectedIndex = 0;
}

@end

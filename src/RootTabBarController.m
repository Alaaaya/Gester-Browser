#import "RootTabBarController.h"
#import "ReadOnlyBrowserVC.h"

@implementation RootTabBarController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    self.tabBar.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    NSString *title = [[[NSLocale preferredLanguages] firstObject] hasPrefix:@"ar"] ? @"الملفات" : @"Files";
    ReadOnlyBrowserVC *files = [[ReadOnlyBrowserVC alloc] init];
    files.title = title;
    UINavigationController *n = [[UINavigationController alloc] initWithRootViewController:files];
    n.view.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    n.tabBarItem = [[UITabBarItem alloc] initWithTitle:title
                                                 image:[UIImage systemImageNamed:@"folder"]
                                         selectedImage:[UIImage systemImageNamed:@"folder"]];
    n.navigationBar.prefersLargeTitles = YES;
    self.viewControllers = @[n];
    self.selectedIndex = 0;
}

@end

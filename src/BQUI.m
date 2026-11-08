#import "BQUI.h"

static UIWindow *BQKeyWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) return w;
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

UIViewController *BQTopViewController(void) {
    UIViewController *vc = BQKeyWindow().rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    while ([vc isKindOfClass:[UINavigationController class]]) {
        vc = ((UINavigationController *)vc).visibleViewController ?: vc;
    }
    while ([vc isKindOfClass:[UITabBarController class]]) {
        vc = ((UITabBarController *)vc).selectedViewController ?: vc;
    }
    return vc;
}

void BQAlert(UIViewController *vc, NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = vc ?: BQTopViewController();
        if (!top) return;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleDefault handler:nil]];
        [top presentViewController:a animated:YES completion:nil];
    });
}

void BQConfirm(UIViewController *vc, NSString *title, NSString *message, void (^action)(void)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = vc ?: BQTopViewController();
        if (!top) return;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Continue", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
            if (action) action();
        }]];
        [top presentViewController:a animated:YES completion:nil];
    });
}

@implementation BQBusyView {
    UIActivityIndicatorView *_spinner;
    UILabel *_label;
}

+ (instancetype)showInView:(UIView *)view text:(NSString *)text {
    BQBusyView *v = [[BQBusyView alloc] initWithFrame:view.bounds];
    v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    v.backgroundColor = [UIColor colorWithWhite:0 alpha:0.62];
    v->_spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    v->_spinner.color = [UIColor whiteColor];
    v->_spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [v->_spinner startAnimating];
    v->_label = [[UILabel alloc] initWithFrame:CGRectZero];
    v->_label.text = text ?: NSLocalizedString(@"Working...", nil);
    v->_label.textColor = [UIColor whiteColor];
    v->_label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    v->_label.textAlignment = NSTextAlignmentCenter;
    v->_label.numberOfLines = 0;
    v->_label.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:v->_spinner];
    [v addSubview:v->_label];
    [NSLayoutConstraint activateConstraints:@[
        [v->_spinner.centerXAnchor constraintEqualToAnchor:v.centerXAnchor],
        [v->_spinner.centerYAnchor constraintEqualToAnchor:v.centerYAnchor constant:-20],
        [v->_label.topAnchor constraintEqualToAnchor:v->_spinner.bottomAnchor constant:12],
        [v->_label.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:24],
        [v->_label.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-24],
    ]];
    dispatch_async(dispatch_get_main_queue(), ^{ [view addSubview:v]; });
    return v;
}

- (void)hide {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_spinner stopAnimating];
        [self removeFromSuperview];
    });
}

@end

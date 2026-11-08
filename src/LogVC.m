#import "LogVC.h"
#import "BQCore.h"
#import "BQUI.h"

@interface LogVC ()
@property (nonatomic, strong) UITextView *textView;
@end

@implementation LogVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Log";
    self.edgesForExtendedLayout = UIRectEdgeNone;
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.textView.editable = NO;
    self.textView.selectable = YES;
    self.textView.alwaysBounceVertical = YES;
    self.textView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.textView.textContainerInset = UIEdgeInsetsMake(12, 12, 24, 12);
    [self.view addSubview:self.textView];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                           target:self
                                                                                           action:@selector(loadLog)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Clear"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(clearLog)];
    [self loadLog];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadLog];
}

- (void)loadLog {
    NSString *text = [NSString stringWithContentsOfFile:BQLogPath() encoding:NSUTF8StringEncoding error:nil] ?: @"(empty log)";
    self.textView.text = text;
    if (text.length) {
        NSRange r = NSMakeRange(text.length - 1, 1);
        [self.textView scrollRangeToVisible:r];
    }
}

- (void)clearLog {
    BQConfirm(self, @"Clear log?", @"Truncate bqtool.log.", ^{
        [[NSFileManager defaultManager] createFileAtPath:BQLogPath() contents:nil attributes:nil];
        [self loadLog];
    });
}

@end

#import "PosterBoardVC.h"
#import "BQCore.h"
#import "BQUI.h"
#import "TendiesExploreVC.h"

@interface PosterBoardVC ()
@property (nonatomic, strong) NSArray<NSString *> *files;
@end

@implementation PosterBoardVC

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"PosterBoard";
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    UIRefreshControl *rc = [[UIRefreshControl alloc] init];
    [rc addTarget:self action:@selector(reloadFiles) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = rc;
    [self reloadFiles];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadFiles];
}

- (void)reloadFiles {
    NSString *dir = [BQDocuments() stringByAppendingPathComponent:@"tendies"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSArray *all = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil] ?: @[];
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *name in all) {
        NSString *l = name.lowercaseString;
        if ([l hasSuffix:@".tendies"] || [l hasSuffix:@".zip"]) {
            [a addObject:[dir stringByAppendingPathComponent:name]];
        }
    }
    [a sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    self.files = a;
    [self.tableView reloadData];
    [self.refreshControl endRefreshing];
}

- (void)applyAll {
    if (self.files.count == 0) {
        BQAlert(self, @"No wallpapers", @"Import a .tendies or .zip pack first.");
        return;
    }
    BQBusyView *busy = [BQBusyView showInView:self.view text:@"Applying wallpapers..."];
    NSArray *snapshot = [self.files copy];
    dispatch_async(BQWorkQueue(), ^{
        int total = 0;
        NSMutableArray<NSString *> *errors = [NSMutableArray array];
        for (NSString *path in snapshot) {
            NSString *err = nil;
            int c = 0;
            if (BQApplyTendies([NSURL fileURLWithPath:path], &c, &err)) {
                total += c;
            } else {
                [errors addObject:[NSString stringWithFormat:@"%@: %@", path.lastPathComponent, err ?: @"failed"]];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [busy hide];
            NSString *title = total > 0 ? @"Wallpapers applied" : @"Apply failed";
            NSMutableString *msg = [NSMutableString string];
            [msg appendFormat:@"%d descriptor(s) written.\n\nFor changes to take effect:\n1. Open PosterBoard\n2. Close it from the App Switcher\n3. Or tap Respring.", total];
            if (errors.count) {
                [msg appendString:@"\n\nErrors:\n"];
                [msg appendString:[errors componentsJoinedByString:@"\n"]];
            }
            UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                                       message:msg
                                                                preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"Open PosterBoard" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
                if (!BQOpenPosterBoard()) BQAlert(self, @"Open failed", @"Could not open com.apple.PosterBoard.");
            }]];
            [a addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
                BQRespring();
            }]];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
        });
    });
}

- (void)importTendies {
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[@"public.data"]
                       inMode:UIDocumentPickerModeImport];
    p.delegate = self;
    p.allowsMultipleSelection = YES;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSString *dir = [BQDocuments() stringByAppendingPathComponent:@"tendies"];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableArray *errors = [NSMutableArray array];
    for (NSURL *u in urls) {
        BOOL access = [u startAccessingSecurityScopedResource];
        NSString *name = u.lastPathComponent.length ? u.lastPathComponent : @"wallpaper.tendies";
        NSString *dest = [dir stringByAppendingPathComponent:name];
        if ([fm fileExistsAtPath:dest]) {
            dest = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", NSUUID.UUID.UUIDString, name]];
        }
        NSError *e = nil;
        if (![fm copyItemAtURL:u toURL:[NSURL fileURLWithPath:dest] error:&e]) {
            [errors addObject:[NSString stringWithFormat:@"%@: %@", name, e.localizedDescription ?: @"copy failed"]];
        }
        if (access) [u stopAccessingSecurityScopedResource];
    }
    [self reloadFiles];
    if (errors.count) BQAlert(self, @"Import errors", [errors componentsJoinedByString:@"\n"]);
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
}

- (void)resetPosterBoard {
    BQConfirm(self, @"Reset PosterBoard?", @"Remove all descriptors from the three provider folders, including stock collections. PosterBoard usually regenerates stock collections. Continue?", ^{
        BQBusyView *busy = [BQBusyView showInView:self.view text:@"Resetting PosterBoard..."];
        dispatch_async(BQWorkQueue(), ^{
            NSString *err = nil;
            BOOL ok = BQResetPosterBoard(&err);
            dispatch_async(dispatch_get_main_queue(), ^{
                [busy hide];
                if (!ok) { BQAlert(self, @"Reset failed", err ?: @"unknown error"); return; }
                UIAlertController *a = [UIAlertController alertControllerWithTitle:@"PosterBoard reset"
                                                                           message:@"Descriptors removed. Respring to apply."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                [a addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { BQRespring(); }]];
                [self presentViewController:a animated:YES completion:nil];
            });
        });
    });
}

- (void)openPosterBoard {
    if (!BQOpenPosterBoard()) BQAlert(self, @"Open failed", @"Could not open com.apple.PosterBoard.");
}

- (void)explore {
    TendiesExploreVC *vc = [[TendiesExploreVC alloc] init];
    __weak typeof(self) weakSelf = self;
    vc.onDownload = ^{
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf reloadFiles]; });
    };
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)respring {
    BQConfirm(self, @"Respring?", @"Restart SpringBoard to apply wallpaper changes.", ^{ BQRespring(); });
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 6;
    return self.files.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Actions";
    return self.files.count ? @"Imported packs" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"Import up to 5 packs. More than 15 is a bad idea. Applying writes descriptor folders into PosterBoard; use Reset to remove them.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"action"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"action"];
        NSArray *titles = @[@"Apply All", @"Import .tendies", @"Explore Wallpapers", @"Reset PosterBoard", @"Open PosterBoard", @"Respring"];
        cell.textLabel.text = titles[indexPath.row];
        cell.textLabel.textColor = indexPath.row == 3 ? [UIColor systemRedColor] : self.view.tintColor;
        cell.textLabel.textAlignment = NSTextAlignmentLeft;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"file"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"file"];
    NSString *path = self.files[indexPath.row];
    cell.textLabel.text = path.lastPathComponent;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    unsigned long long size = [attrs[NSFileSize] unsignedLongLongValue];
    cell.detailTextLabel.text = [NSByteCountFormatter stringFromByteCount:(long long)size countStyle:NSByteCountFormatterCountStyleFile];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 0) return;
    switch (indexPath.row) {
        case 0: [self applyAll]; break;
        case 1: [self importTendies]; break;
        case 2: [self explore]; break;
        case 3: [self resetPosterBoard]; break;
        case 4: [self openPosterBoard]; break;
        case 5: [self respring]; break;
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 1) return nil;
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                     title:@"Delete"
                                                                   handler:^(UIContextualAction *action, UIView *v, void (^done)(BOOL)) {
        NSString *path = self.files[indexPath.row];
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        [self reloadFiles];
        done(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

@end

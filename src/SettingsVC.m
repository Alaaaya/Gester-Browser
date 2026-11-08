#import "SettingsVC.h"
#import "BQCore.h"
#import "BQUI.h"
#import "LogVC.h"

@interface SettingsVC ()
@property (nonatomic, copy) NSString *mgStatus;
@property (nonatomic, copy) NSString *pbStatus;
@property (nonatomic, copy) NSString *managedGroup;
@end

@implementation SettingsVC

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSLocalizedString(@"Settings", nil);
    self.mgStatus = NSLocalizedString(@"not checked", nil);
    self.pbStatus = NSLocalizedString(@"not checked", nil);
    self.managedGroup = [[NSUserDefaults standardUserDefaults] stringForKey:@"BQManagedGroupName"];
    if (!self.managedGroup.length) self.managedGroup = @"KAMUI Test Group";
}

- (BOOL)bannerEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"BQTestBannerEnabled"];
}

- (void)updateBanner {
    if (![self bannerEnabled]) {
        self.tableView.tableHeaderView = nil;
        return;
    }
    CGFloat width = self.tableView.bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 76)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(header.bounds, 20, 10)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.textColor = [UIColor secondaryLabelColor];
    label.text = [NSString stringWithFormat:NSLocalizedString(@"This iPhone is provided specifically for testing.\nManaged by group: %@", nil), self.managedGroup ?: @"KAMUI Test Group"];
    [header addSubview:label];
    self.tableView.tableHeaderView = header;
}

- (void)bannerChanged:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.isOn forKey:@"BQTestBannerEnabled"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self updateBanner];
}

- (NSString *)currentLanguageName {
    NSString *code = [[NSUserDefaults standardUserDefaults] stringForKey:@"BQLanguageOverride"];
    if (!code.length) return NSLocalizedString(@"System", nil);
    NSDictionary *names = @{
        @"en": @"English", @"ru": @"Русский", @"ko": @"한국어",
        @"ar": @"العربية", @"tr": @"Türkçe", @"uk": @"Українська", @"vi": @"Tiếng Việt"
    };
    return names[code] ?: code;
}

- (void)chooseLanguage {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Language", nil)
                                                               message:nil
                                                        preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *opts = @[
        @{@"title": NSLocalizedString(@"System", nil), @"code": @""},
        @{@"title": @"English", @"code": @"en"},
        @{@"title": @"Русский", @"code": @"ru"},
        @{@"title": @"한국어", @"code": @"ko"},
        @{@"title": @"العربية", @"code": @"ar"},
        @{@"title": @"Türkçe", @"code": @"tr"},
        @{@"title": @"Українська", @"code": @"uk"},
        @{@"title": @"Tiếng Việt", @"code": @"vi"},
    ];
    for (NSDictionary *o in opts) {
        [a addAction:[UIAlertAction actionWithTitle:o[@"title"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            NSString *code = o[@"code"];
            NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
            if (!code.length) {
                [defs removeObjectForKey:@"BQLanguageOverride"];
                [defs removeObjectForKey:@"AppleLanguages"];
            } else {
                [defs setObject:code forKey:@"BQLanguageOverride"];
                [defs setObject:@[code] forKey:@"AppleLanguages"];
            }
            [defs synchronize];
            UIAlertController *r = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Language", nil)
                                                                       message:NSLocalizedString(@"Restart KAMUI to apply the language.", nil)
                                                                preferredStyle:UIAlertControllerStyleAlert];
            [r addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:r animated:YES completion:nil];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:4]];
    a.popoverPresentationController.sourceView = cell ?: self.view;
    a.popoverPresentationController.sourceRect = cell ? cell.bounds : CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (void)class2Changed:(UISwitch *)sw {
    BQSetClass2ParentEnabled(sw.isOn);
    if (sw.isOn) {
        BQAlert(self, NSLocalizedString(@"Class-2 fallback enabled", nil),
                @"KAMUI will try to move its own Library on the next Gestalt/PosterBoard operation. "
                @"Some builds kill the app for this; if KAMUI closes, relaunch and disable this switch. "
                @"Send Documents/bqtool.log to the developer.");
    }
}

- (void)editManagedGroup {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Managed by group", nil)
                                                               message:NSLocalizedString(@"This label is shown in the app banner. It does not install an MDM enrollment or change iOS Settings.", nil)
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = NSLocalizedString(@"Group name", nil);
        tf.text = self.managedGroup;
    }];
    [a addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Save", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *name = [a.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        self.managedGroup = name.length ? name : @"KAMUI Test Group";
        [[NSUserDefaults standardUserDefaults] setObject:self.managedGroup forKey:@"BQManagedGroupName"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [self updateBanner];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:3]
                     withRowAnimation:UITableViewRowAnimationAutomatic];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSString *pb = [[NSUserDefaults standardUserDefaults] stringForKey:@"BQPBContainer"];
    if (pb.length) self.pbStatus = pb;
    [self.tableView reloadData];
    [self updateBanner];
}

- (void)runDiagnostics {
    BQBusyView *busy = [BQBusyView showInView:self.view text:NSLocalizedString(@"Checking escape...", nil)];
    dispatch_async(BQWorkQueue(), ^{
        NSString *mgErr = nil;
        BOOL mg = BQCheckAccess([BQMobileGestaltPath() stringByDeletingLastPathComponent], YES, &mgErr);
        NSString *pbErr = nil;
        NSString *pb = BQFindPosterBoardContainer(&pbErr);
        dispatch_async(dispatch_get_main_queue(), ^{
            [busy hide];
            self.mgStatus = mg ? NSLocalizedString(@"read/write OK", nil) : [NSString stringWithFormat:NSLocalizedString(@"FAILED: %@", nil), mgErr ?: NSLocalizedString(@"unknown", nil)];
            self.pbStatus = pb ?: [NSString stringWithFormat:NSLocalizedString(@"not found: %@", nil), pbErr ?: NSLocalizedString(@"unknown", nil)];
            [self.tableView reloadData];
            BQAlert(self, NSLocalizedString(@"Diagnostics", nil),
                    [NSString stringWithFormat:NSLocalizedString(@"MobileGestalt: %@\n\nPosterBoard: %@\n\nApp group:\n%@", nil),
                     self.mgStatus, self.pbStatus, BQGroupRoot() ?: @"(nil)"]);
        });
    });
}

- (void)inPlaceChanged:(UISwitch *)sw {
    BQSetInPlaceWrite(sw.isOn);
}

- (void)respring {
    BQConfirm(self, NSLocalizedString(@"Respring?", nil), NSLocalizedString(@"Restart SpringBoard.", nil), ^{ BQRespring(); });
}

- (void)openLog {
    [self.navigationController pushViewController:[[LogVC alloc] init] animated:YES];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 5; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 4;
        case 1: return 1;
        case 2: return 2;
        case 3: return 3;
        case 4: return 4;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return NSLocalizedString(@"Status", nil);
        case 1: return NSLocalizedString(@"Write method", nil);
        case 2: return NSLocalizedString(@"Tools", nil);
        case 3: return NSLocalizedString(@"Test Device", nil);
        case 4: return NSLocalizedString(@"About", nil);
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) return NSLocalizedString(@"In-place write keeps the same inode and is more likely to persist after reboot. Disable to use atomic replace.", nil);
    if (section == 3) return NSLocalizedString(@"The banner is shown inside KAMUI only. Changing the system Settings banner requires MDM/supervision enrollment. The class-2 fallback is off by default because moving Library can make the sandbox terminate the app.", nil);
    if (section == 4) return NSLocalizedString(@"KAMUI is MIT licensed and free for everyone. No allowlist, no tester group. Use only on devices you own or have permission to modify. UI inspired by mond. NeoSpring by neonmodder123/skadz108.", nil);
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        if (indexPath.row == 3) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"action"];
            if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"action"];
            cell.textLabel.text = NSLocalizedString(@"Run Diagnostics", nil);
            cell.textLabel.textColor = self.view.tintColor;
            cell.textLabel.textAlignment = NSTextAlignmentLeft;
            cell.accessoryType = UITableViewCellAccessoryNone;
            return cell;
        }
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"status"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"status"];
        if (indexPath.row == 0) {
            cell.textLabel.text = NSLocalizedString(@"App Group", nil);
            NSString *gid = BQGroupID();
            cell.detailTextLabel.text = gid.length ? gid : @"none — class2 parent fallback";
        } else if (indexPath.row == 1) {
            cell.textLabel.text = NSLocalizedString(@"MobileGestalt", nil);
            cell.detailTextLabel.text = self.mgStatus;
        } else {
            cell.textLabel.text = NSLocalizedString(@"PosterBoard", nil);
            cell.detailTextLabel.text = self.pbStatus;
        }
        cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        cell.detailTextLabel.numberOfLines = 1;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    if (indexPath.section == 1) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"switch"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"switch"];
        cell.textLabel.text = NSLocalizedString(@"In-place write (persist after reboot)", nil);
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISwitch *sw = (UISwitch *)cell.accessoryView;
        if (![sw isKindOfClass:[UISwitch class]]) {
            sw = [[UISwitch alloc] init];
            sw.onTintColor = self.view.tintColor;
            [sw addTarget:self action:@selector(inPlaceChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
        sw.on = BQInPlaceWrite();
        return cell;
    }
    if (indexPath.section == 2) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"tool"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"tool"];
        cell.textLabel.text = indexPath.row == 0 ? NSLocalizedString(@"Respring", nil) : NSLocalizedString(@"Open Log", nil);
        cell.textLabel.textColor = self.view.tintColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    if (indexPath.section == 3) {
        if (indexPath.row == 0) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"bannerswitch"];
            if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"bannerswitch"];
            cell.textLabel.text = NSLocalizedString(@"Show test-device banner", nil);
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *sw = (UISwitch *)cell.accessoryView;
            if (![sw isKindOfClass:[UISwitch class]]) {
                sw = [[UISwitch alloc] init];
                sw.onTintColor = self.view.tintColor;
                [sw addTarget:self action:@selector(bannerChanged:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = sw;
            }
            sw.on = [self bannerEnabled];
            return cell;
        }
        if (indexPath.row == 2) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"class2switch"];
            if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"class2switch"];
            cell.textLabel.text = NSLocalizedString(@"Class-2 fallback (experimental)", nil);
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *sw = (UISwitch *)cell.accessoryView;
            if (![sw isKindOfClass:[UISwitch class]]) {
                sw = [[UISwitch alloc] init];
                sw.onTintColor = self.view.tintColor;
                [sw addTarget:self action:@selector(class2Changed:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = sw;
            }
            sw.on = BQClass2ParentEnabled();
            return cell;
        }
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"bannergroup"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"bannergroup"];
        cell.textLabel.text = NSLocalizedString(@"Managed by group", nil);
        cell.detailTextLabel.text = self.managedGroup;
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"about"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"about"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    cell.accessoryType = UITableViewCellAccessoryNone;
    if (indexPath.row == 0) {
        cell.textLabel.text = NSLocalizedString(@"Version", nil);
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ (%@)",
            info[@"CFBundleShortVersionString"] ?: @"?", info[@"CFBundleVersion"] ?: @"?"];
    } else if (indexPath.row == 1) {
        cell.textLabel.text = NSLocalizedString(@"Engine", nil);
        cell.detailTextLabel.text = NSLocalizedString(@"MCM symlink escape", nil);
    } else if (indexPath.row == 2) {
        cell.textLabel.text = NSLocalizedString(@"Target", nil);
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ %@", [UIDevice currentDevice].model, [UIDevice currentDevice].systemVersion];
    } else {
        cell.textLabel.text = NSLocalizedString(@"Language", nil);
        cell.detailTextLabel.text = [self currentLanguageName];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && indexPath.row == 3) [self runDiagnostics];
    else if (indexPath.section == 2 && indexPath.row == 0) [self respring];
    else if (indexPath.section == 2 && indexPath.row == 1) [self openLog];
    else if (indexPath.section == 3 && indexPath.row == 1) [self editManagedGroup];
    else if (indexPath.section == 4 && indexPath.row == 3) [self chooseLanguage];
}

@end

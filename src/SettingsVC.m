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
    self.title = @"Settings";
    self.mgStatus = @"not checked";
    self.pbStatus = @"not checked";
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
    label.text = [NSString stringWithFormat:@"This iPhone is provided specifically for testing.\nManaged by group: %@", self.managedGroup ?: @"KAMUI Test Group"];
    [header addSubview:label];
    self.tableView.tableHeaderView = header;
}

- (void)bannerChanged:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.isOn forKey:@"BQTestBannerEnabled"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self updateBanner];
}

- (void)editManagedGroup {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Managed by group"
                                                               message:@"This label is shown in the app banner. It does not install an MDM enrollment or change iOS Settings."
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Group name";
        tf.text = self.managedGroup;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
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
    BQBusyView *busy = [BQBusyView showInView:self.view text:@"Checking escape..."];
    dispatch_async(BQWorkQueue(), ^{
        NSString *mgErr = nil;
        BOOL mg = BQCheckAccess([BQMobileGestaltPath() stringByDeletingLastPathComponent], YES, &mgErr);
        NSString *pbErr = nil;
        NSString *pb = BQFindPosterBoardContainer(&pbErr);
        dispatch_async(dispatch_get_main_queue(), ^{
            [busy hide];
            self.mgStatus = mg ? @"read/write OK" : [NSString stringWithFormat:@"FAILED: %@", mgErr ?: @"unknown"];
            self.pbStatus = pb ?: [NSString stringWithFormat:@"not found: %@", pbErr ?: @"unknown"];
            [self.tableView reloadData];
            BQAlert(self, @"Diagnostics",
                    [NSString stringWithFormat:@"MobileGestalt: %@\n\nPosterBoard: %@\n\nApp group:\n%@",
                     self.mgStatus, self.pbStatus, BQGroupRoot() ?: @"(nil)"]);
        });
    });
}

- (void)inPlaceChanged:(UISwitch *)sw {
    BQSetInPlaceWrite(sw.isOn);
}

- (void)respring {
    BQConfirm(self, @"Respring?", @"Restart SpringBoard.", ^{ BQRespring(); });
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
        case 3: return 2;
        case 4: return 3;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"Status";
        case 1: return @"Write method";
        case 2: return @"Tools";
        case 3: return @"Test Device";
        case 4: return @"About";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) return @"In-place write keeps the same inode and is more likely to persist after reboot. Disable to use atomic replace.";
    if (section == 3) return @"The banner is shown inside KAMUI only. Changing the system Settings banner requires MDM/supervision enrollment.";
    if (section == 4) return @"KAMUI is MIT licensed and free for everyone. No allowlist, no tester group. Use only on devices you own or have permission to modify. UI inspired by mond. NeoSpring by neonmodder123/skadz108.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        if (indexPath.row == 3) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"action"];
            if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"action"];
            cell.textLabel.text = @"Run Diagnostics";
            cell.textLabel.textColor = self.view.tintColor;
            cell.textLabel.textAlignment = NSTextAlignmentLeft;
            cell.accessoryType = UITableViewCellAccessoryNone;
            return cell;
        }
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"status"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"status"];
        if (indexPath.row == 0) {
            cell.textLabel.text = @"App Group";
            NSString *gid = BQGroupID();
            cell.detailTextLabel.text = gid.length ? gid : @"none — class2 parent fallback";
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"MobileGestalt";
            cell.detailTextLabel.text = self.mgStatus;
        } else {
            cell.textLabel.text = @"PosterBoard";
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
        cell.textLabel.text = @"In-place write (persist after reboot)";
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
        cell.textLabel.text = indexPath.row == 0 ? @"Respring" : @"Open Log";
        cell.textLabel.textColor = self.view.tintColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    if (indexPath.section == 3) {
        if (indexPath.row == 0) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"bannerswitch"];
            if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"bannerswitch"];
            cell.textLabel.text = @"Show test-device banner";
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
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"bannergroup"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"bannergroup"];
        cell.textLabel.text = @"Managed by group";
        cell.detailTextLabel.text = self.managedGroup;
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"about"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"about"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    if (indexPath.row == 0) {
        cell.textLabel.text = @"Version";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ (%@)",
            info[@"CFBundleShortVersionString"] ?: @"?", info[@"CFBundleVersion"] ?: @"?"];
    } else if (indexPath.row == 1) {
        cell.textLabel.text = @"Engine";
        cell.detailTextLabel.text = @"MCM symlink escape";
    } else {
        cell.textLabel.text = @"Target";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ %@", [UIDevice currentDevice].model, [UIDevice currentDevice].systemVersion];
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
}

@end

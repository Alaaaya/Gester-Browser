#import "GestaltVC.h"
#import "BQCore.h"
#import "BQUI.h"
#import "CacheExtraEditVC.h"
#import <CoreFoundation/CoreFoundation.h>

static NSString * const kArtKey = @"oPeik/9e8lQWMszEjbPzng";

static NSString *BQValueSummary(id v) {
    if (!v) return @"(null)";
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSNumber class]]) {
        if (CFGetTypeID((__bridge CFTypeRef)v) == CFBooleanGetTypeID()) {
            return [v boolValue] ? @"true" : @"false";
        }
        return [v stringValue];
    }
    if ([v isKindOfClass:[NSData class]]) return [NSString stringWithFormat:@"< %lu bytes >", (unsigned long)[v length]];
    if ([v isKindOfClass:[NSArray class]]) return [NSString stringWithFormat:@"[%lu items]", (unsigned long)[v count]];
    if ([v isKindOfClass:[NSDictionary class]]) return [NSString stringWithFormat:@"{%lu keys}", (unsigned long)[v count]];
    return [v description];
}

@interface GestaltVC ()
@property (nonatomic, strong) NSMutableDictionary *mg;
@property (nonatomic, strong) NSMutableDictionary *cacheExtra;
@property (nonatomic, strong) NSArray<NSString *> *keys;
@property (nonatomic, strong) NSArray<NSDictionary *> *presets;
@property (nonatomic, assign) NSInteger originalSubtype;
@property (nonatomic, assign) BOOL loading;
@end

@implementation GestaltVC

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MobileGestalt";
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

    UIBarButtonItem *apply = [[UIBarButtonItem alloc] initWithTitle:@"Apply"
                                                              style:UIBarButtonItemStyleDone
                                                             target:self
                                                             action:@selector(applyTweaks)];
    UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                         target:self
                                                                         action:@selector(addKey)];
    self.navigationItem.rightBarButtonItems = @[apply, add];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Revert"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(revertTweaks)];

    UIRefreshControl *rc = [[UIRefreshControl alloc] init];
    [rc addTarget:self action:@selector(loadGestalt) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = rc;

    self.presets = @[
        @{@"title": @"Dynamic Island", @"keys": @[@"YlEtTtHlNesRBMal1CqRaA"], @"value": @YES},
        @{@"title": @"Always-On Display", @"keys": @[@"2OOJf1VhaM7NxfRok3HbWQ", @"j8/Omm6s1lsmTDFsXjsBfA"], @"value": @YES},
        @{@"title": @"AOD Vibrancy", @"keys": @[@"ykpu7qyhqFweVMKtxNylWA"], @"value": @YES},
        @{@"title": @"Boot Chime", @"keys": @[@"QHxt+hGLaBPbQJbXiUJX3w"], @"value": @YES},
        @{@"title": @"80% Charge Limit", @"keys": @[@"37NVydb//GP/GrhuTN+exg"], @"value": @YES},
        @{@"title": @"Tap to Wake", @"keys": @[@"yZf3GTRMGTuwSV/lD7Cagw"], @"value": @YES},
        @{@"title": @"Stage Manager", @"keys": @[@"qeaj75wk3HF4DwQ8qbIi7g"], @"value": @YES},
        @{@"title": @"Apple Pencil", @"keys": @[@"yhHcB0iH0d1XzPO/CFd3ow"], @"value": @YES},
        @{@"title": @"Action Button", @"keys": @[@"cT44WE1EohiwRzhsZ8xEsw"], @"value": @YES},
        @{@"title": @"Collision SOS", @"keys": @[@"HCzWusHQwZDea6nNhaKndw"], @"value": @YES},
        @{@"title": @"Disable Parallax", @"keys": @[@"UIParallaxCapability"], @"value": @NO},
    ];
    [self loadGestalt];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.mg && !self.loading) [self loadGestalt];
}

- (void)loadGestalt {
    if (self.loading) { [self.refreshControl endRefreshing]; return; }
    self.loading = YES;
    BQBusyView *busy = [BQBusyView showInView:self.view text:@"Reading MobileGestalt..."];
    dispatch_async(BQWorkQueue(), ^{
        NSString *err = nil;
        NSMutableDictionary *mg = BQLoadGestalt(&err);
        dispatch_async(dispatch_get_main_queue(), ^{
            [busy hide];
            [self.refreshControl endRefreshing];
            self.loading = NO;
            if (!mg) {
                BQAlert(self, @"MobileGestalt", err ?: @"load failed");
                return;
            }
            self.mg = mg;
            NSMutableDictionary *ce = [mg[@"CacheExtra"] isKindOfClass:[NSDictionary class]]
                ? [mg[@"CacheExtra"] mutableCopy] : [NSMutableDictionary dictionary];
            mg[@"CacheExtra"] = ce;
            self.cacheExtra = ce;
            self.keys = [ce.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
            NSDictionary *bak = [NSDictionary dictionaryWithContentsOfFile:BQBackupPath()];
            NSDictionary *art = bak[@"CacheExtra"][kArtKey];
            self.originalSubtype = [art[@"ArtworkDeviceSubType"] integerValue];
            [self.tableView reloadData];
        });
    });
}

- (BOOL)presetOn:(NSDictionary *)p {
    id want = p[@"value"];
    for (NSString *k in p[@"keys"]) {
        id cur = self.cacheExtra[k];
        if (!cur) return NO;
        if ([want isKindOfClass:[NSNumber class]] && [cur isKindOfClass:[NSNumber class]]) {
            if ([want boolValue] != [cur boolValue]) return NO;
        } else if (![cur isEqual:want]) {
            return NO;
        }
    }
    return YES;
}

- (void)presetChanged:(UISwitch *)sw {
    if (sw.tag < 0 || sw.tag >= (NSInteger)self.presets.count) return;
    NSDictionary *p = self.presets[sw.tag];
    if (sw.isOn) {
        for (NSString *k in p[@"keys"]) self.cacheExtra[k] = p[@"value"];
    } else {
        for (NSString *k in p[@"keys"]) [self.cacheExtra removeObjectForKey:k];
    }
    BQLog(@"preset %@ -> %d (in memory)", p[@"title"], sw.isOn);
}

- (NSString *)subtypeNameForValue:(NSInteger)v {
    switch (v) {
        case 2556: return @"iPhone 14 Pro";
        case 2796: return @"iPhone 14 Pro Max";
        case 2976: return @"iPhone 15 Pro Max";
        case 2622: return @"iPhone 16 Pro";
        case 2868: return @"iPhone 16 Pro Max";
        case 2736: return @"iPhone Air";
        default: return [NSString stringWithFormat:@"Original (%ld)", (long)v];
    }
}

- (NSString *)currentSubtypeName {
    NSDictionary *art = self.cacheExtra[kArtKey];
    NSInteger v = [art[@"ArtworkDeviceSubType"] integerValue];
    if (v == 0) v = self.originalSubtype;
    return [self subtypeNameForValue:v];
}

- (void)chooseSubtype {
    NSArray *opts = @[
        @{@"title": [NSString stringWithFormat:@"Original (%ld)", (long)self.originalSubtype], @"value": @(self.originalSubtype)},
        @{@"title": @"iPhone 14 Pro (2556)", @"value": @2556},
        @{@"title": @"iPhone 14 Pro Max (2796)", @"value": @2796},
        @{@"title": @"iPhone 15 Pro Max (2976)", @"value": @2976},
        @{@"title": @"iPhone 16 Pro (2622)", @"value": @2622},
        @{@"title": @"iPhone 16 Pro Max (2868)", @"value": @2868},
        @{@"title": @"iPhone Air (2736)", @"value": @2736},
    ];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Device Subtype"
                                                               message:@"Only changes the Dynamic Island position. Visual artifacts are possible."
                                                        preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *o in opts) {
        [a addAction:[UIAlertAction actionWithTitle:o[@"title"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            NSMutableDictionary *art = [self.cacheExtra[kArtKey] isKindOfClass:[NSDictionary class]]
                ? [self.cacheExtra[kArtKey] mutableCopy] : [NSMutableDictionary dictionary];
            NSInteger v = [o[@"value"] integerValue];
            if (v == 0) [art removeObjectForKey:@"ArtworkDeviceSubType"];
            else art[@"ArtworkDeviceSubType"] = @(v);
            self.cacheExtra[kArtKey] = art;
            BQLog(@"subtype -> %ld", (long)v);
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2]
                         withRowAnimation:UITableViewRowAnimationAutomatic];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2]];
    a.popoverPresentationController.sourceView = cell ?: self.view;
    a.popoverPresentationController.sourceRect = cell ? cell.bounds : CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (void)applyTweaks {
    if (!self.mg) { BQAlert(self, @"MobileGestalt", @"Not loaded yet."); return; }
    self.mg[@"CacheExtra"] = self.cacheExtra;
    BQBusyView *busy = [BQBusyView showInView:self.view text:@"Writing MobileGestalt..."];
    NSDictionary *snapshot = [self.mg copy];
    dispatch_async(BQWorkQueue(), ^{
        NSString *err = nil;
        BOOL ok = BQSaveGestalt(snapshot, &err);
        dispatch_async(dispatch_get_main_queue(), ^{
            [busy hide];
            if (!ok) { BQAlert(self, @"Apply failed", err ?: @"unknown error"); return; }
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Applied"
                                                                       message:@"MobileGestalt written. Respring to apply the changes."
                                                                preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [a addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
                BQRespring();
            }]];
            [self presentViewController:a animated:YES completion:nil];
        });
    });
}

- (void)revertTweaks {
    BQConfirm(self, @"Revert MobileGestalt?", @"Restore OriginalGestalt.plist and overwrite the live cache.", ^{
        BQBusyView *busy = [BQBusyView showInView:self.view text:@"Restoring MobileGestalt..."];
        dispatch_async(BQWorkQueue(), ^{
            NSString *err = nil;
            BOOL ok = BQRestoreGestalt(&err);
            dispatch_async(dispatch_get_main_queue(), ^{
                [busy hide];
                if (!ok) { BQAlert(self, @"Revert failed", err ?: @"unknown error"); return; }
                UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Reverted"
                                                                           message:@"Original MobileGestalt restored. Respring or reboot."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
                [a addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { BQRespring(); }]];
                [self presentViewController:a animated:YES completion:nil];
            });
        });
    });
}

- (void)respring {
    BQConfirm(self, @"Respring?", @"This restarts SpringBoard. Open apps will be closed.", ^{ BQRespring(); });
}

- (void)addKey {
    CacheExtraEditVC *vc = [[CacheExtraEditVC alloc] initWithKey:nil value:nil isNew:YES onSave:^(NSString *key, id value) {
        self.cacheExtra[key] = value;
        self.keys = [self.cacheExtra.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        [self.tableView reloadData];
    } onDelete:nil];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)editKeyAtIndexPath:(NSIndexPath *)ip {
    if (ip.row < 0 || ip.row >= (NSInteger)self.keys.count) return;
    NSString *key = self.keys[ip.row];
    id value = self.cacheExtra[key];
    CacheExtraEditVC *vc = [[CacheExtraEditVC alloc] initWithKey:key value:value isNew:NO onSave:^(NSString *k, id v) {
        self.cacheExtra[k] = v;
        [self.tableView reloadData];
    } onDelete:^(NSString *k) {
        [self.cacheExtra removeObjectForKey:k];
        self.keys = [self.cacheExtra.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        [self.tableView reloadData];
    }];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 3;
        case 1: return self.presets.count;
        case 2: return 1;
        case 3: return self.keys.count;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"Actions";
        case 1: return @"Tweaks";
        case 2: return @"Device Subtype";
        case 3: return @"CacheExtra";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case 1:
            return @"These tweaks can break features or softbrick the device if misused. Backup exists in Documents/OriginalGestalt.plist.";
        case 2:
            return @"Optional: moves the Dynamic Island position. Does not change the device model name.";
        case 3:
            return @"Tap a key to edit; swipe left to delete. Changes are written only when you tap Apply.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"action"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"action"];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.textLabel.textAlignment = NSTextAlignmentLeft;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Apply Tweaks";
            cell.textLabel.textColor = self.view.tintColor;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Revert Tweaks";
            cell.textLabel.textColor = [UIColor systemRedColor];
        } else {
            cell.textLabel.text = @"Respring";
            cell.textLabel.textColor = self.view.tintColor;
        }
        return cell;
    }
    if (indexPath.section == 1) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"preset"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"preset"];
        NSDictionary *p = self.presets[indexPath.row];
        cell.textLabel.text = p[@"title"];
        cell.textLabel.textColor = [UIColor labelColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISwitch *sw = (UISwitch *)cell.accessoryView;
        if (![sw isKindOfClass:[UISwitch class]]) {
            sw = [[UISwitch alloc] init];
            sw.onTintColor = self.view.tintColor;
            [sw addTarget:self action:@selector(presetChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
        sw.tag = indexPath.row;
        sw.on = [self presetOn:p];
        return cell;
    }
    if (indexPath.section == 2) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"subtype"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"subtype"];
        cell.textLabel.text = @"Subtype";
        cell.detailTextLabel.text = [self currentSubtypeName];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ce"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ce"];
    NSString *key = self.keys[indexPath.row];
    cell.textLabel.text = key;
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.detailTextLabel.text = BQValueSummary(self.cacheExtra[key]);
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        if (indexPath.row == 0) [self applyTweaks];
        else if (indexPath.row == 1) [self revertTweaks];
        else [self respring];
    } else if (indexPath.section == 2) {
        [self chooseSubtype];
    } else if (indexPath.section == 3) {
        [self editKeyAtIndexPath:indexPath];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 3) return nil;
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                     title:@"Delete"
                                                                   handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        NSString *key = self.keys[indexPath.row];
        [self.cacheExtra removeObjectForKey:key];
        self.keys = [self.cacheExtra.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        BQLog(@"removed CacheExtra key %@ (in memory)", key);
        done(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

@end

#import "GestaltVC.h"
#import "BQCore.h"
#import "BQUI.h"
#import "CacheExtraEditVC.h"
#import <CoreFoundation/CoreFoundation.h>

static NSString * const kArtKey = @"oPeik/9e8lQWMszEjbPzng";
static NSString * const kIslandKey = @"YlEtTtHlNesRBMal1CqRaA";
static NSString * const kAIKey = @"A62OafQ85EJAiiqKn4agtg";
static NSString * const kProductTypeKey = @"h9jDsbgj7xIVeIQ8S3/X3Q";
static NSString * const kHardwareKey = @"oYicEKzVTz4/CxxE05pEgQ";
static NSString * const kCPUKey = @"5pYKlGnYYBzGvAlIU8RjEQ";
static NSString * const kSiriRegionKey = @"h63QSdBCiT/z0WU6rdQv6Q";
static NSString * const kSiriRegionCodeKey = @"yK+xavymRGZ3xWc1tb8XDg";
static NSString * const kRegulatoryKey = @"97JDvERpVwO+GHtthIh7hA";
static NSString * const kResearchKey = @"XYlJKKkj2hztRP1NWWnhlw";
static NSString * const kStoreDemoKey = @"aadL+4GFBDe6DdsUD2HGGw";
static NSString * const kVersionKey = @"qNNddlUK+B/YlooNoymwgA";
static NSString * const kBuildKey = @"mZfUC7qo4pURNhyMHZ62RQ";
static NSString * const kHumanVersionKey = @"ToLFRidm+eJGWnpw6W4Wwg";
static NSString * const kVersionExtraKey = @"P5Go9WVVA604m7rKhbVndw";

static NSArray<NSString *> *BQIPadOSKeys(void) {
    return @[
        @"mG0AnH/Vy1veoqoLRAIgTA",
        @"UCG5MkVahJxG1YULbbd5Bg",
        @"ZYqko/XM5zD3XBfN5RmaXA",
        @"nVh/gwNpy7Jv1NOk00CMrw",
        @"uKc7FPnEO++lVhHWHFlGbQ",
    ];
}

static NSArray<NSDictionary *> *BQAIModelOptions(void) {
    return @[
        @{@"title": @"Original", @"product": @"", @"hw": @"", @"cpu": @"", @"reg": @""},
        @{@"title": @"iPhone 15 Pro", @"product": @"iPhone16,1", @"hw": @"D83AP", @"cpu": @"t8130", @"reg": @"A2848"},
        @{@"title": @"iPhone 15 Pro Max", @"product": @"iPhone16,2", @"hw": @"D84AP", @"cpu": @"t8130", @"reg": @"A2849"},
        @{@"title": @"iPhone 16 Pro", @"product": @"iPhone17,1", @"hw": @"D93AP", @"cpu": @"t8140", @"reg": @"A3083"},
        @{@"title": @"iPhone 16 Pro Max", @"product": @"iPhone17,2", @"hw": @"D94AP", @"cpu": @"t8140", @"reg": @"A3084"},
    ];
}

static NSString *BQTrim(NSString *s) {
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// Port of the Nugget iPadOS CacheData patch. It flips one nibble in the
// binary CacheData blob after locating the marker at hex offset 1616..1816.
static NSData *BQPatchIPadOSCacheData(NSData *data, NSString **err) {
    if (!data.length) {
        if (err) *err = @"MobileGestalt has no CacheData blob";
        return nil;
    }
    NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 2];
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) [hex appendFormat:@"%02x", bytes[i]];
    if (hex.length <= 1616) {
        if (err) *err = @"CacheData is too short for the iPadOS marker";
        return nil;
    }

    NSRange sliceRange = NSMakeRange(1616, MIN((NSUInteger)200, hex.length - 1616));
    NSString *slice = [hex substringWithRange:sliceRange];
    NSError *reErr = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"0+(?:5555)*([0-9a-f]{4})"
                                                                       options:0 error:&reErr];
    if (!re) {
        if (err) *err = [NSString stringWithFormat:@"CacheData regex: %@", reErr.localizedDescription];
        return nil;
    }

    __block NSInteger marker = -1;
    [re enumerateMatchesInString:slice options:0 range:NSMakeRange(0, slice.length)
                      usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags flags, BOOL *stop) {
        NSRange r = [m rangeAtIndex:1];
        if (r.location == NSNotFound) return;
        NSString *value = [slice substringWithRange:r];
        NSUInteger nonzero = 0;
        for (NSUInteger i = 0; i < value.length; i++) {
            if ([value characterAtIndex:i] != '0') nonzero++;
        }
        if (nonzero >= 3) {
            marker = (NSInteger)sliceRange.location + (NSInteger)r.location;
            *stop = YES;
        }
    }];
    if (marker < 0) {
        if (err) *err = @"iPadOS marker was not found in CacheData";
        return nil;
    }

    NSInteger right = marker + 13;
    NSInteger left = marker - 67;
    if (left <= 0 || right >= (NSInteger)hex.length - 1) {
        if (err) *err = @"iPadOS marker offset is out of range";
        return nil;
    }
    for (NSNumber *n in @[@(left), @(right)]) {
        NSInteger p = n.integerValue;
        unichar c = [hex characterAtIndex:p];
        if ((c != '1' && c != '3') ||
            [hex characterAtIndex:p - 1] != '0' ||
            [hex characterAtIndex:p + 1] != '0') {
            if (err) *err = @"iPadOS marker validation failed; no changes made";
            return nil;
        }
    }
    [hex replaceCharactersInRange:NSMakeRange(left, 1) withString:@"3"];

    NSMutableData *out = [NSMutableData dataWithCapacity:hex.length / 2];
    for (NSUInteger i = 0; i + 1 < hex.length; i += 2) {
        unsigned int byte = 0;
        sscanf([[hex substringWithRange:NSMakeRange(i, 2)] UTF8String], "%02x", &byte);
        uint8_t b = (uint8_t)byte;
        [out appendBytes:&b length:1];
    }
    return out;
}

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
@property (nonatomic, strong) NSData *originalCacheData;
@property (nonatomic, copy) NSString *originalProductType;
@property (nonatomic, copy) NSString *originalHardware;
@property (nonatomic, copy) NSString *originalCPU;
@property (nonatomic, copy) NSString *originalRegulatory;
@property (nonatomic, copy) NSString *originalSiriRegion;
@property (nonatomic, copy) NSString *originalSiriRegionCode;
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
            self.keys = [ce.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare)];
            NSDictionary *bak = [NSDictionary dictionaryWithContentsOfFile:BQBackupPath()];
            NSDictionary *bakCE = [bak[@"CacheExtra"] isKindOfClass:[NSDictionary class]] ? bak[@"CacheExtra"] : @{};
            NSDictionary *art = bakCE[kArtKey];
            self.originalSubtype = [art[@"ArtworkDeviceSubType"] integerValue];
            self.originalCacheData = bak[@"CacheData"] ?: mg[@"CacheData"];
            self.originalProductType = bakCE[kProductTypeKey] ?: ce[kProductTypeKey];
            self.originalHardware = bakCE[kHardwareKey] ?: ce[kHardwareKey];
            self.originalCPU = bakCE[kCPUKey] ?: ce[kCPUKey];
            self.originalRegulatory = bakCE[kRegulatoryKey] ?: ce[kRegulatoryKey];
            self.originalSiriRegion = bakCE[kSiriRegionKey] ?: ce[kSiriRegionKey];
            self.originalSiriRegionCode = bakCE[kSiriRegionCodeKey] ?: ce[kSiriRegionCodeKey];
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

#pragma mark - Dynamic Island

- (BOOL)islandOn {
    return [self.cacheExtra[kIslandKey] boolValue];
}

- (NSMutableDictionary *)artwork {
    id art = self.cacheExtra[kArtKey];
    return [art isKindOfClass:[NSDictionary class]] ? [art mutableCopy] : [NSMutableDictionary dictionary];
}

- (NSString *)subtypeNameForValue:(NSInteger)v {
    switch (v) {
        case 2436: return @"iPhone X gestures (2436)";
        case 2556: return @"iPhone 14 Pro / 15 Pro (2556)";
        case 2796: return @"iPhone 14 Pro Max (2796)";
        case 2976: return @"iPhone 15 Pro Max / 17 (2976)";
        case 2622: return @"iPhone 16 Pro / 17 Pro (2622)";
        case 2868: return @"iPhone 16 Pro Max / 17 Pro Max (2868)";
        case 2736: return @"iPhone Air (2736)";
        default: return [NSString stringWithFormat:@"Original (%ld)", (long)v];
    }
}

- (NSString *)currentSubtypeName {
    NSDictionary *art = self.cacheExtra[kArtKey];
    NSInteger v = [art[@"ArtworkDeviceSubType"] integerValue];
    if (v == 0) v = self.originalSubtype;
    return [self subtypeNameForValue:v];
}

- (void)dynamicIslandChanged:(UISwitch *)sw {
    if (sw.isOn) {
        self.cacheExtra[kIslandKey] = @YES;
        NSMutableDictionary *art = [self artwork];
        if (![art[@"ArtworkDeviceSubType"] isKindOfClass:[NSNumber class]]) {
            art[@"ArtworkDeviceSubType"] = @2556;
            self.cacheExtra[kArtKey] = art;
        }
    } else {
        [self.cacheExtra removeObjectForKey:kIslandKey];
    }
    BQLog(@"dynamic island -> %d", sw.isOn);
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2]
                 withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)resetDynamicIsland {
    [self.cacheExtra removeObjectForKey:kIslandKey];
    NSMutableDictionary *art = [self artwork];
    if (self.originalSubtype > 0) art[@"ArtworkDeviceSubType"] = @(self.originalSubtype);
    else [art removeObjectForKey:@"ArtworkDeviceSubType"];
    if (art.count) self.cacheExtra[kArtKey] = art;
    else [self.cacheExtra removeObjectForKey:kArtKey];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2]
                 withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)setSubtype:(NSInteger)v {
    NSMutableDictionary *art = [self artwork];
    if (v <= 0) {
        [art removeObjectForKey:@"ArtworkDeviceSubType"];
        [self.cacheExtra removeObjectForKey:kIslandKey];
    } else {
        art[@"ArtworkDeviceSubType"] = @(v);
        self.cacheExtra[kIslandKey] = @YES;
    }
    if (art.count) self.cacheExtra[kArtKey] = art;
    else [self.cacheExtra removeObjectForKey:kArtKey];
    BQLog(@"subtype -> %ld", (long)v);
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2]
                 withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)chooseSubtype {
    NSArray *opts = @[
        @{@"title": @"Original", @"value": @0},
        @{@"title": @"iPhone 14 Pro (2556)", @"value": @2556},
        @{@"title": @"iPhone 14 Pro Max (2796)", @"value": @2796},
        @{@"title": @"iPhone 15 Pro (2556)", @"value": @2556},
        @{@"title": @"iPhone 15 Pro Max / 17 (2976)", @"value": @2976},
        @{@"title": @"iPhone 16 Pro / 17 Pro (2622)", @"value": @2622},
        @{@"title": @"iPhone 16 Pro Max / 17 Pro Max (2868)", @"value": @2868},
        @{@"title": @"iPhone Air (2736)", @"value": @2736},
        @{@"title": @"iPhone 17 / 18 (custom subtype...)", @"value": @(-1)},
    ];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Dynamic Island model"
                                                               message:@"Sets ArtworkDeviceSubType and enables Dynamic Island. 17/18 values are experimental; use a custom subtype if the island position is wrong."
                                                        preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *o in opts) {
        [a addAction:[UIAlertAction actionWithTitle:o[@"title"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            NSInteger v = [o[@"value"] integerValue];
            if (v == -1) {
                [self askCustomSubtype];
            } else {
                [self setSubtype:v];
            }
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:2]];
    a.popoverPresentationController.sourceView = cell ?: self.view;
    a.popoverPresentationController.sourceRect = cell ? cell.bounds : CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (void)askCustomSubtype {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Custom subtype"
                                                               message:@"Enter the ArtworkDeviceSubType integer. Wrong values can break layout. Try 2976 for 17/18."
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.placeholder = @"e.g. 2976";
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Apply" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSInteger v = [BQTrim(a.textFields.firstObject.text) integerValue];
        if (v > 0) [self setSubtype:v];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Advanced

- (NSString *)versionSummary {
    NSString *v = self.cacheExtra[kVersionKey];
    NSString *b = self.cacheExtra[kBuildKey];
    if (!v.length && !b.length) return @"off";
    return [NSString stringWithFormat:@"%@ (%@)", v.length ? v : @"?", b.length ? b : @"?"];
}

- (void)spoofVersion {
    NSString *v = self.cacheExtra[kVersionKey] ?: [UIDevice currentDevice].systemVersion ?: @"";
    NSString *b = self.cacheExtra[kBuildKey] ?: self.mg[@"CacheVersion"] ?: @"";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Spoof iOS version"
                                                               message:@"Writes ProductVersion/BuildVersion into MobileGestalt. Apps and system components that query MG will see these values. OTA/update behavior may break. Keep the original backup."
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Marketing version (e.g. 27.2)";
        tf.text = v;
    }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Build (e.g. 24B115)";
        tf.text = b;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [self.cacheExtra removeObjectForKey:kVersionKey];
        [self.cacheExtra removeObjectForKey:kBuildKey];
        [self.cacheExtra removeObjectForKey:kHumanVersionKey];
        [self.cacheExtra removeObjectForKey:kVersionExtraKey];
        BQLog(@"version spoof removed");
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:3]
                     withRowAnimation:UITableViewRowAnimationAutomatic];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Apply" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *nv = BQTrim(a.textFields[0].text);
        NSString *nb = BQTrim(a.textFields[1].text);
        if (nv.length) self.cacheExtra[kVersionKey] = nv;
        else [self.cacheExtra removeObjectForKey:kVersionKey];
        if (nb.length) self.cacheExtra[kBuildKey] = nb;
        else [self.cacheExtra removeObjectForKey:kBuildKey];
        if (nv.length) self.cacheExtra[kHumanVersionKey] = nv;
        else [self.cacheExtra removeObjectForKey:kHumanVersionKey];
        [self.cacheExtra removeObjectForKey:kVersionExtraKey];
        BQLog(@"version spoof -> %@ (%@)", nv, nb);
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:3]
                     withRowAnimation:UITableViewRowAnimationAutomatic];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (NSString *)aiModelName {
    NSString *p = self.cacheExtra[kProductTypeKey];
    for (NSDictionary *o in BQAIModelOptions()) {
        NSString *op = o[@"product"];
        if (op.length && [p isEqualToString:op]) return o[@"title"];
    }
    return @"Original";
}

- (void)chooseAIModel {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"AI device spoof"
                                                               message:@"Spoofs ProductType, HardwareModel and CPUModel so Apple Intelligence/Siri checks see a supported device. This can temporarily break Face ID and system stability. A backup is kept in OriginalGestalt.plist."
                                                        preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *o in BQAIModelOptions()) {
        [a addAction:[UIAlertAction actionWithTitle:o[@"title"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            if (![o[@"product"] length]) {
                if (self.originalProductType.length) self.cacheExtra[kProductTypeKey] = self.originalProductType;
                else [self.cacheExtra removeObjectForKey:kProductTypeKey];
                if (self.originalHardware.length) self.cacheExtra[kHardwareKey] = self.originalHardware;
                else [self.cacheExtra removeObjectForKey:kHardwareKey];
                if (self.originalCPU.length) self.cacheExtra[kCPUKey] = self.originalCPU;
                else [self.cacheExtra removeObjectForKey:kCPUKey];
                if (self.originalRegulatory.length) self.cacheExtra[kRegulatoryKey] = self.originalRegulatory;
                else [self.cacheExtra removeObjectForKey:kRegulatoryKey];
                BQLog(@"AI spoof -> original");
            } else {
                self.cacheExtra[kProductTypeKey] = o[@"product"];
                self.cacheExtra[kHardwareKey] = o[@"hw"];
                self.cacheExtra[kCPUKey] = o[@"cpu"];
                if ([o[@"reg"] length]) self.cacheExtra[kRegulatoryKey] = o[@"reg"];
                self.cacheExtra[kAIKey] = @1;
                BQLog(@"AI spoof -> %@ (%@/%@)", o[@"title"], o[@"product"], o[@"hw"]);
            }
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:3]
                         withRowAnimation:UITableViewRowAnimationAutomatic];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:3]];
    a.popoverPresentationController.sourceView = cell ?: self.view;
    a.popoverPresentationController.sourceRect = cell ? cell.bounds : CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (BOOL)aiOn { return [self.cacheExtra[kAIKey] boolValue]; }
- (BOOL)siriOn {
    return [self.cacheExtra[kSiriRegionKey] isEqualToString:@"LL"] &&
           [self.cacheExtra[kSiriRegionCodeKey] isEqualToString:@"LL/A"];
}
- (BOOL)ipadOSOn {
    for (NSString *key in BQIPadOSKeys()) {
        if (![self.cacheExtra[key] boolValue]) return NO;
    }
    return YES;
}
- (BOOL)researchOn { return [self.cacheExtra[kResearchKey] boolValue]; }
- (BOOL)storeDemoOn { return [self.cacheExtra[kStoreDemoKey] boolValue]; }

- (void)riskySwitch:(UISwitch *)sw title:(NSString *)title message:(NSString *)message action:(void (^)(void))action {
    if (!sw.isOn) {
        action();
        return;
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                               message:message
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) {
        sw.on = NO;
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        action();
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (BOOL)setIPadOS:(BOOL)on error:(NSString **)err {
    if (on) {
        NSData *base = self.originalCacheData ?: self.mg[@"CacheData"];
        NSData *patched = BQPatchIPadOSCacheData(base, err);
        if (!patched) return NO;
        self.mg[@"CacheData"] = patched;
        for (NSString *key in BQIPadOSKeys()) self.cacheExtra[key] = @1;
    } else {
        if (self.originalCacheData) self.mg[@"CacheData"] = self.originalCacheData;
        for (NSString *key in BQIPadOSKeys()) [self.cacheExtra removeObjectForKey:key];
    }
    return YES;
}

- (void)advancedSwitchChanged:(UISwitch *)sw {
    NSInteger row = sw.tag;
    if (row == 1) {
        [self riskySwitch:sw title:@"Enable Apple Intelligence?"
                  message:@"Writes DeviceSupportsGenerativeModelSystems. On iOS 27.2 eligibility checks may still block AI, and this can affect system stability. Keep the backup."
                   action:^{
            if (sw.isOn) self.cacheExtra[kAIKey] = @1;
            else [self.cacheExtra removeObjectForKey:kAIKey];
            BQLog(@"Apple Intelligence -> %d", sw.isOn);
        }];
    } else if (row == 2) {
        [self riskySwitch:sw title:@"Enable Siri AI US region?"
                  message:@"Sets the US region and generative-model capability. Force-enabling on unsupported devices can break Face ID or system stability."
                   action:^{
            if (sw.isOn) {
                self.cacheExtra[kAIKey] = @1;
                self.cacheExtra[kSiriRegionKey] = @"LL";
                self.cacheExtra[kSiriRegionCodeKey] = @"LL/A";
            } else {
                if (self.originalSiriRegion.length) self.cacheExtra[kSiriRegionKey] = self.originalSiriRegion;
                else [self.cacheExtra removeObjectForKey:kSiriRegionKey];
                if (self.originalSiriRegionCode.length) self.cacheExtra[kSiriRegionCodeKey] = self.originalSiriRegionCode;
                else [self.cacheExtra removeObjectForKey:kSiriRegionCodeKey];
            }
            BQLog(@"Siri AI region -> %d", sw.isOn);
        }];
    } else if (row == 4) {
        [self riskySwitch:sw title:@"Enable iPadOS mode?"
                  message:@"Patches the binary CacheData blob and five Medusa/Stage Manager keys. This is experimental and high risk: layout, multitasking and boot behavior can break. A full restore may be required."
                   action:^{
            NSString *err = nil;
            if (![self setIPadOS:sw.isOn error:&err]) {
                sw.on = NO;
                BQAlert(self, @"iPadOS mode failed", err ?: @"CacheData patch failed");
            }
            BQLog(@"iPadOS mode -> %d", sw.isOn);
        }];
    } else if (row == 5) {
        [self riskySwitch:sw title:@"Enable Security Research Device?"
                  message:@"Sets ResearchFuse. iOS will treat this iPhone as a research-fused test device. This is cosmetic on most builds but can affect services and is high risk."
                   action:^{
            if (sw.isOn) self.cacheExtra[kResearchKey] = @1;
            else [self.cacheExtra removeObjectForKey:kResearchKey];
            BQLog(@"ResearchFuse -> %d", sw.isOn);
        }];
    } else if (row == 6) {
        [self riskySwitch:sw title:@"Enable Store Demo Mode?"
                  message:@"Sets StoreDemoMode. iOS may show demo-device messaging and change setup behavior. High risk; keep the backup."
                   action:^{
            if (sw.isOn) self.cacheExtra[kStoreDemoKey] = @1;
            else [self.cacheExtra removeObjectForKey:kStoreDemoKey];
            BQLog(@"StoreDemoMode -> %d", sw.isOn);
        }];
    }
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:3]
                 withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - Actions

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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 5; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 3;
        case 1: return self.presets.count;
        case 2: return 3;
        case 3: return 7;
        case 4: return self.keys.count;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"Actions";
        case 1: return @"Tweaks";
        case 2: return @"Dynamic Island";
        case 3: return @"Advanced";
        case 4: return @"CacheExtra";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case 1:
            return @"These tweaks can break features or softbrick the device if misused. Backup exists in Documents/OriginalGestalt.plist.";
        case 2:
            return @"ArtworkDeviceSubType controls Dynamic Island position. 17/18 values are experimental; use a custom subtype if the island overlaps the status bar.";
        case 3:
            return @"Advanced tweaks are high risk. iPadOS mode patches CacheData. AI/Siri spoofing can break Face ID. Store Demo and ResearchFuse change device identity. Keep the original backup.";
        case 4:
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
        if (indexPath.row == 0) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"island"];
            if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"island"];
            cell.textLabel.text = @"Enable Dynamic Island";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *sw = (UISwitch *)cell.accessoryView;
            if (![sw isKindOfClass:[UISwitch class]]) {
                sw = [[UISwitch alloc] init];
                sw.onTintColor = self.view.tintColor;
                [sw addTarget:self action:@selector(dynamicIslandChanged:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = sw;
            }
            sw.on = [self islandOn];
            return cell;
        }
        if (indexPath.row == 1) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"subtype"];
            if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"subtype"];
            cell.textLabel.text = @"Model / position";
            cell.detailTextLabel.text = [self currentSubtypeName];
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"resetisland"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"resetisland"];
        cell.textLabel.text = @"Disable + reset to original";
        cell.textLabel.textColor = [UIColor systemRedColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    if (indexPath.section == 3) {
        if (indexPath.row == 0 || indexPath.row == 3) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"advancedvalue"];
            if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"advancedvalue"];
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Spoof iOS version";
                cell.detailTextLabel.text = [self versionSummary];
            } else {
                cell.textLabel.text = @"AI device spoof";
                cell.detailTextLabel.text = [self aiModelName];
            }
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"advancedswitch"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"advancedswitch"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISwitch *sw = (UISwitch *)cell.accessoryView;
        if (![sw isKindOfClass:[UISwitch class]]) {
            sw = [[UISwitch alloc] init];
            sw.onTintColor = self.view.tintColor;
            [sw addTarget:self action:@selector(advancedSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
        sw.tag = indexPath.row;
        if (indexPath.row == 1) { cell.textLabel.text = @"Apple Intelligence"; sw.on = [self aiOn]; }
        else if (indexPath.row == 2) { cell.textLabel.text = @"Siri AI (US region)"; sw.on = [self siriOn]; }
        else if (indexPath.row == 4) { cell.textLabel.text = @"iPadOS mode (experimental)"; sw.on = [self ipadOSOn]; }
        else if (indexPath.row == 5) { cell.textLabel.text = @"Security Research Device"; sw.on = [self researchOn]; }
        else { cell.textLabel.text = @"Store Demo Mode"; sw.on = [self storeDemoOn]; }
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
        if (indexPath.row == 1) [self chooseSubtype];
        else if (indexPath.row == 2) [self resetDynamicIsland];
    } else if (indexPath.section == 3) {
        if (indexPath.row == 0) [self spoofVersion];
        else if (indexPath.row == 3) [self chooseAIModel];
    } else if (indexPath.section == 4) {
        [self editKeyAtIndexPath:indexPath];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 4) return nil;
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

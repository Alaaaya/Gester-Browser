#import "TendiesExploreVC.h"
#import "BQCore.h"
#import "BQUI.h"

static NSString * const kCatalogBase = @"https://raw.githubusercontent.com/SerStars/Nugget-Wallpapers/main/";
static NSString * const kCustomCatalog = @"https://raw.githubusercontent.com/SerStars/Nugget-Wallpapers/main/wallpapers-custom.json";
static NSString * const kAppleCatalog = @"https://raw.githubusercontent.com/SerStars/Nugget-Wallpapers/main/wallpapers-apple.json";

@interface TendiesExploreVC ()
@property (nonatomic, strong) NSArray<NSDictionary *> *items;
@property (nonatomic, strong) NSArray<NSDictionary *> *filtered;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, assign) BOOL loading;
@end

@implementation TendiesExploreVC

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSLocalizedString(@"Explore Wallpapers", nil);
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = NSLocalizedString(@"Search wallpapers", nil);
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    UIRefreshControl *rc = [[UIRefreshControl alloc] init];
    [rc addTarget:self action:@selector(loadCatalog) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = rc;
    [self loadCatalog];
}

- (void)loadCatalog {
    if (self.loading) { [self.refreshControl endRefreshing]; return; }
    self.loading = YES;
    dispatch_group_t group = dispatch_group_create();
    __block NSMutableArray *all = [NSMutableArray array];
    __block NSString *firstError = nil;

    void (^fetch)(NSString *) = ^(NSString *urlString) {
        dispatch_group_enter(group);
        NSURL *u = [NSURL URLWithString:urlString];
        [[NSURLSession.sharedSession dataTaskWithURL:u completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
            if (data.length) {
                id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if ([obj isKindOfClass:[NSArray class]]) {
                    @synchronized (all) { [all addObjectsFromArray:obj]; }
                } else if (!firstError) {
                    firstError = @"catalog is not an array";
                }
            } else if (!firstError) {
                firstError = error.localizedDescription ?: @"network error";
            }
            dispatch_group_leave(group);
        }] resume];
    };
    fetch(kCustomCatalog);
    fetch(kAppleCatalog);

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        self.loading = NO;
        [self.refreshControl endRefreshing];
        NSMutableArray *unique = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        for (id x in all) {
            if (![x isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *d = x;
            NSString *url = d[@"url"];
            NSString *name = d[@"name"];
            if (![url isKindOfClass:[NSString class]] || !url.length) continue;
            if (![name isKindOfClass:[NSString class]] || !name.length) continue;
            if ([seen containsObject:url]) continue;
            [seen addObject:url];
            [unique addObject:d];
        }
        [unique sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
        }];
        self.items = unique;
        self.filtered = unique;
        [self.tableView reloadData];
        if (firstError && unique.count == 0) BQAlert(self, NSLocalizedString(@"Catalog failed", nil), firstError);
        BQLog(@"tendies catalog: %lu entries", (unsigned long)unique.count);
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *q = searchController.searchBar.text ?: @"";
    if (!q.length) { self.filtered = self.items; [self.tableView reloadData]; return; }
    NSMutableArray *a = [NSMutableArray array];
    for (NSDictionary *d in self.items) {
        NSString *name = d[@"name"] ?: @"";
        NSString *desc = d[@"description"] ?: @"";
        NSString *authors = d[@"authors"] ?: @"";
        if ([name localizedCaseInsensitiveContainsString:q] ||
            [desc localizedCaseInsensitiveContainsString:q] ||
            [authors localizedCaseInsensitiveContainsString:q]) {
            [a addObject:d];
        }
    }
    self.filtered = a;
    [self.tableView reloadData];
}

- (void)download:(NSDictionary *)item {
    NSString *rel = item[@"url"];
    NSString *urlString = [kCatalogBase stringByAppendingString:rel];
    NSString *name = item[@"name"] ?: rel.lastPathComponent;
    BQBusyView *busy = [BQBusyView showInView:self.view text:[NSString stringWithFormat:NSLocalizedString(@"Downloading %@...", nil), name]];
    NSURL *u = [NSURL URLWithString:urlString];
    [[NSURLSession.sharedSession dataTaskWithURL:u completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [busy hide];
            if (!data.length) {
                BQAlert(self, NSLocalizedString(@"Download failed", nil), error.localizedDescription ?: @"empty response");
                return;
            }
            NSString *dir = [BQDocuments() stringByAppendingPathComponent:@"tendies"];
            [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *leaf = rel.lastPathComponent.length ? rel.lastPathComponent : @"wallpaper.tendies";
            NSString *dest = [dir stringByAppendingPathComponent:leaf];
            if ([[NSFileManager defaultManager] fileExistsAtPath:dest]) {
                dest = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", NSUUID.UUID.UUIDString, leaf]];
            }
            NSError *e = nil;
            if (![data writeToURL:[NSURL fileURLWithPath:dest] options:NSDataWritingAtomic error:&e]) {
                BQAlert(self, NSLocalizedString(@"Save failed", nil), e.localizedDescription ?: @"write error");
                return;
            }
            BQLog(@"downloaded %@ (%lu bytes) -> %@", name, (unsigned long)data.length, leaf);
            if (self.onDownload) self.onDownload();

            UIAlertController *a = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Downloaded", nil)
                                                                       message:[NSString stringWithFormat:NSLocalizedString(@"%@ saved to Documents/tendies.\nApply now?", nil), name]
                                                                preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleCancel handler:nil]];
            [a addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Apply now", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
                BQBusyView *work = [BQBusyView showInView:self.view text:NSLocalizedString(@"Applying wallpaper...", nil)];
                dispatch_async(BQWorkQueue(), ^{
                    NSString *err = nil;
                    int count = 0;
                    BOOL ok = BQApplyTendies([NSURL fileURLWithPath:dest], &count, &err);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [work hide];
                        if (!ok) { BQAlert(self, NSLocalizedString(@"Apply failed", nil), err ?: NSLocalizedString(@"unknown error", nil)); return; }
                        UIAlertController *b = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Applied", nil)
                                                                                   message:[NSString stringWithFormat:NSLocalizedString(@"%d descriptor(s) written. Open PosterBoard and close it from the App Switcher, or respring.", nil), count]
                                                                            preferredStyle:UIAlertControllerStyleAlert];
                        [b addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Open PosterBoard", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *y) {
                            if (!BQOpenPosterBoard()) BQAlert(self, NSLocalizedString(@"Open failed", nil), NSLocalizedString(@"Could not open PosterBoard.", nil));
                        }]];
                        [b addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Respring", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *y) { BQRespring(); }]];
                        [b addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleCancel handler:nil]];
                        [self presentViewController:b animated:YES completion:nil];
                    });
                });
            }]];
            [self presentViewController:a animated:YES completion:nil];
        });
    }] resume];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.filtered.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"item"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"item"];
    NSDictionary *d = self.filtered[indexPath.row];
    cell.textLabel.text = d[@"name"];
    NSString *authors = d[@"authors"];
    NSString *desc = d[@"description"];
    cell.detailTextLabel.text = authors.length ? authors : (desc.length ? desc : @"");
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.numberOfLines = 2;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return NSLocalizedString(@"Catalog: SerStars/Nugget-Wallpapers. Downloads are saved to Documents/tendies.", nil);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self download:self.filtered[indexPath.row]];
}

@end

#import "ReadOnlyBrowserVC.h"
#import "ROAccess.h"
#import <ImageIO/ImageIO.h>
#import <fcntl.h>
#import <unistd.h>
#import <dirent.h>
#import <sys/stat.h>
#import <errno.h>

// This module deliberately has no dependency on BQCore or escape state.
static NSString *ROText(NSString *en, NSString *ar) {
    return [[[NSLocale preferredLanguages] firstObject] hasPrefix:@"ar"] ? ar : en;
}
static NSString *ROError(void) {
    return ROText(@"This location cannot be read. Select it again in Files.", @"ما قدرنا نقرأ هالمكان. اختاره مرة ثانية من الملفات.");
}
// Bounded display only; never write or re-serialize a property list.
static void RODescribePlist(id value, NSMutableString *out, NSUInteger depth, NSUInteger *budget) {
    if (!*budget || out.length >= 65536 || depth >= 12) { [out appendString:@"…\n"]; return; }
    --*budget;
    if ([value isKindOfClass:NSDictionary.class]) {
        [out appendString:@"{\n"];
        for (id key in value) {
            if (!*budget || out.length >= 65536) { [out appendString:@"…\n"]; break; }
            NSString *label = [key isKindOfClass:NSString.class] ? key : @"?";
            [out appendFormat:@"%@ = ", [label substringToIndex:MIN(label.length, 256)]];
            RODescribePlist(value[key], out, depth + 1, budget);
        }
        [out appendString:@"}\n"];
    } else if ([value isKindOfClass:NSArray.class]) {
        [out appendString:@"[\n"];
        for (id item in value) {
            if (!*budget || out.length >= 65536) { [out appendString:@"…\n"]; break; }
            RODescribePlist(item, out, depth + 1, budget);
        }
        [out appendString:@"]\n"];
    } else if ([value isKindOfClass:NSData.class]) {
        [out appendFormat:@"<data %lu bytes>\n", (unsigned long)[value length]];
    } else {
        NSString *line = [value description];
        [out appendFormat:@"%@\n", [line substringToIndex:MIN(line.length, 4096)]];
    }
}
@interface ROLocation : NSObject
@property(nonatomic,strong) NSURL *url;
@property(nonatomic) BOOL scoped;
@property(nonatomic) int descriptor;
@end
@implementation ROLocation
- (instancetype)init { if ((self = [super init])) _descriptor = -1; return self; }
- (void)dealloc {
    if (_descriptor >= 0) close(_descriptor);
    if (_scoped) [_url stopAccessingSecurityScopedResource];
}
@end

// Walk every component relative to an already authorized descriptor.
// Never follow symbolic links, accept absolute paths or permit parent traversal.
static int ROOpen(ROLocation *location, NSString *relative) {
    return ROOpenRelative(location.descriptor, relative.fileSystemRepresentation);
}
@interface ReadOnlyBrowserVC () <UISearchResultsUpdating, UIDocumentPickerDelegate>
@property(nonatomic,strong) ROLocation *location;
@property(nonatomic,copy) NSString *relative;
@property(nonatomic,copy) NSArray<NSDictionary *> *entries;
@property(nonatomic,copy) NSArray<NSDictionary *> *visible;
@property(nonatomic,strong) UISearchController *search;
@property(nonatomic,strong) UILabel *notice;
@property(nonatomic) NSUInteger generation;
@end

@implementation ReadOnlyBrowserVC
- (instancetype)init { return [self initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    self.tableView.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    self.navigationController.view.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    self.title = ROText(@"Files", @"الملفات");
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"folder.badge.plus"] style:UIBarButtonItemStylePlain
        target:self action:@selector(chooseLocation)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel = ROText(@"Choose a location in Files", @"اختار مكان من الملفات");
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = ROText(@"Search this folder", @"بحث بهالمجلد");
    self.navigationItem.searchController = self.search;
    self.definesPresentationContext = YES;
    self.notice = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 300, 130)];
    self.notice.numberOfLines = 0;
    self.notice.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.notice.textColor = UIColor.secondaryLabelColor;
    self.notice.textAlignment = NSTextAlignmentLeft;
    self.tableView.tableHeaderView = self.notice;
    if (!self.location) {
        self.relative = @"";
        self.location = [self locationForURL:[NSURL fileURLWithPath:NSHomeDirectory()] scoped:NO];
    }
    [self reloadFolder];
}
- (ROLocation *)locationForURL:(NSURL *)url scoped:(BOOL)requestScope {
    ROLocation *location = [ROLocation new];
    location.url = url;
    location.scoped = requestScope && [url startAccessingSecurityScopedResource];
    // An unsuccessful scope grant is not treated as permission. open still must succeed.
    location.descriptor = open(url.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    return location.descriptor < 0 ? nil : location;
}
- (void)chooseLocation {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[@"public.folder", @"public.item"] inMode:UIDocumentPickerModeOpen];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url.isFileURL) return;
    // Coordinate materialization through the document provider, without write intent.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL scope = [url startAccessingSecurityScopedResource];
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        __block ROLocation *location;
        NSError *error;
        [coordinator coordinateReadingItemAtURL:url options:0 error:&error byAccessor:^(NSURL *authorizedURL) {
            location = [self locationForURL:authorizedURL scoped:NO];
        }];
        if (location) { location.url = url; location.scoped = scope; }
        else if (scope) [url stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!location) { [self message:ROError()]; return; }
            struct stat st;
            if (fstat(location.descriptor, &st) != 0) { [self message:ROError()]; return; }
            if (S_ISDIR(st.st_mode)) {
                ReadOnlyBrowserVC *next = [ReadOnlyBrowserVC new];
                next.location = location; next.relative = @"";
                [self.navigationController pushViewController:next animated:YES];
            } else if (S_ISREG(st.st_mode)) {
                [self preview:location relative:@"" name:url.lastPathComponent];
            } else [self message:ROText(@"Only folders and regular files are supported.", @"بس المجلدات والملفات العادية مدعومة.")];
        });
    });
}
- (void)reloadFolder {
    NSUInteger token = ++self.generation;
    self.notice.text = ROText(@"READ ONLY\nApp sandbox or a location you choose in Files. Other apps are not automatically accessible.\n", @"للقراءة فقط\nملفات التطبيق أو مكان بتختاره من الملفات. ملفات التطبيقات الثانية مو متاحة تلقائياً.\n");
    self.notice.text = [self.notice.text stringByAppendingString:
        [NSString stringWithFormat:@"%@ / %@", self.location.url.lastPathComponent ?: @"", self.relative ?: @""]];
    ROLocation *location = self.location;
    NSString *relative = self.relative ?: @"";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray *rows = [NSMutableArray array];
        int fd = ROOpen(location, relative);
        DIR *directory = fd >= 0 ? fdopendir(fd) : NULL;
        BOOL failed = directory == NULL, limited = NO;
        if (!directory && fd >= 0) close(fd);
        if (directory) {
            struct dirent *entry;
            errno = 0;
            while ((entry = readdir(directory))) {
                if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
                if (rows.count >= 2000) { limited = YES; break; }
                NSString *name = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:entry->d_name length:strlen(entry->d_name)];
                struct stat st;
                if (!name || fstatat(dirfd(directory), entry->d_name, &st, AT_SYMLINK_NOFOLLOW)) continue;
                [rows addObject:@{@"name":name, @"directory":@(S_ISDIR(st.st_mode)),
                    @"regular":@(S_ISREG(st.st_mode)), @"size":@(st.st_size), @"modified":@(st.st_mtime)}];
                errno = 0;
            }
            if (!entry && errno) failed = YES;
            closedir(directory);
        }
        [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            if ([a[@"directory"] boolValue] != [b[@"directory"] boolValue])
                return [a[@"directory"] boolValue] ? NSOrderedAscending : NSOrderedDescending;
            return [a[@"name"] localizedStandardCompare:b[@"name"]];
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (token != self.generation) return;
            self.entries = rows; [self updateSearchResultsForSearchController:self.search];
            if (failed) self.notice.text = [self.notice.text stringByAppendingFormat:@"\n%@", ROError()];
            else if (limited) self.notice.text = [self.notice.text stringByAppendingString:ROText(@"\nFirst 2,000 entries only.", @"\nأول ٢٠٠٠ ملف فقط.")];
            else if (!rows.count) self.notice.text = [self.notice.text stringByAppendingString:ROText(@"\nThis folder is empty.", @"\nالمجلد فاضي.")];
        });
    });
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = searchController.searchBar.text ?: @"";
    self.visible = query.length ? [self.entries filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *row, NSDictionary *bindings) {
        return [row[@"name"] rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound;
    }]] : self.entries;
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.visible.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"file"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"file"];
    NSDictionary *row = self.visible[indexPath.row];
    BOOL directory = [row[@"directory"] boolValue], regular = [row[@"regular"] boolValue];
    cell.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    cell.textLabel.text = row[@"name"];
    cell.textLabel.textAlignment = NSTextAlignmentLeft;
    NSString *size = directory ? ROText(@"Folder", @"مجلد") :
        [NSByteCountFormatter stringFromByteCount:[row[@"size"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
    NSString *date = [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:[row[@"modified"] doubleValue]]
        dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@%@", size, date,
        (!directory && !regular) ? ROText(@" · Link/special file not opened", @" · رابط أو ملف خاص، ما بينفتح") : @""];
    cell.detailTextLabel.textAlignment = NSTextAlignmentLeft;
    cell.imageView.image = [UIImage systemImageNamed:directory ? @"folder" : (regular ? @"doc" : @"link")];
    cell.imageView.tintColor = UIColor.systemTealColor;
    cell.accessoryType = directory ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *row = self.visible[indexPath.row];
    NSString *relative = [self.relative stringByAppendingPathComponent:row[@"name"]];
    if ([row[@"directory"] boolValue]) {
        ReadOnlyBrowserVC *next = [ReadOnlyBrowserVC new];
        next.location = self.location; next.relative = relative;
        [self.navigationController pushViewController:next animated:YES];
    } else if ([row[@"regular"] boolValue]) [self preview:self.location relative:relative name:row[@"name"]];
    else [self message:ROText(@"Symbolic links and special files are never opened.", @"الروابط والملفات الخاصة ما بتنفتح.")];
}
- (void)message:(NSString *)text {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:ROText(@"Read only", @"للقراءة فقط") message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:ROText(@"OK", @"تمام") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)preview:(ROLocation *)location relative:(NSString *)relative name:(NSString *)name {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int fd = ROOpen(location, relative);
        struct stat st;
        NSString *ext = name.pathExtension.lowercaseString;
        BOOL image = [@[@"png", @"jpg", @"jpeg", @"heic", @"gif", @"webp"] containsObject:ext];
        NSUInteger cap = image ? 8 * 1024 * 1024 : 512 * 1024;
        NSMutableData *data = [NSMutableData data];
        NSString *failure;
        if (fd < 0 || fstat(fd, &st) || !S_ISREG(st.st_mode)) failure = ROError();
        else if (st.st_size > cap) failure = ROText(@"Preview limit is 512 KB for text/plist and 8 MB for images.", @"حد المعاينة ٥١٢ كيلوبايت للنص وplist، و٨ ميغابايت للصور.");
        else {
            unsigned char buffer[16384];
            ssize_t count;
            while ((count = read(fd, buffer, MIN(sizeof(buffer), cap + 1 - data.length))) > 0) {
                [data appendBytes:buffer length:(NSUInteger)count];
                if (data.length > cap) break;
            }
            if (count < 0 || data.length > cap) failure = ROText(@"File changed or could not be read within the preview limit.", @"الملف تغير أو ما قدرنا نقرأه ضمن حد المعاينة.");
        }
        if (fd >= 0) close(fd);
        UIImage *thumbnail;
        NSString *text;
        if (!failure && image) {
            CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
            if (source) {
                NSDictionary *options = @{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
                    (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@1600,
                    (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES};
                CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
                if (cg) { thumbnail = [UIImage imageWithCGImage:cg]; CGImageRelease(cg); }
                CFRelease(source);
            }
            if (!thumbnail) failure = ROText(@"Unsupported or invalid image.", @"الصورة مو مدعومة أو مو سليمة.");
        } else if (!failure) {
            if ([ext isEqual:@"plist"]) {
                id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
                if (plist) {
                    NSMutableString *summary = [NSMutableString string];
                    NSUInteger budget = 1000;
                    RODescribePlist(plist, summary, 0, &budget);
                    text = summary;
                }
            } else text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (!text || [text rangeOfString:[NSString stringWithFormat:@"%C", (unichar)0]].location != NSNotFound)
                failure = ROText(@"No safe text/plist preview. Binary files are not executed.", @"ما في معاينة نص أو plist مناسبة. الملفات ما بتتنفّذ.");
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (failure) { [self message:failure]; return; }
            UIViewController *preview = [UIViewController new];
            preview.title = name;
            preview.view.backgroundColor = UIColor.systemBackgroundColor;
            preview.view.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
            UIView *content;
            if (thumbnail) {
                UIImageView *iv = [[UIImageView alloc] initWithImage:thumbnail];
                iv.contentMode = UIViewContentModeScaleAspectFit;
                iv.accessibilityLabel = name; iv.isAccessibilityElement = YES;
                content = iv;
            } else {
                UITextView *tv = [UITextView new];
                tv.editable = NO; tv.selectable = YES;
                tv.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
                tv.text = text; tv.textAlignment = NSTextAlignmentLeft;
                tv.textContainerInset = UIEdgeInsetsMake(16, 16, 16, 16);
                content = tv;
            }
            content.translatesAutoresizingMaskIntoConstraints = NO;
            [preview.view addSubview:content];
            UILayoutGuide *guide = preview.view.safeAreaLayoutGuide;
            [NSLayoutConstraint activateConstraints:@[
                [content.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
                [content.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
                [content.topAnchor constraintEqualToAnchor:guide.topAnchor],
                [content.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor]]];
            [self.navigationController pushViewController:preview animated:YES];
        });
    });
}
@end

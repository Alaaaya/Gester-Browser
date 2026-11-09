#import "ReadOnlyBrowserVC.h"
#import "ROAccess.h"
#import "GBSafeWrite.h"
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
@property(nonatomic) BOOL selected;
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
    // The empty relative path means the authorized root itself. Foundation throws
    // when asked for an empty NSString fileSystemRepresentation, before ROOpenRelative
    // can handle it. Pass the C empty path directly so the policy duplicates root.
    if (relative.length == 0) return ROOpenRelative(location.descriptor, "");
    return ROOpenRelative(location.descriptor, relative.fileSystemRepresentation);
}
// Editing is bounded and saved as a NEW sibling. Originals are never overwritten.
@interface GBTextEditor : UIViewController
@property(nonatomic,strong) UITextView *textView;
@property(nonatomic,copy) NSString *initialText;
@property(nonatomic,copy) void (^saveText)(NSString *);
@end
@implementation GBTextEditor
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.view.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    self.textView = [UITextView new];
    self.textView.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
    self.textView.text = self.initialText;
    self.textView.textAlignment = NSTextAlignmentLeft;
    self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.textView];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.textView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [self.textView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
        [self.textView.topAnchor constraintEqualToAnchor:g.topAnchor],
        [self.textView.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor]]];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:ROText(@"Save copy", @"حفظ نسخة") style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    self.navigationItem.prompt = ROText(@"Original unchanged · maximum 256 KB", @"الأصل ما بيتغير · الحد ٢٥٦ كيلوبايت");
}
- (void)save { if (self.saveText) self.saveText(self.textView.text); }
@end

@interface ReadOnlyBrowserVC () <UISearchResultsUpdating, UIDocumentPickerDelegate>
@property(nonatomic,strong) ROLocation *location;
@property(nonatomic,copy) NSString *relative;
@property(nonatomic,copy) NSArray<NSDictionary *> *entries;
@property(nonatomic,copy) NSArray<NSDictionary *> *visible;
@property(nonatomic,strong) UISearchController *search;
@property(nonatomic,strong) UILabel *notice;
@property(nonatomic) NSUInteger generation;
@property(nonatomic,strong) NSMutableDictionary *pendingWrite;
@property(nonatomic,strong) NSData *backupBytes;
@property(nonatomic,strong) NSURL *backupTemporaryURL;
@property(nonatomic) NSInteger backupPickerPhase;
@property(nonatomic) BOOL backupVerified;
@property(nonatomic,strong) NSData *editingOriginal;
@property(nonatomic,strong) GBTextEditor *draftEditor;

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
    UIBarButtonItem *create = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"plus"]
        style:UIBarButtonItemStylePlain target:self action:@selector(createFolder)];
    create.accessibilityLabel = ROText(@"Create folder after verified backup", @"مجلد جديد بعد تأكيد النسخة الاحتياطية");
    self.navigationItem.rightBarButtonItems = @[self.navigationItem.rightBarButtonItem, create];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 70;
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
    if (self.backupPickerPhase) { [self handleBackupPicker:urls]; return; }
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
        if (location) { location.url = url; location.scoped = scope; location.selected = YES; }
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
    self.notice.text = ROText(@"App files or a folder you choose in Files. Other apps are not automatically accessible. Hold a regular file for edit-copy or copy. Rename is not yet enabled. Every change requires an exported, re-opened verified backup. No delete or overwrite.\n", @"ملفات التطبيق أو مجلد بتختاره من الملفات. ملفات التطبيقات الثانية مو متاحة تلقائياً. اضغط مطوّل على ملف للتعديل بنسخة أو النسخ. تغيير الاسم مو مفعّل حالياً. كل تغيير بده نسخة احتياطية محفوظة برا التطبيق ومنرجع نفتحها لنتأكد. ما في حذف أو استبدال.\n");
    self.notice.text = [self.notice.text stringByAppendingString:
        [NSString stringWithFormat:@"%@ / %@", self.location.url.lastPathComponent ?: @"", self.relative ?: @""]];
    [self fitNotice];
    ROLocation *location = self.location;
    NSString *relative = self.relative ?: @"";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray *rows = [NSMutableArray array];
        int fd = ROOpen(location, relative);
        // openat(".") gives this listing its own cursor; dup(root) shares offsets.
        int listing = fd >= 0 ? openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) : -1;
        if (fd >= 0) close(fd);
        fd = listing;
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
            [self fitNotice];
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
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
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
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:ROText(@"Files", @"الملفات") message:text preferredStyle:UIAlertControllerStyleAlert];
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

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self fitNotice];
}
- (void)fitNotice {
    CGFloat width = MAX(120, self.tableView.bounds.size.width - 40);
    CGSize size = [self.notice sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    CGFloat height = ceil(size.height) + 32;
    if (fabs(self.notice.frame.size.height - height) > 1 ||
        fabs(self.notice.frame.size.width - width) > 1) {
        self.notice.frame = CGRectMake(20, 0, width, height);
        self.tableView.tableHeaderView = self.notice;
    }
}
- (BOOL)writableFolder {
    if (!self.location) return NO;
    NSURL *folder = self.relative.length ? [self.location.url URLByAppendingPathComponent:self.relative] : self.location.url;
    NSString *path = folder.URLByResolvingSymlinksInPath.path;
    NSString *home = [NSURL fileURLWithPath:NSHomeDirectory()].URLByResolvingSymlinksInPath.path;
    if ([path isEqual:home] || [path hasPrefix:[home stringByAppendingString:@"/"]]) {
        // Own Documents/tmp only. Never write Library, SystemData or the app root.
        for (NSString *part in @[@"Documents", @"tmp"]) {
            NSString *allowed = [home stringByAppendingPathComponent:part];
            if ([path isEqual:allowed] || [path hasPrefix:[allowed stringByAppendingString:@"/"]]) return YES;
        }
        return NO;
    }
    return self.location.selected;
}
- (NSData *)folderSnapshot:(int)fd {
    // Directory metadata and names, never recursive reads or link traversal.
    int scan = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    DIR *dir = scan >= 0 ? fdopendir(scan) : NULL;
    if (!dir) { if (scan >= 0) close(scan); return nil; }
    NSMutableArray *items = [NSMutableArray array];
    struct dirent *entry;
    BOOL valid = YES;
    errno = 0;
    while ((entry = readdir(dir))) {
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        struct stat st;
        NSString *name = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:entry->d_name length:strlen(entry->d_name)];
        if (!name || items.count >= 2000 || fstatat(fd, entry->d_name, &st, AT_SYMLINK_NOFOLLOW)) { valid = NO; break; }
        [items addObject:[NSString stringWithFormat:@"%@|%llu|%llu|%u|%lld|%lld.%ld|%lld.%ld",
            name, (unsigned long long)st.st_dev, (unsigned long long)st.st_ino, st.st_mode,
            (long long)st.st_size, (long long)st.st_mtimespec.tv_sec, st.st_mtimespec.tv_nsec,
            (long long)st.st_ctimespec.tv_sec, st.st_ctimespec.tv_nsec]];
        errno = 0;
    }
    if (!entry && errno) valid = NO;
    closedir(dir);
    if (!valid) return nil;
    [items sortUsingSelector:@selector(compare:)];
    return [NSPropertyListSerialization dataWithPropertyList:items format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
}
- (NSData *)boundedFile:(int)parent name:(NSString *)name {
    if (!GBValidName(name.fileSystemRepresentation)) return nil;
    int fd = openat(parent, name.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    struct stat before, after;
    if (fd < 0) return nil;
    if (fstat(fd, &before) || !S_ISREG(before.st_mode) || before.st_size < 0 || before.st_size > 512*1024) { close(fd); return nil; }
    NSMutableData *data = [NSMutableData data];
    char buffer[16384]; ssize_t n = 0;
    while (data.length <= 512*1024 && (n = read(fd, buffer, sizeof(buffer))) > 0)
        [data appendBytes:buffer length:(NSUInteger)n];
    BOOL valid = n == 0 && data.length <= 512*1024 && !fstat(fd, &after) &&
        before.st_ino == after.st_ino && before.st_dev == after.st_dev &&
        before.st_size == after.st_size && before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec &&
        before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec && data.length == after.st_size;
    close(fd);
    return valid ? data : nil;
}
- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)path point:(CGPoint)point {
    NSDictionary *row = self.visible[path.row];
    if (![row[@"regular"] boolValue]) return nil;
    NSString *name = row[@"name"];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        UIAction *edit = [UIAction actionWithTitle:ROText(@"Edit text/plist into new copy", @"تعديل النص أو plist بنسخة جديدة") image:[UIImage systemImageNamed:@"square.and.pencil"] identifier:nil handler:^(__kindof UIAction *action) { [self editFile:name]; }];
        UIAction *copy = [UIAction actionWithTitle:ROText(@"Copy in this folder", @"نسخ بنفس المجلد") image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(__kindof UIAction *action) { [self askNameFor:@"copy" source:name bytes:nil]; }];
        UIAction *rename = [UIAction actionWithTitle:ROText(@"Rename file", @"تغيير اسم الملف") image:[UIImage systemImageNamed:@"pencil"] identifier:nil handler:^(__kindof UIAction *action) { [self askNameFor:@"rename" source:name bytes:nil]; }];
        rename.attributes = UIMenuElementAttributesDisabled;
        return [UIMenu menuWithTitle:name children:@[edit,copy,rename]];
    }];
}
- (void)createFolder { [self askNameFor:@"mkdir" source:nil bytes:nil]; }
- (void)askNameFor:(NSString *)operation source:(NSString *)source bytes:(NSData *)bytes {
    if (self.pendingWrite) { [self message:ROText(@"Finish or cancel the pending backup first.", @"كمّل أو الغي النسخة الاحتياطية الحالية بالأول.")]; return; }
    if (![self writableFolder]) { [self message:ROText(@"Changes are allowed only in this app’s Documents/tmp or a folder you select in Files. Library and SystemData stay read-only.", @"التغيير بس ضمن Documents وtmp للتطبيق أو مجلد بتختاره من الملفات. Library وSystemData بيضلوا للقراءة.")]; return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:ROText(@"New name", @"الاسم الجديد")
        message:ROText(@"Same folder only. Existing names are never replaced. Next you must export and re-open the backup.", @"بنفس المجلد فقط. ما منستبدل اسم موجود. بعدها لازم تحفظ النسخة الاحتياطية برا التطبيق وترجع تفتحها.")
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = [operation isEqual:@"mkdir"] ? @"" : [operation isEqual:@"rename"] ? source :
            [NSString stringWithFormat:@"%@-copy%@", source.stringByDeletingPathExtension,
                source.pathExtension.length ? [@"." stringByAppendingString:source.pathExtension] : @""];
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.textAlignment = NSTextAlignmentLeft;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:ROText(@"Cancel", @"إلغاء") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { [self cancelPending]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:ROText(@"Prepare backup", @"تجهيز النسخة الاحتياطية") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self prepareOperation:operation source:source destination:alert.textFields.firstObject.text bytes:bytes];
    }]];
    UIAlertAction *cancel = alert.actions.firstObject;
    (void)cancel;
    [self.navigationController.topViewController presentViewController:alert animated:YES completion:nil];
}
- (void)editFile:(NSString *)name {
    if (![self writableFolder]) { [self message:ROText(@"This folder is read-only.", @"هالمجلد للقراءة فقط.")]; return; }
    int fd = ROOpen(self.location, self.relative ?: @"");
    NSData *data = fd >= 0 ? [self boundedFile:fd name:name] : nil;
    if (fd >= 0) close(fd);
    if (!data || data.length > 256*1024) { [self message:ROText(@"Editor limit is 256 KB; only regular UTF-8 text and valid plists.", @"حد التعديل ٢٥٦ كيلوبايت، بس نص UTF-8 وملفات plist سليمة.")]; return; }
    BOOL plist = [name.pathExtension.lowercaseString isEqual:@"plist"];
    NSPropertyListFormat format = NSPropertyListXMLFormat_v1_0;
    NSString *text;
    if (plist) {
        id value = [NSPropertyListSerialization propertyListWithData:data options:0 format:&format error:NULL];
        if (value) {
            NSData *xml = [NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
            if (xml.length <= 256*1024) text = [[NSString alloc] initWithData:xml encoding:NSUTF8StringEncoding];
        }
    } else text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text || [text rangeOfString:[NSString stringWithFormat:@"%C", (unichar)0]].location != NSNotFound) {
        [self message:ROText(@"Not editable UTF-8 text or valid bounded plist.", @"مو نص UTF-8 أو plist سليم ضمن الحد.")]; return;
    }
    GBTextEditor *editor = [GBTextEditor new]; editor.title = name; editor.initialText = text;
    NSPropertyListFormat originalFormat = format;
    __weak GBTextEditor *weakEditor = editor;
    editor.saveText = ^(NSString *edited) {
        GBTextEditor *editor = weakEditor;
        NSData *output = [edited dataUsingEncoding:NSUTF8StringEncoding];
        if (output.length > 256*1024) { [self editorMessage:editor text:ROText(@"256 KB limit exceeded.", @"تجاوزت حد ٢٥٦ كيلوبايت.")]; return; }
        if (plist) {
            id value = [NSPropertyListSerialization propertyListWithData:output options:0 format:NULL error:NULL];
            if (!value || ![NSPropertyListSerialization propertyList:value isValidForFormat:originalFormat]) {
                [self editorMessage:editor text:ROText(@"Invalid plist. Nothing saved.", @"ملف plist مو سليم. ما انحفظ شي.")]; return;
            }
            output = [NSPropertyListSerialization dataWithPropertyList:value format:originalFormat options:0 error:NULL];
        }
        if (!output || output.length > 256*1024) { [self editorMessage:editor text:ROText(@"Serialized copy exceeds 256 KB.", @"النسخة بعد التحويل تجاوزت ٢٥٦ كيلوبايت.")]; return; }
        int current = ROOpen(self.location, self.relative ?: @"");
        NSData *now = current >= 0 ? [self boundedFile:current name:name] : nil;
        if (current >= 0) close(current);
        if (![now isEqual:data]) { [self editorMessage:editor text:ROText(@"Original changed while editing. Re-open it; nothing saved.", @"الأصل تغير وقت التعديل. افتحه من جديد، ما انحفظ شي.")]; return; }
        [self.navigationController popToViewController:self animated:NO];
        self.draftEditor = editor;
        self.editingOriginal = data;
        [self askNameFor:@"edit-copy" source:name bytes:output];
    };
    [self.navigationController pushViewController:editor animated:YES];
}
- (void)editorMessage:(UIViewController *)editor text:(NSString *)text {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:ROText(@"Editor", @"التعديل") message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:ROText(@"OK", @"تمام") style:UIAlertActionStyleCancel handler:nil]];
    [editor presentViewController:alert animated:YES completion:nil];
}
- (void)prepareOperation:(NSString *)operation source:(NSString *)source destination:(NSString *)destination bytes:(NSData *)bytes {
    if ([operation isEqual:@"rename"]) { [self message:ROText(@"Rename is disabled until source-identity races can be excluded.", @"تغيير الاسم موقوف لحين ضمان عدم تبدّل الملف وقت التنفيذ.")]; return; }
    if (self.pendingWrite || ![self writableFolder] || !destination.length ||
        !GBValidName(destination.fileSystemRepresentation)) { [self message:ROText(@"Invalid name or another operation is pending.", @"الاسم مو صالح أو في عملية تانية.")]; return; }
    int fd = ROOpen(self.location, self.relative ?: @"");
    if (fd < 0) { [self message:ROError()]; return; }
    struct stat st;
    BOOL conflict = fstatat(fd, destination.fileSystemRepresentation, &st, AT_SYMLINK_NOFOLLOW) == 0 || errno != ENOENT;
    NSData *snapshot = [self folderSnapshot:fd];
    NSData *original = source ? [self boundedFile:fd name:source] : [NSData data];
    close(fd);
    if (conflict || !snapshot || !original || ([operation isEqual:@"edit-copy"] && ![original isEqual:self.editingOriginal])) {
        [self message:ROText(@"Name already exists, folder changed, or source is not a regular file within 512 KB. Nothing changed.", @"الاسم موجود، المجلد تغير، أو الملف مو عادي وضمن ٥١٢ كيلوبايت. ما تغير شي.")]; return;
    }
    self.pendingWrite = [@{@"operation":operation, @"source":source ?: @"", @"destination":destination,
        @"original":original, @"snapshot":snapshot, @"output":bytes ?: original} mutableCopy];
    NSDictionary *backup = @{@"schema":@1, @"operation":operation, @"source":source ?: @"",
        @"destination":destination, @"original":original, @"folderManifest":snapshot,
        @"sourceFolder":self.relative ?: @"", @"created":[NSDate date],
        @"notice":@"File data is complete for source only. Folder creation backs up the parent manifest, not a recursive folder backup."};
    self.backupBytes = [NSPropertyListSerialization dataWithPropertyList:backup format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    NSString *cache = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    NSURL *staging = [[NSURL fileURLWithPath:cache] URLByAppendingPathComponent:@"GesterBrowserBackup" isDirectory:YES];
    NSError *error = nil;
    // Staging is app-private backup material only, not a mutation of the selected document.
    if (![[NSFileManager defaultManager] createDirectoryAtURL:staging withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionComplete} error:&error]) {
        [self cancelPending]; [self message:ROText(@"Cannot stage a backup. Nothing changed.", @"ما قدرنا نجهز نسخة احتياطية. ما تغير شي.")]; return;
    }
    self.backupTemporaryURL = [staging URLByAppendingPathComponent:[NSString stringWithFormat:@"Gester-backup-%@.plist", NSUUID.UUID.UUIDString]];
    if (!self.backupBytes || ![self.backupBytes writeToURL:self.backupTemporaryURL options:NSDataWritingWithoutOverwriting error:&error]) {
        [self cancelPending]; [self message:ROText(@"Backup creation failed. Nothing changed.", @"فشل تجهيز النسخة الاحتياطية. ما تغير شي.")]; return;
    }
    self.backupVerified = NO;
    self.backupPickerPhase = 1;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[self.backupTemporaryURL] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    if (self.backupPickerPhase) [self cancelPending];
}
- (BOOL)externalBackupURL:(NSURL *)url {
    if (!url.isFileURL) return NO;
    NSString *path = url.URLByResolvingSymlinksInPath.path;
    NSString *home = [NSURL fileURLWithPath:NSHomeDirectory()].URLByResolvingSymlinksInPath.path;
    NSString *root = self.location.url.URLByResolvingSymlinksInPath.path;
    return path.length && ![path isEqual:home] && ![path hasPrefix:[home stringByAppendingString:@"/"]] &&
        ![path isEqual:root] && ![path hasPrefix:[root stringByAppendingString:@"/"]];
}
- (void)handleBackupPicker:(NSArray<NSURL *> *)urls {
    if (!self.pendingWrite || !urls.count) { [self cancelPending]; return; }
    if (self.backupPickerPhase == 1) {
        // Export completion alone is NOT proof. Force a fresh user-selected open.
        self.backupPickerPhase = 2;
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:ROText(@"Re-open the exported backup", @"افتح النسخة المحفوظة")
                message:ROText(@"Choose the backup you just saved OUTSIDE this app and the source folder. Its exact bytes will be checked. Cancel means no changes.", @"اختار النسخة اللي حفظتها برا التطبيق وبرا مجلد المصدر. رح نطابق محتواها بالكامل. الإلغاء يعني ما منغير شي.")
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:ROText(@"Cancel", @"إلغاء") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { [self cancelPending]; }]];
            [alert addAction:[UIAlertAction actionWithTitle:ROText(@"Open backup", @"فتح النسخة") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.data"] inMode:UIDocumentPickerModeOpen];
                picker.delegate = self; [self presentViewController:picker animated:YES completion:nil];
            }]];
            [self presentViewController:alert animated:YES completion:nil];
        });
        return;
    }
    NSURL *url = urls.firstObject;
    if (![self externalBackupURL:url]) { [self cancelPending]; [self message:ROText(@"Backup must be outside this app and the selected source folder. Nothing changed.", @"النسخة لازم تكون برا التطبيق وبرا مجلد المصدر. ما تغير شي.")]; return; }
    BOOL scoped = [url startAccessingSecurityScopedResource];
    __block NSData *actual;
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [coordinator coordinateReadingItemAtURL:url options:0 error:NULL byAccessor:^(NSURL *readURL) {
        if (![self externalBackupURL:readURL]) return;
        int fd = open(readURL.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
        struct stat st;
        if (fd >= 0 && !fstat(fd,&st) && S_ISREG(st.st_mode) && st.st_size >= 0 && st.st_size <= 2*1024*1024) {
            NSMutableData *data = [NSMutableData data]; char buffer[16384]; ssize_t n = 0;
            while (data.length <= 2*1024*1024 && (n=read(fd,buffer,sizeof(buffer))) > 0) [data appendBytes:buffer length:(NSUInteger)n];
            if (!n && data.length <= 2*1024*1024) actual = data;
        }
        if (fd >= 0) close(fd);
    }];
    if (scoped) [url stopAccessingSecurityScopedResource];
    if (![actual isEqual:self.backupBytes]) { [self cancelPending]; [self message:ROText(@"Backup differs or could not be read. Nothing changed.", @"النسخة مختلفة أو ما قدرنا نقرأها. ما تغير شي.")]; return; }
    self.backupVerified = YES; self.backupPickerPhase = 0;
    NSDictionary *plan = self.pendingWrite;
    NSString *summary = [NSString stringWithFormat:@"%@\n%@  →  %@\n%@ (%lu → %lu bytes)\n%@",
        plan[@"operation"], plan[@"source"], plan[@"destination"],
        ROText(@"Original / output", @"الأصل / الناتج"), (unsigned long)[plan[@"original"] length], (unsigned long)[plan[@"output"] length],
        ROText(@"External backup verified byte-for-byte. No overwrite or delete. Apply this one change?", @"تأكدنا من النسخة الخارجية بايت ببايت. بدون استبدال أو حذف. نطبق هالتغيير بس؟")];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:ROText(@"Confirm change", @"تأكيد التغيير") message:summary preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:ROText(@"Cancel", @"إلغاء") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { [self cancelPending]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:ROText(@"Apply", @"تطبيق") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self executePending]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)executePending {
    if (!self.pendingWrite || !self.backupVerified || ![self writableFolder]) { [self cancelPending]; return; }
    NSDictionary *plan = self.pendingWrite;
    NSURL *folder = self.relative.length ? [self.location.url URLByAppendingPathComponent:self.relative] : self.location.url;
    __block BOOL success = NO;
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [coordinator coordinateWritingItemAtURL:folder options:0 error:NULL byAccessor:^(NSURL *authorizedURL) {
        int fd = ROOpen(self.location, self.relative ?: @"");
        if (fd < 0) return;
        // Provider URL and descriptor must still refer to exactly the same directory.
        struct stat opened, named;
        BOOL unchanged = !fstat(fd,&opened) && !lstat(authorizedURL.fileSystemRepresentation,&named) &&
            S_ISDIR(named.st_mode) && opened.st_dev == named.st_dev && opened.st_ino == named.st_ino &&
            [[self folderSnapshot:fd] isEqual:plan[@"snapshot"]];
        NSString *source = plan[@"source"], *destination = plan[@"destination"], *operation = plan[@"operation"];
        if (unchanged && source.length) unchanged = [[self boundedFile:fd name:source] isEqual:plan[@"original"]];
        if (unchanged) {
            if ([operation isEqual:@"mkdir"]) {
                struct stat result;
                success = GBMakeFolder(fd,destination.fileSystemRepresentation) == 0 &&
                    !fstatat(fd,destination.fileSystemRepresentation,&result,AT_SYMLINK_NOFOLLOW) && S_ISDIR(result.st_mode);
            }
            else if ([operation isEqual:@"copy"] || [operation isEqual:@"edit-copy"]) {
                NSData *output = plan[@"output"];
                success = GBCreateFile(fd,destination.fileSystemRepresentation,output.bytes,output.length) == 0;
                if (success) success = [[self boundedFile:fd name:destination] isEqual:output];
            }
        }
        close(fd);
    }];
    if (success) self.draftEditor = nil;
    [self cancelPending];
    [self reloadFolder];
    [self message:success ? ROText(@"Change verified. Keep the exported backup. Original text/plist stays unchanged when saving an edited copy.", @"تأكدنا من التغيير. احتفظ بالنسخة الاحتياطية. حفظ النسخة المعدلة ما بيغير النص أو plist الأصلي.") :
        ROText(@"Operation not verified: conflict, changed folder/source, read-only provider or I/O failure. Inspect the folder; do not retry blindly. The exported backup remains.", @"ما تأكدنا من العملية، ممكن تعارض أو تغير المصدر أو المجلد للقراءة أو خطأ كتابة. افحص المجلد قبل ما تعيد. النسخة الخارجية بتضل موجودة.")];
}
- (void)cancelPending {
    self.backupPickerPhase = 0; self.backupVerified = NO; self.pendingWrite = nil; self.backupBytes = nil;
    if (self.backupTemporaryURL) [[NSFileManager defaultManager] removeItemAtURL:self.backupTemporaryURL error:NULL];
    self.backupTemporaryURL = nil; self.editingOriginal = nil;
    if (self.draftEditor && ![self.navigationController.viewControllers containsObject:self.draftEditor]) {
        GBTextEditor *draft = self.draftEditor;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.presentedViewController) [self.navigationController pushViewController:draft animated:YES];
        });
    }
}

@end

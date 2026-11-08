#import "CacheExtraEditVC.h"
#import "BQUI.h"
#import <CoreFoundation/CoreFoundation.h>

typedef NS_ENUM(NSInteger, CEType) {
    CETypeString = 0,
    CETypeInteger = 1,
    CETypeBoolean = 2,
    CETypeData = 3,
    CETypeCollection = -1,
};

@interface CacheExtraEditVC ()
@property (nonatomic, copy) NSString *key;
@property (nonatomic, strong) id value;
@property (nonatomic, assign) BOOL isNew;
@property (nonatomic, copy) void (^onSave)(NSString *, id);
@property (nonatomic, copy) void (^onDelete)(NSString *);
@property (nonatomic, assign) CEType type;
@property (nonatomic, strong) UITextField *keyField;
@property (nonatomic, strong) UITextField *valueField;
@property (nonatomic, strong) UISegmentedControl *typeControl;
@end

@implementation CacheExtraEditVC

- (instancetype)initWithKey:(NSString *)key
                      value:(id)value
                      isNew:(BOOL)isNew
                     onSave:(void (^)(NSString *, id))onSave
                   onDelete:(void (^)(NSString *))onDelete {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _key = [key copy] ?: @"";
        _value = value;
        _isNew = isNew;
        _onSave = [onSave copy];
        _onDelete = [onDelete copy];
        _type = [self typeForValue:value];
    }
    return self;
}

- (CEType)typeForValue:(id)v {
    if (!v) return CETypeString;
    if ([v isKindOfClass:[NSString class]]) return CETypeString;
    if ([v isKindOfClass:[NSNumber class]]) {
        if (CFGetTypeID((__bridge CFTypeRef)v) == CFBooleanGetTypeID()) return CETypeBoolean;
        return CETypeInteger;
    }
    if ([v isKindOfClass:[NSData class]]) return CETypeData;
    if ([v isKindOfClass:[NSArray class]] || [v isKindOfClass:[NSDictionary class]]) return CETypeCollection;
    return CETypeString;
}

- (NSString *)textForValue:(id)v type:(CEType)t {
    if (!v) return @"";
    switch (t) {
        case CETypeString: return [v isKindOfClass:[NSString class]] ? v : [v description];
        case CETypeInteger: return [v isKindOfClass:[NSNumber class]] ? [v stringValue] : [v description];
        case CETypeBoolean: return ([v isKindOfClass:[NSNumber class]] && [v boolValue]) ? @"true" : @"false";
        case CETypeData: return [v isKindOfClass:[NSData class]] ? [v base64EncodedStringWithOptions:0] : @"";
        case CETypeCollection: {
            if ([v isKindOfClass:[NSArray class]]) return [NSString stringWithFormat:@"Array (%lu items)", (unsigned long)[v count]];
            if ([v isKindOfClass:[NSDictionary class]]) return [NSString stringWithFormat:@"Dictionary (%lu keys)", (unsigned long)[v count]];
            return @"Collection";
        }
    }
    return @"";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.isNew ? @"Add Field" : @"Edit Field";
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                          target:self
                                                                                          action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                                                           target:self
                                                                                           action:@selector(save)];

    self.keyField = [[UITextField alloc] init];
    self.keyField.text = self.key;
    self.keyField.placeholder = @"CacheExtra key";
    self.keyField.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.keyField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.keyField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.keyField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.keyField.userInteractionEnabled = self.isNew;
    self.keyField.textColor = self.isNew ? [UIColor labelColor] : [UIColor secondaryLabelColor];
    [self.keyField addTarget:self action:@selector(keyChanged) forControlEvents:UIControlEventEditingChanged];

    self.valueField = [[UITextField alloc] init];
    self.valueField.text = [self textForValue:self.value type:self.type];
    self.valueField.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.valueField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.valueField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.valueField.clearButtonMode = UITextFieldViewModeWhileEditing;
    [self.valueField addTarget:self action:@selector(valueChanged) forControlEvents:UIControlEventEditingChanged];

    self.typeControl = [[UISegmentedControl alloc] initWithItems:@[@"String", @"Integer", @"Boolean", @"Data"]];
    self.typeControl.selectedSegmentIndex = self.type == CETypeCollection ? UISegmentedControlNoSegment : self.type;
    self.typeControl.enabled = self.type != CETypeCollection;
    [self.typeControl addTarget:self action:@selector(typeChanged) forControlEvents:UIControlEventValueChanged];

    [self updateValueFieldForType];
}

- (void)keyChanged { self.key = self.keyField.text ?: @""; }
- (void)valueChanged { /* read at save time */ }

- (void)typeChanged {
    self.type = (CEType)self.typeControl.selectedSegmentIndex;
    [self updateValueFieldForType];
}

- (void)updateValueFieldForType {
    if (self.type == CETypeCollection) {
        self.valueField.enabled = NO;
        self.valueField.placeholder = @"Collection — use a plist tool";
        return;
    }
    self.valueField.enabled = YES;
    switch (self.type) {
        case CETypeString:
            self.valueField.placeholder = @"String value";
            self.valueField.keyboardType = UIKeyboardTypeDefault;
            break;
        case CETypeInteger:
            self.valueField.placeholder = @"123 / -1";
            self.valueField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
            break;
        case CETypeBoolean:
            self.valueField.placeholder = @"true / false";
            self.valueField.keyboardType = UIKeyboardTypeDefault;
            break;
        case CETypeData:
            self.valueField.placeholder = @"Base64 data";
            self.valueField.keyboardType = UIKeyboardTypeDefault;
            break;
        default:
            break;
    }
}

- (void)cancel {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)save {
    NSString *key = self.isNew ? [self.keyField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                               : self.key;
    if (!key.length) {
        BQAlert(self, @"Invalid key", @"Key must not be empty.");
        return;
    }
    if (self.type == CETypeCollection) {
        BQAlert(self, @"Not editable", @"Collections cannot be edited here. Use the swipe-to-delete action or a plist tool.");
        return;
    }
    NSString *text = self.valueField.text ?: @"";
    id value = nil;
    if (self.type == CETypeString) {
        value = text;
    } else if (self.type == CETypeInteger) {
        NSString *t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        char *end = NULL;
        errno = 0;
        long long v = strtoll(t.UTF8String, &end, 0);
        if (errno != 0 || !end || *end != '\0' || t.length == 0) {
            BQAlert(self, @"Invalid integer", @"Enter a valid integer.");
            return;
        }
        value = @(v);
    } else if (self.type == CETypeBoolean) {
        NSString *t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
        if ([t isEqualToString:@"true"] || [t isEqualToString:@"1"] || [t isEqualToString:@"yes"]) value = @YES;
        else if ([t isEqualToString:@"false"] || [t isEqualToString:@"0"] || [t isEqualToString:@"no"]) value = @NO;
        else {
            BQAlert(self, @"Invalid boolean", @"Enter true/false, 1/0 or yes/no.");
            return;
        }
    } else if (self.type == CETypeData) {
        NSString *t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSData *d = [[NSData alloc] initWithBase64EncodedString:t options:0];
        if (!d) {
            BQAlert(self, @"Invalid base64", @"Enter valid base64 data.");
            return;
        }
        value = d;
    }
    if (self.onSave) self.onSave(key, value);
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)deleteKey {
    NSString *key = self.key;
    if (!key.length || !self.onDelete) return;
    BQConfirm(self, @"Delete key?", [NSString stringWithFormat:@"Remove %@ from CacheExtra. Apply to persist.", key], ^{
        self.onDelete(key);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.navigationController popViewControllerAnimated:YES];
        });
    });
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.isNew ? 2 : 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 1) return 2;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Key";
    if (section == 1) return @"Value";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (indexPath.section == 0) {
        [self embed:self.keyField inCell:cell];
        return cell;
    }
    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Type";
            self.typeControl.frame = CGRectMake(0, 0, 260, 32);
            cell.accessoryView = self.typeControl;
        } else {
            [self embed:self.valueField inCell:cell];
        }
        return cell;
    }
    cell.textLabel.text = @"Delete Key";
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.textLabel.textColor = [UIColor systemRedColor];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)embed:(UIView *)view inCell:(UITableViewCell *)cell {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [view.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [view.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
        [view.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
        [view.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
    ]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.isNew && indexPath.section == 2) [self deleteKey];
}

@end

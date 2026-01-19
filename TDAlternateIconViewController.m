#import "TDAlternateIconViewController.h"
#import "TDAlternateIconCell.h"
#import <dlfcn.h>
#import <rootless.h>
#import <objc/runtime.h>
#import "Localize.h"

static UIImage *alternateIconImage(NSString *iconName) {
    NSString *fileName = [NSString stringWithFormat:@"%@60x60@2x.png", iconName];
    NSString *path = [[[NSBundle mainBundle] bundleURL] URLByAppendingPathComponent:fileName].path;
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    if (!image) {
        NSLog(@"[td] Failed to load alternate icon image: %@", path);
        image = [UIImage systemImageNamed:@"questionmark"];
    }

    return image;
}

@implementation TDAlternateIconViewController {
    NSDictionary *_alternateIconsDictionary;
    BOOL _hasSnowBoardFixInstalled;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // self.title = @"Alternate Icons";
    self.title = [Localize localizedStringForKey:@"ALTERNATE_ICONS"];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.tableFooterView = [UIView new];

    _alternateIconsDictionary = [self alternateIconInfo];

    // the space is not a typo; its's to load earlier than snowboard's stub: AAASnowBoardStub.dylib
    _hasSnowBoardFixInstalled = dlopen(ROOT_PATH("/Library/MobileSubstrate/DynamicLibraries/ SnowBoardFix.dylib"), RTLD_LAZY);
}

- (NSArray<NSString *> *)alternateIconKeys {
    return @[ @"Default", @"Original", @"ClearDark", @"ClearLight", @"Dark", @"TintedDark", @"TintedLight" ];
}

- (NSDictionary *)alternateIconInfo {
    static dispatch_once_t onceToken;
    static NSDictionary *iconsDict = nil;
    dispatch_once(&onceToken, ^{
        iconsDict = @{
            @"Default": @{
                @"name": @"Default",
                @"image": alternateIconImage(@"AppIcon")
            },
            @"Original": @{
                @"name": @"Original",
                @"image": alternateIconImage(@"Original")
            },
            @"ClearDark": @{
                @"name": @"Clear Dark",
                @"image": alternateIconImage(@"ClearDark")
            },
            @"ClearLight": @{
                @"name": @"Clear Light",
                @"image": alternateIconImage(@"ClearLight")
            },
            @"Dark": @{
                @"name": @"Dark",
                @"image": alternateIconImage(@"Dark")
            },
            @"TintedDark": @{
                @"name": @"Tinted Dark (Purple)",
                @"image": alternateIconImage(@"TintedDark")
            },
            @"TintedLight": @{
                @"name": @"Tinted Light (Purple)",
                @"image": alternateIconImage(@"TintedLight")
            },
        };
    });
    return iconsDict;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.alternateIconKeys.count;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 75.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    TDAlternateIconCell *cell = [tableView dequeueReusableCellWithIdentifier:@"IconCell"];
    if (!cell) {
        cell = [[TDAlternateIconCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"IconCell"];
    }

    NSString *iconKey = self.alternateIconKeys[indexPath.row];
    NSDictionary *iconData = _alternateIconsDictionary[iconKey];

    cell.iconNameLabel.text = iconData[@"name"];
    cell.iconImageView.image = iconData[@"image"];

    if (([UIApplication sharedApplication].alternateIconName == nil && [iconKey isEqualToString:@"Default"]) ||
        [[UIApplication sharedApplication].alternateIconName isEqualToString:iconKey]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (![UIApplication sharedApplication].supportsAlternateIcons) {
        NSLog(@"[td] Alternate icons not supported on this device.");
        return;
    }

    NSString *iconKey = self.alternateIconKeys[indexPath.row];
    NSString *currentIconName = [UIApplication sharedApplication].alternateIconName;

    if ((currentIconName == nil && [iconKey isEqualToString:@"Default"]) ||
        [currentIconName isEqualToString:iconKey]) {
        return; 
    }

    NSString *old = currentIconName ?: @"Default";
    NSString *alternateIconName = [iconKey isEqualToString:@"Default"] ? nil : iconKey;
    NSLog(@"Setting alternate icon: %@ -> %@", old, alternateIconName ?: @"Default");

    [[UIApplication sharedApplication] setAlternateIconName:alternateIconName completionHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"[td] Error setting alternate icon: %@", error);
            return;
        }
        
        if (!_hasSnowBoardFixInstalled) {
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFSTR("com.spark.snowboard.refresh"),
                NULL,
                NULL,
                true
            );
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView reloadData];
        });
    }];
}


@end
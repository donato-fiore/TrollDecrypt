#import "TDFileManagerViewController.h"
#import "Decryption/TDDecryptionTask.h"
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import "Localize.h"

@implementation TDFileManagerViewController {
    UIView *_noFilesInfoView;
    NSMutableArray<NSURL *> *_decryptedIPAURLs;
    NSMutableArray<NSURL *> *_decryptedAppBundleURLs;
    NSMutableArray<NSURL *> *_decryptedBinaries;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self loadDecryptedOutputs];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];

    [self updateEmptyState];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)loadDecryptedOutputs {
    NSMutableArray<NSURL *> *decryptedIPAURLs = [NSMutableArray new];
    NSMutableArray<NSURL *> *decryptedAppBundleURLs = [NSMutableArray new];
    NSMutableArray<NSURL *> *decryptedBinaries = [NSMutableArray new];

    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:ROOT_OUTPUT_PATH error:nil];

    for (NSString *filename in files) {
        NSURL *fileURL = [[NSURL fileURLWithPath:ROOT_OUTPUT_PATH] URLByAppendingPathComponent:filename];
        BOOL isDirectory = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:fileURL.path isDirectory:&isDirectory]) {
            continue;
        }

        if (isDirectory) {
            if ([fileURL.pathExtension.lowercaseString isEqualToString:@"app"]) {
                [decryptedAppBundleURLs addObject:fileURL];
            }
            continue;
        }

        if ([fileURL.pathExtension.lowercaseString isEqualToString:@"ipa"] || [fileURL.pathExtension.lowercaseString isEqualToString:@"tipa"]) {
            [decryptedIPAURLs addObject:fileURL];
        }

        int fd = open(fileURL.path.UTF8String, O_RDONLY);
        if (fd < 0) continue;

        uint32_t magic = 0;
        ssize_t readBytes = read(fd, &magic, sizeof(magic));
        close(fd);

        if (readBytes != sizeof(magic)) continue;

        switch (magic) {
            case MH_MAGIC:
            case MH_CIGAM:
            case MH_MAGIC_64:
            case MH_CIGAM_64:
            case FAT_MAGIC:
            case FAT_CIGAM:
                [decryptedBinaries addObject:fileURL];
                break;
            default:
                break;
        }
    }

    _decryptedIPAURLs = [decryptedIPAURLs copy];
    _decryptedAppBundleURLs = [decryptedAppBundleURLs copy];
    _decryptedBinaries = [decryptedBinaries copy];
}

- (void)reload {
    [self loadDecryptedOutputs];
    [self.tableView reloadData];
    [self.refreshControl endRefreshing];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    if (_decryptedIPAURLs.count == 0 && _decryptedAppBundleURLs.count == 0 && _decryptedBinaries.count == 0) {
        self.tableView.backgroundView = [self noFilesInfoView];
    } else {
        self.tableView.backgroundView = nil;
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return _decryptedIPAURLs.count;
    } else if (section == 1) {
        return _decryptedAppBundleURLs.count;
    } else {
        return _decryptedBinaries.count;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSString *format;
    NSInteger count = 0;
    if (section == 0) {
        format = [Localize localizedStringForKey:@"DECRYPTED_IPAS"];
        count = _decryptedIPAURLs.count;
    } else if (section == 1) {
        format = [Localize localizedStringForKey:@"DECRYPTED_APP_BUNDLES"];
        count = _decryptedAppBundleURLs.count;
    } else {
        format = [Localize localizedStringForKey:@"DECRYPTED_BINARIES"];
        count = _decryptedBinaries.count;
    }

    return [NSString stringWithFormat:format, (unsigned long)count];
}

- (NSURL *)_outputURLForIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return _decryptedIPAURLs[indexPath.row];
    if (indexPath.section == 1) return _decryptedAppBundleURLs[indexPath.row];
    return _decryptedBinaries[indexPath.row];
}

- (BOOL)_indexPathIsAppBundle:(NSIndexPath *)indexPath {
    return indexPath.section == 1;
}

- (unsigned long long)_recursiveSizeOfDirectoryAtURL:(NSURL *)url {
    unsigned long long totalSize = 0;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator =
        [fileManager enumeratorAtURL:url
          includingPropertiesForKeys:@[ NSURLFileSizeKey ]
                             options:0
                        errorHandler:^BOOL(NSURL *unreadableURL, NSError *error) {
                            NSLog(@"Skipping unreadable output item %@: %@", unreadableURL.path, error);
                            return YES;
                        }];

    for (NSURL *itemURL in enumerator) {
        NSNumber *fileSize = nil;
        if ([itemURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil]) {
            totalSize += fileSize.unsignedLongLongValue;
        }
    }
    return totalSize;
}

- (void)_presentLocationActionsForURL:(NSURL *)url sourceView:(UIView *)sourceView sourceRect:(CGRect)sourceRect {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:url.lastPathComponent message:url.path preferredStyle:UIAlertControllerStyleActionSheet];

    if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"filza://"]]) {
        [alert addAction:[UIAlertAction actionWithTitle:[Localize localizedStringForKey:@"SHOW_IN_FILZA"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSURL *filzaURL = [[NSURL URLWithString:@"filza://view"] URLByAppendingPathComponent:url.path];
            [[UIApplication sharedApplication] openURL:filzaURL options:@{} completionHandler:nil];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:[Localize localizedStringForKey:@"COPY_PATH"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [UIPasteboard generalPasteboard].string = url.path;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:[Localize localizedStringForKey:@"CANCEL"] style:UIAlertActionStyleCancel handler:nil]];

    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover) {
        popover.sourceView = sourceView ?: self.view;
        popover.sourceRect = sourceRect;
        popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }

    [self presentViewController:alert animated:YES completion:nil];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DecryptedFileCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DecryptedFileCell"];

    NSURL *fileURL = [self _outputURLForIndexPath:indexPath];
    NSString *imageName;
    if (indexPath.section == 0) {
        imageName = @"doc.zipper";
    } else if (indexPath.section == 1) {
        imageName = @"folder.fill";
    } else {
        imageName = @"doc.fill";
    }

    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:fileURL.path error:nil];
    NSDate *modificationDate = attributes[NSFileModificationDate];
    NSNumber *fileSize = attributes[NSFileSize];
    unsigned long long outputSize = [self _indexPathIsAppBundle:indexPath] ? [self _recursiveSizeOfDirectoryAtURL:fileURL] : fileSize.unsignedLongLongValue;
    
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"MMM d, yyyy h:mm a"];

    cell.textLabel.text = fileURL.lastPathComponent;
    cell.detailTextLabel.text = [dateFormatter stringFromDate:modificationDate];
    cell.detailTextLabel.textColor = [UIColor systemGray2Color];
    cell.imageView.image = [UIImage systemImageNamed:imageName];

    UILabel *fileSizeLabel = [[UILabel alloc] init];
    fileSizeLabel.text = [NSString stringWithFormat:@"%.2f MB", (double)outputSize / (1024.0 * 1024.0)];
    fileSizeLabel.textColor = [UIColor systemGray2Color];
    fileSizeLabel.font = [UIFont systemFontOfSize:12.0f];
    [fileSizeLabel sizeToFit];
    fileSizeLabel.textAlignment = NSTextAlignmentCenter;
    cell.accessoryView = fileSizeLabel;

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 65.0f;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:[Localize localizedStringForKey:@"Delete"] handler:^(UIContextualAction *action, __kindof UIView *sourceView, void (^completionHandler)(BOOL)) {
        NSURL *fileURL = [self _outputURLForIndexPath:indexPath];
        [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];

        [self reload];

        completionHandler(YES);
    }];

    UISwipeActionsConfiguration *swipeActions = [UISwipeActionsConfiguration configurationWithActions:@[ deleteAction ]];
    return swipeActions;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSURL *fileURL = [self _outputURLForIndexPath:indexPath];

    if ([self _indexPathIsAppBundle:indexPath]) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        [self _presentLocationActionsForURL:fileURL sourceView:cell.contentView sourceRect:cell.contentView.bounds];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }

    UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[ fileURL ] applicationActivities:nil];
    
    // if the popover presentation controller exists, then we require one for this device (e.g. iPad) (@joshuaseltzer)
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        if (cell) {
            activityViewController.popoverPresentationController.sourceView = cell.contentView;
            activityViewController.popoverPresentationController.sourceRect = cell.contentView.bounds;
        }
    }

    [self presentViewController:activityViewController animated:YES completion:nil];

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (UIView *)noFilesInfoView {
    if (_noFilesInfoView) return _noFilesInfoView;

    UIImageView *fileImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"doc" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:52]]];
    fileImageView.tintColor = [UIColor systemGray2Color];

    UILabel *label = [[UILabel alloc] init];
    label.text = @"No files.";
    label.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightMedium];
    label.textColor = [UIColor systemGray2Color];
    label.textAlignment = NSTextAlignmentCenter;

    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[fileImageView, label]];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.alignment = UIStackViewAlignmentCenter;
    stackView.spacing = 10;

    _noFilesInfoView = [[UIView alloc] initWithFrame:self.tableView.bounds];
    [_noFilesInfoView addSubview:stackView];

    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [stackView.centerXAnchor constraintEqualToAnchor:_noFilesInfoView.centerXAnchor],
        [stackView.centerYAnchor constraintEqualToAnchor:_noFilesInfoView.centerYAnchor]
    ]];

    return _noFilesInfoView;
}

@end

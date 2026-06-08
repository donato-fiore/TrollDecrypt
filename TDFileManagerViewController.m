#import "TDFileManagerViewController.h"
#import "Decryption/TDDecryptionTask.h"
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import "Localize.h"

@implementation TDFileManagerViewController {
    UIView *_noFilesInfoView;
    UILabel *_noFilesInfoLabel;
    NSArray<NSURL *> *_decryptedIPAURLs;
    NSArray<NSURL *> *_decryptedBinaries;
    NSArray<NSURL *> *_filteredDecryptedIPAURLs;
    NSArray<NSURL *> *_filteredDecryptedBinaries;
    UISearchController *_searchController;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self loadDecryptedIPAs];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];

    [self _configureSearchController];
    [self updateEmptyState];
}

- (void)_configureSearchController {
    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.searchResultsUpdater = self;
    _searchController.obscuresBackgroundDuringPresentation = NO;
    _searchController.searchBar.placeholder = @"Search Files";
    _searchController.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _searchController.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;

    self.navigationItem.searchController = _searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)loadDecryptedIPAs {
    NSMutableArray<NSURL *> *decryptedIPAURLs = [NSMutableArray new];
    NSMutableArray<NSURL *> *decryptedBinaries = [NSMutableArray new];

    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:ROOT_OUTPUT_PATH error:nil];

    for (NSString *filename in files) {
        NSURL *fileURL = [[NSURL fileURLWithPath:ROOT_OUTPUT_PATH] URLByAppendingPathComponent:filename];
        BOOL isDirectory = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:fileURL.path isDirectory:&isDirectory] || isDirectory) {
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
    _decryptedBinaries = [decryptedBinaries copy];

    [self _applySearchFilter];
}

- (void)reload {
    [self loadDecryptedIPAs];
    [self.tableView reloadData];
    [self.refreshControl endRefreshing];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    if (_filteredDecryptedIPAURLs.count == 0 && _filteredDecryptedBinaries.count == 0) {
        NSString *query = [_searchController.searchBar.text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        self.tableView.backgroundView = [self noFilesInfoView];
        _noFilesInfoLabel.text = (query.length > 0) ? @"No matching files." : @"No files.";
    } else {
        self.tableView.backgroundView = nil;
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (section == 0 ? _filteredDecryptedIPAURLs : _filteredDecryptedBinaries).count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSString *format;
    NSInteger count = 0;
    if (section == 0) {
        format = [Localize localizedStringForKey:@"DECRYPTED_IPAS"];
        count = _filteredDecryptedIPAURLs.count;
    } else {
        format = [Localize localizedStringForKey:@"DECRYPTED_BINARIES"];
        count = _filteredDecryptedBinaries.count;
    }

    return [NSString stringWithFormat:format, (unsigned long)count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DecryptedFileCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DecryptedFileCell"];

    NSURL *fileURL;
    NSString *imageName;
    if (indexPath.section == 0) {
        fileURL = _filteredDecryptedIPAURLs[indexPath.row];
        imageName = @"doc.zipper";
    } else {
        fileURL = _filteredDecryptedBinaries[indexPath.row];
        imageName = @"doc.fill";
    }

    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:fileURL.path error:nil];
    NSDate *modificationDate = attributes[NSFileModificationDate];
    NSNumber *fileSize = attributes[NSFileSize];
    
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"MMM d, yyyy h:mm a"];

    cell.textLabel.text = fileURL.lastPathComponent;
    cell.detailTextLabel.text = [dateFormatter stringFromDate:modificationDate];
    cell.detailTextLabel.textColor = [UIColor systemGray2Color];
    cell.imageView.image = [UIImage systemImageNamed:imageName];

    UILabel *fileSizeLabel = [[UILabel alloc] init];
    fileSizeLabel.text = [NSString stringWithFormat:@"%.2f MB", [fileSize doubleValue] / (1024.0 * 1024.0)];
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
    NSString *title = [Localize localizedStringForKey:@"Delete"];
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:title handler:^(UIContextualAction *action, __kindof UIView *sourceView, void (^completionHandler)(BOOL)) {
        NSURL *fileURL = indexPath.section == 0 ? _filteredDecryptedIPAURLs[indexPath.row] : _filteredDecryptedBinaries[indexPath.row];
        [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];

        [self reload];
        completionHandler(YES);
    }];

    UISwipeActionsConfiguration *swipeActions = [UISwipeActionsConfiguration configurationWithActions:@[ deleteAction ]];
    return swipeActions;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSURL *fileURL = (indexPath.section == 0 ? _filteredDecryptedIPAURLs : _filteredDecryptedBinaries)[indexPath.row];

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

    _noFilesInfoLabel = [[UILabel alloc] init];
    _noFilesInfoLabel.text = @"No files.";
    _noFilesInfoLabel.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightMedium];
    _noFilesInfoLabel.textColor = [UIColor systemGray2Color];
    _noFilesInfoLabel.textAlignment = NSTextAlignmentCenter;

    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[fileImageView, _noFilesInfoLabel]];
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

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
    [self _applySearchFilter];
    [self.tableView reloadData];
    [self updateEmptyState];
}

- (void)_applySearchFilter {
    NSString *query = [_searchController.searchBar.text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (query.length == 0) {
        _filteredDecryptedIPAURLs = _decryptedIPAURLs ?: @[];
        _filteredDecryptedBinaries = _decryptedBinaries ?: @[];
        return;
    }

    NSString *lowercaseQuery = [query lowercaseString];
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSURL *fileURL, NSDictionary *bindings) {
        return [[fileURL.lastPathComponent lowercaseString] containsString:lowercaseQuery];
    }];

    _filteredDecryptedIPAURLs = [_decryptedIPAURLs filteredArrayUsingPredicate:predicate];
    _filteredDecryptedBinaries = [_decryptedBinaries filteredArrayUsingPredicate:predicate];
}

@end

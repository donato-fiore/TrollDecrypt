#import "TDFileManagerViewController.h"
#import "TDUtils.h"

@implementation TDFileManagerViewController

- (void)loadView {
    [super loadView];

    self.title = @"Decrypted IPAs";
    self.fileList = decryptedFileList();

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(done)];

    if (self.fileList.count == 0) {
        [self addNoFilesView];
    }
}

- (void)refresh {
    self.fileList = decryptedFileList();
    [self.tableView reloadData];
}

- (void)done {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSelectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.fileList.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"FileCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];

    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
    }

    NSString *path = [docPath() stringByAppendingPathComponent:self.fileList[indexPath.row]];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSDate *date = attributes[NSFileModificationDate];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"MMM d, yyyy h:mm a"];

    NSNumber *fileSize = attributes[NSFileSize];

    cell.textLabel.text = self.fileList[indexPath.row];
    cell.detailTextLabel.text = [dateFormatter stringFromDate:date];
    cell.detailTextLabel.textColor = [UIColor systemGray2Color];
    cell.imageView.image = [UIImage systemImageNamed:@"doc.fill"];

    UILabel *label = [[UILabel alloc] init];
    label.text = [NSString stringWithFormat:@"%.2f MB", [fileSize doubleValue] / 1000000.0f];
    label.textColor = [UIColor systemGray2Color];
    label.font = [UIFont systemFontOfSize:12.0f];
    [label sizeToFit];
    label.textAlignment = NSTextAlignmentCenter;
    cell.accessoryView = label;

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 65.0f;
}

- (bool)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:@"Delete"
                                                                             handler:^(UIContextualAction *action, __kindof UIView *sourceView, void (^completionHandler)(BOOL)) {
                                                                                 NSString *file = self.fileList[indexPath.row];
                                                                                 NSString *path = [docPath() stringByAppendingPathComponent:file];
                                                                                 [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
                                                                                 [self refresh];

                                                                                 if (self.fileList.count == 0) {
                                                                                     [self addNoFilesView];
                                                                                 }
                                                                             }];

    UISwipeActionsConfiguration *swipeActions = [UISwipeActionsConfiguration configurationWithActions:@[ deleteAction ]];
    return swipeActions;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *file = self.fileList[indexPath.row];
    NSString *path = [docPath() stringByAppendingPathComponent:file];
    NSURL *url = [NSURL fileURLWithPath:path];

    UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[ url ] applicationActivities:nil];
    [self presentViewController:activityViewController animated:YES completion:nil];

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)addNoFilesView {
    UIView *view = [[UIView alloc] init];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tableView addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [view.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
        [view.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor
                                           constant:-(self.navigationController.navigationBar.frame.size.height + 25)],
        [view.widthAnchor constraintEqualToConstant:200],
        [view.heightAnchor constraintEqualToConstant:200]
    ]];

    UIImageView *docView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"doc"]];
    docView.tintColor = [UIColor systemGray2Color];
    docView.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:docView];
    [NSLayoutConstraint activateConstraints:@[
        [docView.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
        [docView.centerYAnchor constraintEqualToAnchor:view.centerYAnchor],
        [docView.widthAnchor constraintEqualToConstant:50],
        [docView.heightAnchor constraintEqualToConstant:50]
    ]];

    UILabel *label = [[UILabel alloc] init];
    label.text = @"No files.";
    label.font = [UIFont systemFontOfSize:24.0f weight:UIFontWeightMedium];
    [view addSubview:label];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = [UIColor systemGray2Color];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
        [label.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [label.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [label.heightAnchor constraintEqualToConstant:28],
        [label.topAnchor constraintEqualToAnchor:docView.bottomAnchor
                                        constant:10]
    ]];
}

@end
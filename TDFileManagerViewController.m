#import "TDFileManagerViewController.h"
#import "TDUtils.h"

@implementation TDFileManagerViewController

- (void)loadView {
    [super loadView];

    self.title = @"Decrypted IPAs";
    self.fileList = decryptedFileList();

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(done)];
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
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete" handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        NSString *file = self.fileList[indexPath.row];
        NSString *path = [docPath() stringByAppendingPathComponent:file];
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        [self refresh];
    }];

    UISwipeActionsConfiguration *swipeActions = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
    return swipeActions;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *file = self.fileList[indexPath.row];
    NSString *path = [docPath() stringByAppendingPathComponent:file];
    NSURL *url = [NSURL fileURLWithPath:path];

    UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    [self presentViewController:activityViewController animated:YES completion:nil];

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
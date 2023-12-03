#import "TDRootViewController.h"
#import "TDFileManagerViewController.h"
#import "TDUtils.h"

@implementation TDRootViewController

- (void)loadView {
    [super loadView];

    self.apps = appList();
    self.title = @"TrollDecrypt";
	self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"info.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(about:)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"folder"] style:UIBarButtonItemStylePlain target:self action:@selector(openDocs:)];

    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(refreshApps:) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refreshControl;
}

- (void)viewDidAppear:(bool)animated {
    [super viewDidAppear:animated];

    fetchLatestTrollDecryptVersion(^(NSString *latestVersion) {
        NSString *currentVersion = trollDecryptVersion();
        NSComparisonResult result = [currentVersion compare:latestVersion options:NSNumericSearch];
        NSLog(@"[trolldecrypter] Current version: %@, Latest version: %@", currentVersion, latestVersion);
        if (result == NSOrderedAscending) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Update Available" message:@"An update for TrollDecrypt is available." preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
                UIAlertAction *update = [UIAlertAction actionWithTitle:@"Download" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://github.com/donato-fiore/TrollDecrypt/releases/latest"]] options:@{} completionHandler:nil];
                }];

                [alert addAction:update];
                [alert addAction:cancel];
                [self presentViewController:alert animated:YES completion:nil];
            });
        }
    });
}

- (void)openDocs:(id)sender {
    TDFileManagerViewController *fmVC = [[TDFileManagerViewController alloc] init];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:fmVC];
    [self presentViewController:navController animated:YES completion:nil];
}

- (void)about:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"TrollDecrypt" message:@"by fiore\nIcon by @super.user\nbfdecrypt by @bishopfox\ndumpdecrypted by @i0n1c\nUpdated for TrollStore by @wh1te4ever" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Dismiss" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)refreshApps:(UIRefreshControl *)refreshControl {
    self.apps = appList();
    [self.tableView reloadData];
    [refreshControl endRefreshing];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { 
    return self.apps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"AppCell";
    UITableViewCell *cell;
    if (([self.apps count] - 1) != indexPath.row) {
        cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
        if (cell == nil) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
    
        NSDictionary *app = self.apps[indexPath.row];

        cell.textLabel.text = app[@"name"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", app[@"version"], app[@"bundleID"]];
        cell.imageView.image = [UIImage _applicationIconImageForBundleIdentifier:app[@"bundleID"] format:iconFormat() scale:[UIScreen mainScreen].scale];
    } else {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        
        cell.textLabel.text = @"Advanced";
        cell.detailTextLabel.text = @"Decrypt app from a specified PID";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 80.0f;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UIAlertController *alert;
    
    if (([self.apps count] - 1) != indexPath.row) {
        NSDictionary *app = self.apps[indexPath.row];

        alert = [UIAlertController alertControllerWithTitle:@"Decrypt" message:[NSString stringWithFormat:@"Decrypt %@?", app[@"name"]] preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
        UIAlertAction *decrypt = [UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            decryptApp(app);
        }];

        [alert addAction:decrypt];
        [alert addAction:cancel];
    } else {
        alert = [UIAlertController alertControllerWithTitle:@"Decrypt" message:@"Enter PID to decrypt" preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = @"PID";
            textField.keyboardType = UIKeyboardTypeNumberPad;
        }];

        UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
        UIAlertAction *decrypt = [UIAlertAction actionWithTitle:@"Decrypt" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *pid = alert.textFields.firstObject.text;
            decryptAppWithPID([pid intValue]);
        }];

        [alert addAction:decrypt];
        [alert addAction:cancel];
    }

    [self presentViewController:alert animated:YES completion:nil];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
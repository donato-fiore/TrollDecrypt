#import <UIKit/UIKit.h>

#import "TDRootViewController.h"
#import "TDApplicationListViewController.h"
#import "TDFileManagerViewController.h"
#import "Localize.h"

@implementation TDRootViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    TDApplicationListViewController *decryptionViewController = [[TDApplicationListViewController alloc] init];
    // decryptionViewController.title = @"Decrypt Apps";
    decryptionViewController.title = [Localize localizedStringForKey:@"DECRYPT_APPS"];

    UINavigationController *decryptionNavigationController = [[UINavigationController alloc] initWithRootViewController:decryptionViewController];
    decryptionNavigationController.tabBarItem.image = [UIImage systemImageNamed:@"square.stack.3d.up.fill"];

    TDFileManagerViewController *fileManagerViewController = [[TDFileManagerViewController alloc] init];
    fileManagerViewController.title = [Localize localizedStringForKey:@"DECRYPTED_FILES"];

    UINavigationController *fileManagerNavigationController = [[UINavigationController alloc] initWithRootViewController:fileManagerViewController];
    fileManagerNavigationController.tabBarItem.image = [UIImage systemImageNamed:@"folder.fill"];

    self.viewControllers = @[decryptionNavigationController, fileManagerNavigationController];
}

@end
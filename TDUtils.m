#import "TDUtils.h"
#import "TDDumpDecrypted.h"

UIWindow *alertWindow = NULL;
UIWindow *kw = NULL;
UIViewController *root = NULL;
UIAlertController *alertController = NULL;
UIAlertController *doneController = NULL;
UIAlertController *errorController = NULL;

NSArray *appList(void) {
    NSMutableArray *apps = [NSMutableArray array];
    
    for (LSApplicationProxy *app in [[LSApplicationWorkspace defaultWorkspace] allInstalledApplications]) {
        if (![[app applicationType] isEqualToString:@"User"]) continue;

        NSString *bundleID = app.bundleIdentifier;
        NSString *name = [app localizedName];
        NSString *version = app.shortVersionString;
        NSString *executable = [app canonicalExecutablePath];

        NSDictionary *item = @{
            @"bundleID":bundleID,
            @"name":name,
            @"version":version,
            @"executable":executable
        };

        [apps addObject:item];
    }
    
    NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
    [apps sortUsingDescriptors:@[descriptor]];
    
    [apps addObject:@{@"bundleID":@"", @"name":@"", @"version":@"", @"executable":@""}];

    return [apps copy];
}

NSUInteger iconFormat(void) {
    return (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) ? 8 : 10;
}

NSArray *sysctl_ps(void) {
    // int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    // size_t miblen = 4;
    // size_t size;
    // int st = sysctl(mib, miblen, NULL, &size, NULL, 0);
    // struct kinfo_proc * process = NULL;
    // struct kinfo_proc * newprocess = NULL;
    
    // do {
    //     size += size / 10;
    //     newprocess = realloc(process, size);
    //     if (!newprocess){
    //         if (process){
    //             free(process);
    //         }
    //         return nil;
    //     }
    //     process = newprocess;
    //     st = sysctl(mib, miblen, process, &size, NULL, 0);
    // } while (st == -1 && errno == ENOMEM);
    
    // if (st == 0) {
    //     if (size % sizeof(struct kinfo_proc) == 0){
    //         int nprocess = size / sizeof(struct kinfo_proc);
    //         if (nprocess){
    //             NSMutableArray * array = [[NSMutableArray alloc] init];
    //             for (int i = nprocess - 1; i >= 0; i--){
    //                 NSString *processID = [[NSString alloc] initWithFormat:@"%d", process[i].kp_proc.p_pid];
    //                 NSString *processName = [[NSString alloc] initWithFormat:@"%s", process[i].kp_proc.p_comm];
    //                 NSDictionary *dict = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:processID, processName, nil] forKeys:[NSArray arrayWithObjects:@"pid", @"proc_name", nil]];
    //                 [array addObject:dict];
    //             }
    //             free(process);
    //             return array; 
    //         }
    //     }
    // }
    NSMutableArray *array = [[NSMutableArray alloc] init];

    int numberOfProcesses = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    pid_t pids[numberOfProcesses];
    bzero(pids, sizeof(pids));
    proc_listpids(PROC_ALL_PIDS, 0, pids, sizeof(pids));
    for (int i = 0; i < numberOfProcesses; ++i) {
        if (pids[i] == 0) { continue; }
        char pathBuffer[PROC_PIDPATHINFO_MAXSIZE];
        bzero(pathBuffer, PROC_PIDPATHINFO_MAXSIZE);
        proc_pidpath(pids[i], pathBuffer, sizeof(pathBuffer));

        if (strlen(pathBuffer) > 0) {
            NSString *processID = [[NSString alloc] initWithFormat:@"%d", pids[i]];
            NSString *processName = [[NSString stringWithUTF8String:pathBuffer] lastPathComponent];
            NSDictionary *dict = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:processID, processName, nil] forKeys:[NSArray arrayWithObjects:@"pid", @"proc_name", nil]];
            
            [array addObject:dict];
        }
    }

    return [array copy];
}

void decryptApp(NSDictionary *app) {
    dispatch_async(dispatch_get_main_queue(), ^{
        alertWindow = [[UIWindow alloc] initWithFrame: [UIScreen mainScreen].bounds];
        alertWindow.rootViewController = [UIViewController new];
        alertWindow.windowLevel = UIWindowLevelAlert + 1;
        [alertWindow makeKeyAndVisible];
        
        // Show a "Decrypting!" alert on the device and block the UI
            
        kw = alertWindow;
        if([kw respondsToSelector:@selector(topmostPresentedViewController)])
            root = [kw performSelector:@selector(topmostPresentedViewController)];
        else
            root = [kw rootViewController];
        root.modalPresentationStyle = UIModalPresentationFullScreen;
    });

    NSLog(@"[trolldecrypt] spawning thread to do decryption in background...");

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSLog(@"[trolldecrypt] inside decryption thread.");

        NSString *bundleID = app[@"bundleID"];
        NSString *name = app[@"name"];
        NSString *version = app[@"version"];
        NSString *executable = app[@"executable"];
        NSString *binaryName = [executable lastPathComponent];

        NSLog(@"[trolldecrypt] bundleID: %@", bundleID);
        NSLog(@"[trolldecrypt] name: %@", name);
        NSLog(@"[trolldecrypt] version: %@", version);
        NSLog(@"[trolldecrypt] executable: %@", executable);
        NSLog(@"[trolldecrypt] binaryName: %@", binaryName);

        [[UIApplication sharedApplication] launchApplicationWithIdentifier:bundleID suspended:YES];
        sleep(1);

        pid_t pid = -1;
        NSArray *processes = sysctl_ps();
        for (NSDictionary *process in processes) {
            NSString *proc_name = process[@"proc_name"];
            if ([proc_name isEqualToString:binaryName]) {
                pid = [process[@"pid"] intValue];
                break;
            }
        }

        if (pid == -1) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [alertController dismissViewControllerAnimated:NO completion:nil];
                NSLog(@"[trolldecrypt] failed to get pid for binary name: %@", binaryName);

                errorController = [UIAlertController alertControllerWithTitle:@"Error: -1" message:[NSString stringWithFormat:@"Failed to get PID for binary name: %@", binaryName] preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Ok", @"Ok") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    NSLog(@"[trolldecrypt] Ok action");
                    [errorController dismissViewControllerAnimated:NO completion:nil];
                    [kw removeFromSuperview];
                    kw.hidden = YES;
                }];

                [errorController addAction:okAction];
                [root presentViewController:errorController animated:YES completion:nil];
            });

            return;
        }

        NSLog(@"[trolldecrypt] pid: %d", pid);

        bfinject_rocknroll(pid, name, version);
    });
}

void bfinject_rocknroll(pid_t pid, NSString *appName, NSString *version) {
    NSLog(@"[trolldecrypt] Spawning thread to do decryption in the background...");
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSLog(@"[trolldecrypt] Inside decryption thread");

		char pathbuf[PROC_PIDPATHINFO_MAXSIZE];
    	// int proc_pidpath(pid, pathbuf, sizeof(pathbuf));
        proc_pidpath(pid, pathbuf, sizeof(pathbuf));
		const char *fullPathStr = pathbuf;


        NSLog(@"[trolldecrypt] fullPathStr: %s", fullPathStr);
        DumpDecrypted *dd = [[DumpDecrypted alloc] initWithPathToBinary:[NSString stringWithUTF8String:fullPathStr] appName:appName appVersion:version];
        if(!dd) {
            NSLog(@"[trolldecrypt] ERROR: failed to get DumpDecrypted instance");
            return;
        }

        NSLog(@"[trolldecrypt] Full path to app: %s   ///   IPA File: %@", fullPathStr, [dd IPAPath]);

        dispatch_async(dispatch_get_main_queue(), ^{
            alertWindow = [[UIWindow alloc] initWithFrame: [UIScreen mainScreen].bounds];
            alertWindow.rootViewController = [UIViewController new];
            alertWindow.windowLevel = UIWindowLevelAlert + 1;
            [alertWindow makeKeyAndVisible];
            
            // Show a "Decrypting!" alert on the device and block the UI
            alertController = [UIAlertController
                alertControllerWithTitle:@"Decrypting"
                message:@"Please wait, this will take a few seconds..."
                preferredStyle:UIAlertControllerStyleAlert];
                
            kw = alertWindow;
            if([kw respondsToSelector:@selector(topmostPresentedViewController)])
                root = [kw performSelector:@selector(topmostPresentedViewController)];
            else
                root = [kw rootViewController];
            root.modalPresentationStyle = UIModalPresentationFullScreen;
            [root presentViewController:alertController animated:YES completion:nil];
        });
        
        // Do the decryption
        [dd createIPAFile:pid];

        // Dismiss the alert box
        dispatch_async(dispatch_get_main_queue(), ^{
            [alertController dismissViewControllerAnimated:NO completion:nil];

            doneController = [UIAlertController alertControllerWithTitle:@"Decryption Complete!" message:[NSString stringWithFormat:@"IPA file saved to:\n%@", [dd IPAPath]] preferredStyle:UIAlertControllerStyleAlert];

            UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Ok", @"Ok") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [kw removeFromSuperview];
                kw.hidden = YES;
            }];
            [doneController addAction:okAction];

            if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"filza://"]]) {
                UIAlertAction *openAction = [UIAlertAction actionWithTitle:@"Show in Filza" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    [kw removeFromSuperview];
                    kw.hidden = YES;

                    NSString *urlString = [NSString stringWithFormat:@"filza://view%@", [dd IPAPath]];
                    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:urlString] options:@{} completionHandler:nil];
                }];
                [doneController addAction:openAction];
            }

            [root presentViewController:doneController animated:YES completion:nil];
        }); // dispatch on main
                    
        NSLog(@"[trolldecrypt] Over and out.");
        while(1)
            sleep(9999999);
    }); // dispatch in background
    
    NSLog(@"[trolldecrypt] All done, exiting constructor.");
}

NSArray *decryptedFileList(void) {
    NSMutableArray *files = [NSMutableArray array];

    // iterate through all files in the Documents directory
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *directoryEnumerator = [fileManager enumeratorAtPath:docPath()];

    NSString *file;
    while (file = [directoryEnumerator nextObject]) {
        if ([[file pathExtension] isEqualToString:@"ipa"]) {
            NSString *filePath = [[docPath() stringByAppendingPathComponent:file] stringByStandardizingPath];

            NSDictionary *fileAttributes = [fileManager attributesOfItemAtPath:filePath error:nil];
            NSDate *modificationDate = [fileAttributes fileModificationDate];

            NSDictionary *fileInfo = @{@"fileName": file, @"modificationDate": modificationDate};
            [files addObject:fileInfo];
        }
    }

    // Sort the array based on modification date
    NSArray *sortedFiles = [files sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        NSDate *date1 = [obj1 objectForKey:@"modificationDate"];
        NSDate *date2 = [obj2 objectForKey:@"modificationDate"];
        return [date2 compare:date1];
    }];

    return [sortedFiles valueForKey:@"fileName"];
}

NSString *docPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
}

void decryptAppWithPID(pid_t pid) {
    // generate App NSDictionary object to pass into decryptApp()
    // proc_pidpath(self.pid, buffer, sizeof(buffer));
    NSString *message = nil;
    NSString *error = nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        alertWindow = [[UIWindow alloc] initWithFrame: [UIScreen mainScreen].bounds];
        alertWindow.rootViewController = [UIViewController new];
        alertWindow.windowLevel = UIWindowLevelAlert + 1;
        [alertWindow makeKeyAndVisible];
        
        // Show a "Decrypting!" alert on the device and block the UI
            
        kw = alertWindow;
        if([kw respondsToSelector:@selector(topmostPresentedViewController)])
            root = [kw performSelector:@selector(topmostPresentedViewController)];
        else
            root = [kw rootViewController];
        root.modalPresentationStyle = UIModalPresentationFullScreen;
    });

    NSLog(@"[trolldecrypt] pid: %d", pid);

    char pathbuf[PROC_PIDPATHINFO_MAXSIZE];
    proc_pidpath(pid, pathbuf, sizeof(pathbuf));

    NSString *executable = [NSString stringWithUTF8String:pathbuf];
    NSString *path = [executable stringByDeletingLastPathComponent];
    NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Info.plist"]];
    NSString *bundleID = infoPlist[@"CFBundleIdentifier"];

    if (!bundleID) {
        error = @"Error: -2";
        message = [NSString stringWithFormat:@"Failed to get bundle id for pid: %d", pid];
    }

    LSApplicationProxy *app = [LSApplicationProxy applicationProxyForIdentifier:bundleID];
    if (!app) {
        error = @"Error: -3";
        message = [NSString stringWithFormat:@"Failed to get LSApplicationProxy for bundle id: %@", bundleID];
    }

    if (message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [alertController dismissViewControllerAnimated:NO completion:nil];
            NSLog(@"[trolldecrypt] failed to get bundleid for pid: %d", pid);

            errorController = [UIAlertController alertControllerWithTitle:error message:message preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Ok", @"Ok") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                NSLog(@"[trolldecrypt] Ok action");
                [errorController dismissViewControllerAnimated:NO completion:nil];
                [kw removeFromSuperview];
                kw.hidden = YES;
            }];

            [errorController addAction:okAction];
            [root presentViewController:errorController animated:YES completion:nil];
        });
    }

    NSLog(@"[trolldecrypt] app: %@", app);

    NSString *name = [app localizedName];
    NSString *version = app.shortVersionString;
    if (!version) version = @"1.0";

    NSString *exec = [app canonicalExecutablePath];

    NSDictionary *appInfo = @{
        @"bundleID":bundleID,
        @"name":name,
        @"version":version,
        @"executable":exec
    };

    NSLog(@"[trolldecrypt] appInfo: %@", appInfo);

    dispatch_async(dispatch_get_main_queue(), ^{
        [alertController dismissViewControllerAnimated:NO completion:nil];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Decrypt" message:[NSString stringWithFormat:@"Decrypt %@?", appInfo[@"name"]] preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
        UIAlertAction *decrypt = [UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            decryptApp(appInfo);
        }];

        [alert addAction:decrypt];
        [alert addAction:cancel];
        
        [root presentViewController:alert animated:YES completion:nil];
    });
}
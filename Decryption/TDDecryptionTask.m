#import "TDDecryptionTask.h"
#import "TDError.h"
#import "Extensions/LSApplicationProxy+AltList.h"
#import "Localize.h"

#import "LaunchdResponse.h"
#import "MemoryUtilities.h"
#import <objc/runtime.h>
#import <SSZipArchive/SSZipArchive.h>
// #import <SSZipArchive.h>

#import <MobileCoreServices/MobileCoreServices.h>
#import "Extensions/LSBundleProxy+TrollDecrypt.h"

TDDecryptionTaskOptions TDDecryptionTaskOptionsMake(bool decryptBinaryOnly) {
    TDDecryptionTaskOptions options = {0};
    options.decryptBinaryOnly = decryptBinaryOnly;
    return options;
}

TDDecryptionTaskOptions TDDecryptionTaskDefaultOptions(void) {
    return TDDecryptionTaskOptionsMake(false);
}

@implementation TDDecryptionTask {
    NSFileManager *_fileManager;
    NSString *_workingDirectoryPath;
    NSString *_destinationPath;
}

- (instancetype)initWithApplicationProxy:(LSApplicationProxy *)application {
    self = [super init];
    if (self) {
        _applicationProxy = application;
        _fileManager = [NSFileManager defaultManager];
    }
    return self;
}

- (void)executeWithCompletionHandler:(void (^)(BOOL success, NSURL *outputURL, NSError *error))completionHandler {
    [self executeWithCompletionHandler:completionHandler options:TDDecryptionTaskDefaultOptions()];
}

- (void)executeWithCompletionHandler:(void (^)(BOOL success, NSURL *outputURL, NSError *error))completionHandler
                             options:(TDDecryptionTaskOptions)options {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{

        NSString *bundleIdentifier = self->_applicationProxy.bundleIdentifier;

        void (^progress)(NSString *) = ^(NSString *msg) {
            if (!self->_progressHandler) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_progressHandler(msg);
            });
        };

        if (![self createOutputDirectoryIfNeeded]) {
            NSError *dirError = [TDError errorWithCode:TDErrorCodeUnknown];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completionHandler) completionHandler(NO, nil, dirError);
            });
            return;
        }

        progress([Localize localizedStringForKey:@"LAUNCHING_APPLICATION"]);

        LaunchdResponse_t response = [self->_applicationProxy td_launchProcess];
        if (response.pid == -1) {
            NSLog(@"Failed to launch application %@", bundleIdentifier);
            NSError *launchError = [TDError errorWithCode:TDErrorCodeLaunchFailed];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completionHandler) completionHandler(NO, nil, launchError);
            });
            return;
        }

        pid_t targetPID = response.pid;

        if (!options.decryptBinaryOnly) {    
            progress([Localize localizedStringForKey:@"COPYING_BUNDLE"]);
            if (![self _copyApplicationBundle]) {
                NSError *copyError = [TDError errorWithCode:TDErrorCodeApplicationBundleCopyFailed];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completionHandler) completionHandler(NO, nil, copyError);
                });
                return;
            }
        }

        progress([Localize localizedStringForKey:@"DECRYPTING_BINARY"]);

        NSString *imagePath = [self->_applicationProxy td_canonicalExecutablePath];

        BOOL status = false;
        NSString *fullOutputPath = nil;
        if (options.decryptBinaryOnly) {
            NSLog(@"Decrypting main binary only to output directory: %@", ROOT_OUTPUT_PATH);
            NSLog(@"image path: %@", imagePath);
            NSString *fileName = [NSString stringWithFormat:@"%@_%@_decrypted",
                                  [imagePath lastPathComponent],
                                  [self->_applicationProxy atl_shortVersionString]];

            fullOutputPath = [ROOT_OUTPUT_PATH stringByAppendingPathComponent:fileName];
            status = [self decryptImageAtPath:imagePath forPID:targetPID outputPath:fullOutputPath];
        } else {
            status = [self decryptImageAtPath:imagePath forPID:targetPID];
        }

        if (!status) {
            NSError *decryptError = [TDError errorWithCode:TDErrorCodeBinaryDecryptionFailed];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completionHandler) completionHandler(NO, nil, decryptError);
            });
            return;
        }

        if (options.decryptBinaryOnly) {
            kill(targetPID, SIGKILL);
            progress([Localize localizedStringForKey:@"DECRYPTION_COMPLETED"]);

            dispatch_async(dispatch_get_main_queue(), ^{
                if (completionHandler) completionHandler(YES, [NSURL fileURLWithPath:fullOutputPath], nil);
            });
            return;
        }

        NSInteger extensionCount = self->_applicationProxy.plugInKitPlugins.count;
        NSInteger currentExtensionIndex = 0;

        for (LSPlugInKitProxy *extension in self->_applicationProxy.plugInKitPlugins) {
            LaunchdResponse_t extensionResponse = [extension td_launchProcess];
            if (extensionResponse.pid == -1) {
                NSLog(@"Failed to launch extension %@", extension.bundleIdentifier);
                continue;
            }

            currentExtensionIndex++;
            progress([NSString stringWithFormat:@"Decrypting extension %ld/%ld...",
                    (long)currentExtensionIndex, (long)extensionCount]);

            NSString *extensionImagePath = [extension td_canonicalExecutablePath];
            if (![self decryptImageAtPath:extensionImagePath forPID:extensionResponse.pid]) {
                NSLog(@"Failed to decrypt main executable for extension %@", extension.bundleIdentifier);
            }

            kill(extensionResponse.pid, SIGKILL);
        }

        progress([Localize localizedStringForKey:@"BUILDING_IPA"]);
        NSString *outputIPAName =
            [NSString stringWithFormat:@"%@_%@_decrypted.ipa",
             bundleIdentifier, [self->_applicationProxy atl_shortVersionString]];

        if (![self _buildIPAWithName:outputIPAName]) {
            NSError *ipaError = [TDError errorWithCode:TDErrorCodeIPAConstructionFailed];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completionHandler) completionHandler(NO, nil, ipaError);
            });
            return;
        }

        kill(targetPID, SIGKILL);
        progress([Localize localizedStringForKey:@"DECRYPTION_COMPLETED"]);

        NSString *ipaPath = [ROOT_OUTPUT_PATH stringByAppendingPathComponent:outputIPAName];
        NSURL *url = [NSURL fileURLWithPath:ipaPath];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completionHandler) completionHandler(YES, url, nil);
        });
    });
}


- (BOOL)decryptImageAtPath:(NSString *)imagePath forPID:(pid_t)pid {
    NSString *delimeter = [_destinationPath lastPathComponent]; // XXX.app
    NSString *rhs = [imagePath componentsSeparatedByString:delimeter].lastObject;
    NSString *outputPath = [_destinationPath stringByAppendingString:rhs];

    NSString *scInfoPath = [[outputPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"SC_Info"];
    if ([_fileManager fileExistsAtPath:scInfoPath]) {
        NSError *removeError = nil;
        NSLog(@"Removing SC_Info at path: %@", scInfoPath);
        [_fileManager removeItemAtPath:scInfoPath error:&removeError];
        if (removeError) {
            NSLog(@"failed to remove existing SC_Info at path %@, error: %@", scInfoPath, removeError);
            return NO;
        }
    }

    // if (!rebuildDecryptedImageAtPath(imagePath, task, mainImageInfo.loadAddress, &encryptionInfo, loadCommandAddress, outputPath)) {
    //     NSLog(@"failed to rebuild decrypted image for pid %d", pid);
    //     return NO;
    // }

    return [self decryptImageAtPath:imagePath forPID:pid outputPath:outputPath];
}

- (BOOL)decryptImageAtPath:(NSString *)imagePath forPID:(pid_t)pid outputPath:(NSString *)outputPath {
    vm_map_t task = 0;
    if (task_for_pid(mach_task_self(), pid, &task)) {
        NSLog(@"failed to get task for pid %d", pid);
        return NO;
    }

    MainImageInfo_t mainImageInfo = imageInfoForPIDWithRetry([imagePath UTF8String], task, pid);
    if (!mainImageInfo.ok) {
        NSLog(@"failed to get main image load address for pid %d", pid);
        return NO;
    }

    NSLog(@"main image info: %@", NSStringFromMainImageInfo(mainImageInfo));

    struct encryption_info_command encryptionInfo = {0};
    uint64_t loadCommandAddress = 0;
    if (!readEncryptionInfo(task, mainImageInfo.loadAddress, &encryptionInfo, &loadCommandAddress)) {
        NSLog(@"failed to read encryption info for pid %d", pid);
        return NO;
    }

    NSLog(@"encryption info: cryptoff=0x%x cryptsize=0x%x cryptid=%d",
          encryptionInfo.cryptoff, encryptionInfo.cryptsize, encryptionInfo.cryptid);
    
    if (encryptionInfo.cryptid == 0) {
        NSLog(@"image is not encrypted");
        return YES;
    }

    if (!rebuildDecryptedImageAtPath(imagePath, task, mainImageInfo.loadAddress, &encryptionInfo, loadCommandAddress, outputPath)) {
        NSLog(@"failed to rebuild decrypted image for pid %d", pid);
        return NO;
    }

    return YES;   
}

- (BOOL)_buildIPAWithName:(NSString *)ipaName {
    NSString *ipaPath = [ROOT_OUTPUT_PATH stringByAppendingPathComponent:ipaName];

    NSError *error = nil;
    if ([_fileManager fileExistsAtPath:ipaPath]) {
        [_fileManager removeItemAtPath:ipaPath error:&error];
        if (error) {
            NSLog(@"Failed to remove existing IPA at path %@, error: %@", ipaPath, error);
            return NO;
        }
    }


    // NSError *zipError = nil;
    // NSLog(@"_workingDirectoryPath: %@", _workingDirectoryPath);

    // MFFileArchive *archive = [objc_getClass("MFFileArchive") archive];
    // NSURL *workingDirURL = [NSURL fileURLWithPath:_workingDirectoryPath isDirectory:YES];
    // NSMutableData *zipData = [archive compressFolder:workingDirURL error:&zipError];
    // if (zipError) {
    //     NSLog(@"failed to create zip archive: %@", zipError);
    //     return NO;
    // }


    // zip ROOT_OUTPUT_PATH/.work/Payload to ROOT_OUTPUT_PATH/outputIPAName
    NSDate *methodStart = [NSDate date];
    NSLog(@"Zipping IPA to path: %@", ipaPath);
    NSLog(@"_workingDirectoryPath: %@", _workingDirectoryPath);
    

    BOOL success = [SSZipArchive createZipFileAtPath:ipaPath withContentsOfDirectory:_workingDirectoryPath];
    if (!success) {
        NSLog(@"failed to create zip archive at path: %@", ipaPath);
        return NO;
    }

    // void(^ _Nullable progressHandler)(NSUInteger entryNumber, NSUInteger total) = ^(NSUInteger entryNumber, NSUInteger total) {
    //     NSLog(@"Zipping progress: %lu / %lu", (unsigned long)entryNumber, (unsigned long)total);
    // };

    // bool success = [SSZipArchive createZipFileAtPath:ipaPath
    //                          withContentsOfDirectory:_workingDirectoryPath
    //                              keepParentDirectory:NO
    //                                     withPassword:nil
    //                               andProgressHandler:progressHandler];
    if (!success) {
        NSLog(@"failed to create zip archive at path: %@", ipaPath);
        return NO;
    }

    NSTimeInterval methodEnd = -[methodStart timeIntervalSinceNow];
    NSLog(@"Zipping IPA took %.3f seconds", methodEnd);

    NSLog(@"Successfully created IPA at path %@", ipaPath);

    // Clean up working directory
    NSError *cleanupError = nil;
    [_fileManager removeItemAtPath:_workingDirectoryPath error:&cleanupError];
    if (cleanupError) {
        NSLog(@"failed to clean up working directory: %@, error: %@", _workingDirectoryPath, cleanupError);
        return NO;
    }

    NSLog(@"Successfully created IPA at path %@", ipaPath);
    return YES;
}

- (BOOL)createOutputDirectoryIfNeeded {
    BOOL isDirectory = NO;
    if ([_fileManager fileExistsAtPath:ROOT_OUTPUT_PATH isDirectory:&isDirectory]) {
        return isDirectory;
    }

    NSError *error = nil;
    [_fileManager createDirectoryAtPath:ROOT_OUTPUT_PATH withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) {
        NSLog(@"Error creating output directory: %@", error);
        return NO;
    }

    return YES;
}

- (BOOL)_copyApplicationBundle {
    NSString *workingPath = [ROOT_OUTPUT_PATH stringByAppendingPathComponent:@".work"];

    NSError *error = nil;
    if ([_fileManager fileExistsAtPath:workingPath]) {
        [_fileManager removeItemAtPath:workingPath error:&error];
        if (error) {
            NSLog(@"Failed to remove existing working directory: %@, error: %@", workingPath, error);
            return NO;
        }
    }

    NSString *payloadPath = [workingPath stringByAppendingPathComponent:@"Payload"];

    NSError *copyError = nil;
    [_fileManager createDirectoryAtPath:payloadPath withIntermediateDirectories:YES attributes:nil error:&copyError];
    if (copyError) {
        NSLog(@"Failed to create Payload directory: %@, error: %@", payloadPath, copyError);
        return NO;
    }

    _destinationPath = [payloadPath stringByAppendingPathComponent:[_applicationProxy.bundleURL lastPathComponent]];
    copyError = nil;
    [_fileManager copyItemAtURL:_applicationProxy.bundleURL toURL:[NSURL fileURLWithPath:_destinationPath] error:&copyError];
    if (copyError) {
        NSLog(@"Failed to copy application bundle to %@, error: %@", _destinationPath, copyError);
        return NO;
    }

    _workingDirectoryPath = workingPath;
    return YES;
}

@end
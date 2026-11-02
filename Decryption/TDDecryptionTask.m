#import "TDDecryptionTask.h"
#import "TDError.h"
#import "Extensions/LSApplicationProxy+AltList.h"
#import "Localize.h"

#import "LaunchdResponse.h"
#import "MemoryUtilities.h"
#import "MachOInspection.h"
#import "SuspendedDecryption.h"
#import "DecryptionOutput.h"
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

@interface TDDecryptionTask ()
@property (nonatomic, readwrite) BOOL hasUndecryptedFiles;
@end

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

        self.hasUndecryptedFiles = NO;
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

        // Without embedded frameworks, there is no reason to let dyld or app code run.
        // Keeping the main executable suspended also avoids startup exits and side effects.
        NSString *embeddedFrameworks = [self->_applicationProxy.bundleURL.path stringByAppendingPathComponent:@"Frameworks"];
        BOOL needsRunningApp = [self->_fileManager contentsOfDirectoryAtPath:embeddedFrameworks error:nil].count > 0;
        LaunchdResponse_t response = needsRunningApp ? [self->_applicationProxy td_launchProcess] : NIL_LAUNCHD_RESPONSE;
        if (needsRunningApp && response.pid <= 0) {
            NSLog(@"Application %@ could not start normally; trying suspended decryption", bundleIdentifier);
        }

        pid_t targetPID = response.pid;
        @try {

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
                status = targetPID > 0 && [self decryptImageAtPath:imagePath forPID:targetPID outputPath:fullOutputPath];
            } else {
                status = targetPID > 0 && [self decryptImageAtPath:imagePath forPID:targetPID];
            }

            if (!status) {
                NSString *outputExecutable = fullOutputPath ?: [self->_destinationPath stringByAppendingPathComponent:imagePath.lastPathComponent];
                NSError *decryptError = nil;
                status = TDWriteDecryptionOutput(imagePath, outputExecutable, ^BOOL(NSString *stagedPath, NSError **attemptError) {
                    return TDDecryptSuspendedExecutable(self->_applicationProxy.bundleURL.path, stagedPath, attemptError);
                }, &decryptError);
                if (!status) {
                    if (options.decryptBinaryOnly) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (completionHandler) completionHandler(NO, nil, decryptError);
                        });
                        return;
                    }
                    self.hasUndecryptedFiles = YES;
                    NSLog(@"Keeping original main executable %@: %@", imagePath, decryptError);
                }
            }

            if (options.decryptBinaryOnly) {
                progress([Localize localizedStringForKey:@"DECRYPTION_COMPLETED"]);

                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completionHandler) completionHandler(YES, [NSURL fileURLWithPath:fullOutputPath], nil);
                });
                return;
            }

            NSString *originalAppPath = self->_applicationProxy.bundleURL.path.stringByResolvingSymlinksInPath;
            NSString *frameworksPath = [originalAppPath stringByAppendingPathComponent:@"Frameworks"];
            NSError *fsError = nil;
            NSArray *frameworkContents = [self->_fileManager contentsOfDirectoryAtPath:frameworksPath error:&fsError];
            if (!fsError && frameworkContents.count > 0) {
                NSInteger frameworkCount = 0;
                for (NSString *item in frameworkContents) {
                    if ([item hasSuffix:@".framework"]) frameworkCount++;
                }
                NSInteger currentFrameworkIndex = 0;
                for (NSString *item in frameworkContents) {
                    if ([item hasSuffix:@".framework"]) {
                        currentFrameworkIndex++;
                        NSString *frameworkName = [item stringByDeletingPathExtension]; 
                        NSString *frameworkBinaryPath = [[frameworksPath stringByAppendingPathComponent:item] stringByAppendingPathComponent:frameworkName]; 
                        if ([self->_fileManager fileExistsAtPath:frameworkBinaryPath]) {
                            progress([NSString stringWithFormat:@"Decrypting framework %ld/%ld: %@...", (long)currentFrameworkIndex, (long)frameworkCount, frameworkName]);
                            if (![self decryptImageAtPath:frameworkBinaryPath forPID:targetPID]) {
                                self.hasUndecryptedFiles = YES;
                                NSLog(@"Keeping original framework %@", item);
                            }
                        }
                    }
                }
            }

            NSError *extensionError = nil;
            NSArray<NSString *> *extensions = TDExtensionBundles(originalAppPath, &extensionError);
            if (extensionError) {
                self.hasUndecryptedFiles = YES;
                NSLog(@"Some extensions could not be enumerated; keeping their original files: %@", extensionError);
            }
            NSInteger currentExtensionIndex = 0;
            for (NSString *bundlePath in extensions) {
                currentExtensionIndex++;
                progress([NSString stringWithFormat:@"Decrypting extension %ld/%ld: %@...",
                    (long)currentExtensionIndex, (long)extensions.count, bundlePath.lastPathComponent]);
                NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[bundlePath stringByAppendingPathComponent:@"Info.plist"]];
                NSString *executable = info[@"CFBundleExecutable"];
                NSString *relativeBundle = [bundlePath substringFromIndex:originalAppPath.length + 1];
                if (![executable isKindOfClass:NSString.class] || !executable.length ||
                    ![executable isEqualToString:executable.lastPathComponent]) {
                    self.hasUndecryptedFiles = YES;
                    continue;
                }
                NSString *outputBundle = [self->_destinationPath stringByAppendingPathComponent:relativeBundle];
                NSString *outputExecutable = [outputBundle stringByAppendingPathComponent:executable];
                NSError *decryptError = nil;
                NSString *sourceExecutable = [bundlePath stringByAppendingPathComponent:executable];
                if (!TDWriteDecryptionOutput(sourceExecutable, outputExecutable, ^BOOL(NSString *stagedPath, NSError **attemptError) {
                    return TDDecryptSuspendedExecutable(bundlePath, stagedPath, attemptError);
                }, &decryptError)) {
                    NSLog(@"Keeping original extension %@: %@", relativeBundle, decryptError);
                    self.hasUndecryptedFiles = YES;
                }
            }

            NSError *inspectionError = nil;
            NSArray<NSString *> *encrypted = TDEncryptedFilesInBundle(self->_destinationPath, &inspectionError);
            if (!encrypted || encrypted.count) {
                self.hasUndecryptedFiles = YES;
                NSLog(@"Exporting with remaining encrypted or unverified files: %@ (%@)", encrypted, inspectionError);
            }

            // A skipped binary still needs its original FairPlay metadata. Clean SC_Info
            // only when the entire corresponding output bundle is confirmed decrypted.
            NSMutableArray<NSString *> *outputBundles = [NSMutableArray arrayWithObject:self->_destinationPath];
            for (NSString *bundlePath in extensions) {
                NSString *relative = [bundlePath substringFromIndex:originalAppPath.length + 1];
                [outputBundles addObject:[self->_destinationPath stringByAppendingPathComponent:relative]];
            }
            for (NSString *outputBundle in outputBundles) {
                NSString *scInfo = [outputBundle stringByAppendingPathComponent:@"SC_Info"];
                if (![self->_fileManager fileExistsAtPath:scInfo]) continue;
                if (!encrypted) continue;
                NSString *prefix = [outputBundle isEqualToString:self->_destinationPath] ? @""
                    : [[outputBundle substringFromIndex:self->_destinationPath.length + 1] stringByAppendingString:@"/"];
                BOOL needsMetadata = [outputBundle isEqualToString:self->_destinationPath] ? encrypted.count > 0 :
                    [encrypted indexOfObjectPassingTest:^BOOL(NSString *path, NSUInteger idx, BOOL *stop) {
                    return [path hasPrefix:prefix];
                }] != NSNotFound;
                if (!needsMetadata) {
                    NSError *cleanupError = nil;
                    if (![self->_fileManager removeItemAtPath:scInfo error:&cleanupError]) {
                        NSLog(@"Keeping SC_Info at %@: %@", scInfo, cleanupError);
                    }
                }
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

            progress([Localize localizedStringForKey:@"DECRYPTION_COMPLETED"]);

            NSString *ipaPath = [ROOT_OUTPUT_PATH stringByAppendingPathComponent:outputIPAName];
            NSURL *url = [NSURL fileURLWithPath:ipaPath];

            dispatch_async(dispatch_get_main_queue(), ^{
                if (completionHandler) completionHandler(YES, url, nil);
            });
        } @finally {
            if (targetPID > 0) kill(targetPID, SIGKILL);
            if (self->_workingDirectoryPath) {
                [self->_fileManager removeItemAtPath:self->_workingDirectoryPath error:nil];
            }
        }
    });
}


- (BOOL)decryptImageAtPath:(NSString *)imagePath forPID:(pid_t)pid {
    NSString *delimeter = [_destinationPath lastPathComponent]; // XXX.app
    NSString *rhs = [imagePath componentsSeparatedByString:delimeter].lastObject;
    NSString *outputPath = [_destinationPath stringByAppendingString:rhs];

    return [self decryptImageAtPath:imagePath forPID:pid outputPath:outputPath];
}

- (BOOL)decryptImageAtPath:(NSString *)imagePath forPID:(pid_t)pid outputPath:(NSString *)outputPath {
    NSArray<TDMachOImage *> *sourceImages = TDInspectMachO(imagePath, nil);
    if (!sourceImages.count) return NO;
    BOOL encrypted = [sourceImages indexOfObjectPassingTest:^BOOL(TDMachOImage *image, NSUInteger idx, BOOL *stop) {
        return image.encryption.cryptid != 0;
    }] != NSNotFound;
    if (!encrypted) return TDWriteDecryptionOutput(imagePath, outputPath, ^BOOL(NSString *stagedPath, NSError **attemptError) { return YES; }, nil);
    // The running-process rebuilder uses thin-image file offsets. Other layouts must
    // use the suspended path or be retained unchanged rather than patching wrong bytes.
    TDMachOImage *sourceImage = sourceImages.firstObject;
    if (sourceImages.count != 1 || sourceImage.fileOffset != 0 ||
        sourceImage.encryptedVMOffset != sourceImage.encryption.cryptoff) return NO;
    vm_map_t task = 0;
    if (task_for_pid(mach_task_self(), pid, &task)) {
        NSLog(@"failed to get task for pid %d", pid);
        return NO;
    }

    @try {
        MainImageInfo_t mainImageInfo = imageInfoForPIDWithRetry([imagePath UTF8String], task, pid);
        if (!mainImageInfo.ok) {
            NSLog(@"failed to get main image load address for pid %d", pid);
            return NO;
        }

        NSLog(@"main image info: %@", NSStringFromMainImageInfo(mainImageInfo));

        __block struct encryption_info_command encryptionInfo = {0};
        uint64_t loadCommandAddress = 0;
        if (!readEncryptionInfo(task, mainImageInfo.loadAddress, &encryptionInfo, &loadCommandAddress)) {
            NSLog(@"failed to read encryption info for pid %d", pid);
            return NO;
        }

        NSLog(@"encryption info: cryptoff=0x%x cryptsize=0x%x cryptid=%d",
              encryptionInfo.cryptoff, encryptionInfo.cryptsize, encryptionInfo.cryptid);
        if (encryptionInfo.cryptoff != sourceImage.encryption.cryptoff ||
            encryptionInfo.cryptsize != sourceImage.encryption.cryptsize) return NO;

        return TDWriteDecryptionOutput(imagePath, outputPath, ^BOOL(NSString *stagedPath, NSError **attemptError) {
            return rebuildDecryptedImageAtPath(imagePath, task, mainImageInfo.loadAddress,
                &encryptionInfo, loadCommandAddress, stagedPath);
        }, nil);
    } @finally {
        mach_port_deallocate(mach_task_self(), task);
    }
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
    NSString *workingPath = [ROOT_OUTPUT_PATH stringByAppendingPathComponent:
        [@".work-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    _workingDirectoryPath = workingPath;

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

#import "DecryptionOutput.h"
#import "MachOInspection.h"
#import <stdio.h>

BOOL TDWriteDecryptionOutput(NSString *sourcePath, NSString *outputPath,
                            BOOL (^attempt)(NSString *stagedPath, NSError **attemptError), NSError **error) {
    NSFileManager *fm = NSFileManager.defaultManager;
    sourcePath = sourcePath.stringByResolvingSymlinksInPath;
    NSString *outputLocation = [outputPath.stringByDeletingLastPathComponent.stringByResolvingSymlinksInPath
        stringByAppendingPathComponent:outputPath.lastPathComponent];
    if ([sourcePath isEqualToString:outputLocation]) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteInvalidFileNameError
            userInfo:@{NSFilePathErrorKey:outputPath}];
        return NO;
    }
    NSString *stagedPath = [outputPath stringByAppendingFormat:@".%@.staged", NSUUID.UUID.UUIDString];
    @try {
        // Each attempt may truncate or patch its output before failing. Keep the original
        // bundle copy intact until the entire attempt, including helper cleanup, succeeds.
        // Resolve the source before copying: an absolute symlink in the staging file
        // would let an in-place writer truncate the installed executable instead.
        if (![fm copyItemAtPath:sourcePath toPath:stagedPath error:error]) return NO;
        if (!attempt(stagedPath, error)) return NO;
        NSArray<TDMachOImage *> *images = TDInspectMachO(stagedPath, error);
        if (!images.count || [images indexOfObjectPassingTest:^BOOL(TDMachOImage *image, NSUInteger idx, BOOL *stop) {
            return image.encryption.cryptid != 0;
        }] != NSNotFound) {
            if (error && !*error) *error = [NSError errorWithDomain:@"com.fiore.TDError" code:102
                userInfo:@{NSLocalizedDescriptionKey:@"The output is not a complete decrypted executable."}];
            return NO;
        }
        if (rename(stagedPath.fileSystemRepresentation, outputPath.fileSystemRepresentation) != 0) {
            if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno
                userInfo:@{NSFilePathErrorKey:outputPath}];
            return NO;
        }
        return YES;
    } @catch (NSException *exception) {
        if (error) *error = [NSError errorWithDomain:@"com.fiore.TDError" code:102
            userInfo:@{NSLocalizedDescriptionKey:exception.reason ?: @"Decryption failed."}];
        return NO;
    } @finally {
        [fm removeItemAtPath:stagedPath error:nil];
    }
}

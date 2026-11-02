#import <Foundation/Foundation.h>

BOOL TDWriteDecryptionOutput(NSString *sourcePath, NSString *outputPath,
                            BOOL (^attempt)(NSString *stagedPath, NSError **attemptError), NSError **error);

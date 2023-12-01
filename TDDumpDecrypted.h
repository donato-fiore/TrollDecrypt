@interface DumpDecrypted : NSObject {
	char decryptedAppPathStr[PATH_MAX];
	char *filename;
	char *appDirName;
	char *appDirPath;
}

@property (assign) NSString *appPath;
@property (assign) NSString *docPath;
@property (assign) NSString *appName;
@property (assign) NSString *appVersion;

- (id)initWithPathToBinary:(NSString *)pathToBinary appName:(NSString *)appName appVersion:(NSString *)appVersion;
- (void)createIPAFile:(pid_t)pid;
- (BOOL)dumpDecryptedImage:(const struct mach_header *)image_mh fileName:(const char *)encryptedImageFilenameStr image:(int)imageNum task:(vm_map_t)targetTask;
- (NSString *)IPAPath;
@end
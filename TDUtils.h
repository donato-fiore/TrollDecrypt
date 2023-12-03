#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <mach-o/loader.h>
#include <mach-o/dyld_images.h>
#include <fcntl.h>
#include <mach/task_info.h>

#import <sys/sysctl.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@interface UIApplication (tweakName)
+ (id)sharedApplication;
- (BOOL)launchApplicationWithIdentifier:(id)arg1 suspended:(BOOL)arg2;
@end

@interface UIImage (Private)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(NSUInteger)format scale:(CGFloat)scale;
@end

#define PROC_PIDPATHINFO                11
#define PROC_PIDPATHINFO_SIZE           (MAXPATHLEN)
#define PROC_PIDPATHINFO_MAXSIZE        (4 * MAXPATHLEN)
#define PROC_ALL_PIDS	            	1

#ifndef DEBUG
#   define NSLog(...) (void)0
#endif

int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
int proc_listpids(uint32_t type, uint32_t typeinfo, void *buffer, int buffersize);
NSArray *appList(void);
NSUInteger iconFormat(void);
NSArray *sysctl_ps(void);
void decryptApp(NSDictionary *app);
void decryptAppWithPID(pid_t pid);
void bfinject_rocknroll(pid_t pid, NSString *appName, NSString *version);
NSArray *decryptedFileList(void);
NSString *docPath(void);
void fetchLatestTrollDecryptVersion(void (^completionHandler)(NSString *version));
void github_fetchLatedVersion(NSString *repo, void (^completionHandler)(NSString *latestVersion));
NSString *trollDecryptVersion(void);
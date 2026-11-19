#import "MachOInspection.h"

// Match the image actually loaded by the target, including CPU subtype and UUID.
TDMachOImage *TDImageMatchingLoadedHeader(NSArray<TDMachOImage *> *images, NSData *header, NSError **error);

// Write only the selected slice into a disposable staging file. Offsets passed to
// readMemory are relative to the loaded Mach-O header, not the FAT container.
BOOL TDRebuildMachOSlice(NSString *sourcePath, TDMachOImage *image, NSString *stagedPath,
                        BOOL (^readMemory)(uint64_t offset, void *buffer, size_t size), NSError **error);

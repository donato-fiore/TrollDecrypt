#import <Foundation/Foundation.h>

#define NIL_LAUNCHD_RESPONSE (LaunchdResponse_t){ nil, 0, 0, NO }

typedef struct LaunchdResponse {
    NSUUID *job_handle;
    NSUInteger job_state;
    pid_t pid;
    BOOL removing;
} LaunchdResponse_t;

LaunchdResponse_t responseFromXPCObject(xpc_object_t responseObj);
NSString *NSStringFromLaunchdResponse(LaunchdResponse_t response);


typedef NS_ENUM(int, OSLaunchdJobSelector) {
    OSLaunchdJobSelectorSubmitAndStart        = 1000, // Submit a job to launchd and immediately start it
    OSLaunchdJobSelectorMonitor               = 1001, // Register for job state change notifications
    OSLaunchdJobSelectorRemove                = 1003, // Remove a job from launchd
    OSLaunchdJobSelectorCopyJobsManagedBy     = 1004, // Copy jobs managed by a specific domain or owner
    OSLaunchdJobSelectorCopyJobWithLabel      = 1005, // Lookup a job by label and domain
    OSLaunchdJobSelectorStart                 = 1006, // Start an already-submitted job
    OSLaunchdJobSelectorSubmitExtension       = 1007, // Submit an extension or overlay job
    OSLaunchdJobSelectorCopyJobWithPID        = 1008, // Lookup the launchd job owning a PID
    OSLaunchdJobSelectorPropertiesForRB       = 1009, // Extract RunningBoard properties for a job
    OSLaunchdJobSelectorCreateInstance        = 1010, // Create a new instance of an instance-based job
    OSLaunchdJobSelectorSubmit                = 1011, // Submit a job without starting it
    OSLaunchdJobSelectorCopyJobWithHandle     = 1013, // Lookup a job using an opaque launchd handle
    OSLaunchdJobSelectorSubmitAll             = 1014, // Submit multiple jobs in a single operation
    OSLaunchdJobSelectorGetCurrentJobInfo     = 1015  // Query the current state and info of a job
};

kern_return_t _launch_job_routine(OSLaunchdJobSelector selector, xpc_object_t request, id *response);
xpc_object_t _CFXPCCreateXPCObjectFromCFObject(id cfObject);

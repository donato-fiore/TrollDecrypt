#import <Foundation/Foundation.h>

#ifndef XPC_TYPE_DICTIONARY
typedef void* xpc_object_t;
typedef const struct _xpc_type_s* xpc_type_t;

extern const struct _xpc_type_s _xpc_type_dictionary;
extern const struct _xpc_type_s _xpc_type_uuid;
#define XPC_TYPE_DICTIONARY (&_xpc_type_dictionary)
#define XPC_TYPE_UUID (&_xpc_type_uuid)

extern xpc_type_t xpc_get_type(xpc_object_t object);
extern xpc_object_t xpc_dictionary_get_value(xpc_object_t xdict, const char* key);
extern uint64_t xpc_dictionary_get_uint64(xpc_object_t xdict, const char* key);
extern int64_t xpc_dictionary_get_int64(xpc_object_t xdict, const char* key);
extern bool xpc_dictionary_get_bool(xpc_object_t xdict, const char* key);
extern void xpc_dictionary_set_uint64(xpc_object_t xdict, const char* key, uint64_t value);
extern const uint8_t* xpc_uuid_get_bytes(xpc_object_t xuuid);
#endif

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

kern_return_t _launch_job_routine(OSLaunchdJobSelector selector, xpc_object_t request, xpc_object_t *response);
xpc_object_t _CFXPCCreateXPCObjectFromCFObject(id cfObject);

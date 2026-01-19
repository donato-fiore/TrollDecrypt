#import "LaunchdResponse.h"

static NSUUID *NSUUIDFromXPCUUID(xpc_object_t xpcUuid) {
    if (!xpcUuid || xpc_get_type(xpcUuid) != XPC_TYPE_UUID) return nil;

    return [[NSUUID alloc] initWithUUIDBytes:xpc_uuid_get_bytes(xpcUuid)];
}

LaunchdResponse_t responseFromXPCObject(xpc_object_t responseObj) {
    LaunchdResponse_t response = NIL_LAUNCHD_RESPONSE;
    
    if (responseObj) {
        response.job_handle = NSUUIDFromXPCUUID(xpc_dictionary_get_value(responseObj, "job-handle"));
        response.job_state = (NSUInteger)xpc_dictionary_get_uint64(responseObj, "job-state");
        response.pid = (pid_t)xpc_dictionary_get_int64(responseObj, "pid");
        response.removing = xpc_dictionary_get_bool(responseObj, "removing");
    }
    
    return response;
}

NSString *NSStringFromLaunchdResponse(LaunchdResponse_t response) {
    return [NSString stringWithFormat:@"LaunchdResponse: job_handle=%@, job_state=%lu, pid=%d, removing=%d",
            response.job_handle,
            (unsigned long)response.job_state,
          response.pid,
          response.removing];
}
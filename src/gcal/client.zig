//! TODO(GCAL-EVENTS): thin wrapper over std.http.Client for
//! calendar.googleapis.com. Bearer auth from auth.zig, 429/5xx backoff
//! (exponential, respect Retry-After), paginated list for dedupe queries.

pub fn insertEvent() void {
    @panic("TODO(GCAL-EVENTS)");
}

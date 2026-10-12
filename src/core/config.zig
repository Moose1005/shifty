//! TODO(CONFIG): load and validate config.json. Use std.json.parseFromSlice
//! into a typed struct with all fields required (no defaults — fail loudly;
//! the "raise over .get defaults" rule). Validate: name non-empty, month 1-12,
//! reminders sorted or not (your choice, document it), timezone string is
//! tzdata-compatible (you'll need an tz->offset table or link libc's localtime
//! for the RFC3339 timestamps Google expects).

const std = @import("std");

pub const Config = struct {
    name: []const u8,
    year: u16,
    month: u8,
    office_address: []const u8,
    timezone: []const u8,
    reminders_minutes: []const i32, // 1440 = day before, 0 = day of, 60 = 1h before
    calendar_id: []const u8,
    palette: []const []const u8, // Google colorId strings, e.g. "1".."11"
};

pub fn load(allocator: std.mem.Allocator, path: []const u8) !Config {
    _ = allocator;
    _ = path;
    @panic("TODO(CONFIG)");
}

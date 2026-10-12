//! Step 2: config.json loader. Typed parse + loud validation.
//! Rule: NO defaults for required fields — a missing/typo'd field is an
//! error at load time, not a silent surprise at calendar-write time.

const std = @import("std");

pub const Error = error{
    ConfigReadFailed,
    ConfigParseFailed,
    InvalidConfig,
    OutOfMemory,
};

pub const Config = struct {
    name: []const u8,
    year: u16,
    month: u8, // 1-12
    office_address: []const u8,
    timezone: []const u8, // IANA name, e.g. "America/Toronto" (used in Step 3+)
    reminders_minutes: []const i32, // e.g. {1440, 0, 60} = day before, day of, 1h before
    calendar_id: []const u8, // "primary" or a calendar's email-style id
    palette: []const []const u8, // Google colorId strings "1".."11"

    pub fn validate(self: Config) Error!void {
        if (self.name.len == 0) return Error.InvalidConfig;
        if (self.month < 1 or self.month > 12) return Error.InvalidConfig;
        if (self.office_address.len == 0) return Error.InvalidConfig;
        if (self.timezone.len == 0) return Error.InvalidConfig;
        if (self.calendar_id.len == 0) return Error.InvalidConfig;
        if (self.palette.len == 0) return Error.InvalidConfig;
        for (self.reminders_minutes) |m| {
            if (m < 0) return Error.InvalidConfig;
        }
    }
};

/// Load + validate config.json. `io` is threaded in (0.17 file API lives in
/// std.Io); callers pass init.io, tests pass std.Io.Threaded.global_single_threaded.io().
pub fn load(allocator: std.mem.Allocator, io: std.Io, path: []const u8) Error!std.json.Parsed(Config) {
    const text = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, std.Io.Limit.limited(1024 * 1024)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return Error.ConfigReadFailed,
    };
    // alloc_always below means parsed strings are copies — text can be freed.
    defer allocator.free(text);
    const parsed = std.json.parseFromSlice(Config, allocator, text, .{
        .ignore_unknown_fields = false, // typo'd key = loud error, not silent drop
        .allocate = .alloc_always, // strings/buffers owned by caller's allocator
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return Error.ConfigParseFailed,
    };
    try parsed.value.validate();
    return parsed; // caller owns; .deinit() frees the strings
}

test "validate rejects bad month" {
    const c = Config{
        .name = "Moe",
        .year = 2026,
        .month = 13,
        .office_address = "x",
        .timezone = "America/Toronto",
        .reminders_minutes = &.{1440, 0, 60},
        .calendar_id = "primary",
        .palette = &.{"1"},
    };
    try std.testing.expectError(Error.InvalidConfig, c.validate());
}

test "validate rejects negative reminder" {
    const c = Config{
        .name = "Moe",
        .year = 2026,
        .month = 10,
        .office_address = "x",
        .timezone = "America/Toronto",
        .reminders_minutes = &.{-5},
        .calendar_id = "primary",
        .palette = &.{"1"},
    };
    try std.testing.expectError(Error.InvalidConfig, c.validate());
}

test "load parses example config" {
    const io = std.Io.Threaded.global_single_threaded.io();
    var parsed = try load(std.testing.allocator, io, "config.example.json");
    defer parsed.deinit();
    const cfg = parsed.value;
    try std.testing.expectEqualStrings("Moe", cfg.name);
    try std.testing.expectEqual(@as(u8, 10), cfg.month);
    try std.testing.expectEqual(@as(usize, 3), cfg.reminders_minutes.len);
}

test "load fails loudly on missing file" {
    const io = std.Io.Threaded.global_single_threaded.io();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(Error.ConfigReadFailed, load(arena.allocator(), io, "config.DOESNOTEXIST.json"));
}

test "parse fails loudly on typo'd key" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const bad = "{\"name\":\"Moe\",\"yer\":2026,\"month\":10,\"office_address\":\"x\",\"timezone\":\"t\",\"reminders_minutes\":[60],\"calendar_id\":\"primary\",\"palette\":[\"1\"]}";
    // any error = pass; a successful parse of a typo'd-key doc = fail
    if (std.json.parseFromSlice(Config, arena.allocator(), bad, .{
        .ignore_unknown_fields = false,
        .allocate = .alloc_always,
    })) |_| {
        try std.testing.expect(false);
    } else |_| {}
}

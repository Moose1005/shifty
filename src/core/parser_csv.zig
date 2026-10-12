//! CSV parser for the weekly-matrix schedule export. (Step 1 — implemented)
//! Layout (empirically verified against the real Oct 2026 export):
//!   row k:   " Sunday,,Monday,, ... ,Saturday,"   <- repeated per week block
//!   row k+1: " 4,,5,,6,,7,,8,,9,,10,"             <- date numbers
//!   row k+2..: "Name,,,15:00:00,23:00:00, ..."    <- 2 cols per day: start,end
//! Gotchas handled: BOM, blank separator rows, ragged rows (missing trailing
//! commas), overnight shifts (end <= start -> end is NEXT day), name match is
//! case-insensitive + trimmed. Nothing about the target person is hardcoded:
//! `opts.name` comes from config/CLI.

const std = @import("std");
const types = @import("types.zig");

pub const Options = struct {
    name: []const u8, // e.g. "Moe" — from config, never hardcoded
    year: u16,
    month: u8, // 1-12
};

pub const ParseResult = struct {
    shifts: std.ArrayList(types.Shift),

    pub fn deinit(self: *ParseResult, allocator: std.mem.Allocator) void {
        self.shifts.deinit(allocator);
    }
};

pub const Error = error{
    NameNotFound,
    NoWeekBlocks,
    BadTimeField,
    BadDateField,
    MalformedShiftRow, // exactly one of start/end filled for a day
    OutOfMemory,
};

const WEEKDAYS = [_][]const u8{ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" };

const SUNDAY_COL = 1; // day d occupies columns 1+2d (start) and 2+2d (end)

fn cellAt(row: []const []const u8, idx: usize) []const u8 {
    return if (idx < row.len) row[idx] else ""; // ragged-row safe
}

fn isHeaderRow(fields: []const []const u8) bool {
    if (fields.len < SUNDAY_COL + 2 * 7) return false;
    for (WEEKDAYS, 0..) |wd, d| {
        const cell = std.mem.trim(u8, cellAt(fields, SUNDAY_COL + d * 2), " \t\r");
        if (!std.ascii.eqlIgnoreCase(cell, wd)) return false;
    }
    return true;
}

fn parseTime(cell_in: []const u8) ?u16 {
    // Accepts "15:00:00", "7:00", "7:00:00" — hours are NOT fixed-width,
    // split at the first colon. Also tolerates Excel datetime spill like
    // "1899-12-30T15:00:00" (takes the part after 'T' if present).
    var cell = std.mem.trim(u8, cell_in, " \t\r");
    if (std.mem.indexOfScalar(u8, cell, 'T')) |t_idx| cell = cell[t_idx + 1 ..];
    const colon = std.mem.indexOfScalar(u8, cell, ':') orelse return null;
    const h = std.fmt.parseInt(u16, cell[0..colon], 10) catch return null;
    const rest = cell[colon + 1 ..];
    if (rest.len < 2) return null;
    const m = std.fmt.parseInt(u16, rest[0..2], 10) catch return null;
    if (h > 24 or m > 59) return null;
    return h * 60 + m;
}

fn makeDate(year: u16, month: u8, day: u8) types.Date {
    return .{ .year = year, .month = month, .day = day };
}

/// Full parse. Returns shifts in file order (week blocks top to bottom,
/// Sunday->Saturday within a week). Caller owns result (deinit).
pub fn parseCsv(allocator: std.mem.Allocator, text: []const u8, opts: Options) Error!ParseResult {
    var shifts: std.ArrayList(types.Shift) = .empty;
    errdefer shifts.deinit(allocator);

    var found_name = false;
    var saw_header = false;
    var expect_date_row = false;
    var dates: [7]u8 = undefined;
    var line_no: usize = 0;

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        line_no += 1;
        var line = raw;
        if (line_no == 1) line = std.mem.trimStart(u8, line, "\xef\xbb\xbf"); // BOM

        var fields: std.ArrayList([]const u8) = .empty;
        defer fields.deinit(allocator);
        var fit = std.mem.splitScalar(u8, line, ',');
        while (fit.next()) |f| try fields.append(allocator, f);
        const row = fields.items;

        if (isHeaderRow(row)) {
            saw_header = true;
            expect_date_row = true;
            continue;
        }

        if (expect_date_row) {
            expect_date_row = false;
            for (0..7) |d| {
                const cell = std.mem.trim(u8, cellAt(row, SUNDAY_COL + d * 2), " \t\r");
                dates[d] = std.fmt.parseInt(u8, cell, 10) catch return Error.BadDateField;
                if (dates[d] < 1 or dates[d] > 31) return Error.BadDateField;
            }
            continue;
        }

        const name = std.mem.trim(u8, cellAt(row, 0), " \t\r");
        if (name.len == 0) continue; // blank separator row
        if (!std.ascii.eqlIgnoreCase(name, opts.name)) continue;

        found_name = true;
        for (0..7) |d| {
            const s_cell = std.mem.trim(u8, cellAt(row, SUNDAY_COL + d * 2), " \t\r");
            const e_cell = std.mem.trim(u8, cellAt(row, SUNDAY_COL + d * 2 + 1), " \t\r");
            if (s_cell.len == 0 and e_cell.len == 0) continue;
            if (s_cell.len == 0 or e_cell.len == 0) return Error.MalformedShiftRow;
            const sm = parseTime(s_cell) orelse return Error.BadTimeField;
            const em = parseTime(e_cell) orelse return Error.BadTimeField;

            const date = makeDate(opts.year, opts.month, dates[d]);
            const end_date = if (em <= sm) date.nextDay() else date; // overnight
            try shifts.append(allocator, .{
                .date = date,
                .end_date = end_date,
                .start_minutes = sm,
                .end_minutes = em,
            });
        }
    }

    if (!saw_header) return Error.NoWeekBlocks;
    if (!found_name) return Error.NameNotFound;
    return .{ .shifts = shifts };
}

test "overnight detection" {
    const s = types.Shift{
        .date = .{ .year = 2026, .month = 10, .day = 25 },
        .end_date = .{ .year = 2026, .month = 10, .day = 26 },
        .start_minutes = 23 * 60,
        .end_minutes = 7 * 60,
    };
    try std.testing.expect(s.isOvernight());
    try std.testing.expectEqual(@as(u16, 8 * 60), s.durationMinutes());
}

test "parseTime forms" {
    try std.testing.expectEqual(@as(?u16, 15 * 60), parseTime("15:00:00"));
    try std.testing.expectEqual(@as(?u16, 7 * 60), parseTime("7:00"));
    try std.testing.expectEqual(@as(?u16, 2 * 60 + 30), parseTime("1899-12-30T02:30:00"));
    try std.testing.expectEqual(@as(?u16, null), parseTime(""));
    try std.testing.expectEqual(@as(?u16, null), parseTime("banana"));
}

test "parseCsv on a synthetic mini-sheet" {
    const sheet =
        " ,Sunday,,Monday,,Tuesday,,Wednesday,,Thursday,,Friday,,Saturday,\n" ++
        ",4,,5,,6,,7,,8,,9,,10,\n" ++
        "Moe,,,,,15:00:00,23:00:00,23:00:00,7:00:00,,,,,,\n" ++
        "Chris,7:00:00,15:00:00,,,,,,,,,,,,\n" ++
        ",,,,,,,,,,,,,,\n" ++
        " ,Sunday,,Monday,,Tuesday,,Wednesday,,Thursday,,Friday,,Saturday,\n" ++
        ",11,,12,,13,,14,,15,,16,,17,\n" ++
        "Moe,9:00:00,17:00:00,,,,,,,,,,,,\n";
    var r = try parseCsv(std.testing.allocator, sheet, .{ .name = "moe", .year = 2026, .month = 10 });
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 3), r.shifts.items.len);

    // Tue Oct 6, 15:00-23:00 (day index 2 -> col 5)
    try std.testing.expectEqual(@as(u8, 6), r.shifts.items[0].date.day);
    try std.testing.expectEqual(@as(u16, 15 * 60), r.shifts.items[0].start_minutes);
    try std.testing.expectEqual(@as(u16, 23 * 60), r.shifts.items[0].end_minutes);
    try std.testing.expect(!r.shifts.items[0].isOvernight());

    // Wed Oct 7 23:00 -> Thu Oct 8 7:00 overnight
    try std.testing.expect(r.shifts.items[1].isOvernight());
    try std.testing.expectEqual(@as(u8, 8), r.shifts.items[1].end_date.day);

    // next week block: Sun Oct 11 9-17, case-insensitive name matched
    try std.testing.expectEqual(@as(u8, 11), r.shifts.items[2].date.day);
}

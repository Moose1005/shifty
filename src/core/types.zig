const std = @import("std");

/// Minimal civil date. std.time.epoch lost its Date struct in 0.17, and we
/// only need three ops: validity by construction (parser checks ranges),
/// nextDay (overnight rolls), dayOfWeek (pretty printing).
/// Plain integers, no enums — month is 1-12, day is 1-31.
pub const Date = struct {
    year: u16,
    month: u8, // 1-12
    day: u8, // 1-31

    fn isLeapYear(y: u16) bool {
        return (@mod(y, 4) == 0 and @mod(y, 100) != 0) or @mod(y, 400) == 0;
    }

    pub fn daysInMonth(y: u16, m: u8) u8 {
        return switch (m) {
            1, 3, 5, 7, 8, 10, 12 => 31,
            4, 6, 9, 11 => 30,
            2 => if (isLeapYear(y)) 29 else 28,
            else => unreachable,
        };
    }

    pub fn nextDay(self: Date) Date {
        var r = self;
        r.day += 1;
        if (r.day > daysInMonth(r.year, r.month)) {
            r.day = 1;
            r.month += 1;
            if (r.month > 12) {
                r.month = 1;
                r.year += 1;
            }
        }
        return r;
    }

    /// days_from_civil (Howard Hinnant's algorithm): days since 1970-01-01.
    fn toEpochDay(self: Date) i64 {
        var y: i64 = self.year;
        const m: i64 = self.month;
        const d: i64 = self.day;
        if (m <= 2) y -= 1;
        const era = @divFloor(y, 400);
        const yoe = y - era * 400; // [0, 399]
        const mp = @mod(m + 9, 12); // [0,11], Mar=0
        const doy = @divFloor(153 * mp + 2, 5) + d - 1;
        const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + @divFloor(yoe, 400) + doy;
        return era * 146097 + doe - 719468;
    }

    /// 0 = Sunday ... 6 = Saturday. Epoch day 0 (1970-01-01) was a Thursday.
    pub fn dayOfWeek(self: Date) u8 {
        return @intCast(@mod(self.toEpochDay() + 4, 7));
    }
};

/// One parsed shift. `start`/`end` are local wall-clock on `date` / `end_date`.
/// Overnight shifts: end_date = date + 1 day when end <= start.
pub const Shift = struct {
    date: Date, // local date of shift start
    end_date: Date, // == date unless overnight
    start_minutes: u16, // minutes after midnight, local
    end_minutes: u16,

    pub fn isOvernight(self: Shift) bool {
        return self.end_minutes <= self.start_minutes;
    }

    pub fn durationMinutes(self: Shift) u16 {
        if (self.isOvernight()) {
            return (24 * 60 - self.start_minutes) + self.end_minutes;
        }
        return self.end_minutes - self.start_minutes;
    }

    pub fn weekdayOf(self: Shift) []const u8 {
        const names = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
        return names[self.date.dayOfWeek()];
    }
};

pub const ParseError = error{
    NameNotFound,
    NoWeekBlocks,
    BadTimeField,
    BadDateField,
    MalformedShiftRow,
    OutOfMemory,
};

test "date math" {
    const d = Date{ .year = 2026, .month = 10, .day = 31 };
    const n = d.nextDay();
    try std.testing.expectEqual(@as(u16, 2026), n.year);
    try std.testing.expectEqual(@as(u8, 11), n.month);
    try std.testing.expectEqual(@as(u8, 1), n.day);
    // 2026-10-11 was a Sunday -> dayOfWeek 0; 2026-10-06 Tuesday -> 2
    try std.testing.expectEqual(@as(u8, 0), (Date{ .year = 2026, .month = 10, .day = 11 }).dayOfWeek());
    try std.testing.expectEqual(@as(u8, 2), (Date{ .year = 2026, .month = 10, .day = 6 }).dayOfWeek());
    // leap year roll
    try std.testing.expectEqual(@as(u8, 29), (Date{ .year = 2024, .month = 2, .day = 28 }).nextDay().day);
}

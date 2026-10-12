//! shifty — CLI entry point (Step 1: parse + print).
//! Usage: shifty --name Moe --year 2026 --month 10 --in "2026 Schedule (Oct).csv"
//! TUI/GUI frontends will import the same `core` module later.

const std = @import("std");
const core = @import("core");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 0.17: argsAlloc removed -> lazily-decoded iterator (WTF-16 -> UTF-8
    // on demand). Collect into a slice so the parsing loop stays index-based.
    var arg_it = try std.process.args.Iterator.initAllocator(std.process.args, allocator);
    defer arg_it.deinit();
    var args_list: std.ArrayList([]const u8) = .empty;
    defer args_list.deinit(allocator);
    while (arg_it.next()) |a| try args_list.append(allocator, a);
    const args = args_list.items;

    var name: ?[]const u8 = null;
    var in_path: ?[]const u8 = null;
    var year: u16 = 0;
    var month: u8 = 0;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--name")) {
            i += 1;
            name = args[i];
        } else if (std.mem.eql(u8, a, "--in")) {
            i += 1;
            in_path = args[i];
        } else if (std.mem.eql(u8, a, "--year")) {
            i += 1;
            year = try std.fmt.parseInt(u16, args[i], 10);
        } else if (std.mem.eql(u8, a, "--month")) {
            i += 1;
            month = try std.fmt.parseInt(u8, args[i], 10);
        } else {
            std.debug.print("unknown arg: {s}\n", .{a});
            return error.BadArgs;
        }
    }

    if (name == null or in_path == null or year == 0 or month == 0) {
        std.debug.print("usage: shifty --name <you> --year <y> --month <m> --in <csv>\n", .{});
        return error.BadArgs;
    }

    var file = try std.fs.cwd().openFile(in_path.?, .{});
    defer file.close();
    const text = try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
    defer allocator.free(text);

    var result = core.parser_csv.parseCsv(allocator, text, .{
        .name = name.?,
        .year = year,
        .month = month,
    }) catch |err| {
        std.debug.print("parse error: {s}\n", .{@errorName(err)});
        return err;
    };
    defer result.deinit(allocator);

    var out_buf: [8192]u8 = undefined;
    var out_file = std.fs.File.stdout();
    var out_writer = out_file.writer(&out_buf);
    const stdout = &out_writer;
    try stdout.print("{d} shifts for {s}:\n", .{ result.shifts.items.len, name.? });
    for (result.shifts.items) |s| {
        try stdout.print("  {s} {d:0>4}-{d:0>2}-{d:0>2}  {d:0>2}:{d:0>2} -> {d:0>2}:{d:0>2}{s}\n", .{
            s.weekdayOf(),
            s.date.year,
            s.date.month,
            s.date.day,
            s.start_minutes / 60,
            s.start_minutes % 60,
            s.end_minutes / 60,
            s.end_minutes % 60,
            if (s.isOvernight()) " (+1)" else "",
        });
    }
    try out_writer.flush();
}

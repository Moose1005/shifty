//! shifty — CLI entry point (Step 1: parse + print).
//! Usage: shifty --name Moe --year 2026 --month 10 --in "schedule.csv"
//! TUI/GUI frontends will import the same `core` module later.

const std = @import("std");
const core = @import("core");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    // Lazily-decoded args iterator (WTF-16 -> WTF-8 on Windows, handled by std).
    var arg_it = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer arg_it.deinit();
    var args_list: std.ArrayList([]const u8) = .empty;
    while (arg_it.next()) |a| try args_list.append(allocator, a);
    const args = args_list.items;

    var config_path: []const u8 = "config.json";
    var in_path: ?[]const u8 = null;

    var i: usize = 1; // args[0] is the exe path
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--config")) {
            i += 1;
            config_path = args[i];
        } else if (std.mem.eql(u8, a, "--in")) {
            i += 1;
            in_path = args[i];
        } else {
            std.debug.print("unknown arg: {s}\n", .{a});
            return error.BadArgs;
        }
    }

    if (in_path == null) {
        std.debug.print("usage: shifty [--config config.json] --in <csv>\n", .{});
        return error.BadArgs;
    }

    var parsed_cfg = core.config.load(allocator, init.io, config_path) catch |err| {
        std.debug.print("config error ({s}): copy config.example.json to config.json and edit it\n", .{@errorName(err)});
        return err;
    };
    defer parsed_cfg.deinit();
    const cfg = parsed_cfg.value;

    // 0.17: fs API lives in std.Io; cwd + readFileAlloc in one call.
    const text = try std.Io.Dir.cwd().readFileAlloc(init.io, in_path.?, allocator, std.Io.Limit.limited(16 * 1024 * 1024));

    var result = core.parser_csv.parseCsv(allocator, text, .{
        .name = cfg.name,
        .year = cfg.year,
        .month = cfg.month,
    }) catch |err| {
        std.debug.print("parse error: {s}\n", .{@errorName(err)});
        return err;
    };
    defer result.deinit(allocator);

    // Output via std.debug.print: verified-present symbol on both OSes.
    // (A proper buffered stdout helper lands as src/out.zig in Step 2,
    // once, with tests — instead of inline std.Io plumbing per file.)
    std.debug.print("{d} shifts for {s}:\n", .{ result.shifts.items.len, cfg.name });
    for (result.shifts.items) |s| {
        std.debug.print("  {s} {d:0>4}-{d:0>2}-{d:0>2}  {d:0>2}:{d:0>2} -> {d:0>2}:{d:0>2}{s}\n", .{
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
}

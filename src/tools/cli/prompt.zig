const std = @import("std");
const builtin = @import("builtin");

const Printer = @import("printer.zig");
const Constants = @import("constants");
const Logger = @import("logger");

pub const InputStruct = struct {
    required: bool = false,
    validate: ?*const fn (a: []const u8) bool = null,
    invalid_error_msg: ?[]const u8 = null,
    initial_value: ?[]const u8 = null,
};

pub fn input(
    allocator: std.mem.Allocator,
    printer: *Printer,
    stdin: anytype,
    prompt: []const u8,
    opts: InputStruct,
) ![]const u8 {
    try printer.append("{s}", .{prompt}, .{});

    var stdout_buf: [128]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    while (true) {
        if (opts.initial_value) |v| {
            try printer.append("{s} => ", .{v}, .{});
        }
        const read_line = try stdin.takeDelimiterInclusive('\n');
        defer allocator.free(read_line);
        const line = std.mem.trimRight(u8, read_line, "\r\n");

        try stdout.print("\x1b[2K\r", .{}); // clear line
        try stdout.print("\x1b[1A", .{}); // move up one line
        if (opts.required and line.len == 0) {
            try stdout.flush();
            try printer.clearScreen();
            try printer.print();
            continue;
        }

        if (line.len == 0) {
            if (opts.initial_value) |v| {
                try stdout.flush();
                printer.pop(1);
                try printer.append("{s}\n", .{v}, .{});
                return try allocator.dupe(u8, v);
            }
        }

        if (opts.validate) |v_fn| {
            if (!v_fn(line)) {
                try stdout.print("\x1b[2K\r", .{}); // clear line
                if (opts.invalid_error_msg) |e| {
                    try stdout.print("({s})\n", .{e}); // clear line
                }
                try stdout.flush();

                try printer.clearScreen();
                try printer.print();
                continue;
            }
        }
        try stdout.flush();

        const duped_line = try allocator.dupe(u8, line);
        try printer.append("{s}\n", .{duped_line}, .{});
        return duped_line;
    }
}

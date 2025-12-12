const std = @import("std");
const builtin = @import("builtin");

const Printer = @import("printer.zig").Printer;
const Constants = @import("constants");

pub const InputStruct = struct {
    required: bool = false,
    validate: ?*const fn (a: []const u8) bool = null,
    initial_value: ?[]const u8 = null,
};

pub fn input(
    allocator: std.mem.Allocator,
    printer: *Printer,
    stdin: anytype,
    prompt: []const u8,
    opts: InputStruct,
) ![]const u8 {
    const stdout = std.io.getStdOut().writer();
    try printer.append("{s}", .{prompt}, .{});

    while (true) {
        if (opts.initial_value) |v| {
            _ = try stdout.write(v);
            _ = try stdout.write(" => ");
        }

        var read_line = try stdin.readUntilDelimiterAlloc(allocator, '\n', Constants.Default.kb);
        const line = if (builtin.os.tag == .windows) read_line[0 .. read_line.len - 1] else read_line;
        try stdout.print("\x1b[2K\r", .{}); // clear line
        try stdout.print("\x1b[1A", .{}); // move up one line

        if (line.len == 0) {
            if (opts.initial_value) |v| {
                try printer.append("{s}\n", .{v}, .{});
                return try allocator.dupe(u8, v);
            }
        }

        if (opts.required and line.len == 0) {
            allocator.free(read_line);
            try printer.print();
            continue;
        }

        if (opts.validate) |v_fn| {
            if (!v_fn(line)) {
                allocator.free(read_line);
                try stdout.print("\x1b[2K\r", .{}); // clear line
                try printer.print();
                continue;
            }
        }

        try printer.append("{s}\n", .{line}, .{});
        return line;
    }
}

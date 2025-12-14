const std = @import("std");
const builtin = @import("builtin");

const Printer = @import("printer.zig").Printer;
const Constants = @import("constants");
const Logger = @import("logger");

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
    const logger = Logger.get();
    try logger.debugf("prompt input: input prompt={s} opts={any}", .{ prompt, opts }, @src());

    var stdout_buf: [128]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    try printer.append("{s}", .{prompt}, .{});

    while (true) {
        if (opts.initial_value) |v| {
            _ = try stdout.write(v);
            _ = try stdout.write(" => ");
        }
        try logger.debug("prompt input: reading input", @src());
        const read_line = try stdin.takeDelimiterInclusive('\n');
        const line = read_line[0 .. read_line.len - 1];
        try stdout.print("\x1b[2K\r", .{}); // clear line
        try stdout.print("\x1b[1A", .{}); // move up one line

        if (line.len == 0) {
            if (opts.initial_value) |v| {
                try logger.warn("prompt input [optional], line length is zero", @src());
                try printer.append("{s}\n", .{v}, .{});
                return try allocator.dupe(u8, v);
            }
        }

        if (opts.required and line.len == 0) {
            try logger.warn("prompt input [required], line length is zero", @src());
            allocator.free(read_line);
            try printer.print();
            continue;
        }

        if (opts.validate) |v_fn| {
            if (!v_fn(line)) {
                try logger.warn("prompt input [validation] invalid", @src());
                allocator.free(read_line);
                try stdout.print("\x1b[2K\r", .{}); // clear line
                try printer.print();
                continue;
            }
        }

        try printer.append("{s}\n", .{line}, .{});

        try logger.debug("prompt input: input done, flushing stdout", @src());
        try stdout.flush();
        return line;
    }
}

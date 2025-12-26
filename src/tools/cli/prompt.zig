const std = @import("std");
const builtin = @import("builtin");

const Printer = @import("printer.zig");

pub const InputStruct = struct {
    required: bool = false,
    password: bool = false, // still unused — either implement or delete
    validate: ?*const fn ([]const u8) bool = null,
    invalid_error_msg: ?[]const u8 = null,
    initial_value: ?[]const u8 = null,
    compare: ?[]const u8 = null,
};

fn handleInvalid(
    printer: *Printer,
    stdout: anytype,
    opts: InputStruct,
    invalid_attempt: *bool,
) !void {
    try stdout.print("\x1b[2K\r", .{}); // clear line
    try stdout.flush();

    if (!invalid_attempt.*) {
        invalid_attempt.* = true;
        if (opts.invalid_error_msg) |msg| {
            try printer.append("[{s}] ", .{msg}, .{});
            return;
        }
    }

    try printer.clearScreen();
    try printer.print();
}

fn setEchoW(enable: bool) !void {
    const windows = std.os.windows;
    const kernel32 = windows.kernel32;

    const stdout_handle = kernel32.GetStdHandle(windows.STD_INPUT_HANDLE) orelse return error.StdHandleFailed;

    var mode: windows.DWORD = undefined;
    _ = kernel32.GetConsoleMode(stdout_handle, &mode);

    const ENABLE_ECHO_MODE: u32 = 0x0004;
    const new_mode = if (enable) mode | ENABLE_ECHO_MODE else mode & ~ENABLE_ECHO_MODE;
    _ = kernel32.SetConsoleMode(stdout_handle, new_mode);
}

fn setEcho(fd: std.posix.fd_t, enable: bool) !void {
    var termios: std.posix.termios = try std.posix.tcgetattr(fd);
    termios.lflag.ECHO = enable;
    try std.posix.tcsetattr(fd, .NOW, termios);
}

pub fn input(
    allocator: std.mem.Allocator,
    printer: *Printer,
    prompt: []const u8,
    opts: InputStruct,
) ![]const u8 {
    var stdin_buf: [128]u8 = undefined;
    var reader = std.fs.File.stdin().reader(&stdin_buf);
    const stdin = &reader.interface;

    if (opts.password) {
        switch (builtin.os.tag) {
            .windows => try setEchoW(false),
            else => try setEcho(false, reader.file.handle),
        }
        defer {
            switch (builtin.os.tag) {
                .windows => setEchoW(true) catch {},
                else => setEcho(true, reader.file.handle) catch {},
            }
        }
    } else {
        switch (builtin.os.tag) {
            .windows => try setEchoW(true),
            else => try setEcho(true, reader.file.handle),
        }
    }

    try printer.append("{s}", .{prompt}, .{});

    var stdout_buf: [128]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;

    var invalid_attempt = false;

    while (true) {
        if (opts.initial_value) |v| {
            try printer.append("{s} => ", .{v}, .{});
        }

        const raw = try stdin.takeDelimiterInclusive('\n');
        defer allocator.free(raw);

        const line = std.mem.trimRight(u8, raw, "\r\n");

        try stdout.print("\x1b[2K\r\x1b[1A", .{}); // clear + move up

        // Required check
        if (opts.required and line.len == 0) {
            try stdout.flush();
            try printer.clearScreen();
            try printer.print();
            continue;
        }

        // Empty input => initial value
        if (line.len == 0) {
            if (opts.initial_value) |v| {
                try stdout.flush();
                printer.pop(1);
                try printer.append("{s}\n", .{v}, .{});
                return try allocator.dupe(u8, v);
            }
        }

        // Validation
        if (opts.validate) |validate_fn| {
            if (!validate_fn(line)) {
                try handleInvalid(printer, stdout, opts, &invalid_attempt);
                continue;
            }
        }

        // Compare
        if (opts.compare) |cmp| {
            if (!std.mem.eql(u8, line, cmp)) {
                try handleInvalid(printer, stdout, opts, &invalid_attempt);
                continue;
            }
        }

        try stdout.flush();

        const result = try allocator.dupe(u8, line);

        if (invalid_attempt) {
            printer.pop(1);
        }

        try printer.append("{s}\n", .{result}, .{});
        return result;
    }
}

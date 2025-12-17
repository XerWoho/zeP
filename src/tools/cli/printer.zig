const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;

const Structs = @import("structs");
const Locales = @import("locales");

const Color = enum {
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    bright_black,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,
};

pub fn getColor(color: Color) []const u8 {
    const color_string = switch (color) {
        .black => "\x1b[30m",
        .red => "\x1b[31m",
        .green => "\x1b[32m",
        .yellow => "\x1b[33m",
        .blue => "\x1b[34m",
        .magenta => "\x1b[35m",
        .cyan => "\x1b[36m",
        .white => "\x1b[37m",
        .bright_black => "\x1b[90m",
        .bright_red => "\x1b[91m",
        .bright_green => "\x1b[92m",
        .bright_yellow => "\x1b[93m",
        .bright_blue => "\x1b[94m",
        .bright_magenta => "\x1b[95m",
        .bright_cyan => "\x1b[96m",
        .bright_white => "\x1b[97m",
    };
    return color_string;
}

const Weight = enum { none, bold, dim, emphasis, underline };

pub fn getWeight(weight: Weight) []const u8 {
    const color_weight = switch (weight) {
        .none => "",
        .bold => "\x1b[1m",
        .dim => "\x1b[2m",
        .emphasis => "\x1b[3m",
        .underline => "\x1b[4m",
    };
    return color_weight;
}

const AppendOptions = struct {
    verbosity: u8 = 1,
    color: Color = .white,
    weight: Weight = .none,

    pub fn init() AppendOptions {
        return AppendOptions{
            .color = .white,
            .verbosity = 1,
            .weight = .none,
        };
    }
};

const PrinterData = struct {
    data: []const u8,
    verbosity: u8 = 1,
    color: Color = .white,
    weight: Weight = .none,
};

/// Handles Cleaner printing and interactivity.
pub const Printer = struct {
    data: std.ArrayList(PrinterData),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Printer {
        const data = try std.ArrayList(PrinterData).initCapacity(allocator, 25);
        return Printer{
            .data = data,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Printer) void {
        for (self.data.items) |d| {
            self.allocator.free(d.data);
        }
        self.data.deinit(self.allocator);
    }

    pub fn append(self: *Printer, comptime fmt: []const u8, args: anytype, options: AppendOptions) !void {
        if (options.verbosity > Locales.VERBOSITY_MODE) return;
        const data = try std.fmt.allocPrint(self.allocator, fmt, args);
        try self.data.append(
            self.allocator,
            PrinterData{
                .data = data,
                .verbosity = options.verbosity,
                .color = options.color,
                .weight = options.weight,
            },
        );
        try self.print();
        return;
    }

    pub fn pop(self: *Printer, pop_amount: u8) void {
        const amount = pop_amount;
        for (0..amount) |_| {
            const n = self.data.pop();
            if (n == null) break;
        }
        return;
    }

    pub fn clearLine(_: *Printer, n: usize) !void {
        if (n == 0) return;

        var stdout_buf: [1028]u8 = undefined;
        var stdout_writer = std.fs.File.writer(std.fs.File.stdout(), &stdout_buf);
        var stdout = &stdout_writer.interface;
        for (0..n) |i| {
            try stdout.print("\x1b[2K\r", .{}); // Clear line
            if (@as(i8, @intCast(i)) - 1 < n) try stdout.print("\x1b[1A", .{});
        }

        try stdout.print("\x1b[2K\r", .{}); // Clear line
        try stdout.flush();
    }

    pub fn clearScreen(self: *Printer) !void {
        if (self.data.items.len < 2) return;

        var count: u16 = 0;
        for (0..self.data.items.len - 1) |i| {
            const data = self.data.items[i];
            const d = data.data;
            var small_count: usize = 0;
            for (d) |c| {
                if (c == '\n') small_count += 1;
            }
            count += @intCast(small_count);
        }

        try self.clearLine(count);
    }

    pub fn print(self: *Printer) !void {
        try self.clearScreen();
        for (self.data.items) |d| {
            std.debug.print("{s}{s}{s}\x1b[0m", .{
                getWeight(d.weight),
                getColor(d.color),
                d.data,
            });
        }
        return;
    }
};

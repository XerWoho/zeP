const std = @import("std");
const Structs = @import("structs");
const Locales = @import("locales");

const AppendOptions = struct {
    verbosity: u8 = 1,
    color: u8 = 0,
};

pub const Printer = struct {
    data: std.ArrayList(Structs.PrinterData),
    allocator: std.mem.Allocator,

    pub fn init(data: std.ArrayList(Structs.PrinterData)) Printer {
        const allocator = std.heap.page_allocator;
        return Printer{ .data = data, .allocator = allocator };
    }

    pub fn deinit(self: *Printer) void {
        for (self.data.items) |d| {
            self.allocator.free(d.data);
        }
        self.data.deinit();
    }

    pub fn append(self: *Printer, comptime fmt: []const u8, args: anytype, options: AppendOptions) !void {
        if (options.verbosity > Locales.VERBOSITY_MODE) return;
        const data = try std.fmt.allocPrint(self.allocator, fmt, args);
        try self.data.append(Structs.PrinterData{ .data = data, .verbosity = options.verbosity, .color = options.color });
        try self.print();
        return;
    }

    pub fn pop(self: *Printer, popAmount: ?u8) void {
        const amount = popAmount orelse 1;
        for (0..amount) |_| {
            _ = self.data.pop();
        }
        return;
    }

    pub fn clearScreen(_: *Printer) !void {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("\x1B[3J\x1B[2J\x1B[H", .{});
    }

    pub fn print(self: *Printer) !void {
        try self.clearScreen();
        for (self.data.items) |d| {
            std.debug.print("\x1b[{d}m{s}\x1b[0m", .{ d.color, d.data });
        }
        return;
    }
};

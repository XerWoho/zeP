const std = @import("std");

pub const Printer = struct {
    data: std.ArrayList([]const u8),

    pub fn init(data: std.ArrayList([]const u8)) !Printer {
        return Printer{ .data = data };
    }

    pub fn deinit(self: *Printer) void {
        self.data.deinit();
    }

    pub fn append(self: *Printer, data: []const u8) !void {
        try self.data.append(data);
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
            std.debug.print("{s}", .{d});
        }
        return;
    }
};

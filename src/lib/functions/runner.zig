const std = @import("std");
const builtin = @import("builtin");

const Constants = @import("constants");
const Structs = @import("structs");

const Printer = @import("cli").Printer;
const Fs = @import("io").Fs;

const Manifest = @import("core").Manifest;
const Builder = @import("builder.zig").Builder;

/// Handles running a build
pub const Runner = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,

    /// Initializes Runner
    pub fn init(allocator: std.mem.Allocator, printer: *Printer) !Runner {
        return Runner{
            .allocator = allocator,
            .printer = printer,
        };
    }

    /// Initializes a Child Processor, and executes specified file
    pub fn run(self: *Runner, args: [][]const u8) !void {
        var builder = try Builder.init(self.allocator, self.printer);
        try self.printer.append("\nBuilding executeable...\n\n", .{}, .{ .color = 32 });
        const target_file = try builder.build();

        var exec_args = std.ArrayList([]const u8).init(self.allocator);
        for (args) |arg| {
            try exec_args.append(arg);
        }

        if (builtin.os.tag != .windows) {
            const exec = try std.fmt.allocPrint(self.allocator, "./{s}", .{target_file});
            try exec_args.insert(0, exec);
        } else {
            try exec_args.insert(0, target_file);
        }

        try self.printer.append("\nRunning...\n\n", .{}, .{ .color = 32 });
        var process = std.process.Child.init(exec_args.items, self.allocator);
        _ = process.spawnAndWait() catch {};
    }
};

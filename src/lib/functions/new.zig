const std = @import("std");

const Printer = @import("cli").Printer;
const Fs = @import("io").Fs;

const Init = @import("../packages/init.zig").Init;

/// Handles bootstrapping
pub fn new(allocator: std.mem.Allocator, printer: *Printer, name: []const u8) !void {
    var initer = try Init.init(allocator, printer, true);

    var zig_version: []const u8 = "0.14.0";
    blk: {
        const child = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "zig", "version" },
        }) catch |err| {
            switch (err) {
                else => {
                    try printer.append("Zig is not installed!\nDefaulting to 0.14.0!\n\n", .{}, .{ .color = 31 });
                },
            }
            break :blk;
        };
        zig_version = child.stdout[0 .. child.stdout.len - 1];
    }

    initer.name = name;
    initer.zig_version = zig_version;

    try initer.commitInit();
}

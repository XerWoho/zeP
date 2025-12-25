const std = @import("std");
const builtin = @import("builtin");

pub const Runner = @This();

const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Builder = @import("builder.zig");
const Context = @import("context");

/// Handles running a build
ctx: *Context,

/// Initializes Runner
pub fn init(ctx: *Context) Runner {
    return Runner{
        .ctx = ctx,
    };
}

/// Initializes a Child Processor, and executes specified file
pub fn run(self: *Runner, target_exe: []const u8, args: [][]const u8) !void {
    var builder = try Builder.init(self.ctx);
    try self.ctx.printer.append("\nBuilding executeable...\n\n", .{}, .{ .color = .green });
    var target_files = try builder.build();
    defer target_files.deinit(self.ctx.allocator);

    var target_file = target_files.items[0];
    if (target_files.items.len > 0 and target_exe.len > 0) {
        for (target_files.items) |tf| {
            if (std.mem.eql(u8, tf, target_exe)) {
                target_file = tf;
                break;
            }
            continue;
        }
    }

    var exec_args = try std.ArrayList([]const u8).initCapacity(self.ctx.allocator, 5);
    for (args) |arg| {
        try exec_args.append(self.ctx.allocator, arg);
    }

    if (builtin.os.tag == .windows) {
        try exec_args.insert(self.ctx.allocator, 0, target_file);
    } else {
        var buf: [256]u8 = undefined;
        const exec = try std.fmt.bufPrint(
            &buf,
            "./{s}",
            .{target_file},
        );
        try exec_args.insert(self.ctx.allocator, 0, exec);
    }

    self.ctx.printer.pop(50);

    const cmd = try std.mem.join(self.ctx.allocator, " ", exec_args.items);
    defer self.ctx.allocator.free(cmd);
    try self.ctx.printer.append("\nRunning...\n $ {s}\n\n\n", .{cmd}, .{ .color = .green });
    var process = std.process.Child.init(exec_args.items, self.ctx.allocator);
    _ = process.spawnAndWait() catch {};
}

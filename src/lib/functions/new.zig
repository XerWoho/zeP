const std = @import("std");

const Constants = @import("constants");
const Fs = @import("io").Fs;
const Init = @import("./init.zig");
const Context = @import("context");

/// Handles quick-starting a project
pub fn new(
    ctx: *Context,
    name: []const u8,
) !void {
    ctx.logger.info("Running New", @src());

    var initer = try Init.init(
        ctx,
        true,
    );

    var zig_version: []const u8 = Constants.Default.zig_version;
    blk: {
        const child = std.process.Child.run(.{
            .allocator = ctx.allocator,
            .argv = &[_][]const u8{ "zig", "version" },
        }) catch |err| {
            switch (err) {
                else => {
                    ctx.logger.info("Zig is not instealled", @src());
                    ctx.printer.append(
                        "Zig is not installed!\nDefaulting to {s}!\n\n",
                        .{
                            Constants.Default.zig_version,
                        },
                        .{ .color = .red },
                    );
                },
            }
            break :blk;
        };
        zig_version = child.stdout[0 .. child.stdout.len - 1];
    }

    initer.name = name;
    initer.zig_version = zig_version;

    try initer._init();
}

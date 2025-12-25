const std = @import("std");

const Builder = @import("../../lib/functions/builder.zig");
const Context = @import("context");

fn builder(ctx: *Context) !void {
    try ctx.logger.info("running builder", @src());
    var b = try Builder.init(ctx);
    _ = b.build() catch |err| {
        switch (err) {
            error.FileNotFound => {
                try ctx.printer.append("Zig is not installed!\nExiting!\n\n", .{}, .{ .color = .red });
                try ctx.printer.append("\nSUGGESTION:\n", .{}, .{ .color = .blue });
                try ctx.printer.append(" - Install zig\n $ zep zig install <version>\n\n", .{}, .{});
                return error.ZigNotInstalled;
            },
            else => {
                try ctx.printer.append("\nZig building failed!\nExiting.\n\n", .{}, .{ .color = .red });
                return err;
            },
        }
    };

    try ctx.logger.info("builder finished", @src());
    return;
}

pub fn _builderController(ctx: *Context) !void {
    try builder(ctx);
}

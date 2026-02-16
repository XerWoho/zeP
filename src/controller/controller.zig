const std = @import("std");
const Context = @import("context");

const Help = @import("help.zig");
const Dispatcher = @import("dispatcher.zig");

pub fn _controller(ctx: *Context) !void {
    if (ctx.cmds.len < 2) {
        Help.help(ctx);
        return;
    }

    const c = ctx.cmds[1];
    if (std.mem.eql(u8, c, "help")) {
        Help.help(ctx);
        return;
    }

    Dispatcher.dispatcher(ctx, c) catch |err| {
        switch (err) {
            error.InvalidCommand => {
                ctx.printer.append("Invalid Command. Run: \n $ zep help\n\n", .{}, .{ .verbosity = 0 });
            },
            else => {
                ctx.printer.append("Command failed. Error={any}\n", .{err}, .{ .verbosity = 0 });
            },
        }
    };
}

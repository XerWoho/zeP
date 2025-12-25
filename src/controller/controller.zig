const std = @import("std");
const Context = @import("context");

const Help = @import("help.zig");
const Dispatcher = @import("dispatcher.zig");

pub fn _controller(ctx: *Context) !void {
    if (ctx.args.len < 2) {
        Help.help(ctx);
        return;
    }

    const c = ctx.args[1];
    if (std.mem.eql(u8, c, "help")) {
        Help.help(ctx);
        return;
    }

    Dispatcher.dispatcher(ctx, c) catch |err| {
        switch (err) {
            error.InvalidCommand => {
                std.debug.print("Invalid Command.\n", .{});
                return;
            },
            error.MissingArguments => {
                std.debug.print("Arguments Missing.\n", .{});
                return;
            },
            else => {
                std.debug.print("Command failed.\n", .{});
                return err;
            },
        }
    };
}

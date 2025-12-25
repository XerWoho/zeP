const std = @import("std");
const Context = @import("context").Context;

const Help = @import("help.zig");
const Dispatcher = @import("dispatcher.zig");

pub fn _controller(ctx: *Context) !void {
    if (ctx.args.len < 2) {
        try Help.help(ctx);
        return;
    }

    const c = ctx.args[1];
    if (std.mem.eql(u8, c, "help")) {
        try Help.help(ctx);
        return;
    }

    Dispatcher.dispatcher(ctx, c) catch |err| {
        switch (err) {
            error.InvalidCommand => {
                try ctx.printer.append("Invalid Command\n", .{}, .{});
                return;
            },
            else => {
                try ctx.printer.append("Dispatching failed {any}\n", .{err}, .{});
                return;
            },
        }
    };

    try ctx.printer.append("Done.\n\n", .{}, .{});
}

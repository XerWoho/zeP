const std = @import("std");
const Purger = @import("../../lib/packages/purge.zig");
const Context = @import("context");

const Errors = @import("errors");

fn purge(ctx: *Context) !void {
    try Purger.purge(ctx);
}

pub fn _purgeController(ctx: *Context) Errors.Controller.Main!void {
    purge(ctx) catch return Errors.Controller.Main.Failed;
}

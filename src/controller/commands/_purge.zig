const std = @import("std");
const Purger = @import("../../lib/packages/purge.zig");
const Context = @import("context").Context;

fn purge(ctx: *Context) !void {
    try Purger.purge(ctx);
    return;
}

pub fn _purgeController(
    ctx: *Context,
) !void {
    try purge(ctx);
}

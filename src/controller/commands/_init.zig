const std = @import("std");

const Init = @import("../../lib/packages/init.zig").Init;

const Context = @import("context").Context;

fn init(ctx: *Context) !void {
    try ctx.logger.info("running init", @src());
    var i = try Init.init(ctx, true);
    try i.commitInit();

    try ctx.logger.info("init finished", @src());
    return;
}

pub fn _initController(ctx: *Context) !void {
    try init(ctx);
}

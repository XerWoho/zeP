const std = @import("std");

const Builder = @import("../../lib/functions/builder.zig").Builder;

const Context = @import("context").Context;

fn builder(ctx: *Context) !void {
    try ctx.logger.info("running builder", @src());
    var b = try Builder.init(ctx);
    _ = try b.build();

    try ctx.logger.info("builder finished", @src());
    return;
}

pub fn _builderController(ctx: *Context) !void {
    try builder(ctx);
}

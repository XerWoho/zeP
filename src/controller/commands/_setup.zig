const std = @import("std");

const Setup = @import("cli").Setup;
const Context = @import("context");

fn setup(ctx: *Context) !void {
    try Setup.setup(
        ctx.allocator,
        &ctx.paths,
        &ctx.printer,
    );
    return;
}

pub fn _setupController(ctx: *Context) !void {
    try setup(ctx);
}

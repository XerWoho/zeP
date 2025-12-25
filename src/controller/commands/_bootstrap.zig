const std = @import("std");

const Bootstrap = @import("../../lib/functions/bootstrap.zig");

const Context = @import("context").Context;
const Args = @import("args");

fn bootstrap(ctx: *Context) !void {
    const bootstrap_args = try Args.parseBootstrap();
    try ctx.logger.info("running bootstrap", @src());
    try Bootstrap.bootstrap(ctx, bootstrap_args.zig, bootstrap_args.deps);
    try ctx.logger.info("bootstrap finished", @src());
    return;
}

pub fn _bootstrapController(
    ctx: *Context,
) !void {
    try bootstrap(ctx);
}

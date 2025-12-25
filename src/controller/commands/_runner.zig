const std = @import("std");

const Runner = @import("../../lib/functions/runner.zig");
const Context = @import("context");
const Args = @import("args");

fn new(ctx: *Context) !void {
    try ctx.logger.info("running new", @src());

    const runner_args = try Args.parseRunner();

    var r = Runner.init(ctx);
    try r.run(runner_args.target, runner_args.args);

    try ctx.logger.info("new finished", @src());
    return;
}

pub fn _newController(ctx: *Context) !void {
    try new(ctx);
}

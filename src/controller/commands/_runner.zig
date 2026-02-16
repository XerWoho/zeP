const std = @import("std");

const Runner = @import("../../lib/functions/runner.zig");
const Context = @import("context");
const Args = @import("args");

const Errors = @import("errors");
const CErrors = @import("../errors.zig");

fn runner(ctx: *Context) !void {
    const runner_args = Args.parseRunner(ctx.options);
    const builder_args = Args.parseBuilder(ctx.options);
    var args = try std.ArrayList([]const u8).initCapacity(ctx.allocator, 5);
    defer args.deinit(ctx.allocator);
    var split_args = std.mem.splitAny(u8, runner_args.args, ",");
    while (split_args.next()) |p| {
        try args.append(ctx.allocator, p);
    }

    var r = Runner.init(ctx);
    r.run(
        runner_args.target,
        args.items,
        builder_args.zig_version,
        builder_args.path,
    ) catch |err| CErrors.handleBuildError(ctx, err);
}

pub fn _runnerController(ctx: *Context) Errors.Controller.Main!void {
    runner(ctx) catch return Errors.Controller.Main.Failed;
}

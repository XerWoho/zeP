const std = @import("std");

const Builder = @import("../../lib/functions/builder.zig");
const Context = @import("context");
const Args = @import("args");

const Errors = @import("errors");
const CErrors = @import("../errors.zig");

fn builder(ctx: *Context) void {
    const builder_args = Args.parseBuilder(ctx.options);
    _ = Builder.build(
        ctx,
        builder_args.path,
        builder_args.zig_version,
        .{},
    ) catch |err| CErrors.handleBuildError(ctx, err);
}

pub fn _builderController(ctx: *Context) !void {
    builder(ctx);
}

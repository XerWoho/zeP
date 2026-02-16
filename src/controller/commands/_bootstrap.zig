const std = @import("std");

const Bootstrap = @import("../../lib/functions/bootstrap.zig");

const Context = @import("context");
const Args = @import("args");

const Errors = @import("errors");

fn bootstrap(ctx: *Context) !void {
    const bootstrap_args = Args.parseBootstrap(ctx.options);
    var pkgs = try std.ArrayList([]const u8).initCapacity(ctx.allocator, 5);
    defer pkgs.deinit(ctx.allocator);
    var split_pkgs = std.mem.splitAny(u8, bootstrap_args.pkgs, ",");
    while (split_pkgs.next()) |p| {
        try pkgs.append(ctx.allocator, p);
    }

    try Bootstrap.bootstrap(ctx, bootstrap_args.zig, pkgs.items);
}

pub fn _bootstrapController(ctx: *Context) Errors.Controller.Main!void {
    bootstrap(ctx) catch return Errors.Controller.Main.Failed;
}

const std = @import("std");

const Lister = @import("../../lib/packages/list.zig");
const Context = @import("context");

const Errors = @import("errors");
const CErrors = @import("../errors.zig");

fn list(ctx: *Context) void {
    const package = ctx.cmds[2];
    var split = std.mem.splitScalar(u8, package, '@');
    const name = split.first();
    Lister.list(ctx, name) catch |err| CErrors.handleInstallableError(ctx, err, "Listing");
}

pub fn _listController(ctx: *Context) !void {
    if (ctx.cmds.len < 3) return Errors.Controller.MissingArguments.List;
    list(ctx);
}

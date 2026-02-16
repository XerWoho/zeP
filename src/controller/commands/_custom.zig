const std = @import("std");

const Custom = @import("../../lib/packages/custom.zig");

const Context = @import("context");
const Errors = @import("errors");

fn customAdd(ctx: *Context) !void {
    var custom = Custom.init(ctx);
    try custom.requestPackage();
}

fn customRemove(ctx: *Context) !void {
    const package = ctx.cmds[3];
    var custom = Custom.init(ctx);
    try custom.removePackage(package);
}

pub fn _customController(ctx: *Context) Errors.Controller.Main!void {
    if (ctx.cmds.len < 3) return Errors.Controller.MissingSubcommand.Custom;

    const arg = ctx.cmds[2];
    if (std.mem.eql(u8, arg, "add")) {
        customAdd(ctx) catch return Errors.Controller.Main.Failed;
    } else if (std.mem.eql(u8, arg, "remove")) {
        if (ctx.cmds.len < 4) return Errors.Controller.MissingArguments.Custom;
        customRemove(ctx) catch return Errors.Controller.Main.Failed;
    } else {
        return Errors.Controller.MissingSubcommand.Custom;
    }
}

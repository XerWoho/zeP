const std = @import("std");

const New = @import("../../lib/functions/new.zig");

const Context = @import("context");
const Errors = @import("errors");

fn new(ctx: *Context) !void {
    const name = ctx.cmds[2];
    try New.new(ctx, name);
}

pub fn _newController(ctx: *Context) Errors.Controller.Main!void {
    if (ctx.cmds.len < 3) return Errors.Controller.MissingArguments.New;
    new(ctx) catch return Errors.Controller.Main.Failed;
}

const std = @import("std");

const Init = @import("../../lib/functions/init.zig");

const Context = @import("context");
const Errors = @import("errors");

fn init(ctx: *Context) !void {
    var i = try Init.init(ctx, false);
    try i._init();
}

pub fn _initController(ctx: *Context) Errors.Controller.Main!void {
    init(ctx) catch return Errors.Controller.Main.Failed;
}

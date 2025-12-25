const std = @import("std");

const Constants = @import("constants");
const Context = @import("context");

fn version(ctx: *Context) !void {
    try ctx.printer.append("zeP {s}\n", .{Constants.Default.version}, .{});
    return;
}

pub fn _versionController(ctx: *Context) !void {
    try version(ctx);
}

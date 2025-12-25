const std = @import("std");

const Auth = @import("../../lib/cloud/auth.zig");
const Context = @import("context");

fn whoami(ctx: *Context) !void {
    try ctx.logger.info("running package: add", @src());
    var auth = try Auth.init(ctx);
    try auth.whoami();
    try ctx.logger.info("running package: add finished", @src());
    return;
}

pub fn _whoamiController(ctx: *Context) !void {
    try whoami(ctx);
}

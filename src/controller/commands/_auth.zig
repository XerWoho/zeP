const std = @import("std");

const Auth = @import("../../lib/cloud/auth.zig");
const Context = @import("context");

fn authLogin(ctx: *Context, auth: *Auth) !void {
    try ctx.logger.info("running package: add", @src());
    try auth.login();
    try ctx.logger.info("running package: add finished", @src());
    return;
}

fn authRegister(ctx: *Context, auth: *Auth) !void {
    try ctx.logger.info("running package: remove", @src());
    try auth.register();
    try ctx.logger.info("running package: remove finished", @src());
    return;
}

fn authLogout(ctx: *Context, auth: *Auth) !void {
    try ctx.logger.info("running package: list", @src());
    try auth.logout();
    try ctx.logger.info("running package: list finished", @src());
}

pub fn _authController(ctx: *Context) !void {
    if (ctx.args.len < 3) return error.MissingSubcommand;

    var auth = try Auth.init(ctx);
    const arg = ctx.args[2];
    if (std.mem.eql(u8, arg, "login"))
        try authLogin(ctx, &auth);

    if (std.mem.eql(u8, arg, "register"))
        try authRegister(ctx, &auth);

    if (std.mem.eql(u8, arg, "logout"))
        try authLogout(ctx, &auth);
}

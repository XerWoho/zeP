const std = @import("std");

const Auth = @import("../../lib/cloud/auth.zig");
const Context = @import("context");

const Errors = @import("errors");
const CErrors = @import("../errors.zig");

fn authLogin(ctx: *Context, auth: *Auth) void {
    auth.login() catch |err| CErrors.handleAuthError(
        ctx,
        err,
        "login",
    );
}

fn authRegister(ctx: *Context, auth: *Auth) void {
    auth.register() catch |err| CErrors.handleAuthError(
        ctx,
        err,
        "register",
    );
}

fn authLogout(ctx: *Context, auth: *Auth) void {
    auth.logout() catch |err| CErrors.handleAuthError(
        ctx,
        err,
        "logout",
    );
}

fn authWhoami(ctx: *Context, auth: *Auth) void {
    auth.whoami() catch |err| CErrors.handleAuthError(
        ctx,
        err,
        "whoami",
    );
}

pub fn _authController(ctx: *Context) Errors.Controller.Main!void {
    if (ctx.cmds.len < 3) return Errors.Controller.MissingSubcommand.Auth;

    var auth = Auth.init(ctx);
    const arg = ctx.cmds[2];
    if (std.mem.eql(u8, arg, "login")) {
        authLogin(ctx, &auth);
    } else if (std.mem.eql(u8, arg, "register")) {
        authRegister(ctx, &auth);
    } else if (std.mem.eql(u8, arg, "logout")) {
        authLogout(ctx, &auth);
    } else if (std.mem.eql(u8, arg, "whoami")) {
        authWhoami(ctx, &auth);
    } else {
        return Errors.Controller.Main.Failed;
    }
}

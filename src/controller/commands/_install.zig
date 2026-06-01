const std = @import("std");

const Installer = @import("../../lib/packages/install.zig");

const Structs = @import("structs");
const Context = @import("context");
const Args = @import("args");

const Errors = @import("errors");
const CErrors = @import("../errors.zig");

fn install(ctx: *Context) !void {
    const install_args = Args.parseInstall(ctx.options);

    const package_query = if (ctx.cmds.len < 3) null else ctx.cmds[2]; // package name;
    const selected =
        @as(u3, @intFromBool(install_args.zep)) +
        @as(u3, @intFromBool(install_args.github)) +
        @as(u3, @intFromBool(install_args.codeberg)) +
        @as(u3, @intFromBool(install_args.gitlab)) +
        @as(u3, @intFromBool(install_args.local));

    if (selected > 1) return Errors.Controller.MissingArguments.Install;
    var namespace: Structs.Extras.Namespaces = .zep;
    if (install_args.zep) namespace = Structs.Extras.Namespaces.zep;
    if (install_args.github) namespace = Structs.Extras.Namespaces.github;
    if (install_args.gitlab) namespace = Structs.Extras.Namespaces.gitlab;
    if (install_args.codeberg) namespace = Structs.Extras.Namespaces.codeberg;
    if (install_args.local) namespace = Structs.Extras.Namespaces.local;

    var installer = Installer.init(ctx);
    defer installer.deinit();

    if (package_query) |query| {
        var split = std.mem.splitScalar(u8, query, '@');
        const name = split.first();
        const version = split.next();

        // if (!install_args.binary) {
        installer.installPackage(
            name,
            version,
            namespace,
            install_args.inject,
        ) catch |err| CErrors.handleInstallableError(ctx, err, "Installing Package");
        // } else {
        //     installer.installBinary(
        //         name,
        //         version,
        //         namespace,
        //     ) catch |err| CErrors.handleInstallableError(ctx, err, "Installing Binary");
        // }
    } else {
        installer.installAll() catch |err| CErrors.handleInstallableError(ctx, err, "Installing All");
    }
}

pub fn _installController(ctx: *Context) Errors.Controller.Main!void {
    install(ctx) catch return Errors.Controller.Main.Failed;
}

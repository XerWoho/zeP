const std = @import("std");

const Package = @import("package");
const Context = @import("context");
const Structs = @import("structs");
const Args = @import("args");
const Errors = @import("errors");
const CErrors = @import("../errors.zig");

fn info(ctx: *Context) void {
    const id = ctx.cmds[2];
    var split = std.mem.splitScalar(u8, id, '@');
    const name = split.first();
    const version = split.next();

    const install_args = Args.parseInstall(ctx.options);
    var namespace: Structs.Extras.Namespaces = .zep;
    if (install_args.zep) namespace = Structs.Extras.Namespaces.zep;
    if (install_args.github) namespace = Structs.Extras.Namespaces.github;
    if (install_args.gitlab) namespace = Structs.Extras.Namespaces.gitlab;
    if (install_args.codeberg) namespace = Structs.Extras.Namespaces.codeberg;
    if (install_args.local) namespace = Structs.Extras.Namespaces.local;

    var package = Package.init(
        ctx,
        name,
        version,
        namespace,
    ) catch |err| return CErrors.handleInstallableError(ctx, err, "Packaging");
    defer package.deinit();

    ctx.printer.append("Package Name: {s}\n", .{package.package.name}, .{});
    ctx.printer.append("Version: {s}\n", .{package.package.version}, .{});
    ctx.printer.append("Hash: {s}\n", .{package.package.hash}, .{});
    ctx.printer.append("Source: {s}\n", .{package.package.source}, .{});
    ctx.printer.append("Zig Version: {s}\n\n", .{package.package.zig_version}, .{});
}

pub fn _infoController(ctx: *Context) Errors.Controller.Main!void {
    if (ctx.cmds.len < 3) return Errors.Controller.MissingArguments.Info;
    info(ctx);
}

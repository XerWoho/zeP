const std = @import("std");

const Uninstaller = @import("../../lib/packages/uninstall.zig");
const Package = @import("package");

const Structs = @import("structs");
const Context = @import("context");
const Args = @import("args");

const Errors = @import("errors");
const CErrors = @import("../errors.zig");

fn uninstall(ctx: *Context) !void {
    const query = ctx.cmds[2]; // package name;
    var split = std.mem.splitScalar(u8, query, '@');
    const name = split.first();
    const version = split.next();

    const uninstall_args = Args.parseUninstall(ctx.options);
    const install_args = Args.parseInstall(ctx.options);
    var _namespace: ?Structs.Extras.Namespaces = null;
    if (install_args.zep) _namespace = Structs.Extras.Namespaces.zep;
    if (install_args.github) _namespace = Structs.Extras.Namespaces.github;
    if (install_args.gitlab) _namespace = Structs.Extras.Namespaces.gitlab;
    if (install_args.codeberg) _namespace = Structs.Extras.Namespaces.codeberg;
    if (install_args.local) _namespace = Structs.Extras.Namespaces.local;

    if (uninstall_args.global and !install_args.binary) {
        if (version == null) {
            ctx.printer.append(
                "WARNING: For global uninstalls, a version is required.\n\n",
                .{},
                .{ .color = .red },
            );
            return;
        }

        if (_namespace == null) {
            ctx.printer.append(
                "WARNING: For global uninstalls, a namespace is required.\n\n",
                .{},
                .{ .color = .red },
            );
            return;
        }
        const namespace = _namespace orelse .zep;

        var package = Package.init(
            ctx,
            name,
            version,
            namespace,
        ) catch |err| return CErrors.handleInstallableError(ctx, err, "Packaging");
        defer package.deinit();

        package.uninstallFromDisk(uninstall_args.force) catch |err| return CErrors.handleInstallableError(
            ctx,
            err,
            "Uninstalling",
        );
        if (uninstall_args.force) {
            ctx.printer.append(
                "{s} package deleted, consequences ignored.\n\n",
                .{query},
                .{ .color = .green },
            );
        }
    }

    var uninstaller = Uninstaller.init(ctx);
    defer uninstaller.deinit();

    if (install_args.binary) {
        if (_namespace == null) {
            ctx.printer.append(
                "WARNING: For binary uninstalls, a namespace is required.\n\n",
                .{},
                .{ .color = .red },
            );
        }
        const namespace = _namespace orelse .zep;
        uninstaller.uninstallBinary(name, version, namespace) catch |err| CErrors.handleInstallableError(ctx, err, "Uninstalling Binary");
    }

    uninstaller.uninstallPackage(name) catch |err| CErrors.handleInstallableError(ctx, err, "Uninstalling Package");
}

pub fn _uninstallController(ctx: *Context) Errors.Controller.Main!void {
    if (ctx.cmds.len < 3) return Errors.Controller.MissingArguments.Uninstall;
    uninstall(ctx) catch return Errors.Controller.Main.Failed;
}

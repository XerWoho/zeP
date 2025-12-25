const std = @import("std");

const Installer = @import("../../lib/packages/install.zig");

const Context = @import("context");
const Args = @import("args");

fn install(ctx: *Context) !void {
    try ctx.logger.info("running install", @src());

    const install_args = try Args.parseInstall();

    const target = if (ctx.args.len < 3) null else ctx.args[2]; // package name;
    var installer = Installer.init(ctx);
    installer.force_inject = install_args.inject;
    installer.install_unverified_packages = install_args.unverified;

    defer installer.deinit();

    if (target) |package| {
        try ctx.logger.infof("install: package={s}", .{package}, @src());
        var split = std.mem.splitScalar(u8, package, '@');
        const package_name = split.first();
        const package_version = split.next();
        installer.install(package_name, package_version) catch |err| {
            try ctx.logger.errf("install: failed, err={}", .{err}, @src());

            switch (err) {
                error.AlreadyInstalled => {
                    try ctx.printer.append("\nAlready installed!\n\n", .{}, .{ .color = .yellow });
                },
                error.PackageNotFound => {
                    try ctx.printer.append("\nPackage not Found!\n\n", .{}, .{ .color = .yellow });
                },
                error.HashMismatch => {
                    try ctx.printer.append("  ! HASH MISMATCH!\nPLEASE REPORT!\n\n", .{}, .{ .color = .red });
                },
                else => {
                    try ctx.printer.append("\nInstalling {s} has failed... {any}\n\n", .{ package, err }, .{ .color = .red });
                },
            }
        };
    } else {
        try ctx.logger.info("install: all", @src());
        installer.installAll() catch |err| {
            try ctx.logger.infof("install all: failed, err={}", .{err}, @src());
            switch (err) {
                error.AlreadyInstalled => {
                    try ctx.printer.append("\nAlready installed!\n\n", .{}, .{ .color = .yellow });
                },
                error.HashMismatch => {
                    try ctx.printer.append("\n  ! HASH MISMATCH!\nPLEASE REPORT!\n\n", .{}, .{ .color = .red });
                },
                else => {
                    try ctx.printer.append("\nInstalling all has failed...\n\n", .{}, .{ .color = .red });
                },
            }
        };
    }

    try ctx.logger.info("install: finished", @src());
    return;
}

pub fn _installController(ctx: *Context) !void {
    try install(ctx);
}

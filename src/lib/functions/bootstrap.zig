const std = @import("std");

const Locales = @import("locales");
const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;

const Artifact = @import("../artifact/artifact.zig");
const Installer = @import("../packages/install.zig");
const Init = @import("./init.zig");

const Context = @import("context");

/// Handles bootstrapping
pub fn bootstrap(
    ctx: *Context,
    zig_version: []const u8,
    pkgs: [][]const u8,
) !void {
    ctx.logger.info("Bootstrapping", @src());

    ctx.printer.append(
        "-- GETTING ZIG --\n\n",
        .{},
        .{
            .color = .blue,
            .weight = .bold,
        },
    );

    var zig = Artifact.init(ctx, .zig);
    defer zig.deinit();

    const default_target = Constants.Default.resolveDefaultTarget();
    ctx.logger.infof("Installing zig version={s}...", .{zig_version}, @src());
    try zig.install(zig_version, default_target);

    ctx.printer.append("\n", .{}, .{});

    ctx.logger.info("Initting...", @src());
    var initer = try Init.init(
        ctx,
        false,
    );

    ctx.logger.info("Committing Init...", @src());
    try initer._init();
    ctx.printer.append("\n", .{}, .{});

    ctx.printer.append(
        "-- GETTING PACKAGES --\n\n",
        .{},
        .{
            .color = .blue,
            .weight = .bold,
        },
    );

    ctx.logger.info("Installing packages...", @src());

    var installer = Installer.init(ctx);
    defer installer.deinit();
    for (pkgs) |pkg| {
        var p_split = std.mem.splitScalar(u8, pkg, '@');
        const name = p_split.first();
        const version = p_split.next();

        installer.installPackage(
            name,
            version,
            .zep,
            true,
        ) catch |err| {
            switch (err) {
                error.AlreadyInstalled => {
                    ctx.printer.append("{s} already installed.\n", .{name}, .{});
                },
                else => {
                    ctx.printer.append("{s} failed to install.\n", .{name}, .{});
                },
            }
        };
    }
}

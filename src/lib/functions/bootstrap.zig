const std = @import("std");

const Locales = @import("locales");
const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;

const Artifact = @import("../artifact/artifact.zig");
const Installer = @import("../packages/install.zig");
const Init = @import("../packages/init.zig");

const Context = @import("context");

/// Handles bootstrapping
pub fn bootstrap(
    ctx: *Context,
    zig_version: []const u8,
    deps: [][]const u8,
) !void {
    const previous_verbosity = Locales.VERBOSITY_MODE;
    Locales.VERBOSITY_MODE = 0;

    var zig = try Artifact.init(ctx, .zig);
    defer zig.deinit();

    const default_target = Constants.Default.resolveDefaultTarget();
    try zig.install(zig_version, default_target);
    Locales.VERBOSITY_MODE = previous_verbosity;

    var initer = try Init.init(
        ctx,
        false,
    );
    try initer.commitInit();

    for (deps) |dep| {
        var d = std.mem.splitScalar(u8, dep, '@');
        const package_name = d.first();
        const package_version = d.next();

        var installer = Installer.init(ctx);
        installer.install_unverified_packages = true;

        installer.install(
            package_name,
            package_version,
        ) catch |err| {
            switch (err) {
                error.AlreadyInstalled => {
                    try ctx.printer.append("{s} already installed.\n", .{package_name}, .{});
                },
                else => {
                    try ctx.printer.append("{s} failed to install.\n", .{package_name}, .{});
                },
            }
        };
    }
}

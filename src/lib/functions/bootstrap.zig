const std = @import("std");

const Locales = @import("locales");
const Constants = @import("constants");
const Structs = @import("structs");

const Printer = @import("cli").Printer;
const Fs = @import("io").Fs;

const Artifact = @import("../artifact/artifact.zig").Artifact;
const Installer = @import("../packages/install.zig").Installer;
const Init = @import("../packages/init.zig").Init;

/// Handles bootstrapping
pub fn bootstrap(
    allocator: std.mem.Allocator,
    printer: *Printer,
    zig_version: []const u8,
    deps: [][]const u8,
) !void {
    const previous_verbosity = Locales.VERBOSITY_MODE;
    Locales.VERBOSITY_MODE = 0;

    var zig = try Artifact.init(allocator, printer, .zig);
    try zig.install(zig_version, Constants.Default.default_targets.windows);
    Locales.VERBOSITY_MODE = previous_verbosity;

    var initer = try Init.init(allocator, printer, false);
    try initer.commitInit();

    for (deps) |dep| {
        var d = std.mem.splitScalar(u8, dep, '@');
        const package_name = d.first();
        const package_version = d.next();

        var installer = Installer.init(allocator, printer, package_name, package_version) catch |err| {
            switch (err) {
                error.PackageNotFound => {
                    try printer.append("{s} not found.\n", .{package_name}, .{});
                },
                else => {
                    try printer.append("{s} failed to init.\n", .{package_name}, .{});
                },
            }
            continue;
        };
        installer.install() catch |err| {
            switch (err) {
                error.AlreadyInstalled => {
                    try printer.append("{s} already installed.\n", .{package_name}, .{});
                },
                else => {
                    try printer.append("{s} failed to install.\n", .{package_name}, .{});
                },
            }
        };
    }
}

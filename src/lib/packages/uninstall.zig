const std = @import("std");

pub const Uninstaller = @This();

const Locales = @import("locales");
const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Injector = @import("core").Injector;
const Context = @import("context");

/// Handles the uninstallation of a package
ctx: *Context,

/// Initialize the uninstaller with allocator, package name, and printer
pub fn init(ctx: *Context) Uninstaller {
    return Uninstaller{ .ctx = ctx };
}

pub fn deinit(_: *Uninstaller) void {}

/// Main uninstallation routine
pub fn uninstall(
    self: *Uninstaller,
    package_name: []const u8,
) !void {
    const lock = try self.ctx.manifest.readManifest(
        Structs.ZepFiles.PackageLockStruct,
        Constants.Extras.package_files.lock,
    );
    var package_version: []const u8 = "";
    for (lock.value.packages) |package| {
        if (std.mem.startsWith(u8, package.name, package_name)) {
            var split = std.mem.splitScalar(u8, package.name, '@');
            _ = split.first();
            const version = split.next();
            if (version) |v| {
                package_version = v;
            } else {
                return error.NotInstalled;
            }

            break;
        }
        continue;
    }

    if (package_version.len == 0) {
        return error.NotInstalled;
    }

    const package_id = try std.fmt.allocPrint(
        self.ctx.allocator,
        "{s}@{s}",
        .{ package_name, package_version },
    );
    defer self.ctx.allocator.free(package_id);

    try self.ctx.printer.append("Deleting Package...\n[{s}]\n\n", .{package_name}, .{});
    try self.removePackageFromJson(package_id);

    var injector = try Injector.init(
        self.ctx.allocator,
        &self.ctx.printer,
        &self.ctx.manifest,
        false,
    );
    try injector.initInjector();

    // Remove symbolic link
    const symbolic_link_path = try std.fs.path.join(
        self.ctx.allocator,
        &.{
            Constants.Extras.package_files.zep_folder,
            package_name,
        },
    );
    defer self.ctx.allocator.free(symbolic_link_path);

    if (Fs.existsDir(symbolic_link_path)) {
        Fs.deleteTreeIfExists(symbolic_link_path) catch {};
        Fs.deleteFileIfExists(symbolic_link_path) catch {};

        const cwd = try std.fs.cwd().realpathAlloc(self.ctx.allocator, ".");
        defer self.ctx.allocator.free(cwd);

        const absolute_path = try std.fs.path.join(self.ctx.allocator, &.{ cwd, symbolic_link_path });
        defer self.ctx.allocator.free(absolute_path);

        // ! Handles the deletion of the package
        // ! as the package can ONLY be deleted,
        // ! if no other project uses it
        // !
        try self.ctx.manifest.removePathFromManifest(
            package_id,
            absolute_path,
        );
    }
    try self.removePackageFromJson(package_id);
    try self.ctx.printer.append("Successfully deleted - {s}\n\n", .{package_name}, .{ .color = .green });
}

/// Remove package from `zep.json` and `zep.lock`
pub fn removePackageFromJson(
    self: *Uninstaller,
    package_id: []const u8,
) !void {
    var package_json = try self.ctx.manifest.readManifest(
        Structs.ZepFiles.PackageJsonStruct,
        Constants.Extras.package_files.manifest,
    );
    var lock_json = try self.ctx.manifest.readManifest(
        Structs.ZepFiles.PackageLockStruct,
        Constants.Extras.package_files.lock,
    );

    defer package_json.deinit();
    defer lock_json.deinit();

    const previous_verbosity = Locales.VERBOSITY_MODE;
    Locales.VERBOSITY_MODE = 0;
    try self.ctx.manifest.manifestRemove(
        &package_json.value,
        package_id,
    );
    try self.ctx.manifest.lockRemove(
        &lock_json.value,
        package_id,
    );
    Locales.VERBOSITY_MODE = previous_verbosity;
}

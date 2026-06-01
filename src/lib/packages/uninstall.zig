const std = @import("std");

pub const Uninstaller = @This();

const Constants = @import("constants");
const Structs = @import("structs");
const Package = @import("package");
const Errors = @import("errors");

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
pub fn uninstallPackage(
    self: *Uninstaller,
    name: []const u8,
) Errors.Installable!void {
    self.ctx.logger.infof(
        "Uninstalling Package {s}",
        .{name},
        @src(),
    );

    const lock = self.ctx.manifest.readManifest(
        Structs.ZepFiles.Lock,
        Constants.Default.package_files.lock,
    ) catch return Errors.Installable.ManifestFailed;

    var target_package: ?Structs.ZepFiles.Package = null;
    for (lock.value.packages) |package| {
        if (!std.mem.startsWith(u8, package.name, name)) continue;
        target_package = package;
        continue;
    }

    const p = target_package orelse return Errors.Installable.NotInstalled;

    var package = try Package.init(
        self.ctx,
        name,
        p.version,
        p.namespace,
    );
    defer package.deinit();

    self.ctx.printer.append(
        "Deleting Package...\n[{s}]\n\n",
        .{name},
        .{ .verbosity = 1 },
    );

    // Remove symbolic link
    const relative_symbolic_link_path = try std.fs.path.join(
        self.ctx.allocator,
        &.{
            Constants.Default.package_files.zep_folder,
            name,
        },
    );
    defer self.ctx.allocator.free(relative_symbolic_link_path);

    Fs.deleteSymlinkIfExists(relative_symbolic_link_path);
    package.lockUnregister() catch return Errors.Installable.LockFailed;

    var injector = Injector.init(
        self.ctx.allocator,
        self.ctx.manifest,
        &self.ctx.printer,
    );
    injector.initInjector(false) catch return Errors.Installable.InjectFailed;
    self.ctx.printer.append(
        "Successfully deleted - {s}\n\n",
        .{name},
        .{ .color = .green },
    );
}

// pub fn uninstallBinary(
//     self: *Uninstaller,
//     name: []const u8,
//     version: ?[]const u8,
//     namespace: Structs.Extras.Namespaces,
// ) Errors.Installable!void {
//     self.ctx.logger.infof("Uninstalling Binary {s}", .{name}, @src());

//     var binary = try Package.init(
//         self.ctx,
//         name,
//         version,
//         namespace,
//     );
//     defer binary.deinit();

//     self.ctx.printer.append("Deleting Binary...\n[{s}]\n\n", .{name}, .{ .verbosity = 1 });
//     try binary.uninstallFromDisk(true);
//     self.ctx.printer.append("Successfully deleted - {s}\n\n", .{name}, .{ .color = .green });
// }

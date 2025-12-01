const std = @import("std");

const Locales = @import("locales");
const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Package = @import("core").Package.Package;
const Injector = @import("core").Injector.Injector;
const Manifest = @import("core").Manifest;
const Json = @import("core").Json.Json;

/// Handles the uninstallation of a package
pub const Uninstaller = struct {
    allocator: std.mem.Allocator,
    json: Json,
    printer: *Printer,
    package_name: []const u8,
    package_version: []const u8,
    package: Package,

    /// Initialize the uninstaller with allocator, package name, and printer
    pub fn init(allocator: std.mem.Allocator, package_name: []const u8, printer: *Printer) !Uninstaller {
        const json = try Json.init(allocator);

        const lock = try Manifest.readManifest(Structs.ZepFiles.PackageLockStruct, allocator, Constants.Extras.package_files.lock);
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
        const package = try Package.init(allocator, package_name, package_version, printer);
        if (package == null) {
            try printer.append("{s} is invalid!\n\n", .{package_name}, .{ .color = 31 });
            return error.InvalidPackage;
        }

        return Uninstaller{ .allocator = allocator, .package_name = package_name, .package_version = package_version, .package = package.?, .json = json, .printer = printer };
    }

    pub fn deinit(self: *Uninstaller) void {
        self.package.deinit();
    }

    /// Main uninstallation routine
    pub fn uninstall(self: *Uninstaller) !void {
        try self.printer.append("Deleting Package...\n[{s}]\n\n", .{self.package_name}, .{});
        try self.removePackageFromJson();

        var injector = Injector.init(self.allocator, self.package_name, self.printer);
        try injector.initInjector();

        // Remove symbolic link
        const symbolic_link_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ Constants.Extras.package_files.zep_folder, self.package_name });
        defer self.allocator.free(symbolic_link_path);
        if (Fs.existsDir(symbolic_link_path)) {
            std.fs.cwd().deleteDir(symbolic_link_path) catch {};
            std.fs.cwd().deleteFile(symbolic_link_path) catch {};

            const cwd = try std.fs.cwd().realpathAlloc(self.allocator, ".");
            defer self.allocator.free(cwd);

            const absolute_path = try std.fs.path.join(self.allocator, &.{ cwd, symbolic_link_path });
            defer self.allocator.free(absolute_path);

            // ! Handles the deletion of the package
            // ! as the package can ONLY be deleted,
            // ! if no other project uses it
            // !
            try Manifest.removePathFromManifest(
                &self.json,
                self.package_name,
                self.package.id,
                absolute_path,
            );
        }
        try self.removePackageFromJson();
        try self.printer.append("Successfully deleted - {s}\n\n", .{self.package_name}, .{ .color = 32 });
    }

    /// Remove package from `zep.json` and `zep.lock`
    pub fn removePackageFromJson(self: *Uninstaller) !void {
        var package_json = try Manifest.readManifest(Structs.ZepFiles.PackageJsonStruct, self.allocator, Constants.Extras.package_files.manifest);
        var lock_json = try Manifest.readManifest(Structs.ZepFiles.PackageLockStruct, self.allocator, Constants.Extras.package_files.lock);

        defer package_json.deinit();
        defer lock_json.deinit();

        const previous_verbosity = Locales.VERBOSITY_MODE;
        Locales.VERBOSITY_MODE = 0;
        try self.package.manifestRemove(&package_json.value);
        try self.package.lockRemove(&lock_json.value);
        Locales.VERBOSITY_MODE = previous_verbosity;
    }
};

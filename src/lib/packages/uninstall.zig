const std = @import("std");

const Locales = @import("locales");
const Constants = @import("constants");
const Structs = @import("structs");

const Utils = @import("utils");
const UtilsJson = Utils.UtilsJson;
const UtilsPackage = Utils.UtilsPackage;
const UtilsFs = Utils.UtilsFs;
const UtilsInjector = Utils.UtilsInjector;
const UtilsPrinter = Utils.UtilsPrinter;
const UtilsManifest = Utils.UtilsManifest;

/// Handles the uninstallation of a package
pub const Uninstaller = struct {
    allocator: std.mem.Allocator,
    json: UtilsJson.Json,
    printer: *UtilsPrinter.Printer,
    packageName: []const u8,
    packageVersion: []const u8,
    package: UtilsPackage.Package,

    /// Initialize the uninstaller with allocator, package name, and printer
    pub fn init(allocator: std.mem.Allocator, packageName: []const u8, printer: *UtilsPrinter.Printer) !Uninstaller {
        const json = try UtilsJson.Json.init(allocator);

        const lock = try UtilsManifest.readManifest(Structs.PackageLockStruct, allocator, Constants.ZEP_LOCK_PACKAGE_FILE);
        var packageVersion: []const u8 = "";
        for (lock.value.packages) |package| {
            if (std.mem.startsWith(u8, package.name, packageName)) {
                var split = std.mem.splitScalar(u8, package.name, '@');
                _ = split.first();
                const version = split.next();
                if (version) |v| {
                    packageVersion = v;
                } else {
                    try printer.append("{s} is not installed!\n", .{packageName}, .{ .color = 31 });
                    std.process.exit(0);
                    return error.NotInstalled;
                }

                break;
            }
            continue;
        }

        if (packageVersion.len == 0) {
            try printer.append("{s} is not installed!\n\n", .{packageName}, .{ .color = 31 });
            std.process.exit(0);
            return error.NotInstalled;
        }
        const package = try UtilsPackage.Package.init(allocator, packageName, packageVersion, printer);
        if (package == null) {
            try printer.append("{s} is invalid!\n\n", .{packageName}, .{ .color = 31 });
            return error.InvalidPackage;
        }

        return Uninstaller{ .allocator = allocator, .packageName = packageName, .packageVersion = packageVersion, .package = package.?, .json = json, .printer = printer };
    }

    pub fn deinit(self: *Uninstaller) void {
        self.package.deinit();
    }

    /// Main uninstallation routine
    pub fn uninstall(self: *Uninstaller) !void {
        try self.printer.append("Deleting Package...\n[{s}]\n\n", .{self.packageName}, .{});
        try self.removePackageFromJson();

        var injector = UtilsInjector.Injector.init(self.allocator, self.packageName, self.printer);
        try injector.initInjector();

        // Remove symbolic link
        const linkPath = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ Constants.ZEP_FOLDER, self.packageName });
        defer self.allocator.free(linkPath);
        if (UtilsFs.checkDirExists(linkPath)) {
            const cwd = try std.fs.cwd().realpathAlloc(self.allocator, ".");
            defer self.allocator.free(cwd);

            const absLinkedPath = try std.fs.path.resolve(self.allocator, &[_][]const u8{ cwd, linkPath });
            defer self.allocator.free(absLinkedPath);

            // ! Handles the deletion of the package
            // ! as the package can ONLY be deleted,
            // ! if no other project uses it
            // !
            try UtilsManifest.removePathFromManifest(
                &self.json,
                self.packageName,
                self.package.id,
                absLinkedPath,
            );
            try std.fs.cwd().deleteDir(linkPath);
        }
        try self.removePackageFromJson();
        try self.printer.append("Successfully deleted - {s}\n\n", .{self.packageName}, .{ .color = 32 });
    }

    /// Remove package from `zep.json` and `zep.lock`
    pub fn removePackageFromJson(self: *Uninstaller) !void {
        var packageJson = try UtilsManifest.readManifest(Structs.PackageJsonStruct, self.allocator, Constants.ZEP_PACKAGE_FILE);
        var lockJson = try UtilsManifest.readManifest(Structs.PackageLockStruct, self.allocator, Constants.ZEP_LOCK_PACKAGE_FILE);

        var packageJsonValue = packageJson.value;
        defer packageJson.deinit();

        var lockJsonValue = lockJson.value;
        defer lockJson.deinit();

        const previous_verbosity = Locales.VERBOSITY_MODE;
        Locales.VERBOSITY_MODE = 0;
        try self.package.manifestRemove(&packageJsonValue);
        try self.package.lockRemove(&lockJsonValue);
        Locales.VERBOSITY_MODE = previous_verbosity;
    }
};

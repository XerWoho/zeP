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

/// Handles the uninstallation of a package
pub const Uninstaller = struct {
    allocator: std.mem.Allocator,
    json: UtilsJson.Json,
    package: UtilsPackage.Package,
    printer: *UtilsPrinter.Printer,

    /// Initialize the uninstaller with allocator, package name, and printer
    pub fn init(allocator: std.mem.Allocator, packageName: []const u8, printer: *UtilsPrinter.Printer) !Uninstaller {
        const json = try UtilsJson.Json.init(allocator);
        const package = try UtilsPackage.Package.init(allocator, packageName, printer);
        if (package == null) {
            std.process.exit(0);
            return;
        }
        return Uninstaller{ .allocator = allocator, .package = package.?, .json = json, .printer = printer };
    }

    pub fn deinit(self: *Uninstaller) void {
        self.package.deinit();
    }

    /// Main uninstallation routine
    pub fn uninstall(self: *Uninstaller) !void {
        if (Locales.VERBOSITY_MODE >= 1) {
            const msg = try std.fmt.allocPrint(self.allocator, "Deleting Package...\n[{s}]\n\n", .{self.package.packageName});
            try self.printer.append(msg);
        }

        try self.removePackageFromJson();

        var injector = UtilsInjector.Injector.init(self.allocator, self.package.packageName, self.printer);
        try injector.initInjector();

        // Remove symbolic link
        const linkPath = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ Constants.ZEP_FOLDER, self.package.packageName });
        defer self.allocator.free(linkPath);
        if (try UtilsFs.checkDirExists(linkPath)) {
            const cwd = try std.fs.cwd().realpathAlloc(self.allocator, ".");
            defer self.allocator.free(cwd);

            const absLinkedPath = try std.fs.path.resolve(self.allocator, &[_][]const u8{ cwd, linkPath });
            defer self.allocator.free(absLinkedPath);

            try self.removePathFromManifest(absLinkedPath);
            try std.fs.cwd().deleteDir(linkPath);
        }

        try self.removePackageFromJson();

        // Check if package is used by other projects
        const pkgManifest = try self.json.parsePkgManifest();
        if (pkgManifest) |pkg| {
            defer pkg.deinit();
            for (pkg.value.packages) |p| {
                if (!std.mem.eql(u8, p.name, self.package.packageName)) continue;
                if (p.paths.len != 0) return;
            }
        }

        const deleted = try self.deletePackage();
        if (deleted and Locales.VERBOSITY_MODE >= 1) {
            const msg = try std.fmt.allocPrint(self.allocator, "Successfully deleted - {s}\n\n", .{self.package.packageName});
            try self.printer.append(msg);
        }
    }

    /// Deletes the package directory
    pub fn deletePackage(self: *Uninstaller) !bool {
        const allocator = std.heap.page_allocator;
        const pkgPath = try std.fmt.allocPrint(allocator, "{s}/{s}/", .{ Constants.ROOT_ZEP_PKG_FOLDER, self.package.packageName });
        defer allocator.free(pkgPath);

        if (!try UtilsFs.checkDirExists(pkgPath)) {
            if (Locales.VERBOSITY_MODE >= 1) {
                try self.printer.append("Package not in storage...\nNothing to uninstall...\n\n");
            }
            return false;
        }

        try std.fs.cwd().deleteTree(pkgPath);
        return true;
    }

    /// Remove package from `pkg.json` and `zep.lock`
    pub fn removePackageFromJson(self: *Uninstaller) !void {
        const pkgJsonOpt = try self.json.parsePkgJson();
        const lockJsonOpt = try self.json.parseLockJson();

        if (pkgJsonOpt == null or lockJsonOpt == null) {
            try self.printer.append("\nNO JSON OR LOCK FILE!\n");
            return;
        }

        var pkgJson = pkgJsonOpt.?.value;
        defer pkgJsonOpt.?.deinit();

        var lockJson = lockJsonOpt.?.value;
        defer lockJsonOpt.?.deinit();

        try self.package.pkgRemovePackage(&pkgJson);
        try self.package.lockRemovePackage(&lockJson);
    }

    /// Remove a symbolic link path from the manifest
    pub fn removePathFromManifest(self: *Uninstaller, linkedPath: []const u8) !void {
        const pkgManifest = try self.json.parsePkgManifest();
        var pkgVal: Structs.PkgsManifest = Structs.PkgsManifest{ .packages = &[_]Structs.PkgManifest{} };
        defer if (pkgManifest) |pkg| pkg.deinit();
        if (pkgManifest) |pkg| pkgVal = pkg.value;

        var list = std.ArrayList(Structs.PkgManifest).init(self.allocator);
        defer list.deinit();

        var listPath = std.ArrayList([]const u8).init(self.allocator);
        defer listPath.deinit();

        for (pkgVal.packages) |p| {
            if (std.mem.eql(u8, p.name, self.package.packageName)) {
                for (p.paths) |path| {
                    if (std.mem.eql(u8, path, linkedPath)) continue;
                    try listPath.append(path);
                }
                continue;
            }
            try list.append(p);
        }

        if (listPath.items.len > 0) {
            try list.append(Structs.PkgManifest{ .name = self.package.packageName, .paths = listPath.items });
        }

        pkgVal.packages = list.items;
        const str = try std.json.stringifyAlloc(self.allocator, pkgVal, .{ .whitespace = .indent_2 });
        try std.fs.cwd().deleteFile(Constants.ROOT_ZEP_PKG_MANIFEST);

        const wFile = try UtilsFs.openCFile(Constants.ROOT_ZEP_PKG_MANIFEST);
        _ = try wFile.write(str);
    }
};

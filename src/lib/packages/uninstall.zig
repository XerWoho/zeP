const std = @import("std");

const Locales = @import("locales");
const Constants = @import("constants");

const Utils = @import("utils");
const UtilsJson = Utils.UtilsJson;
const UtilsPackage = Utils.UtilsPackage;
const UtilsFs = Utils.UtilsFs;
const UtilsInjector = Utils.UtilsInjector;
const UtilsPrinter = Utils.UtilsPrinter;

pub const Uninstaller = struct {
    allocator: std.mem.Allocator,
    json: UtilsJson.Json,
    package: UtilsPackage.Package,
    printer: *UtilsPrinter.Printer,

    pub fn init(allocator: std.mem.Allocator, packageName: []const u8, printer: *UtilsPrinter.Printer) !Uninstaller {
        const json = try UtilsJson.Json.init(allocator);
        const package = try UtilsPackage.Package.init(allocator, packageName, printer);
        if (package == null) {
            std.process.exit(0);
            return;
        }
        return Uninstaller{ .allocator = allocator, .package = package.?, .json = json, .printer = printer };
    }

    pub fn uninstall(self: *Uninstaller) !void {
        if (Locales.VERBOSITY_MODE >= 1) {
            const deleting = try std.fmt.allocPrint(self.allocator, "Deleting Package...\n[{s}]\n\n", .{self.package.packageName});
            try self.printer.append(deleting);
        }

        if (try self.deletePackage() and true) {
            if (Locales.VERBOSITY_MODE >= 1) {
                const deleted = try std.fmt.allocPrint(self.allocator, "Successfully deleted - {s}\n\n", .{self.package.packageName});
                try self.printer.append(deleted);
            }
        }

        try self.removePackageFromJson();

        var injector = UtilsInjector.Injector.init(self.allocator, self.package.packageName, self.printer);
        try injector.initInjector();

        // remove a symbolic link
        const linkPath = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ Constants.ZEP_FOLDER, self.package.packageName });
        defer self.allocator.free(linkPath);
        try std.fs.cwd().deleteDir(linkPath);
    }

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

        var package = self.package;
        try package.pkgRemovePackage(&pkgJson);
        try package.lockRemovePackage(&lockJson);
    }
};

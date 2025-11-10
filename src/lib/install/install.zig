const std = @import("std");

const Locales = @import("locales");
const Constants = @import("constants");
const Structs = @import("structs");

const Utils = @import("utils");
const UtilsJson = Utils.UtilsJson;
const UtilsFs = Utils.UtilsFs;
const UtilsCompression = Utils.UtilsCompression;
const UtilsInjector = Utils.UtilsInjector;
const UtilsPackage = Utils.UtilsPackage;
const UtilsPrinter = Utils.UtilsPrinter;

const CachePackage =
    @import("lib/cachePackage.zig");
const DownloadPackage =
    @import("lib/downloadPackage.zig");
const Init =
    @import("../init/init.zig");

pub const Installer = struct {
    allocator: std.mem.Allocator,

    json: UtilsJson.Json,
    package: UtilsPackage.Package,
    downloader: DownloadPackage.Downloader,
    cacher: CachePackage.Cacher,

    printer: *UtilsPrinter.Printer,

    pub fn init(allocator: std.mem.Allocator, printer: *UtilsPrinter.Printer, packageName: ?[]const u8) anyerror!Installer {
        var json = try UtilsJson.Json.init(allocator);
        if (packageName == null) {
            try printer.append("Installing all packages...\n");
            try installAll(allocator, &json, printer);
            std.process.exit(0);
            return error.NoPackage;
        }

        const package = try UtilsPackage.Package.init(allocator, packageName.?, printer);
        if (package == null) {
            std.process.exit(0);
            return error.NoPackage;
        }

        const cacher = try CachePackage.Cacher.init(allocator, package.?, printer);
        const downloader = try DownloadPackage.Downloader.init(allocator, package.?, cacher, printer);

        return Installer{ .allocator = allocator, .package = package.?, .downloader = downloader, .cacher = cacher, .json = json, .printer = printer };
    }

    pub fn install(self: *Installer) !void {
        var package = self.package;
        if (Locales.VERBOSITY_MODE >= 1) {
            try self.printer.append("Downloading Package...\n");
        }

        try self.downloader.downloadPackage();
        if (Locales.VERBOSITY_MODE >= 1)
            try self.printer.append("\nChecking fingerprint...\n");

        const fingerprint = try package.checkFingerprint();
        if (Locales.VERBOSITY_MODE >= 1 and fingerprint)
            try self.printer.append("FINGERPRINT IDENTICAL!\n");

        if (Locales.VERBOSITY_MODE >= 1)
            try self.printer.append("\nChecking Caching...\n");

        const isCached = try self.cacher.isPackageCached();
        if (isCached) {
            if (Locales.VERBOSITY_MODE >= 1) {
                try self.printer.append("PACKAGE ALREADY CACHED! SKIPPING CACHING!\n\n");
            }
        } else {
            if (Locales.VERBOSITY_MODE >= 1)
                try self.printer.append("\nCaching...\n");

            const cached = try self.cacher.cachePackage();
            if (cached and Locales.VERBOSITY_MODE >= 1)
                try self.printer.append("PACKAGE CACHED!\n\n");
        }

        try self.addPackageToJson();

        if (Locales.VERBOSITY_MODE >= 1) {
            const success = try std.fmt.allocPrint(self.allocator, "Successfully installed - {s}\n\n", .{package.packageName});
            try self.printer.append(success);
        }

        var injector = UtilsInjector.Injector.init(self.allocator, package.packageName, self.printer);
        try injector.initInjector();

        // create a symbolic link
        const targetPath = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ Constants.ROOT_ZEP_PKG_FOLDER, package.packageName });
        defer self.allocator.free(targetPath);

        var openTargetDir = try UtilsFs.openCDir(targetPath);
        defer openTargetDir.close();

        const linkPath = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ Constants.ZEP_FOLDER, package.packageName });
        defer self.allocator.free(linkPath);
        if (!try UtilsFs.checkDirExists(linkPath)) {
            _ = try std.fs.cwd().makePath(linkPath);
        } else {
            return;
        }

        var openLinkPath = try UtilsFs.openDir(linkPath);
        defer openLinkPath.close();
        const lAbsPath = try openLinkPath.realpathAlloc(self.allocator, ".");
        defer self.allocator.free(lAbsPath);
        _ = try std.fs.cwd().deleteDir(lAbsPath);
        try openTargetDir.symLink(targetPath, lAbsPath, .{ .is_directory = true });
    }

    pub fn addPackageToJson(self: *Installer) !void {
        var pkgJson = try self.json.parsePkgJson();
        var lckJson = try self.json.parseLockJson();

        if (pkgJson == null or lckJson == null) {
            try self.printer.append("\nNO JSON OR LOCK FILE!\nInitializing now...\n");
            var initter = try Init.Init.init(self.allocator);
            try initter.commitInit();
            pkgJson = try self.json.parsePkgJson() orelse return error.InitFailed;
            lckJson = try self.json.parseLockJson() orelse return error.InitFailed;
        }

        defer pkgJson.?.deinit();
        defer lckJson.?.deinit();

        var packageJson = pkgJson.?.value;
        var lockJson = lckJson.?.value;

        var package = self.package;
        try package.pkgAppendPackage(&packageJson);
        try package.lockAppendPackage(&lockJson);
    }
};

fn installAll(allocator: std.mem.Allocator, json: *UtilsJson.Json, printer: *UtilsPrinter.Printer) !void {
    const pkgJsonOpt = try json.parsePkgJson();
    if (pkgJsonOpt == null) {
        var initter = try Init.Init.init(allocator);
        try initter.commitInit();

        try printer.append("zep.json not initialized. Initializing...\n");
        try printer.append("Nothing to install...\n");
        return;
    }

    Locales.VERBOSITY_MODE = 0;

    const pkgJson = pkgJsonOpt.?.value;
    defer pkgJsonOpt.?.deinit();

    for (pkgJson.packages) |p| {
        const installing = try std.fmt.allocPrint(allocator, " > Installing - {s}...\n", .{p});
        try printer.append(installing);
        var installer = try Installer.init(allocator, printer, p);
        try installer.install();
    }

    try printer.append("\nFinished installing!\n");
    Locales.VERBOSITY_MODE = 1;
}

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

const CachePackage = @import("lib/cachePackage.zig");
const DownloadPackage = @import("lib/downloadPackage.zig");
const Init = @import("init.zig");

/// Check if an array of strings, contains a specific
/// string
fn stringInArray(haystack: [][]const u8, needle: []const u8) bool {
    for (haystack) |h| {
        if (std.mem.eql(u8, h, needle)) return true;
    }
    return false;
}

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

        const package = try UtilsPackage.Package.init(allocator, packageName.?, printer) orelse {
            std.process.exit(0);
            return error.NoPackage;
        };

        const cacher = try CachePackage.Cacher.init(allocator, package, printer);
        const downloader = try DownloadPackage.Downloader.init(allocator, package, cacher, printer);

        return Installer{
            .allocator = allocator,
            .package = package,
            .downloader = downloader,
            .cacher = cacher,
            .json = json,
            .printer = printer,
        };
    }

    pub fn deinit(self: *Installer) void {
        self.cacher.deinit();
        self.downloader.deinit();
        self.package.deinit();
    }

    pub fn install(self: *Installer) !void {
        var pkg = self.package;

        if (Locales.VERBOSITY_MODE >= 1) try self.printer.append("Downloading Package...\n");
        try self.downloader.downloadPackage();

        if (Locales.VERBOSITY_MODE >= 1) try self.printer.append("\nChecking fingerprint...\n");
        if (try pkg.checkFingerprint() and Locales.VERBOSITY_MODE >= 1) try self.printer.append("FINGERPRINT IDENTICAL!\n");

        if (Locales.VERBOSITY_MODE >= 1) try self.printer.append("\nChecking Caching...\n");
        if (!(try self.cacher.isPackageCached())) {
            if (Locales.VERBOSITY_MODE >= 1) try self.printer.append("\nCaching...\n");

            try self.cacher.cachePackage();
            if (Locales.VERBOSITY_MODE >= 1) try self.printer.append("PACKAGE CACHED!\n\n");
        } else if (Locales.VERBOSITY_MODE >= 1) try self.printer.append("PACKAGE ALREADY CACHED! SKIPPING CACHING!\n\n");

        try self.addPackageToJson();

        if (Locales.VERBOSITY_MODE >= 1) {
            const success = try std.fmt.allocPrint(self.allocator, "Successfully installed - {s}\n\n", .{pkg.packageName});
            try self.printer.append(success);
        }

        var injector = UtilsInjector.Injector.init(self.allocator, pkg.packageName, self.printer);
        try injector.initInjector();

        // symbolic link
        const targetPath = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ Constants.ROOT_ZEP_PKG_FOLDER, pkg.packageName });
        defer self.allocator.free(targetPath);

        const linkPath = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ Constants.ZEP_FOLDER, pkg.packageName });
        defer self.allocator.free(linkPath);

        const cwd = try std.fs.cwd().realpathAlloc(self.allocator, ".");
        defer self.allocator.free(cwd);

        const absLinkedPath = try std.fs.path.resolve(self.allocator, &[_][]const u8{ cwd, linkPath });
        defer self.allocator.free(absLinkedPath);

        if (try UtilsFs.checkDirExists(linkPath)) try std.fs.cwd().deleteDir(linkPath);
        try std.fs.cwd().symLink(targetPath, linkPath, .{ .is_directory = true });

        try self.addPathToManifest(absLinkedPath);
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

        try self.package.pkgAppendPackage(&pkgJson.?.value);
        try self.package.lockAppendPackage(&lckJson.?.value);
    }

    pub fn addPathToManifest(self: *Installer, linkedPath: []const u8) !void {
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
                for (p.paths) |path| try listPath.append(path);
                continue;
            }
            try list.append(p);
        }

        if (!stringInArray(listPath.items, linkedPath)) try listPath.append(linkedPath);
        // if (!std.mem.indexOf([]u8, listPath.items, linkedPath)) try listPath.append(linkedPath);
        try list.append(Structs.PkgManifest{ .name = self.package.packageName, .paths = listPath.items });

        pkgVal.packages = list.items;
        const str = try std.json.stringifyAlloc(self.allocator, pkgVal, .{ .whitespace = .indent_2 });
        const wFile = try UtilsFs.openCFile(Constants.ROOT_ZEP_PKG_MANIFEST);
        _ = try wFile.write(str);
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

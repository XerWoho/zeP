const std = @import("std");
const builtin = @import("builtin");

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
const UtilsManifest = Utils.UtilsManifest;

const CachePackage = @import("lib/cachePackage.zig");
const DownloadPackage = @import("lib/downloadPackage.zig");
const Init = @import("init.zig");
const Uninstaller = @import("uninstall.zig");

pub const Installer = struct {
    allocator: std.mem.Allocator,
    json: UtilsJson.Json,
    package: UtilsPackage.Package,
    downloader: DownloadPackage.Downloader,
    cacher: CachePackage.Cacher,
    printer: *UtilsPrinter.Printer,

    pub fn init(allocator: std.mem.Allocator, printer: *UtilsPrinter.Printer, packageName: ?[]const u8, packageVersionTarget: ?[]const u8) !Installer {
        if (packageName == null) {
            const previous_verbosity = Locales.VERBOSITY_MODE;
            Locales.VERBOSITY_MODE = 0;

            try printer.append("Installing all packages...\n", .{}, .{ .verbosity = 0 });

            try installAll(allocator, printer);

            Locales.VERBOSITY_MODE = previous_verbosity;
            std.process.exit(0);
            return .NoPackageSpecified;
        }

        const package = try UtilsPackage.Package.init(allocator, packageName.?, packageVersionTarget, printer) orelse {
            std.process.exit(0);
            return .PackageNotFound;
        };

        const cacher = try CachePackage.Cacher.init(allocator, package, printer);
        const downloader = try DownloadPackage.Downloader.init(allocator, package, cacher, printer);
        const json = try UtilsJson.Json.init(allocator);

        return Installer{
            .json = json,
            .allocator = allocator,
            .package = package,
            .downloader = downloader,
            .cacher = cacher,
            .printer = printer,
        };
    }

    pub fn deinit(self: *Installer) void {
        self.cacher.deinit();
        self.downloader.deinit();
        self.package.deinit();
    }

    pub fn install(self: *Installer) !void {
        const package = self.package;
        const parsed = package.package;

        const lock = try UtilsManifest.readManifest(Structs.PackageLockStruct, self.allocator, Constants.ZEP_LOCK_PACKAGE_FILE);
        defer lock.deinit();
        if (!std.mem.containsAtLeast(u8, parsed.zigVersion, 1, lock.value.root.zigVersion)) {
            try self.printer.append("WARNING: ", .{}, .{ .color = 31 });
            try self.printer.append("ZIG VERSIONS ARE NOT MATCHING!\n", .{}, .{ .color = 34 });
            try self.printer.append("{s} Zig Version: {s}\n", .{ package.id, parsed.zigVersion }, .{});
            try self.printer.append("Your Zig Version: {s}\n\n", .{lock.value.root.zigVersion}, .{});
        }

        for (lock.value.packages) |lockPackage| {
            if (std.mem.startsWith(u8, lockPackage.name, self.package.packageName)) {
                if (std.mem.eql(u8, lockPackage.name, self.package.id)) {
                    try self.setPackage();
                    return error.AlreadyInstalled;
                }
                const previous_verbosity = Locales.VERBOSITY_MODE;
                Locales.VERBOSITY_MODE = 0;

                var uninstaller = try Uninstaller.Uninstaller.init(
                    self.allocator,
                    self.package.packageName,
                    self.printer,
                );

                try uninstaller.uninstall();
                Locales.VERBOSITY_MODE = previous_verbosity;
            }
        }

        try self.printer.append("Downloading Package...\n", .{}, .{});
        try self.downloader.downloadPackage(parsed.url);

        try self.printer.append("\nChecking hash...\n", .{}, .{});
        if (std.mem.eql(u8, package.packageHash, parsed.sha256sum)) {
            try self.printer.append("HASH IDENTICAL!\n", .{}, .{});
        } else {
            try self.package.deletePackage();
            try self.cacher.deletePackageFromCache();
            return error.HashMismatch;
        }

        try self.printer.append("\nChecking Caching...\n", .{}, .{});
        const isPackageCached = try self.cacher.isPackageCached();
        if (!isPackageCached) {
            try self.printer.append("\nCaching...\n", .{}, .{});

            try self.cacher.cachePackage();
            try self.printer.append("PACKAGE CACHED!\n\n", .{}, .{});
        }
        try self.printer.append("PACKAGE ALREADY CACHED! SKIPPING CACHING!\n\n", .{}, .{});

        try self.setPackage();
        try self.printer.append("Successfully installed - {s}\n\n", .{package.packageName}, .{ .color = 32 });
    }

    fn setPackage(self: *Installer) !void {
        try self.addPackageToJson();
        const package = self.package;

        var injector = UtilsInjector.Injector.init(self.allocator, package.packageName, self.printer);
        try injector.initInjector();

        // symbolic link
        const targetPath = try std.fmt.allocPrint(self.allocator, "{s}/{s}@{s}", .{ Constants.ROOT_ZEP_PKG_FOLDER, package.packageName, package.packageVersion });
        defer self.allocator.free(targetPath);

        const linkPath = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ Constants.ZEP_FOLDER, package.packageName });
        std.fs.cwd().deleteDir(linkPath) catch {};
        std.fs.cwd().deleteFile(linkPath) catch {};
        defer self.allocator.free(linkPath);

        const cwd = try std.fs.cwd().realpathAlloc(self.allocator, ".");
        defer self.allocator.free(cwd);

        const absLinkedPath = try std.fs.path.resolve(self.allocator, &[_][]const u8{ cwd, linkPath });
        defer self.allocator.free(absLinkedPath);
        try std.fs.cwd().symLink(targetPath, linkPath, .{ .is_directory = true });
        UtilsManifest.addPathToManifest(
            &self.json,
            self.package.id,
            absLinkedPath,
        ) catch {
            try self.printer.append("Adding to manifest failed!\n", .{}, .{ .color = 31 });
        };
    }

    fn addPackageToJson(self: *Installer) !void {
        var packageJson = try UtilsManifest.readManifest(Structs.PackageJsonStruct, self.allocator, Constants.ZEP_PACKAGE_FILE);
        var lockJson = try UtilsManifest.readManifest(Structs.PackageLockStruct, self.allocator, Constants.ZEP_LOCK_PACKAGE_FILE);

        defer packageJson.deinit();
        defer lockJson.deinit();
        try self.package.manifestAdd(&packageJson.value);
        try self.package.lockAdd(&lockJson.value);
    }
};

fn installAll(allocator: std.mem.Allocator, printer: *UtilsPrinter.Printer) anyerror!void {
    var pkgJson = try UtilsManifest.readManifest(Structs.PackageJsonStruct, allocator, Constants.ZEP_PACKAGE_FILE);

    const pkgJsonValue = pkgJson.value;
    defer pkgJson.deinit();
    for (pkgJsonValue.packages) |packageId| {
        try printer.append(" > Installing - {s}...\n", .{packageId}, .{ .verbosity = 0 });

        var packageSplit = std.mem.splitScalar(u8, packageId, '@');
        const packageName = packageSplit.first();
        const packageVersion = packageSplit.next();
        var installer = try Installer.init(allocator, printer, packageName, packageVersion);
        installer.install() catch |err| {
            switch (err) {
                error.AlreadyInstalled => {
                    try printer.append(" >> already installed!\n", .{}, .{ .verbosity = 0, .color = 32 });
                    continue;
                },
                else => {
                    try printer.append("  ! [ERROR] Failed to install - {s}...\n", .{packageId}, .{ .verbosity = 0 });
                },
            }
        };
        try printer.append(" >> done!\n", .{}, .{ .verbosity = 0, .color = 32 });
    }
    try printer.append("\nInstalled all!\n", .{}, .{ .verbosity = 0, .color = 32 });
}

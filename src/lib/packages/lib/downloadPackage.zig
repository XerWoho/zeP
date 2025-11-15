const std = @import("std");

const Locales = @import("locales");
const Constants = @import("constants");
const Structs = @import("structs");

const Utils = @import("utils");
const UtilsFs = Utils.UtilsFs;
const UtilsJson = Utils.UtilsJson;
const UtilsPackage = Utils.UtilsPackage;
const UtilsCompression = Utils.UtilsCompression;
const UtilsPrinter = Utils.UtilsPrinter;

const CachePackage =
    @import("cachePackage.zig");

pub const Downloader = struct {
    allocator: std.mem.Allocator,
    cacher: CachePackage.Cacher,
    package: UtilsPackage.Package,
    printer: *UtilsPrinter.Printer,

    pub fn init(allocator: std.mem.Allocator, package: UtilsPackage.Package, cacher: CachePackage.Cacher, printer: *UtilsPrinter.Printer) !Downloader {
        return Downloader{ .allocator = allocator, .cacher = cacher, .package = package, .printer = printer };
    }

    pub fn deinit(self: *Downloader) void {
        defer {
            self.cacher.deinit();
            self.package.deinit();
        }
    }

    fn cloneGit(self: *Downloader) !void {
        const url = self.package.packageParsed.value.git;
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}/", .{ Constants.ROOT_ZEP_PKG_FOLDER, self.package.packageName });
        defer self.allocator.free(path);

        if (try UtilsFs.checkDirExists(path)) {
            try UtilsFs.delDir(path);
        }
        try std.fs.cwd().makeDir(path);

        if (Locales.VERBOSITY_MODE >= 1) {
            const cloning = try std.fmt.allocPrint(self.allocator, "Cloning Git Repo... \n[{s}]\n", .{url});
            try self.printer.append(cloning);
        }

        var child = std.process.Child.init(&.{ "git", "clone", "--depth", "1", url, path }, self.allocator);
        if (Locales.VERBOSITY_MODE == 0) {
            child.stdin_behavior = .Ignore;
            child.stdout_behavior = .Ignore;
            child.stderr_behavior = .Ignore;
        }
        _ = try child.spawnAndWait();

        if (Locales.VERBOSITY_MODE >= 1) {
            try self.printer.append("Filtering unimportant folders...\n\n");
        }

        for (Constants.FILTER_PACKAGE_FOLDERS) |folder| {
            const folderPath = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ path, folder });
            defer self.allocator.free(folderPath);
            try UtilsFs.delTree(folderPath);
        }
        for (Constants.FILTER_PACKAGE_FILES) |file| {
            const filePath = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ path, file });
            defer self.allocator.free(filePath);
            try UtilsFs.delFile(filePath);
        }
    }

    fn doesPackageExist(self: *Downloader) !bool {
        const path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}/", .{ Constants.ROOT_ZEP_PKG_FOLDER, self.package.packageName });
        defer std.heap.page_allocator.free(path);
        return try UtilsFs.checkDirExists(path);
    }

    pub fn downloadPackage(self: *Downloader) !void {
        const outdated = false;
        const exists = try self.doesPackageExist();

        if (!outdated) {
            if (Locales.VERBOSITY_MODE >= 1) try self.printer.append(" > PACKAGE NOT OUTDATED!\n");
            if (exists) return;

            if (Locales.VERBOSITY_MODE >= 1) try self.printer.append(" > CHECKING CACHE!\n");
            if (try self.cacher.getPackageFromCache()) {
                if (Locales.VERBOSITY_MODE >= 1) try self.printer.append(" > CACHE HIT!\n\n");
                return;
            } else if (Locales.VERBOSITY_MODE >= 1) {
                try self.printer.append(" > CACHE MISS!\n\n");
            }
        } else {
            const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}/", .{ Constants.ROOT_ZEP_PKG_FOLDER, self.package.packageName });
            defer self.allocator.free(path);
            try UtilsFs.delTree(path);
        }

        try self.cloneGit();
        return;
    }
};

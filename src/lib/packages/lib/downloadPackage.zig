const std = @import("std");
const builtin = @import("builtin");

const Locales = @import("locales");
const Constants = @import("constants");
const Utils = @import("utils");
const UtilsFs = Utils.UtilsFs;
const UtilsPackage = Utils.UtilsPackage;
const UtilsPrinter = Utils.UtilsPrinter;

const CachePackage = @import("cachePackage.zig");

pub const Downloader = struct {
    allocator: std.mem.Allocator,
    cacher: CachePackage.Cacher,
    package: UtilsPackage.Package,
    printer: *UtilsPrinter.Printer,

    pub fn init(allocator: std.mem.Allocator, package: UtilsPackage.Package, cacher: CachePackage.Cacher, printer: *UtilsPrinter.Printer) !Downloader {
        return Downloader{ .allocator = allocator, .cacher = cacher, .package = package, .printer = printer };
    }

    pub fn deinit(_: *Downloader) void {
        // currently no deinit required
    }

    fn packagePath(self: *Downloader) ![]u8 {
        return std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ Constants.ROOT_ZEP_PKG_FOLDER, self.package.packageName });
    }

    fn cloneGit(self: *Downloader) !void {
        const url = self.package.packageParsed.value.git;
        const path = try self.packagePath();
        defer self.allocator.free(path);

        if (try UtilsFs.checkDirExists(path)) {
            try UtilsFs.delDir(path);
        }
        try std.fs.cwd().makeDir(path);

        if (Locales.VERBOSITY_MODE >= 1) {
            const msg = try std.fmt.allocPrint(self.allocator, "Cloning Git Repo... [{s}]\n", .{url});
            try self.printer.append(msg);
        }

        var child = std.process.Child.init(&.{ "git", "clone", "--depth", "1", url, path }, self.allocator);
        if (Locales.VERBOSITY_MODE == 0) {
            child.stdin_behavior = .Ignore;
            child.stdout_behavior = .Ignore;
            child.stderr_behavior = .Ignore;
        }
        _ = try child.spawnAndWait();

        if (builtin.os.tag == .windows) {
            const dotGit = try std.fmt.allocPrint(self.allocator, "{s}/.git/objects/pack/*", .{path});
            defer self.allocator.free(dotGit);

            var rmAttrChild = std.process.Child.init(&.{ "attrib", "-R", dotGit, "/S", "/D" }, self.allocator);
            if (Locales.VERBOSITY_MODE == 0) {
                rmAttrChild.stdin_behavior = .Ignore;
                rmAttrChild.stdout_behavior = .Ignore;
                rmAttrChild.stderr_behavior = .Ignore;
            }
            _ = try rmAttrChild.spawnAndWait();
        }

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
        const path = try self.packagePath();
        defer self.allocator.free(path);
        return try UtilsFs.checkDirExists(path);
    }

    pub fn downloadPackage(self: *Downloader) !void {
        const exists = try self.doesPackageExist();

        if (exists) {
            if (Locales.VERBOSITY_MODE >= 1) try self.printer.append(" > PACKAGE ALREADY EXISTS!\n");
            return;
        }

        if (Locales.VERBOSITY_MODE >= 1) try self.printer.append(" > CHECKING CACHE...\n");

        if (try self.cacher.isPackageCached()) {
            if (try self.cacher.getPackageFromCache() and Locales.VERBOSITY_MODE >= 1) try self.printer.append(" > CACHE HIT!\n\n");
            return;
        } else if (Locales.VERBOSITY_MODE >= 1) {
            try self.printer.append(" > CACHE MISS!\n\n");
        }

        try self.cloneGit();
    }
};

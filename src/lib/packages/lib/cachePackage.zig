const std = @import("std");

const Locales = @import("locales");
const Constants = @import("constants");
const Utils = @import("utils");
const UtilsFs = Utils.UtilsFs;
const UtilsPackage = Utils.UtilsPackage;
const UtilsCompression = Utils.UtilsCompression;
const UtilsPrinter = Utils.UtilsPrinter;

pub const Cacher = struct {
    allocator: std.mem.Allocator,
    package: UtilsPackage.Package,
    compressor: UtilsCompression.Compressor,
    printer: *UtilsPrinter.Printer,

    pub fn init(
        allocator: std.mem.Allocator,
        package: UtilsPackage.Package,
        printer: *UtilsPrinter.Printer,
    ) !Cacher {
        return .{
            .allocator = allocator,
            .package = package,
            .compressor = UtilsCompression.Compressor.init(allocator, printer),
            .printer = printer,
        };
    }

    pub fn deinit(_: *Cacher) void {}

    // ---------------------------
    // PATH HELPERS
    // ---------------------------

    fn cacheFilePath(self: *Cacher) ![]u8 {
        return try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}@{s}.zep",
            .{
                Constants.ROOT_ZEP_ZEPPED_FOLDER,
                self.package.packageName,
                self.package.packageVersion,
            },
        );
    }

    fn extractPath(self: *Cacher) ![]u8 {
        return try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}@{s}",
            .{
                Constants.ROOT_ZEP_PKG_FOLDER,
                self.package.packageName,
                self.package.packageVersion,
            },
        );
    }

    fn tmpOutputPath(self: *Cacher) ![]u8 {
        return try std.fmt.allocPrint(
            self.allocator,
            ".ZEPtmp/{s}@{s}",
            .{ self.package.packageName, self.package.packageVersion },
        );
    }

    // ---------------------------
    // CACHE CHECK
    // ---------------------------

    pub fn isPackageCached(self: *Cacher) !bool {
        const path = try self.cacheFilePath();
        defer self.allocator.free(path);

        return UtilsFs.checkFileExists(path);
    }

    // ---------------------------
    // EXTRACT FROM CACHE
    // ---------------------------

    pub fn getPackageFromCache(self: *Cacher) !bool {
        const isCached = try self.isPackageCached();
        if (!isCached) return false;

        const _tmpOutputPath = try self.tmpOutputPath();
        var tmpDir = try UtilsFs.openCDir(_tmpOutputPath);
        defer {
            tmpDir.close();
            std.fs.cwd().deleteTree(".ZEPtmp") catch {
                self.printer.append("\nFailed to deleted .ZEPtmp!\n", .{}, .{ .color = 31 }) catch {};
            };
            self.allocator.free(_tmpOutputPath);
        }

        const cachePath = try self.cacheFilePath();
        defer self.allocator.free(cachePath);

        const destPath = try self.extractPath();
        defer self.allocator.free(destPath);

        return try self.compressor.decompress(cachePath, destPath);
    }

    pub fn setPackageToCache(self: *Cacher, targetFolder: []const u8) !bool {
        const cfPath = try self.cacheFilePath();
        return try self.compressor.compress(targetFolder, cfPath);
    }

    pub fn deletePackageFromCache(self: *Cacher) !void {
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.zep", .{ Constants.ROOT_ZEP_ZEPPED_FOLDER, self.package.id });
        defer self.allocator.free(path);

        if (UtilsFs.checkFileExists(path)) {
            try UtilsFs.delFile(path);
        }
    }

    // ---------------------------
    // WRITE CACHE METADATA / LOG
    // ---------------------------

    pub fn cachePackage(self: *Cacher) !void {
        try self.printer.append(
            " > PACKAGE CACHED: {s}\n",
            .{self.package.packageName},
            .{},
        );
    }
};

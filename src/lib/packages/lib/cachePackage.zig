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

    pub fn init(allocator: std.mem.Allocator, package: UtilsPackage.Package, printer: *UtilsPrinter.Printer) !Cacher {
        const compressor = try UtilsCompression.Compressor.init(allocator, printer);
        return Cacher{
            .allocator = allocator,
            .package = package,
            .compressor = compressor,
            .printer = printer,
        };
    }

    pub fn deinit(_: *Cacher) void {
        // currently no deinit required
    }

    fn cacheFilePath(self: *Cacher) ![]u8 {
        return std.fmt.allocPrint(self.allocator, "{s}/{s}_{s}.zep", .{ Constants.ROOT_ZEP_ZEPPED_FOLDER, self.package.packageName, self.package.packageFingerprint });
    }

    fn extractPath(self: *Cacher) ![]u8 {
        return std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ Constants.ROOT_ZEP_PKG_FOLDER, self.package.packageName });
    }

    pub fn isPackageCached(self: *Cacher) !bool {
        const path = try self.cacheFilePath();
        defer self.allocator.free(path);
        return try UtilsFs.checkFileExists(path);
    }

    pub fn getPackageFromCache(self: *Cacher) !bool {
        if (!try self.isPackageCached()) return false;

        const zepPath = try self.cacheFilePath();
        defer self.allocator.free(zepPath);

        const extractedPath = try self.extractPath();
        defer self.allocator.free(extractedPath);

        _ = try self.compressor.decompress(zepPath, extractedPath);
        return true;
    }

    pub fn cachePackage(self: *Cacher) !void {
        const targetFolder = try self.extractPath();
        defer self.allocator.free(targetFolder);

        const tarPath = try self.cacheFilePath();
        defer self.allocator.free(tarPath);

        try self.compressor.compress(targetFolder, tarPath);

        if (Locales.VERBOSITY_MODE >= 1) {
            try self.printer.append(" > PACKAGE CACHED: ");
            try self.printer.append(self.package.packageName);
            try self.printer.append("\n");
        }
    }
};

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

pub const Cacher = struct {
    allocator: std.mem.Allocator,
    package: UtilsPackage.Package,
    compressor: UtilsCompression.Compressor,
    printer: *UtilsPrinter.Printer,

    pub fn init(allocator: std.mem.Allocator, package: UtilsPackage.Package, printer: *UtilsPrinter.Printer) !Cacher {
        const compressor = try UtilsCompression.Compressor.init(allocator, package, printer);
        return Cacher{ .allocator = allocator, .package = package, .compressor = compressor.?, .printer = printer };
    }

    pub fn deinit(self: *Cacher) void {
        defer {
            self.package.deinit();
        }
    }

    pub fn isPackageCached(self: *Cacher) !bool {
        const cachedPackage = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}_{s}.zep",
            .{ Constants.ROOT_ZEP_ZEPPED_FOLDER, self.package.packageName, self.package.packageFingerprint },
        );
        defer self.allocator.free(cachedPackage);

        return try UtilsFs.checkFileExists(cachedPackage);
    }

    pub fn getPackageFromCache(self: *Cacher) !bool {
        const cached = try self.isPackageCached();
        if (!cached) return false;

        return try self.compressor.decompress();
    }

    pub fn cachePackage(self: *Cacher) !bool {
        try self.compressor.compress();

        if (Locales.VERBOSITY_MODE >= 1) {
            try self.printer.append(" > PACKAGE CACHED: ");
            try self.printer.append(self.package.packageName);
            try self.printer.append("\n");
        }

        return true;
    }
};

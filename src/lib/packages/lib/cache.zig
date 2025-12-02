const std = @import("std");

const Locales = @import("locales");
const Constants = @import("constants");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Package = @import("core").Package.Package;
const Compressor = @import("core").Compression.Compressor;

const TEMPORARY_DIRECTORY_PATH = ".zep/.ZEPtmp";

pub const Cacher = struct {
    allocator: std.mem.Allocator,
    package: Package,
    compressor: Compressor,
    printer: *Printer,

    pub fn init(
        allocator: std.mem.Allocator,
        package: Package,
        printer: *Printer,
    ) !Cacher {
        return .{
            .allocator = allocator,
            .package = package,
            .compressor = Compressor.init(allocator, printer),
            .printer = printer,
        };
    }

    pub fn deinit(_: *Cacher) void {}

    // ---------------------------
    // PATH HELPERS
    // ---------------------------

    fn cacheFilePath(self: *Cacher) ![]u8 {
        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();

        return try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}@{s}.zep",
            .{
                try self.allocator.dupe(u8, paths.zepped),
                self.package.package_name,
                self.package.package_version,
            },
        );
    }

    fn extractPath(self: *Cacher) ![]u8 {
        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();

        return try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}@{s}",
            .{
                try self.allocator.dupe(u8, paths.pkg_root),
                self.package.package_name,
                self.package.package_version,
            },
        );
    }

    fn tmpOutputPath(self: *Cacher) ![]u8 {
        return try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}@{s}",
            .{ TEMPORARY_DIRECTORY_PATH, self.package.package_name, self.package.package_version },
        );
    }

    // ---------------------------
    // CACHE CHECK
    // ---------------------------

    pub fn isPackageCached(self: *Cacher) !bool {
        const path = try self.cacheFilePath();
        defer self.allocator.free(path);

        return Fs.existsFile(path);
    }

    // ---------------------------
    // EXTRACT FROM CACHE
    // ---------------------------

    pub fn getPackageFromCache(self: *Cacher) !bool {
        const is_cached = try self.isPackageCached();
        if (!is_cached) return false;

        const temporary_output_path = try self.tmpOutputPath();
        var temporary_directory = try Fs.openOrCreateDir(temporary_output_path);
        defer {
            temporary_directory.close();
            Fs.deleteTreeIfExists(TEMPORARY_DIRECTORY_PATH) catch {
                self.printer.append("\nFailed to delete {s}!\n", .{TEMPORARY_DIRECTORY_PATH}, .{ .color = 31 }) catch {};
            };
            self.allocator.free(temporary_output_path);
        }

        const cache_path = try self.cacheFilePath();
        defer self.allocator.free(cache_path);

        const extract_path = try self.extractPath();
        defer self.allocator.free(extract_path);

        return try self.compressor.decompress(cache_path, extract_path);
    }

    pub fn setPackageToCache(self: *Cacher, target_folder: []const u8) !bool {
        return try self.compressor.compress(target_folder, try self.cacheFilePath());
    }

    pub fn deletePackageFromCache(self: *Cacher) !void {
        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();

        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.zep", .{ paths.zepped, self.package.id });
        defer self.allocator.free(path);

        if (Fs.existsFile(path)) {
            try Fs.deleteFileIfExists(path);
        }
    }

    // ---------------------------
    // WRITE CACHE METADATA / LOG
    // ---------------------------

    pub fn cachePackage(self: *Cacher) !void {
        try self.printer.append(
            " > PACKAGE CACHED: {s}\n",
            .{self.package.package_name},
            .{},
        );
    }
};

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
    paths: *Constants.Paths.Paths,

    pub fn init(
        allocator: std.mem.Allocator,
        package: Package,
        printer: *Printer,
        paths: *Constants.Paths.Paths,
    ) !Cacher {
        return .{
            .allocator = allocator,
            .package = package,
            .compressor = Compressor.init(allocator, printer, paths),
            .printer = printer,
            .paths = paths,
        };
    }

    pub fn deinit(_: *Cacher) void {}

    fn cacheFilePath(self: *Cacher) ![]u8 {
        const zstd_id = try std.fmt.allocPrint(
            self.allocator,
            "{s}@{s}.tar.zstd",
            .{
                self.package.package_name,
                self.package.package_version,
            },
        );
        const cache_fp = try std.fs.path.join(
            self.allocator,
            &.{
                self.paths.zepped,
                zstd_id,
            },
        );

        return cache_fp;
    }

    fn extractPath(self: *Cacher) ![]u8 {
        const extract_p = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}@{s}",
            .{
                self.paths.pkg_root,
                self.package.package_name,
                self.package.package_version,
            },
        );

        return extract_p;
    }

    fn tmpOutputPath(self: *Cacher) ![]u8 {
        const tmp_p = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}@{s}",
            .{
                TEMPORARY_DIRECTORY_PATH,
                self.package.package_name,
                self.package.package_version,
            },
        );

        return tmp_p;
    }

    pub fn isPackageCached(self: *Cacher) !bool {
        const path = try self.cacheFilePath();
        return Fs.existsFile(path);
    }

    pub fn getPackageFromCache(self: *Cacher) !bool {
        const is_cached = try self.isPackageCached();
        if (!is_cached) return false;

        const temporary_output_path = try self.tmpOutputPath();
        var temporary_directory = try Fs.openOrCreateDir(temporary_output_path);
        defer {
            temporary_directory.close();
            Fs.deleteTreeIfExists(TEMPORARY_DIRECTORY_PATH) catch {
                self.printer.append("\nFailed to delete {s}!\n", .{TEMPORARY_DIRECTORY_PATH}, .{ .color = .red }) catch {};
            };
            self.allocator.free(temporary_output_path);
        }

        const cache_path = try self.cacheFilePath();
        defer self.allocator.free(cache_path);

        const extract_path = try self.extractPath();
        defer self.allocator.free(extract_path);

        return try self.compressor.decompress(cache_path, extract_path);
    }

    pub fn setPackageToCache(self: *Cacher, id: []const u8) !bool {
        const target_folder = try std.fs.path.join(
            self.allocator,
            &.{ self.paths.pkg_root, id },
        );
        defer self.allocator.free(target_folder);

        try self.printer.append("Compressing now...", .{}, .{});
        return try self.compressor.compress(target_folder, try self.cacheFilePath());
    }

    pub fn deletePackageFromCache(self: *Cacher) !void {
        var buf: [256]u8 = undefined;
        const path = try std.fmt.bufPrint(
            &buf,
            "{s}/{s}.tar.zstd",
            .{
                self.paths.zepped,
                self.package.id,
            },
        );

        if (Fs.existsFile(path)) {
            try Fs.deleteFileIfExists(path);
        }
    }
};

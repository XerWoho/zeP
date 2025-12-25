const std = @import("std");

const Locales = @import("locales");
const Constants = @import("constants");

const Fs = @import("io").Fs;
const Package = @import("core").Package;

const TEMPORARY_DIRECTORY_PATH = ".zep/.ZEPtmp";

const Context = @import("context").Context;

pub const Cacher = struct {
    ctx: *Context,

    pub fn init(ctx: *Context) Cacher {
        return .{
            .ctx = ctx,
        };
    }

    pub fn deinit(_: *Cacher) void {}

    fn cacheFilePath(
        self: *Cacher,
        package_id: []const u8,
    ) ![]u8 {
        const zstd_id = try std.fmt.allocPrint(
            self.ctx.allocator,
            "{s}.tar.zstd",
            .{
                package_id,
            },
        );
        const cache_fp = try std.fs.path.join(
            self.ctx.allocator,
            &.{
                self.ctx.paths.cached,
                zstd_id,
            },
        );

        return cache_fp;
    }

    fn extractPath(
        self: *Cacher,
        package_id: []const u8,
    ) ![]u8 {
        const extract_p = try std.fs.path.join(
            self.ctx.allocator,
            &.{
                self.ctx.paths.pkg_root,
                package_id,
            },
        );

        return extract_p;
    }

    fn tmpOutputPath(
        self: *Cacher,
        package_id: []const u8,
    ) ![]u8 {
        const tmp_p = try std.fs.path.join(
            self.ctx.allocator,
            &.{
                TEMPORARY_DIRECTORY_PATH,
                package_id,
            },
        );

        return tmp_p;
    }

    pub fn isPackageCached(
        self: *Cacher,
        package_id: []const u8,
    ) !bool {
        try self.ctx.printer.append("\nChecking Cache...\n", .{}, .{});
        const path = try self.cacheFilePath(
            package_id,
        );
        return Fs.existsFile(path);
    }

    pub fn getPackageFromCache(
        self: *Cacher,
        package_id: []const u8,
    ) !void {
        try self.ctx.printer.append(" > CACHE HIT!\n", .{}, .{ .color = .green });

        const temporary_output_path = try self.tmpOutputPath(
            package_id,
        );
        var temporary_directory = try Fs.openOrCreateDir(temporary_output_path);
        defer {
            temporary_directory.close();
            Fs.deleteTreeIfExists(TEMPORARY_DIRECTORY_PATH) catch {
                self.ctx.printer.append("\nFailed to delete {s}!\n", .{TEMPORARY_DIRECTORY_PATH}, .{ .color = .red }) catch {};
            };
            self.ctx.allocator.free(temporary_output_path);
        }

        const cache_path = try self.cacheFilePath(
            package_id,
        );
        defer self.ctx.allocator.free(cache_path);

        const extract_path = try self.extractPath(
            package_id,
        );
        defer self.ctx.allocator.free(extract_path);

        self.ctx.compressor.decompress(cache_path, extract_path) catch {
            try self.ctx.printer.append(" ! CACHING FAILED!\n\n", .{}, .{ .color = .red });
        };
    }

    pub fn setPackageToCache(self: *Cacher, package_id: []const u8) !void {
        try self.ctx.printer.append("Package not cached...\n", .{}, .{});

        const target_folder = try std.fs.path.join(
            self.ctx.allocator,
            &.{
                self.ctx.paths.pkg_root,
                package_id,
            },
        );
        defer self.ctx.allocator.free(target_folder);

        try self.ctx.printer.append("Caching now...\n", .{}, .{});
        const compress_path = try self.cacheFilePath(package_id);
        const is_cached = try self.ctx.compressor.compress(target_folder, compress_path);
        if (is_cached) {
            try self.ctx.printer.append(" > PACKAGE CACHED!\n\n", .{}, .{ .color = .green });
        } else {
            try self.ctx.printer.append(" ! CACHING FAILED!\n\n", .{}, .{ .color = .red });
        }
    }

    pub fn deletePackageFromCache(
        self: *Cacher,
        package_id: []const u8,
    ) !void {
        var buf: [256]u8 = undefined;
        const path = try std.fmt.bufPrint(
            &buf,
            "{s}/{s}.tar.zstd",
            .{
                self.ctx.paths.cached,
                package_id,
            },
        );

        if (Fs.existsFile(path)) {
            try Fs.deleteFileIfExists(path);
        }
    }
};

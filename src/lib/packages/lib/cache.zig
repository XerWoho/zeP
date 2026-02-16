const std = @import("std");

pub const Cacher = @This();

const TEMP_DIR = ".zep/tmp";

const Constants = @import("constants");
const Fs = @import("io").Fs;
const Context = @import("context");

ctx: *Context,

pub fn init(ctx: *Context) Cacher {
    return .{
        .ctx = ctx,
    };
}

pub fn deinit(_: *Cacher) void {}

fn cachedArchivePath(
    self: *Cacher,
    cached_root: []const u8,
    id: []const u8,
) ![]u8 {
    const zstd_id = try std.fmt.allocPrint(
        self.ctx.allocator,
        "{s}.tar.zstd",
        .{
            id,
        },
    );
    const cache_fp = try std.fs.path.join(
        self.ctx.allocator,
        &.{
            cached_root,
            zstd_id,
        },
    );

    return cache_fp;
}

fn installPath(
    self: *Cacher,
    root: []const u8,
    id: []const u8,
) ![]u8 {
    const extract_p = try std.fs.path.join(
        self.ctx.allocator,
        &.{
            root,
            id,
        },
    );

    return extract_p;
}

fn tempExtractPath(
    self: *Cacher,
    id: []const u8,
) ![]u8 {
    const tmp_p = try std.fs.path.join(
        self.ctx.allocator,
        &.{
            TEMP_DIR,
            id,
        },
    );

    return tmp_p;
}

pub fn isCached(
    self: *Cacher,
    cached_root: []const u8,
    id: []const u8,
) !bool {
    self.ctx.logger.info("Checking Cache", @src());

    const path = try self.cachedArchivePath(
        cached_root,
        id,
    );
    return Fs.existsFile(path);
}

pub fn restore(
    self: *Cacher,
    cached_root: []const u8,
    root: []const u8,
    id: []const u8,
) !void {
    self.ctx.logger.info("Getting Cache", @src());

    const temporary_output_path = try self.tempExtractPath(id);
    var temporary_directory = try Fs.openOrCreateDir(temporary_output_path);
    defer {
        temporary_directory.close();
        Fs.deleteTreeIfExists(TEMP_DIR) catch {};
        self.ctx.allocator.free(temporary_output_path);
    }

    const cache_path = try self.cachedArchivePath(
        cached_root,
        id,
    );
    defer self.ctx.allocator.free(cache_path);

    const extract_path = try self.installPath(
        root,
        id,
    );
    defer self.ctx.allocator.free(extract_path);

    try self.ctx.compressor.decompress(cache_path, extract_path);
}

pub fn store(
    self: *Cacher,
    cached_root: []const u8,
    root: []const u8,
    id: []const u8,
) !void {
    self.ctx.logger.info("Setting Cache", @src());

    self.ctx.printer.append("Package not cached...\n", .{}, .{
        .verbosity = 3,
    });

    const target_folder = try std.fs.path.join(
        self.ctx.allocator,
        &.{
            root,
            id,
        },
    );
    defer self.ctx.allocator.free(target_folder);

    self.ctx.printer.append("Caching now...\n", .{}, .{
        .verbosity = 3,
    });
    const compress_path = try self.cachedArchivePath(cached_root, id);
    try self.ctx.compressor.compress(target_folder, compress_path);
    self.ctx.printer.append(" > PACKAGE CACHED!\n\n", .{}, .{
        .color = .green,
        .verbosity = 3,
    });
}

pub fn remove(
    self: *Cacher,
    cached_root: []const u8,
    id: []const u8,
) !void {
    self.ctx.logger.info("Deleting Cache", @src());

    const path = try std.fmt.allocPrint(
        self.ctx.allocator,
        "{s}/{s}.tar.zstd",
        .{
            cached_root,
            id,
        },
    );
    defer self.ctx.allocator.free(path);

    if (Fs.existsFile(path)) {
        try Fs.deleteFileIfExists(path);
    }
}

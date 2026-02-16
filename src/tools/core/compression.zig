const std = @import("std");

pub const Compressor = @This();

const Constants = @import("constants");

const Fs = @import("io").Fs;

const Zstd = @import("zstd.zig");

fn isInArray(haystack: []const []const u8, needle: []const u8) bool {
    for (haystack) |item| {
        if (std.mem.eql(u8, item, needle)) return true;
    }
    return false;
}

/// Handles compression using zstd, and
/// recursion.
allocator: std.mem.Allocator,
paths: Constants.Paths.Paths,

pub fn init(
    allocator: std.mem.Allocator,
    paths: Constants.Paths.Paths,
) Compressor {
    return Compressor{
        .allocator = allocator,
        .paths = paths,
    };
}

fn archive(self: *Compressor, tar_writer: *std.tar.Writer, fs_path: []const u8, real_path: []const u8) !void {
    var open_target = try Fs.openDir(fs_path);
    defer open_target.close();

    var iter = open_target.iterate();
    while (try iter.next()) |input_file_entry| {
        if (input_file_entry.kind == .sym_link) continue;
        const is_filtered = isInArray(
            switch (input_file_entry.kind) {
                .directory => &Constants.Extras.filtering.folders,
                else => &Constants.Extras.filtering.files,
            },
            input_file_entry.name,
        );
        if (is_filtered) continue;

        const tar_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ real_path, input_file_entry.name });
        const input_fs_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ fs_path, input_file_entry.name });

        if (input_file_entry.kind == .directory) {
            try tar_writer.writeDir(tar_path, .{});
            try self.archive(tar_writer, input_fs_path, tar_path);
            continue;
        }

        const reader_buffer: []u8 = try self.allocator.alloc(u8, 4096);
        const input_file = try std.fs.cwd().openFile(input_fs_path, .{ .mode = .read_only });
        defer input_file.close();

        const input_file_size: u64 = (try input_file.stat()).size;
        var input_file_reader = input_file.reader(reader_buffer);
        const input_file_reader_interface: *std.Io.Reader = &input_file_reader.interface;

        tar_writer.writeFileStream(
            tar_path,
            input_file_size,
            input_file_reader_interface,
            .{ .mtime = 0, .mode = 0 },
        ) catch {};
    }
}

pub fn compress(
    self: *Compressor,
    target_folder: []const u8,
    compress_path: []const u8,
) !void {
    if (!Fs.existsDir(target_folder)) {
        return error.TargetNotFound;
    }

    if (!Fs.existsDir(self.paths.pkg_cached)) {
        _ = try Fs.openOrCreateDir(self.paths.pkg_cached);
    }

    const a = try std.fmt.allocPrint(
        self.allocator,
        "{d}.tar",
        .{std.time.nanoTimestamp()},
    );
    defer self.allocator.free(a);

    const archive_path = try std.fs.path.join(
        self.allocator,
        &.{ self.paths.pkg_cached, a },
    );
    try Fs.deleteFileIfExists(archive_path);

    defer {
        Fs.deleteFileIfExists(archive_path) catch {};
        self.allocator.free(archive_path);
    }

    blk: {
        var archive_file = try Fs.openOrCreateFile(archive_path);
        defer archive_file.close();
        var b: [Constants.Default.kb * 32]u8 = undefined;
        var writer = archive_file.writer(&b);

        var tar_writer = std.tar.Writer{ .prefix = ".", .underlying_writer = &writer.interface };
        try self.archive(&tar_writer, target_folder, "");
        try tar_writer.underlying_writer.flush();
        break :blk;
    }

    var archive_file = try Fs.openOrCreateFile(archive_path);
    defer archive_file.close();
    const archive_file_stat = try archive_file.stat();

    var compress_file = try Fs.openOrCreateFile(compress_path);
    defer compress_file.close();

    const data = try self.allocator.alloc(u8, @intCast(archive_file_stat.size));
    defer self.allocator.free(data);
    _ = try archive_file.readAll(data);

    const bound = Zstd.getBound(data);
    var compressed = try self.allocator.alloc(u8, bound);
    defer self.allocator.free(compressed);
    const written = try Zstd.compress(data, &compressed, bound, 3);

    const len = data.len;
    const len_str = try std.fmt.allocPrint(self.allocator, "{d}", .{len});
    defer self.allocator.free(len_str);

    for (0..(64 - len_str.len)) |_| {
        _ = try compress_file.writeAll("0");
    }

    _ = try compress_file.writeAll(len_str);
    _ = try compress_file.writeAll(compressed[0..written]);
}

pub fn decompress(self: *Compressor, zstd_path: []const u8, extract_path: []const u8) !void {
    if (!Fs.existsDir(extract_path)) {
        _ = try Fs.openOrCreateDir(extract_path);
    }

    if (!Fs.existsFile(zstd_path)) return;

    var file = try Fs.openFile(zstd_path);
    defer file.close();
    const file_stat = try file.stat();

    const data = try self.allocator.alloc(u8, @intCast(file_stat.size));
    defer self.allocator.free(data);
    _ = try file.readAll(data);

    if (data.len < 64) return error.InvalidZstd;

    const uncompressed_len_string_full = data[0..64];
    var start_i: usize = 0;
    for (uncompressed_len_string_full, 0..) |n, i| {
        if (n == '0') continue;
        start_i = i;
        break;
    }

    const uncompressed_len_string = uncompressed_len_string_full[start_i..];
    const uncompressed_len = try std.fmt.parseInt(u64, uncompressed_len_string, 10);

    const compressed_data = data[64..];

    var decompressed = try self.allocator.alloc(u8, @intCast(uncompressed_len));
    defer self.allocator.free(decompressed);
    try Zstd.decompress(
        compressed_data,
        &decompressed,
        @intCast(uncompressed_len),
    );
    defer self.allocator.free(decompressed);

    var reader = std.Io.Reader.fixed(decompressed);

    var extract_dir = try Fs.openDir(extract_path);
    defer extract_dir.close();

    std.tar.pipeToFileSystem(extract_dir, &reader, .{}) catch |err| {
        switch (err) {
            error.EndOfStream => return,
            else => return err,
        }
    };
}

pub fn decompressZ(self: *Compressor, zip_path: []const u8, extract_path: []const u8) !void {
    const TEMP_DIR = try std.fmt.allocPrint(
        self.allocator,
        "{s}/tmp/",
        .{self.paths.base},
    );

    var temp_extract_directory = try Fs.openOrCreateDir(TEMP_DIR);
    defer temp_extract_directory.close();
    defer {
        Fs.deleteTreeIfExists(TEMP_DIR) catch {};
    }

    var zip_file = try Fs.openOrCreateFile(zip_path);
    defer zip_file.close();
    var reader_buf: [Constants.Default.kb * 16]u8 = undefined;
    var reader = zip_file.reader(&reader_buf);

    var diagnostics = std.zip.Diagnostics{
        .allocator = self.allocator,
    };

    defer diagnostics.deinit();
    try std.zip.extract(
        temp_extract_directory,
        &reader,
        .{ .diagnostics = &diagnostics },
    );

    const temp_extract_target = try std.fmt.allocPrint(
        self.allocator,
        "{s}/{s}",
        .{
            TEMP_DIR,
            diagnostics.root_dir,
        },
    );
    defer self.allocator.free(temp_extract_target);

    try std.fs.cwd().rename(temp_extract_target, extract_path);
}

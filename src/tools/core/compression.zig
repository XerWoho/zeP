const std = @import("std");

const Logger = @import("logger");
const Constants = @import("constants");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;

const zstd = @import("zstd.zig");

/// Handles compression using zstd, and
/// recursion.
pub const Compressor = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,
    paths: Constants.Paths.Paths,

    pub fn init(
        allocator: std.mem.Allocator,
        printer: *Printer,
        paths: Constants.Paths.Paths,
    ) Compressor {
        return Compressor{
            .allocator = allocator,
            .printer = printer,
            .paths = paths,
        };
    }

    fn archive(self: *Compressor, tar_writer: anytype, fs_path: []const u8, real_path: []const u8) !void {
        const alloc = std.heap.page_allocator;

        const logger = Logger.get();
        try logger.infof("archive: running fs={s} real={s}", .{ fs_path, real_path }, @src());

        var open_target = try Fs.openDir(fs_path);
        defer open_target.close();

        var iter = open_target.iterate();
        while (try iter.next()) |input_file_path| {
            if (std.mem.eql(u8, input_file_path.name, ".git")) continue;
            if (std.mem.eql(u8, input_file_path.name, ".github")) continue;
            if (std.mem.eql(u8, input_file_path.name, "zig-out")) continue;
            if (std.mem.eql(u8, input_file_path.name, ".zig-cache")) continue;
            if (std.mem.eql(u8, input_file_path.name, "c")) continue;
            if (std.mem.eql(u8, input_file_path.name, "zstd")) continue;
            if (std.mem.eql(u8, input_file_path.name, "zep.run")) continue;
            if (std.mem.eql(u8, input_file_path.name, ".zep")) continue;

            const tar_path = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ real_path, input_file_path.name });
            const input_fs_path = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ fs_path, input_file_path.name });

            if (input_file_path.kind == .directory) {
                try tar_writer.writeDir(tar_path, .{});
                try self.archive(tar_writer, input_fs_path, tar_path);
                continue;
            }

            const reader_buffer: []u8 = try alloc.alloc(u8, 4096);
            const input_file = try std.fs.cwd().openFile(input_fs_path, .{ .mode = .read_only });
            defer input_file.close();

            const input_file_size: u64 = (try input_file.stat()).size;
            var input_file_reader = input_file.reader(reader_buffer);
            const input_file_reader_interface: *std.Io.Reader = &input_file_reader.interface;

            try logger.infof("archive: adding file {s} [{d} | {s}]", .{ input_fs_path, input_file_size, tar_path }, @src());

            tar_writer.writeFileStream(
                tar_path,
                input_file_size,
                input_file_reader_interface,
                .{ .mtime = 0, .mode = 0 },
            ) catch |err| {
                try logger.infof("archive: [ERROR] failed adding file {s} [{any}]", .{ input_fs_path, err }, @src());
            };
        }
    }

    pub fn compress(
        self: *Compressor,
        target_folder: []const u8,
        compress_path: []const u8,
    ) !bool {
        const logger = Logger.get();
        try logger.infof("compress: {s} => {s}", .{ target_folder, compress_path }, @src());

        if (!Fs.existsDir(target_folder)) {
            try logger.warnf("compress: target folder {s} does not exist, exiting", .{target_folder}, @src());
            return false;
        }

        if (!Fs.existsDir(self.paths.cached)) {
            try logger.infof("compress: creating directory {s}", .{self.paths.cached}, @src());
            _ = try Fs.openOrCreateDir(self.paths.cached);
        }

        var buf: [256]u8 = undefined;
        const a = try std.fmt.bufPrint(&buf, "{d}.tar", .{std.time.nanoTimestamp()});
        const archive_path = try std.fs.path.join(
            self.allocator,
            &.{ self.paths.prebuilt, a },
        );
        defer {
            Fs.deleteFileIfExists(archive_path) catch |err| {
                logger.warnf("compress: could not remove temp archive {s}, err={}", .{ archive_path, err }, @src()) catch {
                    @panic("Logger failed");
                };
                self.printer.append(
                    "\nRemoving temp archive failed! [{s}]\n",
                    .{archive_path},
                    .{ .color = .red, .weight = .bold, .verbosity = 0 },
                ) catch {
                    @panic("Printer failed");
                };
            };
            self.allocator.free(archive_path);
        }

        blk: {
            try logger.infof("compress: creating archive at {s}", .{archive_path}, @src());

            var archive_file = try std.fs.cwd().createFile(archive_path, .{ .truncate = true });
            defer archive_file.close();
            var b: [Constants.Default.kb * 32]u8 = undefined;
            var writer = archive_file.writer(&b);

            var tar_writer = std.tar.Writer{ .prefix = ".", .underlying_writer = &writer.interface };
            try logger.info("compress: running archive function", @src());
            try self.archive(&tar_writer, target_folder, "");
            try tar_writer.underlying_writer.flush();
            break :blk;
        }

        try logger.infof("compress: opening archive file {s}", .{archive_path}, @src());
        var archive_file = try Fs.openFile(archive_path);
        defer archive_file.close();
        const archive_file_stat = try archive_file.stat();

        try logger.infof("compress: opening compress target {s}", .{compress_path}, @src());
        var compress_file = try Fs.openFile(compress_path);
        defer compress_file.close();

        const data = try self.allocator.alloc(u8, @intCast(archive_file_stat.size));
        defer self.allocator.free(data);
        _ = try archive_file.readAll(data);

        try logger.info("compress: zstd compressing", @src());
        const compressed = try zstd.compress(self.allocator, data, 3);

        const len = data.len;
        const len_str = try std.fmt.allocPrint(self.allocator, "{d}", .{len});
        defer self.allocator.free(len_str);

        for (0..(64 - len_str.len)) |_| {
            _ = try compress_file.writeAll("0");
        }

        try logger.info("compress: writing compression data", @src());
        _ = try compress_file.writeAll(len_str);
        _ = try compress_file.writeAll(compressed);

        try logger.info("compress: compression done", @src());
        return true;
    }

    pub fn decompress(self: *Compressor, zstd_path: []const u8, extract_path: []const u8) !void {
        const logger = Logger.get();
        try logger.infof("decompress: {s} => {s}", .{ zstd_path, extract_path }, @src());

        if (!Fs.existsDir(extract_path)) {
            try logger.infof("decompress: creating directory {s}", .{extract_path}, @src());
            _ = try Fs.openOrCreateDir(extract_path);
        }

        if (!Fs.existsFile(zstd_path)) {
            try logger.warnf("decompress: zstd file {s} does not exist, exiting", .{zstd_path}, @src());
            return;
        }

        try logger.infof("decompress: opening {s}", .{zstd_path}, @src());
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

        try logger.info("decompress: zstd decompressing", @src());
        const decompressed = try zstd.decompress(
            self.allocator,
            compressed_data,
            @intCast(uncompressed_len),
        );
        defer self.allocator.free(decompressed);

        var reader = std.Io.Reader.fixed(decompressed);

        try logger.infof("decompress: opening extract directory {s}", .{extract_path}, @src());
        var extract_dir = try Fs.openDir(extract_path);
        defer extract_dir.close();

        try logger.info("decompress: extracting archive", @src());
        std.tar.pipeToFileSystem(extract_dir, &reader, .{}) catch |err| {
            switch (err) {
                error.EndOfStream => return,
                else => return err,
            }
        };
        try self.printer.append(" > DECOMPRESSED!\n\n", .{}, .{ .color = .green });

        try logger.info("decompress: done", @src());
    }
};

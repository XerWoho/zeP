const std = @import("std");

const Constants = @import("constants");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;

/// Handles compression using zlib, and
/// recursion.
pub const Compressor = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,
    paths: *Constants.Paths.Paths,

    pub fn init(
        allocator: std.mem.Allocator,
        printer: *Printer,
        paths: *Constants.Paths.Paths,
    ) Compressor {
        return Compressor{
            .allocator = allocator,
            .printer = printer,
            .paths = paths,
        };
    }

    fn compressTmp(self: *Compressor, target_folder: []const u8, temporary_path: []const u8) !void {
        var dir = try Fs.openDir(target_folder);
        defer dir.close();
        var temporary_file = try Fs.openFile(temporary_path);
        defer temporary_file.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            const entry_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ target_folder, entry.name });
            defer self.allocator.free(entry_path);

            if (entry.kind == .directory) {
                try self.compressTmp(entry_path, temporary_path);
                continue;
            }

            var uncompressed_file = try Fs.openFile(entry_path);
            defer uncompressed_file.close();

            var compressed_data = std.ArrayList(u8).init(self.allocator);
            defer compressed_data.deinit();

            try std.compress.zlib.compress(uncompressed_file.reader(), compressed_data.writer(), .{ .level = .fast });
            const compressed = try compressed_data.toOwnedSlice();
            try temporary_file.seekTo(try temporary_file.getEndPos());
            _ = try temporary_file.write(entry_path);
            _ = try temporary_file.write("\n");

            var encoded = std.ArrayList(u8).init(self.allocator);
            defer encoded.deinit();

            const encoded_writer = encoded.writer();
            const encoder = std.base64.Base64Encoder.init(std.base64.standard.alphabet_chars, null);
            try encoder.encodeWriter(encoded_writer, compressed);
            const encoded_data = try encoded.toOwnedSlice();
            _ = try temporary_file.write(encoded_data);
            try temporary_file.writeAll("\n\n");
        }
    }

    pub fn compress(self: *Compressor, target_folder: []const u8, tar_path: []const u8) !bool {
        if (!Fs.existsDir(target_folder)) return false;

        if (!Fs.existsDir(self.paths.zepped)) {
            _ = try Fs.openOrCreateDir(self.paths.zepped);
        }

        const temporary_tar_path = try std.fmt.allocPrint(self.allocator, "{s}.tmp", .{tar_path});
        try self.compressTmp(target_folder, temporary_tar_path);

        var temporary_file = try Fs.openFile(temporary_tar_path);
        defer {
            temporary_file.close();
            Fs.deleteFileIfExists(temporary_tar_path) catch {
                @panic("Could not delete temporary tar path");
            };
        }

        var tar_file = try Fs.openFile(tar_path);
        defer tar_file.close();

        try std.compress.zlib.compress(temporary_file.reader(), tar_file.writer(), .{ .level = .fast });
        return true;
    }

    pub fn decompress(self: *Compressor, zep_path: []const u8, extract_path: []const u8) !bool {
        if (!Fs.existsDir(extract_path)) {
            _ = try Fs.openOrCreateDir(extract_path);
        }

        if (!Fs.existsFile(zep_path)) {
            return false;
        }

        var file = try Fs.openFile(zep_path);
        defer file.close();

        var decompressor = std.compress.zlib.decompressor(file.reader());
        const reader = decompressor.reader();
        const read_data = try reader.readAllAlloc(self.allocator, Constants.Default.mb * 10);
        defer self.allocator.free(read_data);

        var split_data = std.mem.splitSequence(u8, read_data, "\n\n");
        while (split_data.next()) |entry| {
            var lines = std.mem.splitSequence(u8, entry, "\n");
            const path_name = lines.first();
            const encoded_data = lines.next() orelse continue;

            const decoded_size = (encoded_data.len * 3) / 4;
            var decoded = try self.allocator.alloc(u8, decoded_size);
            defer self.allocator.free(decoded);

            const decoder = std.base64.Base64Decoder.init(std.base64.standard.alphabet_chars, null);
            try decoder.decode(decoded, encoded_data);
            const compressed_data = decoded[0..];

            var out_file = try Fs.openOrCreateFile(path_name);
            defer out_file.close();

            var input_stream = std.io.fixedBufferStream(compressed_data);
            try std.compress.zlib.decompress(input_stream.reader(), out_file.writer());
        }

        return true;
    }
};

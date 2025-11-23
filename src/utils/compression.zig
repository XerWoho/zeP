const std = @import("std");

const Constants = @import("constants");
const UtilsFs = @import("fs.zig");
const UtilsPrinter = @import("printer.zig");

pub const Compressor = struct {
    allocator: std.mem.Allocator,
    printer: *UtilsPrinter.Printer,

    pub fn init(allocator: std.mem.Allocator, printer: *UtilsPrinter.Printer) Compressor {
        return Compressor{ .allocator = allocator, .printer = printer };
    }

    fn compressTmp(self: *Compressor, folderPath: []const u8, tarPath: []const u8) !void {
        var dir = try UtilsFs.openDir(folderPath);
        defer dir.close();
        var tmpFile = try UtilsFs.openFile(tarPath);
        defer tmpFile.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            const fullPath = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ folderPath, entry.name });
            defer self.allocator.free(fullPath);

            if (entry.kind == .directory) {
                try self.compressTmp(fullPath, tarPath);
                continue;
            }

            var file = try UtilsFs.openFile(fullPath);
            defer file.close();

            var compressed = std.ArrayList(u8).init(self.allocator);
            defer compressed.deinit();
            try std.compress.zlib.compress(file.reader(), compressed.writer(), .{});
            const compressedData = try compressed.toOwnedSlice();

            try tmpFile.seekTo(try tmpFile.getEndPos());
            _ = try tmpFile.write(fullPath);
            _ = try tmpFile.write("\n");

            var encoded = std.ArrayList(u8).init(self.allocator);
            defer encoded.deinit();
            const encoder = std.base64.Base64Encoder.init(std.base64.standard.alphabet_chars, null);
            try encoder.encodeWriter(encoded.writer(), compressedData);
            const encodedData = try encoded.toOwnedSlice();
            _ = try tmpFile.write(encodedData);
            try tmpFile.writeAll("\n\n");
        }
    }

    pub fn compress(self: *Compressor, targetFolder: []const u8, tarPath: []const u8) !bool {
        if (!UtilsFs.checkDirExists(targetFolder)) return false;
        if (!UtilsFs.checkDirExists(Constants.ROOT_ZEP_ZEPPED_FOLDER)) {
            _ = try UtilsFs.openCDir(Constants.ROOT_ZEP_ZEPPED_FOLDER);
        }

        const tmpTarPath = try std.fmt.allocPrint(self.allocator, "{s}.tmp", .{tarPath});
        try self.compressTmp(targetFolder, tmpTarPath);

        var tmpFile = try UtilsFs.openFile(tmpTarPath);
        defer tmpFile.close();
        var outFile = try UtilsFs.openFile(tarPath);
        defer outFile.close();
        try std.compress.zlib.compress(tmpFile.reader(), outFile.writer(), .{});
        try UtilsFs.delFile(tmpTarPath);
        return true;
    }

    pub fn decompress(self: *Compressor, zepPath: []const u8, extractPath: []const u8) !bool {
        if (!UtilsFs.checkDirExists(extractPath)) {
            _ = try UtilsFs.openCDir(extractPath);
        }

        if (!UtilsFs.checkFileExists(zepPath)) {
            return false;
        }

        var file = try UtilsFs.openFile(zepPath);
        defer file.close();

        var decompressor = std.compress.zlib.decompressor(file.reader());
        var reader = decompressor.reader();
        const readData = try reader.readAllAlloc(self.allocator, 10 * 1024 * 1024); // 10 MB
        defer self.allocator.free(readData);

        var splitData = std.mem.splitSequence(u8, readData, "\n\n");
        while (splitData.next()) |entry| {
            var lines = std.mem.splitSequence(u8, entry, "\n");
            const pathName = lines.first();
            const encodedData = lines.next() orelse continue;

            const decodedSize = (encodedData.len * 3) / 4;
            var decoded = try self.allocator.alloc(u8, decodedSize);
            defer self.allocator.free(decoded);

            const decoder = std.base64.Base64Decoder.init(std.base64.standard.alphabet_chars, null);
            try decoder.decode(decoded, encodedData);
            const compressedData = decoded[0..];

            var outFile = try UtilsFs.openCFile(pathName);
            defer outFile.close();

            var inputStream = std.io.fixedBufferStream(compressedData);
            try std.compress.zlib.decompress(inputStream.reader(), outFile.writer());
        }

        return true;
    }
};

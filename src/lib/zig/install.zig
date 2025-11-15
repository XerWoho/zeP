const std = @import("std");
const builtin = @import("builtin");

const Manifest = @import("lib/manifest.zig");
const Path = @import("lib/path.zig");

const Constants = @import("constants");

const Utils = @import("utils");
const UtilsJson = Utils.UtilsJson;
const UtilsFs = Utils.UtilsFs;
const UtilsCompression = Utils.UtilsCompression;
const UtilsInjector = Utils.UtilsInjector;
const UtilsPrinter = Utils.UtilsPrinter;

pub const ZigInstaller = struct {
    allocator: std.mem.Allocator,
    printer: *UtilsPrinter.Printer,

    pub fn init(
        allocator: std.mem.Allocator,
        printer: *UtilsPrinter.Printer,
    ) !ZigInstaller {
        return ZigInstaller{ .allocator = allocator, .printer = printer };
    }

    pub fn deinit(self: *ZigInstaller) void {
        _ = self;
        defer {
            // self.printer.deinit();
        }
    }

    fn fetchData(self: *ZigInstaller, name: []const u8, tarball: []const u8, version: []const u8, target: []const u8) !void {
        // Create a HTTP client
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const targetExtension = if (builtin.os.tag == .windows) "zip" else "tar.xz";
        const targetCompressedFile = try std.fmt.allocPrint(self.allocator, "{s}/z/{s}/{s}.{s}", .{ Constants.ROOT_ZEP_ZIG_FOLDER, version, name, targetExtension });
        if (!try UtilsFs.checkFileExists(targetCompressedFile)) {
            var buf: [4096]u8 = undefined;
            try self.printer.append("Parsing URI...\n");
            const uri = try std.Uri.parse(tarball);
            var req = try client.open(.GET, uri, .{ .server_header_buffer = &buf });
            defer req.deinit();

            try self.printer.append("Sending request...\n");
            try req.send();
            try req.finish();
            try self.printer.append("Waiting request...\n");
            try req.wait();

            try self.printer.append("Receiving data...\n");
            var reader = req.reader();
            var out_file = try UtilsFs.openCFile(targetCompressedFile);
            defer out_file.close();

            try self.printer.append("\nWriting Tmp File");
            var buffered_out = std.io.bufferedWriter(out_file.writer());
            const out_writer = buffered_out.writer();

            var j: u8 = 0;
            var i: u32 = 0;
            var bigBuf: [4096 * 4]u8 = undefined;
            while (true) {
                const n = try reader.read(&bigBuf);
                if (n == 0) break;
                try out_writer.writeAll(bigBuf[0..n]);
                i += 1;
                if (i > 200) {
                    if (j >= 3) {
                        self.printer.pop(3);
                        j = 0;
                        continue;
                    }
                    try self.printer.append(".");
                    j += 1;
                    i = 0;
                }
            }
            try self.printer.append("\n");
            try buffered_out.flush();
        } else {
            try self.printer.append("Data found in Cache!\n");
        }
        var targetOutFile = try UtilsFs.openCFile(targetCompressedFile);
        defer targetOutFile.close();

        try self.printer.append("Extracting data...\n");
        const decompressedDataPath = try std.fmt.allocPrint(self.allocator, "{s}/d/{s}", .{ Constants.ROOT_ZEP_ZIG_FOLDER, version });
        if (builtin.os.tag == .windows) {
            try self.decompressW(targetOutFile.seekableStream(), decompressedDataPath, target);
        } else {
            try self.decompressP(targetOutFile.reader(), decompressedDataPath, target);
        }
    }

    // windows uses .zip
    fn decompressW(self: *ZigInstaller, skStream: std.fs.File.SeekableStream, decompressedDataPath: []const u8, target: []const u8) !void {
        const newExtractTarget = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ decompressedDataPath, target });
        if (try UtilsFs.checkDirExists(newExtractTarget)) {
            try self.printer.append("Already installed!\n");
            return;
        }

        var decompressedDataDir = try UtilsFs.openCDir(decompressedDataPath);
        defer decompressedDataDir.close();

        var iter = try std.zip.Iterator(@TypeOf(skStream)).init(skStream);
        var filename_buf: [std.fs.max_path_bytes]u8 = undefined;
        var f: []u8 = undefined;
        while (try iter.next()) |entry| {
            const crc32 = try entry.extract(skStream, .{}, &filename_buf, decompressedDataDir);
            if (crc32 != entry.crc32) continue;
            f = filename_buf[0..entry.filename_len];
            break;
        }
        const extractTarget = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ decompressedDataPath, f });
        try std.zip.extract(decompressedDataDir, skStream, .{});
        try self.printer.append("Extracted to ");
        try self.printer.append(decompressedDataPath);
        try self.printer.append("!\n");
        try std.fs.cwd().rename(extractTarget, newExtractTarget);
    }

    // decompression for POSIX (linux)
    // requires a different function,
    // linux uses .tar
    fn decompressP(self: *ZigInstaller, reader: std.fs.File.Reader, decompressedDataPath: []const u8, target: []const u8) !void {
        var decompressedDataDir = try UtilsFs.openCDir(decompressedDataPath);
        defer decompressedDataDir.close();

        var decompressed = try std.compress.xz.decompress(self.allocator, reader);
        defer decompressed.deinit();

        var filename_buf: [std.fs.max_path_bytes]u8 = undefined;
        var link_name_buffer: [std.fs.max_path_bytes]u8 = undefined;
        var iter = std.tar.iterator(decompressed.reader(), .{ .file_name_buffer = &filename_buf, .link_name_buffer = &link_name_buffer });
        const check_file = try iter.next();
        const f = check_file.?.name;

        const newExtractTarget = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ decompressedDataPath, target });
        if (try UtilsFs.checkDirExists(newExtractTarget)) {
            try self.printer.append("Already installed!\n");
            return;
        }

        const extractTarget = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ decompressedDataPath, f });

        try std.tar.pipeToFileSystem(decompressedDataDir, decompressed.reader(), .{ .mode_mode = .ignore });
        try self.printer.append("Extracted!\n\n");
        try std.fs.cwd().rename(extractTarget, newExtractTarget);
    }

    pub fn install(self: *ZigInstaller, name: []const u8, tarball: []const u8, version: []const u8, target: []const u8) !void {
        try self.fetchData(name, tarball, version, target);
        try self.printer.append("Modifying Manifest...\n");
        try Manifest.modifyManifest(name, version, target);
        try self.printer.pop(1);
        try self.printer.append("Manifest Up to Date!\n");

        try self.printer.append("Switching to installed version...\n");
        try Path.modifyPath();
        try self.printer.pop(1);
        try self.printer.append("Switched to installed version!\n");
    }
};

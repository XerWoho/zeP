const std = @import("std");
const builtin = @import("builtin");

const Manifest = @import("lib/manifest.zig");

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

        const t = try std.fmt.allocPrint(self.allocator, "{s}/z/{s}/{s}.zip", .{ Constants.ROOT_ZEP_ZIG_FOLDER, version, name });
        if (!try UtilsFs.checkFileExists(t)) {
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
            var out_file = try UtilsFs.openCFile(t);
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
        var out_file = try UtilsFs.openCFile(t);
        defer out_file.close();

        const skStream = out_file.seekableStream();
        try self.printer.append("Extracting data...\n");
        const decompressedDataPath = try std.fmt.allocPrint(self.allocator, "{s}/d/{s}/", .{ Constants.ROOT_ZEP_ZIG_FOLDER, version });
        var decompressedDataDir = try UtilsFs.openCDir(decompressedDataPath);
        defer decompressedDataDir.close();

        if (builtin.os.tag == .windows) {
            try self.decompressW(skStream, decompressedDataPath, decompressedDataDir, target);
        } else {
            try self.decompressP(skStream, decompressedDataPath, decompressedDataDir, target);
        }
    }

    // windows uses .zip
    fn decompressW(self: *ZigInstaller, skStream: std.fs.File.SeekableStream, decompressedDataPath: []const u8, decompressedDataDir: std.fs.Dir, target: []const u8) !void {
        var iter = try std.zip.Iterator(@TypeOf(skStream)).init(skStream);
        var filename_buf: [std.fs.max_path_bytes]u8 = undefined;
        var f: []u8 = undefined;
        while (try iter.next()) |entry| {
            const crc32 = try entry.extract(skStream, .{}, &filename_buf, decompressedDataDir);
            if (crc32 != entry.crc32) continue;
            f = filename_buf[0..entry.filename_len];
            break;
        }

        const newExtractTarget = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ decompressedDataPath, target });
        if (try UtilsFs.checkDirExists(newExtractTarget)) {
            try self.printer.append("Already installed!\n");
            return;
        }
        const extractTarget = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ decompressedDataPath, f });
        if (try UtilsFs.checkDirExists(extractTarget)) {
            try std.fs.cwd().rename(extractTarget, newExtractTarget);
            return;
        }
        try std.zip.extract(decompressedDataDir, skStream, .{});
        try self.printer.append("Extracted!\n\n");
        try std.fs.cwd().rename(extractTarget, newExtractTarget);
    }

    // decompression for POSIX (linux)
    // requires a different function,
    // linux uses .tar
    fn decompressP(self: *ZigInstaller, skStream: std.fs.File.SeekableStream, decompressedDataPath: []const u8, decompressedDataDir: std.fs.Dir, target: []const u8) !void {
        var iter = std.tar.iterator(skStream, .{});
        var f: []u8 = undefined;
        while (try iter.next()) |entry| {
            f = entry.name;
            break;
        }

        const newExtractTarget = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ decompressedDataPath, target });
        if (try UtilsFs.checkDirExists(newExtractTarget)) {
            try self.printer.append("Already installed!\n");
            return;
        }
        const extractTarget = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ decompressedDataPath, f });
        if (try UtilsFs.checkDirExists(extractTarget)) {
            try std.fs.cwd().rename(extractTarget, newExtractTarget);
            return;
        }
        try std.tar.pipeToFileSystem(decompressedDataDir, skStream, .{});
        try self.printer.append("Extracted!\n\n");
        try std.fs.cwd().rename(extractTarget, newExtractTarget);
    }

    pub fn install(self: *ZigInstaller, name: []const u8, tarball: []const u8, version: []const u8, target: []const u8) !void {
        try self.fetchData(name, tarball, version, target);
        try self.printer.append("Modifying Manifest...\n");
        try Manifest.modifyManifest(name, version, target);
        try self.printer.append("Manifest Up to Date!\n");
    }
};

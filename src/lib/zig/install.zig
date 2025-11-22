const std = @import("std");
const builtin = @import("builtin");

const Link = @import("lib/link.zig");

const Structs = @import("structs");
const Constants = @import("constants");
const Utils = @import("utils");
const UtilsFs = Utils.UtilsFs;
const UtilsPrinter = Utils.UtilsPrinter;
const UtilsManifest = Utils.UtilsManifest;

/// Installer for Zig versions
pub const ZigInstaller = struct {
    allocator: std.mem.Allocator,
    printer: *UtilsPrinter.Printer,

    // ------------------------
    // Initialize ZigInstaller
    // ------------------------
    pub fn init(
        allocator: std.mem.Allocator,
        printer: *UtilsPrinter.Printer,
    ) !ZigInstaller {
        return ZigInstaller{
            .allocator = allocator,
            .printer = printer,
        };
    }

    // ------------------------
    // Deinitialize
    // ------------------------
    pub fn deinit(_: *ZigInstaller) void {
        // currently no deinit required
    }

    // ------------------------
    // Fetch and extract Zig archive
    // ------------------------
    fn fetchData(self: *ZigInstaller, name: []const u8, tarball: []const u8, version: []const u8, target: []const u8) !void {
        const targetExt = if (builtin.os.tag == .windows) "zip" else "tar.xz";
        const targetFile = try std.fmt.allocPrint(
            self.allocator,
            "{s}/z/{s}/{s}.{s}",
            .{ Constants.ROOT_ZEP_ZIG_FOLDER, version, name, targetExt },
        );

        // Download if not cached
        if (!try UtilsFs.checkFileExists(targetFile)) {
            try self.downloadFile(tarball, targetFile);
        } else {
            try self.printer.append("Data found in cache!\n", .{}, .{});
        }

        // Open the downloaded file
        var compressedFile = try UtilsFs.openCFile(targetFile);
        defer compressedFile.close();

        try self.printer.append("Extracting data...\n", .{}, .{});

        const decompressedDir = try std.fmt.allocPrint(self.allocator, "{s}/d/{s}", .{ Constants.ROOT_ZEP_ZIG_FOLDER, version });
        if (builtin.os.tag == .windows) {
            try self.decompressWindows(compressedFile.seekableStream(), decompressedDir, target);
        } else {
            try self.decompressPosix(compressedFile.reader(), decompressedDir, target);
        }
    }

    // ------------------------
    // Download file via HTTP
    // ------------------------
    fn downloadFile(self: *ZigInstaller, uriStr: []const u8, outPath: []const u8) !void {
        try self.printer.append("Parsing URI...\n", .{}, .{});
        const uri = try std.Uri.parse(uriStr);
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var buf: [4096]u8 = undefined;
        var req = try client.open(.GET, uri, .{ .server_header_buffer = &buf });
        defer req.deinit();

        try self.printer.append("Sending request...\n", .{}, .{});
        try req.send();
        try req.finish();
        try self.printer.append("Waiting for response", .{}, .{});
        try req.wait();

        var reader = req.reader();
        var outFile = try UtilsFs.openCFile(outPath);
        defer outFile.close();

        var bufferedWriter = std.io.bufferedWriter(outFile.writer());
        defer {
            bufferedWriter.flush() catch {
                @panic("Could not flush buffered Writer!");
            };
        }

        var bigBuf: [4096 * 4]u8 = undefined;
        var lineCounter: u32 = 0;
        var dotCounter: u8 = 0;
        while (true) {
            const n = try reader.read(&bigBuf);
            if (n == 0) break;
            try bufferedWriter.writer().writeAll(bigBuf[0..n]);

            lineCounter += 1;
            if (lineCounter > 200) {
                if (dotCounter >= 3) {
                    self.printer.pop(3);
                    dotCounter = 0;
                }
                try self.printer.append(".", .{}, .{});
                dotCounter += 1;
                lineCounter = 0;
            }
        }
        try self.printer.append("\n", .{}, .{});
    }

    // ------------------------
    // Decompress for Windows (.zip)
    // ------------------------
    fn decompressWindows(self: *ZigInstaller, skStream: std.fs.File.SeekableStream, decompressedPath: []const u8, target: []const u8) !void {
        const newTarget = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ decompressedPath, target });
        if (try UtilsFs.checkDirExists(newTarget)) {
            try self.printer.append("Already installed!\n", .{}, .{});
            return;
        }

        var dir = try UtilsFs.openCDir(decompressedPath);
        defer dir.close();

        var iter = try std.zip.Iterator(@TypeOf(skStream)).init(skStream);
        var filenameBuf: [std.fs.max_path_bytes]u8 = undefined;
        var selectedFile: []u8 = undefined;
        while (try iter.next()) |entry| {
            const crc = try entry.extract(skStream, .{}, &filenameBuf, dir);
            if (crc != entry.crc32) continue;
            selectedFile = filenameBuf[0..entry.filename_len];
            break;
        }

        const extractTarget = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ decompressedPath, selectedFile });
        try std.zip.extract(dir, skStream, .{});
        try self.printer.append("Extracted to {s}!\n", .{decompressedPath}, .{});
        try std.fs.cwd().rename(extractTarget, newTarget);
    }

    // ------------------------
    // Decompress for POSIX (.tar.xz)
    // ------------------------
    fn decompressPosix(self: *ZigInstaller, reader: std.fs.File.Reader, decompressedPath: []const u8, target: []const u8) !void {
        var dir = try UtilsFs.openCDir(decompressedPath);
        defer dir.close();

        var decompressed = try std.compress.xz.decompress(self.allocator, reader);
        defer decompressed.deinit();

        var filenameBuf: [std.fs.max_path_bytes]u8 = undefined;
        var linkBuf: [std.fs.max_path_bytes]u8 = undefined;
        var tarIter = std.tar.iterator(decompressed.reader(), .{ .file_name_buffer = &filenameBuf, .link_name_buffer = &linkBuf });

        const firstFile = try tarIter.next();
        const extractedName = firstFile.?.name;

        const newTarget = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ decompressedPath, target });
        if (try UtilsFs.checkDirExists(newTarget)) {
            try self.printer.append("Already installed!\n", .{}, .{});
            return;
        }

        const extractTarget = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ decompressedPath, extractedName });
        try std.tar.pipeToFileSystem(dir, decompressed.reader(), .{ .mode_mode = .ignore });
        try self.printer.append("Extracted!\n\n", .{}, .{});
        try std.fs.cwd().rename(extractTarget, newTarget);

        const zigExeTarget = try std.fmt.allocPrint(self.allocator, "{s}/zig.exe", .{extractTarget});
        defer self.allocator.free(zigExeTarget);
        const zigExeFile = try UtilsFs.openFile(zigExeTarget);
        defer zigExeFile.close();
        try zigExeFile.chmod(755);
    }

    // ------------------------
    // Public install function
    // ------------------------
    pub fn install(self: *ZigInstaller, name: []const u8, tarball: []const u8, version: []const u8, target: []const u8) !void {
        try self.fetchData(name, tarball, version, target);

        try self.printer.append("Modifying Manifest...\n", .{}, .{});

        const path = try std.fmt.allocPrint(self.allocator, "{s}/d/{s}/{s}", .{ Constants.ROOT_ZEP_ZIG_FOLDER, version, target });
        try UtilsManifest.writeManifest(
            Structs.ZigManifest,
            self.allocator,
            Constants.ROOT_ZEP_ZIG_MANIFEST,
            Structs.ZigManifest{
                .name = name,
                .path = path,
            },
        );

        self.printer.pop(1);
        try self.printer.append("Manifest Up to Date!\n", .{}, .{});

        try self.printer.append("Switching to installed version...\n", .{}, .{});
        try Link.updateLink();
        self.printer.pop(1);
        try self.printer.append("Switched to installed version!\n", .{}, .{});
    }
};

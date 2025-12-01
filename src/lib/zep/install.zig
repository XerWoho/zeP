const std = @import("std");
const builtin = @import("builtin");

const Link = @import("lib/link.zig");

const Structs = @import("structs");
const Constants = @import("constants");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Manifest = @import("core").Manifest;

/// Installer for Zep versions
pub const ZepInstaller = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,

    // ------------------------
    // Initialize ZepInstaller
    // ------------------------
    pub fn init(
        allocator: std.mem.Allocator,
        printer: *Printer,
    ) !ZepInstaller {
        return ZepInstaller{
            .allocator = allocator,
            .printer = printer,
        };
    }

    // ------------------------
    // Deinitialize
    // ------------------------
    pub fn deinit(_: *ZepInstaller) void {
        // currently no deinit required
    }

    // ------------------------
    // Fetch and extract Zep archive
    // ------------------------
    fn fetchData(self: *ZepInstaller, url: []const u8, version: []const u8) !void {
        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();

        const target_extension = if (builtin.os.tag == .windows) "zip" else "tar";
        const target_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/v/temp_{s}.{s}",
            .{ paths.zep_root, version, target_extension },
        );
        try Fs.deleteFileIfExists(target_path);

        try self.downloadFile(url, target_path);

        // Open the downloaded file
        var compressed_file = try Fs.openOrCreateFile(target_path);
        defer compressed_file.close();

        try self.printer.append("Extracting data...\n", .{}, .{});

        const decompressed_directory = try std.fmt.allocPrint(self.allocator, "{s}/v/{s}", .{ paths.zep_root, version });
        try Fs.deleteTreeIfExists(decompressed_directory);

        if (builtin.os.tag == .windows) {
            try self.decompressWindows(compressed_file.seekableStream(), decompressed_directory);
        } else {
            try self.decompressPosix(compressed_file.reader(), decompressed_directory);
        }

        try Fs.deleteFileIfExists(target_path);
    }

    // ------------------------
    // Download file via HTTP
    // ------------------------
    fn downloadFile(self: *ZepInstaller, raw_uri: []const u8, out_path: []const u8) !void {
        try self.printer.append("Parsing URI...\n", .{}, .{});
        const uri = try std.Uri.parse(raw_uri);
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var server_header_buffer: [Constants.Default.kb * 16]u8 = undefined;
        var req = try client.open(.GET, uri, .{ .server_header_buffer = &server_header_buffer });
        defer req.deinit();

        try self.printer.append("Sending request...\n", .{}, .{});
        try req.send();
        try req.finish();
        try self.printer.append("Waiting for response...\n", .{}, .{});
        try req.wait();

        var reader = req.reader();
        var out_file = try Fs.openOrCreateFile(out_path);
        defer out_file.close();

        var buffered_writer = std.io.bufferedWriter(out_file.writer());
        defer {
            buffered_writer.flush() catch {
                self.printer.append("\nFailed to flush buffer!\n", .{}, .{ .color = 31 }) catch {};
            };
        }

        try self.printer.append("Reading data", .{}, .{});
        var read_buffer: [4096 * 4]u8 = undefined;
        var line_counter: u32 = 0;
        var dot_counter: u8 = 0;
        while (true) {
            const n = try reader.read(&read_buffer);
            if (n == 0) break;
            try buffered_writer.writer().writeAll(read_buffer[0..n]);

            line_counter += 1;
            if (line_counter > 200) {
                if (dot_counter >= 3) {
                    self.printer.pop(3);
                    dot_counter = 0;
                }
                try self.printer.append(".", .{}, .{});
                dot_counter += 1;
                line_counter = 0;
            }
        }
        try self.printer.append("\n", .{}, .{});
    }

    // ------------------------
    // Decompress for Windows (.zip)
    // ------------------------
    fn decompressWindows(self: *ZepInstaller, reader: std.fs.File.SeekableStream, decompressed_path: []const u8) !void {
        var dir = try Fs.openOrCreateDir(decompressed_path);
        defer dir.close();
        var diagnostics = std.zip.Diagnostics{
            .allocator = self.allocator,
        };
        defer diagnostics.deinit();
        try std.zip.extract(dir, reader, .{ .diagnostics = &diagnostics });

        const extract_target = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ decompressed_path, diagnostics.root_dir });
        try self.printer.append("Extracted to {s}!\n", .{decompressed_path}, .{});
        try std.fs.cwd().rename(extract_target, decompressed_path);
    }

    // ------------------------
    // Decompress for POSIX (.tar.xz)
    // ------------------------
    fn decompressPosix(self: *ZepInstaller, reader: std.fs.File.Reader, decompressed_path: []const u8) !void {
        var dir = try Fs.openOrCreateDir(decompressed_path);
        defer dir.close();

        var decompressed = try std.compress.xz.decompress(self.allocator, reader);
        defer decompressed.deinit();
        const decompressed_reader = decompressed.reader();

        var filename_buffer: [std.fs.max_path_bytes]u8 = undefined;
        var symbolic_link_buffer: [std.fs.max_path_bytes]u8 = undefined;
        var tar_iterator = std.tar.iterator(decompressed_reader, .{ .file_name_buffer = &filename_buffer, .link_name_buffer = &symbolic_link_buffer });

        const firt_file = tar_iterator.next() catch {
            self.printer.append("\nInvalid tar file!\n", .{}, .{ .color = 31 }) catch {};
            return;
        } orelse {
            self.printer.append("\nInvalid tar file!\n", .{}, .{ .color = 31 }) catch {};
            return;
        };

        const extracted_name = firt_file.name;

        const extract_target = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ decompressed_path, extracted_name });
        try std.tar.pipeToFileSystem(dir, decompressed_reader, .{ .mode_mode = .ignore });
        try self.printer.append("Extracted!\n\n", .{}, .{});
        try std.fs.cwd().rename(extract_target, decompressed_path);

        const zep_exe_path = try std.fmt.allocPrint(self.allocator, "{s}/zep", .{decompressed_path});
        defer self.allocator.free(zep_exe_path);
        const zep_exe_file = try Fs.openFile(zep_exe_path);
        defer zep_exe_file.close();
        try zep_exe_file.chmod(755);
    }

    // ------------------------
    // Public install function
    // ------------------------
    pub fn install(self: *ZepInstaller, version: []const u8) !void {
        const url = if (builtin.os.tag == .windows)
            try std.fmt.allocPrint(self.allocator, "https://github.com/XerWoho/zeP/releases/download/{s}/windows_{s}.zip", .{ version, version })
        else
            try std.fmt.allocPrint(self.allocator, "https://github.com/XerWoho/zeP/releases/download/{s}/linux_{s}.tar", .{ version, version });
        defer self.allocator.free(url);

        try self.fetchData(url, version);
        try self.printer.append("Modifying Manifest...\n", .{}, .{});

        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();

        const path = try std.fs.path.join(self.allocator, &.{ paths.zep_root, "v", version });
        defer self.allocator.free(path);

        Manifest.writeManifest(
            Structs.Manifests.ZepManifest,
            self.allocator,
            paths.zep_manifest,
            Structs.Manifests.ZepManifest{
                .version = version,
                .path = path,
            },
        ) catch {
            try self.printer.append("Updating Manifest failed!\n", .{}, .{ .color = 31 });
        };

        try self.printer.append("Manifest Up to Date!\n", .{}, .{});

        try self.printer.append("Switching to installed version...\n", .{}, .{});
        Link.updateLink() catch {
            try self.printer.append("Updating Link has failed!\n", .{}, .{ .color = 31 });
        };
        try self.printer.append("Switched to installed version!\n", .{}, .{});
    }
};

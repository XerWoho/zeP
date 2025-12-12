const std = @import("std");
const builtin = @import("builtin");

const Link = @import("lib/link.zig");

const Structs = @import("structs");
const Constants = @import("constants");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Manifest = @import("core").Manifest;

/// Installer for Artifact versions
pub const ArtifactInstaller = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,

    // ------------------------
    // Initialize ArtifactInstaller
    // ------------------------
    pub fn init(
        allocator: std.mem.Allocator,
        printer: *Printer,
    ) !ArtifactInstaller {
        return ArtifactInstaller{
            .allocator = allocator,
            .printer = printer,
        };
    }

    // ------------------------
    // Deinitialize
    // ------------------------
    pub fn deinit(_: *ArtifactInstaller) void {
        // currently no deinit required
    }

    // ------------------------
    // Fetch and extract Artifact archive
    // ------------------------
    fn fetchData(
        self: *ArtifactInstaller,
        name: []const u8,
        tarball: []const u8,
        version: []const u8,
        target: []const u8,
        artifact_type: Structs.Extras.ArtifactType,
    ) !void {
        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();

        var tarball_split_iter = std.mem.splitAny(u8, tarball, ".");
        var tarball_extension = tarball_split_iter.next();
        while (tarball_split_iter.next()) |e| {
            tarball_extension = e;
        }

        const target_extension = tarball_extension orelse if (builtin.os.tag == .windows) "zip" else "tar.xz";
        const cached_file = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ name, target_extension });
        defer self.allocator.free(cached_file);
        const target_path = try std.fs.path.join(
            self.allocator,
            &.{
                if (artifact_type == .zig)
                    paths.zig_root
                else
                    paths.zep_root,
                "z",
                version,
                cached_file,
            },
        );

        // Download if not cached
        if (!Fs.existsFile(target_path)) {
            try self.downloadFile(tarball, target_path);
        } else {
            try self.printer.append("Data found in cache!\n", .{}, .{});
        }

        // Open the downloaded file
        var compressed_file = try Fs.openOrCreateFile(target_path);
        defer compressed_file.close();

        try self.printer.append("Extracting data...\n", .{}, .{});

        const decompressed_directory = try std.fs.path.join(
            self.allocator,
            &.{ if (artifact_type == .zig) paths.zig_root else paths.zep_root, "d", version },
        );
        _ = try Fs.openOrCreateDir(decompressed_directory);

        const main_temporary_directory = try std.fs.path.join(
            self.allocator,
            &.{ if (artifact_type == .zig) paths.zig_root else paths.zep_root, "temp" },
        );
        _ = try Fs.openOrCreateDir(main_temporary_directory);

        const temporary_directory = try std.fs.path.join(
            self.allocator,
            &.{ if (artifact_type == .zig) paths.zig_root else paths.zep_root, "temp", version },
        );

        defer Fs.deleteTreeIfExists(main_temporary_directory) catch {};

        defer self.allocator.free(decompressed_directory);
        if (builtin.os.tag == .windows) {
            try self.decompressWindows(
                compressed_file.seekableStream(),
                decompressed_directory,
                temporary_directory,
                target,
            );
        } else {
            try self.decompressPosix(
                compressed_file.reader(),
                decompressed_directory,
                temporary_directory,
                target,
                artifact_type,
            );
        }
    }

    // ------------------------
    // Download file via HTTP
    // ------------------------
    fn downloadFile(self: *ArtifactInstaller, raw_uri: []const u8, out_path: []const u8) !void {
        try self.printer.append("Parsing URI...\n", .{}, .{});
        const uri = try std.Uri.parse(raw_uri);
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var server_header_buffer: [Constants.Default.kb * 32]u8 = undefined;
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
    fn decompressWindows(
        self: *ArtifactInstaller,
        reader: std.fs.File.SeekableStream,
        decompressed_path: []const u8,
        temporary_path: []const u8,
        target: []const u8,
    ) !void {
        const new_target = try std.fs.path.join(self.allocator, &.{ decompressed_path, target });
        defer self.allocator.free(new_target);

        if (Fs.existsDir(new_target)) {
            try self.printer.append("Already installed!\n", .{}, .{});
            return;
        }

        var dir = try Fs.openOrCreateDir(temporary_path);
        defer dir.close();
        var diagnostics = std.zip.Diagnostics{
            .allocator = self.allocator,
        };
        defer diagnostics.deinit();
        try std.zip.extract(dir, reader, .{ .diagnostics = &diagnostics });

        const extract_target = try std.fs.path.join(self.allocator, &.{ temporary_path, diagnostics.root_dir });
        defer self.allocator.free(extract_target);

        try self.printer.append("Extracted {s} => {s}!\n", .{ extract_target, new_target }, .{});
        try std.fs.cwd().rename(extract_target, new_target);
    }

    // ------------------------
    // Decompress for POSIX (.tar.xz)
    // ------------------------
    fn decompressPosix(
        self: *ArtifactInstaller,
        reader: std.fs.File.Reader,
        decompressed_path: []const u8,
        temporary_path: []const u8,
        target: []const u8,
        artifact_type: Structs.Extras.ArtifactType,
    ) !void {
        var dir = try Fs.openOrCreateDir(temporary_path);
        defer dir.close();

        var decompressed = try std.compress.xz.decompress(self.allocator, reader);
        defer decompressed.deinit();
        const decompressed_reader = decompressed.reader();

        const new_target = try std.fs.path.join(self.allocator, &.{ decompressed_path, target });
        defer self.allocator.free(new_target);

        if (Fs.existsDir(new_target)) {
            try self.printer.append("Already installed!\n", .{}, .{});
            return;
        }

        var diagnostics = std.tar.Diagnostics{
            .allocator = self.allocator,
        };
        try std.tar.pipeToFileSystem(dir, decompressed_reader, .{ .mode_mode = .ignore, .diagnostics = &diagnostics });

        const extract_target = try std.fs.path.join(self.allocator, &.{ temporary_path, diagnostics.root_dir });
        defer self.allocator.free(extract_target);
        const stat_extract = try std.fs.cwd().statFile(extract_target);
        if (stat_extract.kind == .file) {
            try self.printer.append("Extracted {s} => {s}!\n", .{ temporary_path, new_target }, .{});
            try std.fs.cwd().rename(temporary_path, new_target);
        } else {
            try self.printer.append("Extracted {s} => {s}!\n", .{ extract_target, new_target }, .{});
            try std.fs.cwd().rename(extract_target, new_target);
        }

        var artifact_exe_path = try std.fs.path.join(self.allocator, &.{ new_target, "zig" });
        defer self.allocator.free(artifact_exe_path);
        if (artifact_type == .zep) {
            self.allocator.free(artifact_exe_path);
            artifact_exe_path = try std.fs.path.join(self.allocator, &.{ new_target, "zeP" });
            if (!Fs.existsFile(artifact_exe_path)) {
                self.allocator.free(artifact_exe_path);
                artifact_exe_path = try std.fs.path.join(self.allocator, &.{ new_target, "zep" });
            }
        }

        const artifact_exe_file = try Fs.openFile(artifact_exe_path);
        defer artifact_exe_file.close();
        try artifact_exe_file.chmod(0o755);
    }

    // ------------------------
    // Public install function
    // ------------------------
    pub fn install(
        self: *ArtifactInstaller,
        name: []const u8,
        tarball: []const u8,
        version: []const u8,
        target: []const u8,
        artifact_type: Structs.Extras.ArtifactType,
    ) !void {
        try self.fetchData(name, tarball, version, target, artifact_type);
        try self.printer.append("Modifying Manifest...\n", .{}, .{});

        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();

        const path = try std.fs.path.join(self.allocator, &.{
            if (artifact_type == .zig) paths.zig_root else paths.zep_root,
            "d",
            version,
            target,
        });
        defer self.allocator.free(path);
        Manifest.writeManifest(
            Structs.Manifests.ArtifactManifest,
            self.allocator,
            if (artifact_type == .zig)
                paths.zig_manifest
            else
                paths.zep_manifest,
            Structs.Manifests.ArtifactManifest{
                .name = name,
                .path = path,
            },
        ) catch {
            try self.printer.append("Updating Manifest failed!\n", .{}, .{ .color = 31 });
        };

        try self.printer.append("Manifest Up to Date!\n", .{}, .{});

        try self.printer.append("Switching to installed version...\n", .{}, .{});
        Link.updateLink(artifact_type) catch {
            try self.printer.append("Updating Link has failed!\n", .{}, .{ .color = 31 });
        };
        try self.printer.append("Switched to installed version!\n", .{}, .{});
    }
};
